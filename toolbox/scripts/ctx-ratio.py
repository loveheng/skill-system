#!/usr/bin/env python3
"""
toolbox-script
format: v1
name: ctx-ratio
summary: 上下文利用率探测（RCR+总量双阈值+冷却锁，fail-open 无源即 n/a）→ dev-loop §4 归并触发线
trigger: manual
cat: docs
platform: any
self-test: --self-test
params: CTX_WINDOW_MAX,CTX_TOTAL_PCT,CTX_RCR_PCT,CTX_RECENT_K,CTX_COOLDOWN_MIN
"""

# ctx-ratio —— 上下文利用率探测（dev-loop §3 自动重构 ③ 的量化触发线）
#
# 指标口径（评估定稿 v1.1）:
#   总量%   = 末端 usage 输入侧 / 窗口上限（真实占用）
#   RCR     = 最近 RECENT_K token 滑窗估算 / 衰减层（总量 - 常驻层）
#             常驻层 ≈ 首个 usage 输入侧（system prompt + 工具定义 + 首轮），切窗不减，故从分母剔除
#   resident% = 常驻层 / 窗口上限（元系统常驻占用；仅展示不触发——用事实替代窗口占比恐慌）
#   窗口上限 = CTX_WINDOW_MAX（默认 200000；须按宿主模型实际窗口上限校准——分母错误使所有百分比失真）
#   命中    = 总量% >= TOTAL_PCT 且 RCR < RCR_PCT（双阈值，防短会话误报）
#   冷却锁  = --mark-merged 落 state 时间戳，COOLDOWN_MIN 分钟内命中降级为"冷却中"（防归并震荡）
#   排错豁免= 协议层职责（dev-loop §3），脚本不探测退出码——权威判断在 AI 侧
#
# 数据源（--source）:
#   zcode   ZCode rollout（~/.zcode/cli/rollout/model-io-sess_*.jsonl，按 cwd 匹配当前项目，取最新）
#   cc      Claude Code transcript JSONL（~/.claude/projects/<cwd 编码>/，仅当前项目，取最新）
#   proxy   usage 单对象 JSON 文件（CTX_PROXY_USAGE_FILE；无消息文本 → RCR 不可测，只报总量不触发）
#   stdin   JSONL 从标准输入喂入（测试/未来宿主接入；cc 与 zcode 双形态自适应）
#   auto    zcode → cc → proxy → n/a（默认；全程 fail-open，无源不报错）
#
# 退出码: 0=未命中/冷却中/不可得 ｜ 1=阈值命中（接 §4 归并）｜ 2=自身故障
# 状态锁: state 路径默认 ~/.agents/toolbox/state/ctx-cooldown.json，可用 CTX_STATE_FILE 覆盖（自测用）

import sys
import os
import json
import re
import time
import glob


def _int_env(key, default):
    try:
        return int(float(os.environ.get(key, default)))
    except (TypeError, ValueError):
        return default


def _float_env(key, default):
    try:
        return float(os.environ.get(key, default))
    except (TypeError, ValueError):
        return default


WINDOW_MAX = _int_env("CTX_WINDOW_MAX", 200000)
TOTAL_PCT = _float_env("CTX_TOTAL_PCT", 55)
RCR_PCT = _float_env("CTX_RCR_PCT", 20)
RECENT_K = _int_env("CTX_RECENT_K", 8000)
COOLDOWN_MIN = _float_env("CTX_COOLDOWN_MIN", 45)
STATE_FILE = os.environ.get("CTX_STATE_FILE") or os.path.join(
    os.path.expanduser("~/.agents/toolbox/state"), "ctx-cooldown.json"
)
PROXY_FILE = os.environ.get("CTX_PROXY_USAGE_FILE", "")

# Claude Code: snake_case ｜ ZCode rollout: camelCase
USAGE_KEYS = ("input_tokens", "inputTokens",
              "cache_read_input_tokens", "cacheReadTokens",
              "cache_creation_input_tokens", "cacheWriteTokens")


def est_tokens(obj):
    # 无 tokenizer 的量级估算（~4 字符/token）；只用于比例判断，不做成本核算
    try:
        s = obj if isinstance(obj, str) else json.dumps(obj, ensure_ascii=False)
    except (TypeError, ValueError):
        s = str(obj)
    return max(0, len(s) // 4)


def usage_input_side(u):
    if not isinstance(u, dict):
        return 0
    total = 0
    for k in USAGE_KEYS:
        try:
            total += int(u.get(k) or 0)
        except (TypeError, ValueError):
            pass  # 有意降级：统计容错，单个坏值字段跳过不影响整体估算
    return total


def parse_jsonl(fp):
    for line in fp:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if isinstance(rec, dict):
            yield rec


def analyze(records):
    # 双形态自适应：Claude Code（message.usage + message.content，逐条累积）
    # ｜ ZCode rollout（response.usage camelCase + request.messages 全量快照——
    # 每行重列整个对话，texts 只取末行，防重复累计）
    usages = []
    cc_texts = []
    zc_usages = []
    zc_last_est = []
    for rec in records:
        msg = rec.get("message")
        if isinstance(msg, dict):
            side = usage_input_side(msg.get("usage"))
            if side > 0:
                usages.append(side)
            if "content" in msg:
                cc_texts.append(est_tokens(msg.get("content")))
        req = rec.get("request")
        resp = rec.get("response")
        if isinstance(resp, dict) or isinstance(req, dict):
            side = usage_input_side(resp.get("usage")) if isinstance(resp, dict) else 0
            if side > 0:
                zc_usages.append(side)
            if isinstance(req, dict) and isinstance(req.get("messages"), list):
                zc_last_est = [est_tokens(m.get("content"))
                               for m in req["messages"] if isinstance(m, dict)]
    if zc_usages and not usages:
        usages, texts = zc_usages, zc_last_est
    else:
        texts = cc_texts
    return _metrics(usages, texts)


def _metrics(usages, texts):
    # usage < 2 条无法定常驻层 → None
    if len(usages) < 2:
        return None
    resident = usages[0]
    total = max(usages)  # 旁路小请求（摘要/标题生成）会污染末值，主对话上下文取峰值
    decayed = max(0, total - resident)
    acc = 0
    for t in reversed(texts):
        acc += t
        if acc >= RECENT_K:
            break
    rcr = (acc / decayed * 100.0) if decayed > 0 else 100.0
    return {
        "total": total,
        "resident": resident,
        "decayed": decayed,
        "recent": acc,
        "total_pct": total / WINDOW_MAX * 100.0,
        "resident_pct": resident / WINDOW_MAX * 100.0,
        "rcr": rcr,
    }


def cc_transcript():
    base = os.path.expanduser("~/.claude/projects")
    if not os.path.isdir(base):
        return None
    enc = os.getcwd().replace("/", "-")
    d = os.path.join(base, enc)
    if not os.path.isdir(d):
        return None  # 不做跨项目兜底——报别的会话的数比不报更糟
    cands = glob.glob(os.path.join(d, "*.jsonl"))
    if not cands:
        return None
    return max(cands, key=os.path.getmtime)


_ZC_USAGE_SPAN = re.compile(r'"usage"\s*:\s*\{[^{}]*\}')


def _side_from_span(span):
    total = 0
    for key in ("inputTokens", "input_tokens",
                "cacheReadTokens", "cache_read_input_tokens",
                "cacheWriteTokens", "cache_creation_input_tokens"):
        m = re.search(r'"%s"\s*:\s*(\d+)' % key, span)
        if m:
            total += int(m.group(1))
    return total


def zcode_sessions_db(cwd):
    # db 权威映射：session.directory = cwd 的会话 id（time_updated 降序）。
    # 只读连接，失败/无行一律返回 []（fail-open，不碰运行库写锁）
    db = os.path.expanduser("~/.zcode/cli/db/db.sqlite")
    if not os.path.isfile(db):
        return []
    try:
        import sqlite3
        con = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
        rows = con.execute(
            "select id from session where directory=? order by time_updated desc",
            (cwd,)).fetchall()
        con.close()
        return [r[0] for r in rows]
    except Exception:
        return []


def zcode_transcript():
    # ~/.zcode/cli/rollout/model-io-sess_*.jsonl 定位当前项目会话，两级匹配：
    # ① db session.directory 精确匹配（会话开场目录即工作区的常态）；
    # ② 兜底：mtime 新→旧探文件尾部 128KB 含 cwd（中途切工作区的会话——
    #    开场目录与 system prompt 锚点都会说谎，近期活动目录才是真归属）
    d = os.path.expanduser("~/.zcode/cli/rollout")
    if not os.path.isdir(d):
        return None
    cwd = os.getcwd()
    for sid in zcode_sessions_db(cwd):
        p = os.path.join(d, "model-io-%s.jsonl" % sid)
        if os.path.isfile(p):
            return p
    files = sorted(glob.glob(os.path.join(d, "model-io-*.jsonl")),
                   key=os.path.getmtime, reverse=True)
    for p in files[:5]:
        try:
            with open(p, encoding="utf-8", errors="replace") as f:
                f.seek(0, os.SEEK_END)
                size = f.tell()
                # 渐进尾窗：大 tool_result 行会把 cwd 段挤出小窗口（实测最远 1.4MB）
                for win in (262144, 1048576, 4194304):
                    f.seek(max(0, size - win))
                    if cwd in f.read(win):
                        return p
        except OSError:
            continue
    return None


def zcode_analyze_file(path):
    # 大文件优化：usage 经正则从行内提取（全量 json 解析 56MB 实测 1.8s，不可接受）；
    # 峰值行完整解析（取该行 request.messages 文本估近窗 RCR——旁路小请求的消息集不代表主对话）
    usages = []
    peak_line = None
    peak_side = 0
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                if '"usage"' not in line:
                    continue
                spans = _ZC_USAGE_SPAN.findall(line)
                if not spans:
                    continue
                side = _side_from_span(spans[-1])
                if side > 0:
                    usages.append(side)
                    if side > peak_side:
                        peak_side = side
                        peak_line = line
    except OSError:
        return None
    texts = []
    if peak_line:
        try:
            r = json.loads(peak_line)
            req = r.get("request")
            if isinstance(req, dict) and isinstance(req.get("messages"), list):
                texts = [est_tokens(m.get("content"))
                         for m in req["messages"] if isinstance(m, dict)]
        except ValueError:
            pass  # 有意降级：peak 行 JSON 损坏则视为无样例，仅影响估算精度
    return _metrics(usages, texts)


def load_proxy_total():
    if not PROXY_FILE or not os.path.isfile(PROXY_FILE):
        return None
    try:
        with open(PROXY_FILE, encoding="utf-8") as f:
            u = json.load(f)
    except (OSError, ValueError):
        return None
    side = usage_input_side(u)
    return side if side > 0 else None


def cooldown_left():
    try:
        with open(STATE_FILE, encoding="utf-8") as f:
            ts = float(json.load(f).get("ts", 0))
    except (OSError, ValueError, AttributeError):
        return 0.0
    rem = COOLDOWN_MIN * 60 - (time.time() - ts)
    return rem if rem > 0 else 0.0


def mark_merged():
    d = os.path.dirname(STATE_FILE)
    if d and not os.path.isdir(d):
        os.makedirs(d, exist_ok=True)
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump({"ts": time.time(), "iso": time.strftime("%Y-%m-%dT%H:%M:%S")}, f)


def pct(v):
    return "%.0f%%" % v


def decide(m):
    hit = m["total_pct"] >= TOTAL_PCT and m["rcr"] < RCR_PCT
    if hit and cooldown_left() > 0:
        return "cooldown"
    return "hit" if hit else "ok"


def probe_zcode():
    # 返回 (指标 dict 或 None, 失败归因或 None)——归因区分 未装/无本会话/数据不足
    if not os.path.isdir(os.path.expanduser("~/.zcode/cli/rollout")):
        return None, "未装"
    path = zcode_transcript()
    if path is None:
        return None, "无本会话"
    m = zcode_analyze_file(path)
    if m is None:
        return None, "会话数据不足"
    m["kind"] = "zcode"
    return m, None


def probe_cc():
    if not os.path.isdir(os.path.expanduser("~/.claude/projects")):
        return None, "未装"
    path = cc_transcript()
    if path is None:
        return None, "无本会话"
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            m = analyze(parse_jsonl(f))
    except OSError:
        return None, "会话数据不足"
    if m is None:
        return None, "会话数据不足"
    m["kind"] = "cc"
    return m, None


def probe_proxy():
    if not PROXY_FILE:
        return None, "未配置"
    total = load_proxy_total()
    if total is None:
        return None, "文件无效"
    return {"kind": "proxy", "total_pct": total / WINDOW_MAX * 100.0}, None


PROBES = {"zcode": probe_zcode, "cc": probe_cc, "proxy": probe_proxy}


def render_brief(res):
    if res is None:
        return "n/a"
    if res["kind"] == "na":
        return "n/a(" + "/".join(res["reasons"]) + ")"
    if res["kind"] == "proxy":
        return "%s（RCR n/a）" % pct(res["total_pct"])
    tag = {"ok": "", "hit": "⚠", "cooldown": "·冷却"}[res["verdict"]]
    return "%s｜RCR %s｜常驻 %s%s" % (pct(res["total_pct"]), pct(res["rcr"]), pct(res["resident_pct"]), tag)


def render_bare(res):
    if res is None:
        return "ctx: n/a（探测异常——fail-open）"
    if res["kind"] == "na":
        return "ctx: n/a（" + "｜".join(res["reasons"]) + "——fail-open 不触发）"
    if res["kind"] == "proxy":
        base = "ctx: 总量 %s（proxy 源——RCR 不可测，不触发）" % pct(res["total_pct"])
        if res["total_pct"] >= TOTAL_PCT:
            return base + "｜总量超阈值——建议宿主 compact/重置窗口"
        return base
    base = "ctx: 总量 %s｜常驻 %s｜RCR %s" % (pct(res["total_pct"]), pct(res["resident_pct"]), pct(res["rcr"]))
    if res["verdict"] == "hit":
        return "%s ⚠ 命中——建议 ::merge 归并后重置窗口（或宿主 compact）" % base
    if res["verdict"] == "cooldown":
        return "%s（冷却中——不触发归并；总量高可宿主 compact/重置窗口）" % base
    if res["total_pct"] >= TOTAL_PCT:
        return "%s｜RCR 高——归并无益，建议宿主 compact/重置窗口" % base
    return base


def render_json(res):
    # message/remedy 内禁双引号（toolbox spec §2 --json 硬契约）
    if res is None:
        return {"status": "OK", "severity": "info",
                "message": "ctx n/a: 探测异常, fail-open 不触发"}
    if res["kind"] == "na":
        return {"status": "OK", "severity": "info",
                "message": "ctx n/a: " + ", ".join(res["reasons"]) + ", fail-open 不触发",
                "remedy": "已装宿主无本会话属常态; 需探测时 stdin 喂会话或配置 CTX_PROXY_USAGE_FILE"}
    if res["kind"] == "proxy":
        msg = "ctx proxy 源: 总量%s, RCR 不可测不触发" % pct(res["total_pct"])
        if res["total_pct"] >= TOTAL_PCT:
            return {"status": "OK", "severity": "warn",
                    "message": msg, "remedy": "总量超阈值: 建议宿主 compact/重置窗口"}
        return {"status": "OK", "severity": "info", "message": msg}
    if res["verdict"] == "hit":
        return {"status": "FAIL", "severity": "warn",
                "message": "ctx 命中: 总量%s 常驻%s RCR%s（阈值 RCR<%s）" % (
                    pct(res["total_pct"]), pct(res["resident_pct"]), pct(res["rcr"]), pct(RCR_PCT)),
                "remedy": "非排错态: ::merge 归并后重置窗口并 --mark-merged（或宿主 compact）; 排错态: 仅提示不归并"}
    if res["verdict"] == "cooldown":
        return {"status": "OK", "severity": "info",
                "message": "ctx 达阈值但冷却中(%g 分钟窗): 不触发, 总量高可宿主 compact" % COOLDOWN_MIN}
    if res["total_pct"] >= TOTAL_PCT:
        return {"status": "OK", "severity": "warn",
                "message": "ctx 总量%s 但 RCR 高%s: 归并无益" % (
                    pct(res["total_pct"]), pct(res["rcr"])),
                "remedy": "建议宿主 compact/重置窗口"}
    return {"status": "OK", "severity": "info",
            "message": "ctx 正常: 总量%s 常驻%s RCR%s" % (pct(res["total_pct"]), pct(res["resident_pct"]), pct(res["rcr"]))}


def collect(source):
    # 返回结果 dict：命中/正常/冷却（含 kind/verdict）或 {"kind":"na","reasons":[...]}
    # n/a 逐源带归因——区分 未装（宿主不存在）/ 无本会话（目录在但没匹配到当前项目）/
    # 会话数据不足 / 未配置 / 文件无效，让人与 AI 不用二次猜
    if source == "stdin":
        m = analyze(parse_jsonl(sys.stdin))
        if m is None:
            return {"kind": "na", "reasons": ["stdin:样本不足（usage<2 条）"]}
        m["kind"] = "stdin"
        m["verdict"] = decide(m)
        return m
    if source in PROBES:
        m, reason = PROBES[source]()
        if m is None:
            return {"kind": "na", "reasons": ["%s:%s" % (source, reason)]}
        if m["kind"] != "proxy":
            m["verdict"] = decide(m)
        return m
    # auto: zcode → cc → proxy，逐源留归因
    reasons = []
    for name in ("zcode", "cc", "proxy"):
        m, reason = PROBES[name]()
        if m is not None:
            if name != "proxy":
                m["verdict"] = decide(m)
            return m
        reasons.append("%s:%s" % (name, reason))
    return {"kind": "na", "reasons": reasons}


def emit(res, brief=False, as_json=False):
    if as_json:
        d = render_json(res)
        order = ["status", "severity", "message", "remedy"]
        print(json.dumps({k: d[k] for k in order if k in d},
                         ensure_ascii=False, separators=(",", ":")))
        return
    print(render_brief(res) if brief else render_bare(res))


def self_test():
    import subprocess
    import tempfile

    here = os.path.abspath(__file__)
    ok = True

    def run(args, stdin_text="", env_extra=None):
        env = dict(os.environ)
        env.update(env_extra or {})
        return subprocess.run(
            [sys.executable, here] + args, input=stdin_text,
            capture_output=True, text=True, env=env,
        )

    thr = {"CTX_WINDOW_MAX": "200000", "CTX_TOTAL_PCT": "55",
           "CTX_RCR_PCT": "20", "CTX_RECENT_K": "8000",
           "CTX_STATE_FILE": tempfile.mktemp(suffix=".json")}

    # 样本: 常驻层 12k，末端总量 128k（衰减层 116k >= 110k），尾部消息极小 → RCR≈0 → 命中
    jsonl = "\n".join([
        json.dumps({"message": {"role": "user", "content": "初始需求说明"}, }),
        json.dumps({"message": {"role": "assistant", "content": [{"type": "text", "text": "收到"}],
                                "usage": {"input_tokens": 10000,
                                          "cache_read_input_tokens": 2000}}}),
        json.dumps({"message": {"role": "user", "content": "继续"}}),
        json.dumps({"message": {"role": "assistant", "content": [{"type": "text", "text": "好的"}],
                                "usage": {"input_tokens": 8000,
                                          "cache_read_input_tokens": 120000}}}),
        json.dumps({"message": {"role": "user", "content": "报错如下"}}),
    ]) + "\n"

    # 用例 1: 命中 → exit 1，输出含 ⚠
    r = run(["--source", "stdin"], jsonl, thr)
    if r.returncode != 1 or "⚠" not in r.stdout:
        print("self-test: 用例1 应命中 exit 1: rc=%s out=%s" % (r.returncode, r.stdout.strip()))
        ok = False

    # 用例 2: 大尾部输出（~25000 token）→ RCR 21% 高于阈值 → 不命中 exit 0
    big = jsonl + json.dumps(
        {"message": {"role": "assistant", "content": [{"type": "text", "text": "x" * 100000}]}}) + "\n"
    r = run(["--source", "stdin"], big, thr)
    if r.returncode != 0 or "宿主 compact" not in r.stdout:
        print("self-test: 用例2 高 RCR 不应命中且应提示 compact: rc=%s out=%s" % (r.returncode, r.stdout.strip()))
        ok = False

    # 用例 3: --mark-merged 落锁 → 同样本再跑降级冷却 exit 0
    r = run(["--mark-merged"], "", thr)
    if r.returncode != 0 or "冷却" not in r.stdout:
        print("self-test: 用例3 mark-merged 失败: %s %s" % (r.stdout.strip(), r.stderr.strip()))
        ok = False
    r = run(["--source", "stdin"], jsonl, thr)
    if r.returncode != 0 or "冷却" not in r.stdout:
        print("self-test: 用例3 冷却未生效: rc=%s out=%s" % (r.returncode, r.stdout.strip()))
        ok = False

    # 用例 4: 空输入 → n/a fail-open exit 0
    r = run(["--source", "stdin"], "", thr)
    if r.returncode != 0 or "n/a" not in r.stdout:
        print("self-test: 用例4 空输入应 n/a: rc=%s out=%s" % (r.returncode, r.stdout.strip()))
        ok = False

    # 用例 5: 命中时 --json 单行 FAIL 契约（独立状态文件，隔离用例 3 的冷却锁）
    thr5 = dict(thr, CTX_STATE_FILE=tempfile.mktemp(suffix=".json"))
    r = run(["--source", "stdin", "--json"], jsonl, thr5)
    line = r.stdout.strip()
    if (r.returncode != 1 or line.count("\n") != 0
            or not line.startswith('{"status":"FAIL"')):
        print("self-test: 用例5 json 契约不符: rc=%s out=%s" % (r.returncode, line[:120]))
        ok = False

    # 用例 6: --brief 紧凑格式（面板嵌入；同样独立状态文件）
    thr6 = dict(thr, CTX_STATE_FILE=tempfile.mktemp(suffix=".json"))
    r = run(["--source", "stdin", "--brief"], jsonl, thr6)
    if r.returncode != 1 or "RCR" not in r.stdout or "⚠" not in r.stdout \
            or "常驻 6%" not in r.stdout:
        print("self-test: 用例6 brief 格式不符: %s" % r.stdout.strip())
        ok = False

    # 用例 7: ZCode rollout 形态（camelCase usage + request.messages 全量快照）→ 命中
    zc = "\n".join([
        json.dumps({"sessionId": "s1", "request": {"messages": [
            {"role": "user", "content": "初始需求说明"}]},
            "response": {"usage": {"inputTokens": 10000, "cacheReadTokens": 2000,
                                   "cacheWriteTokens": 0}}}),
        json.dumps({"sessionId": "s1", "request": {"messages": [
            {"role": "user", "content": "报错如下"}]},
            "response": {"usage": {"inputTokens": 8000, "cacheReadTokens": 120000,
                                   "cacheWriteTokens": 0}}}),
    ]) + "\n"
    thr7 = dict(thr, CTX_STATE_FILE=tempfile.mktemp(suffix=".json"))
    r = run(["--source", "stdin"], zc, thr7)
    if r.returncode != 1 or "⚠" not in r.stdout:
        print("self-test: 用例7 zcode 形态应命中: rc=%s out=%s" % (r.returncode, r.stdout.strip()))
        ok = False

    for p in (thr["CTX_STATE_FILE"],):
        try:
            os.unlink(p)
        except OSError:
            pass  # 有意降级：self-test 临时文件清理尽力而为，残留无影响
    print("self-test: OK" if ok else "self-test: FAIL")
    return 0 if ok else 2


def main():
    args = sys.argv[1:]
    if "--help" in args or "-h" in args:
        print(__doc__.strip() + "\n\n用法: ctx-ratio.py [--source auto|cc|proxy|stdin] [--brief] [--json] "
                                 "[--mark-merged] [--self-test|--help]\n"
                                 "  --brief   紧凑单 token（panel 状态行嵌入）\n"
                                 "  --json    一行 JSON 契约结论\n"
                                 "  --mark-merged 落冷却锁（归并完成后由 AI 按协议执行）")
        return 0
    if "--self-test" in args:
        return self_test()
    brief = "--brief" in args
    as_json = "--json" in args
    if "--mark-merged" in args:
        mark_merged()
        print("ctx: 冷却锁已落 %s（%s 分钟内不重复触发）"
              % (time.strftime("%Y-%m-%dT%H:%M:%S"), _float_env("CTX_COOLDOWN_MIN", 45)))
        return 0
    source = "auto"
    if "--source" in args:
        i = args.index("--source")
        if i + 1 >= len(args):
            print("FAIL: --source 需要值 auto|cc|proxy|stdin", file=sys.stderr)
            return 2
        source = args[i + 1]
        if source not in ("auto", "zcode", "cc", "proxy", "stdin"):
            print("FAIL: 未知 --source: %s" % source, file=sys.stderr)
            return 2
    try:
        res = collect(source)
    except Exception as e:  # 自身故障才 2；探测失败一律 fail-open
        if as_json:
            print(json.dumps({"status": "FAIL", "severity": "error",
                              "message": "ctx-ratio 自身故障: %s" % type(e).__name__}, ensure_ascii=False))
        else:
            print("[remedy] 探测异常(%s): 检查数据源后重试, 或忽略——本工具 fail-open" % type(e).__name__,
                  file=sys.stderr)
        return 2
    emit(res, brief=brief, as_json=as_json)
    if res is not None and res.get("verdict") == "hit":
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
