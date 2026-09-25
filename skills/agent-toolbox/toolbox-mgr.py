#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
toolbox-mgr — 全局脚本工具箱管理器（规范 SSOT + 执行器）。

人类与 AI 共用同一命令入口；无 AI 时可独立完成全部管理动作。
推荐经 shim 调用: toolbox <command> [options]
源码唯一正身: ~/.agents/skills/agent-toolbox/toolbox-mgr.py（只搬运，严禁重生/手改副本）。

命令:
  init [--project]       初始化全局池目录与 shim（幂等）；--project 附加初始化当前仓库项目池
  new <name> [--lang sh|python] [--scope global|project] [--trigger T] [--summary S]
                         生成脚本脚手架（默认 sh——shell 一等公民优先）
  check <path> [--scope global|project] [--force]
                         校验脚本合规（头部/help/--json/self-test/语言门禁/密钥扫描）并移入工具池
  list [--json]          派生工具清单（扫描两级池，⚠ = 不合规；last_run 由使用台账派生）
  run-hooks <hook> [--quiet] [--json] [--notify]
                         执行该钩子下全部工具；任一 FAIL → exit 1（工具自身故障 fail-open）
  install-hooks [--remove]
                         接线/卸载：profile 登录检查 + cron 巡检 + 当前仓库 pre-commit
  spec                   打印脚本编写规范（规范唯一事实源，内嵌本文件）
  remove <name> [--yes]  退役：移入 ~/.agents/toolbox/.trash/
  self-test              元工具自检（金丝雀）

全局退出码契约（元工具与所有工具脚本一致）:
  0 = 通过 / 1 = 检查未通过 / 2 = 自身故障
"""

import argparse
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

VERSION = "1.4"
HOME = Path.home()
TOOLBOX_DIR = HOME / ".agents" / "toolbox"
SCRIPTS_DIR = TOOLBOX_DIR / "scripts"
STATE_DIR = TOOLBOX_DIR / "state"
LEDGER_FILE = STATE_DIR / "usage-ledger.jsonl"
PARAMS_FILE = TOOLBOX_DIR / "params.env"          # 全局参数配置（手工维护）
PROJECT_PARAMS_NAME = ".toolbox.env"              # 项目参数配置（<repo>/.toolbox.env，项目覆盖全局）
TRASH_DIR = TOOLBOX_DIR / ".trash"
MGR_PATH = Path(__file__).resolve()
MARKER_BEGIN = "# >>> toolbox-mgr >>>"
MARKER_END = "# <<< toolbox-mgr <<<"
CRON_TAG = "# toolbox-mgr:cron"
TRIGGERS = ("bootstrap", "audit", "cron", "pre-commit", "manual")
VERBS = ("run", "stop", "status", "restart")  # 服务类动词：经 run 路由，脚本须支持同名首参
IS_WIN = platform.system() == "Windows"
IS_MAC = platform.system() == "Darwin"

FIELD_RE = re.compile(r"^([a-zA-Z][a-zA-Z0-9_-]*):\s*(\S.*)$")
NAME_RE = re.compile(r"^[a-z][a-z0-9-]{1,40}$")
IMPORT_RE = re.compile(r"^\s*(?:import|from)\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)


# ---------- 平台适配层：全部平台差异锁在此处；探测不到即降级，严禁阻塞主功能 ----------

class Adapter:
    def shim_file(self):
        if IS_WIN:
            return HOME / "toolbox.cmd"
        return HOME / ".local" / "bin" / "toolbox"

    def profile_file(self):
        if IS_WIN:
            return None
        for p in (HOME / ".zshrc", HOME / ".bashrc"):
            if p.is_file():
                return p
        return HOME / ".bashrc"

    def notify(self, msg):
        if not IS_WIN and shutil.which("notify-send"):
            run_cmd(["notify-send", "toolbox", msg], 5)
            return
        if IS_MAC and shutil.which("osascript"):
            safe = msg.replace('"', "'")
            run_cmd(["osascript", "-e",
                     'display notification "%s" with title "toolbox"' % safe], 5)
            return
        print(msg)  # 降级：打印兜底

    def cron_supported(self):
        return not IS_WIN and shutil.which("crontab") is not None

    def shim_content(self):
        if IS_WIN:
            return '@echo off\r\npython3 "%s" %%*\r\n' % MGR_PATH
        return '#!/bin/sh\nexec python3 "%s" "$@"\n' % MGR_PATH


def install_shim():
    a = Adapter()
    shim = a.shim_file()
    shim.parent.mkdir(parents=True, exist_ok=True)
    shim.write_text(a.shim_content(), encoding="utf-8")
    if not IS_WIN:
        shim.chmod(0o755)
        path_dirs = os.environ.get("PATH", "").split(os.pathsep)
        if str(shim.parent) not in path_dirs:
            print("⚠ %s 不在 PATH 中，请加入后即可直接使用 toolbox 命令" % shim.parent)
    return shim


# ---------- 头部规范 v1：解析与校验（收集器只认 docstring 内 toolbox-script 标记块） ----------

def parse_header(path):
    """返回 (meta, problems)。只认 'toolbox-script' 标记行之后的连续字段区；
    遇首个非字段/非空/非引号行即结束，块外内容一律忽略。
    双语言载体：python 写在 docstring 内；shell 写在连续 # 注释内（剥 # 后同语法解析）。"""
    meta, problems = {}, []
    try:
        lines = Path(path).read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError) as e:
        return {}, ["无法读取文件: %s" % e]
    in_block = False
    for raw in lines:
        s = raw.strip()
        if s.lstrip("#").strip() == "toolbox-script":
            if in_block:
                problems.append("toolbox-script 标记块重复")
            in_block = True
            continue
        if not in_block:
            continue
        if s.startswith("#"):  # shell 注释载体：剥 # 后按同一字段语法解析
            s = s.lstrip("#").strip()
        if s in ("", '"""', "'''"):
            continue
        m = FIELD_RE.match(s)
        if not m:
            in_block = False
            continue
        key = m.group(1).lower()
        if key in meta:
            problems.append("头部字段重复: %s" % key)
            continue
        meta[key] = m.group(2).strip()
    if not meta and not problems:
        problems.append("未找到 toolbox-script 头部块")
    return meta, problems


def validate_meta(meta):
    problems = []
    for req in ("format", "name", "summary", "trigger"):
        if req not in meta:
            problems.append("缺少必填头部字段: %s" % req)
    if meta.get("format") is not None and meta["format"] != "v1":
        problems.append("format 必须为 v1")
    if meta.get("trigger") is not None and meta["trigger"] not in TRIGGERS:
        problems.append("trigger 非法: %s（可选: %s）" % (meta["trigger"], "|".join(TRIGGERS)))
    if meta.get("platform", "any") not in ("any", "unix", "linux", "darwin", "windows"):
        problems.append("platform 非法: %s" % meta.get("platform"))
    name = meta.get("name")
    if name is not None and not NAME_RE.match(name):
        problems.append("name 非法（小写字母开头，小写字母/数字/连字符）: %s" % name)
    raw_alias = meta.get("alias")
    if raw_alias is not None:
        for a in [x.strip() for x in raw_alias.split(",") if x.strip()]:
            if not NAME_RE.match(a):
                problems.append("alias 非法（同 name 规则，逗号分隔）: %s" % a)
    raw_params = meta.get("params")
    if raw_params is not None:
        for k in [x.strip() for x in raw_params.split(",") if x.strip()]:
            if not re.match(r"^[A-Z][A-Z0-9_]*$", k):
                problems.append("params 非法（大写字母/数字/下划线，逗号分隔）: %s" % k)
    raw_verbs = meta.get("verbs")
    if raw_verbs is not None:
        for v in [x.strip() for x in raw_verbs.split(",") if x.strip()]:
            if v not in VERBS:
                problems.append("verbs 非法（可选: %s）: %s" % ("|".join(VERBS), v))
    raw_cat = meta.get("cat")
    if raw_cat is not None and not NAME_RE.match(raw_cat):
        problems.append("cat 非法（同 name 规则，单个类别）: %s" % raw_cat)
    return problems


def stdlib_problems(path):
    stdlib = getattr(sys, "stdlib_module_names", None)
    if not stdlib:
        return []  # Python < 3.10 无法静态校验，跳过
    try:
        text = Path(path).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return []
    bad = sorted({m for m in IMPORT_RE.findall(text)
                  if m not in stdlib and m != "__future__"})
    return ["引入非标准库: %s" % m for m in bad]


# ---------- 密钥形状扫描（登记门禁）：命中即拒收，杜绝硬编码凭证 ----------

SECRET_RES = (
    ("AWS AKIA", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("GitHub token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}\b")),
    ("OpenAI sk-", re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b")),
    ("Google API key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("Slack token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b")),
    ("私钥块", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY( BLOCK)?-----")),
    ("字面量口令", re.compile(
        r"(?i)(?<![a-z])(?:password|passwd|pwd|secret|api[_-]?key|access[_-]?key|"
        r"auth[_-]?token|token)\b['\"]?\s*[:=]\s*['\"]([^'\"\n$<{]{8,})['\"]")),
)


def secret_problems(path):
    """逐行扫描已知凭证形状与字面量口令；占位符（$VAR/${VAR}/{x}）与 env 引用放行。"""
    try:
        lines = Path(path).read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        return []
    hits = []
    for no, line in enumerate(lines, 1):
        for label, rx in SECRET_RES:
            if rx.search(line):
                hits.append("疑似硬编码密钥(第 %d 行, %s)" % (no, label))
                break
        if len(hits) >= 3:
            break
    if len(hits) >= 3:
        hits.append("疑似硬编码密钥: 仅列前 3 处")
    return hits


# ---------- 语言双通道 v1.1：shell 一等公民优先，python 兜底 ----------

def detect_lang(path):
    return "shell" if Path(path).suffix == ".sh" else "python"


def shebang_problems(path, lang):
    """语言门禁（shebang）：python → python*；shell → sh/bash/dash/zsh。"""
    try:
        first = Path(path).read_text(encoding="utf-8", errors="replace").splitlines()[0].strip()
    except (OSError, IndexError):
        return ["缺少 shebang 首行"]
    if not first.startswith("#!"):
        return ["缺少 shebang 首行: %s" % first[:60]]
    body = first[2:].strip()
    if lang == "python":
        return [] if "python" in body else ["shebang 必须指向 python: %s" % first[:60]]
    tok = body.split()[-1] if body.split() else ""
    if tok.rsplit("/", 1)[-1] in ("sh", "bash", "dash", "zsh", "ash"):
        return []
    return ["shebang 必须为 #!/bin/sh 或 #!/usr/bin/env bash: %s" % first[:60]]


def interpreter_for(path, lang):
    """运行入口：python 用当前解释器；shell 按 shebang 选 sh/bash（Windows 拒收 shell）。"""
    if lang == "shell":
        try:
            first = Path(path).read_text(encoding="utf-8", errors="replace").splitlines()[0]
        except (OSError, IndexError):
            first = ""
        return ["bash"] if "bash" in first else ["sh"]
    return [sys.executable]


def run_cmd(args, timeout=15):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout or ""), (p.stderr or "")
    except subprocess.TimeoutExpired:
        return 124, "", "超时(%ss)" % timeout
    except FileNotFoundError:
        return 127, "", "命令不存在: %s" % args[0]
    except OSError as e:
        return 126, "", str(e)


# ---------- 仓库定位 ----------

def find_repo_root(start):
    p = Path(start).resolve()
    for c in [p] + list(p.parents):
        if (c / ".git").exists():
            return c
    return None


def project_scripts_dir():
    root = find_repo_root(Path.cwd())
    if root is None:
        return None
    return root / "scripts" / "agent-tools"

# ---------- 清单派生（无注册表：扫描即事实） ----------

def collect():
    """扫描两级工具池。项目池同名工具覆盖全局池；不合规项保留并标 problems。"""
    pd = project_scripts_dir()
    pools = [("global", SCRIPTS_DIR)]
    if pd:
        pools.append(("project", pd))
    entries, index = [], {}
    for scope, d in pools:
        if not d.is_dir():
            continue
        for f in sorted(list(d.glob("*.py")) + list(d.glob("*.sh"))):
            lang = detect_lang(f)
            meta, problems = parse_header(f)
            if meta:
                problems += validate_meta(meta)
            if lang == "python":
                problems += stdlib_problems(f)
            else:
                problems += shebang_problems(f, lang)
                if meta.get("platform", "any") == "any":
                    problems.append("shell 工具 platform 必须为 unix（或 linux/darwin）")
            problems += secret_problems(f)
            name = meta.get("name") or ("?" + f.stem)
            e = {"name": name, "file": str(f), "scope": scope,
                 "trigger": meta.get("trigger", "?"),
                 "platform": meta.get("platform", "any"),
                 "alias": [x.strip() for x in (meta.get("alias") or "").split(",")
                           if x.strip()],
                 "params": [x.strip() for x in (meta.get("params") or "").split(",")
                            if x.strip()],
                 "verbs": [x.strip() for x in (meta.get("verbs") or "").split(",")
                           if x.strip()],
                 "cat": meta.get("cat") or "",
                 "summary": meta.get("summary", ""),
                 "problems": problems, "overridden": False}
            prev = index.get(name)
            if prev is not None:
                if scope == "project" and prev["scope"] == "global":
                    prev["overridden"] = True
                    index[name] = e
                else:
                    e["overridden"] = True  # 同池重名：后到者视为冗余
            else:
                index[name] = e
            entries.append(e)
    return entries


def platform_ok(e):
    p = e["platform"]
    cur = "windows" if IS_WIN else ("darwin" if IS_MAC else "linux")
    if p == "any":
        return True
    if p == "unix":
        return cur in ("linux", "darwin")
    return p == cur


def parse_verdict(out):
    """解析工具 --json 契约结论：优先整体 stdout，退回最后一行非空输出。"""
    out = (out or "").strip()
    if not out:
        return None
    cands = [out]
    last = out.splitlines()[-1].strip()
    if last and last != out:
        cands.append(last)
    for cand in cands:
        try:
            v = json.loads(cand)
        except ValueError:
            continue
        if isinstance(v, dict) and "status" in v:
            return v
    return None


# ---------- usage ledger：逐次使用流水（append-only，fail-open） ----------

def record_usage(name, scope, rc, ms, src):
    """追加一行使用流水；台账故障绝不影响工具执行。"""
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        rec = {"ts": datetime.now().isoformat(timespec="seconds"),
               "name": name, "scope": scope, "exit": rc, "ms": ms, "src": src}
        with LEDGER_FILE.open("a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except OSError:
        pass


def load_last_runs():
    """从台账派生每工具最近一次运行时间（坏行/缺文件静默降级为空）。"""
    last = {}
    try:
        lines = LEDGER_FILE.read_text(encoding="utf-8").splitlines()
    except OSError:
        return last
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        name, ts = rec.get("name"), rec.get("ts")
        if name and ts and (name not in last or ts > last[name]):
            last[name] = ts
    return last


# ---------- list / check ----------

def cmd_list(args):
    entries = collect()
    if getattr(args, "cat", None):
        entries = [e for e in entries if e["cat"] == args.cat]
    last_runs = load_last_runs()
    if args.json:
        slim = []
        for e in entries:
            d = {k: e[k] for k in ("name", "scope", "trigger", "platform",
                                   "alias", "verbs", "cat", "summary", "problems", "file")}
            d["last_run"] = last_runs.get(e["name"])
            slim.append(d)
        print(json.dumps(slim, ensure_ascii=False, indent=2))
        return 0
    if not entries:
        cat = getattr(args, "cat", None)
        print("(空) 无%s工具。用 `toolbox new <name>` 生成脚手架，或 `toolbox check <path>` 登记现有脚本。"
              % (("类别 %s 的" % cat) if cat else ""))
        if cat:
            known = sorted({e["cat"] for e in collect() if e["cat"]})
            if cat not in known:
                print("提示: 类别 %r 不存在。池内现有类别: %s（惯例类目: "
                      "build=构建 test=测试 deploy=部署 env=环境 ops=服务运维 docs=文档校验）"
                      % (cat, ",".join(known) or "无"))
        return 0
    rows = []
    for e in entries:
        extra = ""
        if e["overridden"]:
            extra += "  (被项目池覆盖)"
        if e["problems"]:
            extra += "  ⚠ " + e["problems"][0]
        if e["cat"]:
            extra += "  [%s]" % e["cat"]
        if e["verbs"]:
            extra += "  [服务型 verbs: %s]" % ",".join(e["verbs"])
        if e["alias"]:
            extra += "  (别名: %s)" % ",".join(e["alias"])
        rows.append((e["name"], e["scope"], e["trigger"],
                     last_runs.get(e["name"], "-"), e["summary"] + extra))
    if sys.stdout.isatty():
        w1 = max(len(r[0]) for r in rows + [("name", "", "", "", "")])
        w2 = max(len(r[1]) for r in rows + [("", "scope", "", "", "")])
        w3 = max(len(r[2]) for r in rows + [("", "", "trigger", "", "")])
        w4 = max(len(r[3]) for r in rows + [("", "", "", "last_run", "")])
        print("%-*s  %-*s  %-*s  %-*s  %s" % (w1, "name", w2, "scope", w3, "trigger", w4, "last_run", "summary"))
        for r in rows:
            print("%-*s  %-*s  %-*s  %-*s  %s" % (w1, r[0], w2, r[1], w3, r[2], w4, r[3], r[4]))
    else:
        for r in rows:
            print("%s\t%s\t%s\t%s\t%s" % r)
    return 0


def cmd_check(args):
    src = Path(args.path).expanduser().resolve()
    if not src.is_file():
        print("✗ 文件不存在: %s" % src)
        return 2
    if src.suffix not in (".py", ".sh"):
        print("✗ 仅支持 .py / .sh 脚本: %s" % src.name)
        return 1
    lang = detect_lang(src)
    meta, problems = parse_header(src)
    problems += validate_meta(meta)
    expected = (meta.get("name") or "") + src.suffix
    if meta.get("name") and src.name != expected:
        problems.append("文件名必须与 name 一致: 应为 %s" % expected)
    problems += secret_problems(src)
    if lang == "python":
        problems += stdlib_problems(src)
    else:
        if IS_WIN:
            problems.append("shell 工具不支持 Windows（spec: shell 不入 Windows 池）")
        problems += shebang_problems(src, lang)
        if meta.get("platform", "any") == "any":
            problems.append("shell 工具 platform 必须为 unix（或 linux/darwin）")
        if not IS_WIN:
            rc, _, err = run_cmd(interpreter_for(src, lang) + ["-n", str(src)], 15)
            if rc != 0:
                problems.append("shell 语法检查未通过(-n): %s" % (err or "").strip()[:200])
    if problems:
        print("✗ 头部/静态检查未通过:")
        for p in problems:
            print("  - %s" % p)
        return 1
    rc, out, err = run_cmd(interpreter_for(src, lang) + [str(src), "--help"], 15)
    if rc != 0:
        print("✗ --help 退出码 %d（argparse 必须实现标准 --help）\n%s"
              % (rc, (err or out).strip()[:300]))
        return 1
    rc, out, err = run_cmd(interpreter_for(src, lang) + [str(src), "--json"], 15)
    verdict = parse_verdict(out)
    if rc not in (0, 1) or verdict is None or verdict.get("status") not in ("OK", "FAIL"):
        print("✗ --json 未输出契约结论 {status,severity,message}（退出码 %d）\n%s"
              % (rc, (out + err).strip()[-300:]))
        return 1
    st = meta.get("self-test")
    if not st:
        if meta.get("trigger") != "manual":
            print("✗ 钩子型工具（trigger≠manual）必须声明 self-test 参数（金丝雀）")
            return 1
    else:
        rc, out, err = run_cmd(interpreter_for(src, lang) + [str(src), st], 15)
        if rc != 0:
            print("✗ self-test 退出码 %d:\n%s" % (rc, (out + err).strip()[-300:]))
            return 1
    scope = args.scope
    if scope == "project":
        d = project_scripts_dir()
        if d is None:
            print("✗ 当前不在 git 仓库内，项目池不可用；用 --scope global 或先进入仓库")
            return 2
    else:
        d = SCRIPTS_DIR
    d.mkdir(parents=True, exist_ok=True)
    dest = d / src.name
    if dest.exists() and not args.force:
        print("✗ 目标已存在: %s（覆盖用 --force，退役用 toolbox remove %s）"
              % (dest, meta["name"]))
        return 1
    if dest.exists():
        dest.unlink()
    shutil.move(str(src), str(dest))
    if lang == "shell":
        dest.chmod(0o755)
    print("✓ 已登记: [%s] %s → %s" % (scope, meta["name"], dest))
    return 0

# ---------- run-hooks：执行钩子（FAIL→exit1；工具自身故障 fail-open） ----------

def cmd_run_hooks(args):
    hook = args.hook
    if hook not in TRIGGERS:
        print("✗ 未知钩子: %s（可选: %s）" % (hook, "|".join(TRIGGERS)))
        return 2
    if hook == "manual":
        print("✗ manual 不是自动钩子；手动工具直接运行即可")
        return 2
    results = []
    for e in collect():
        if e["overridden"] or e["trigger"] != hook:
            continue
        if e["problems"]:
            record_usage(e["name"], e["scope"], 2, 0, "hook:" + hook)
            results.append({"name": e["name"], "scope": e["scope"], "status": "ERROR",
                            "severity": "error",
                            "message": "不合规: " + "; ".join(e["problems"][:2])})
            continue
        if not platform_ok(e):
            continue
        t0 = time.monotonic()
        rc, out, err = run_cmd(
            interpreter_for(e["file"], detect_lang(e["file"])) + [e["file"], "--json"], 10)
        record_usage(e["name"], e["scope"], rc,
                     int((time.monotonic() - t0) * 1000), "hook:" + hook)
        verdict = parse_verdict(out)
        if verdict is None:
            results.append({"name": e["name"], "scope": e["scope"], "status": "ERROR",
                            "severity": "error",
                            "message": "未按契约输出 --json 结论(退出码 %d) %s"
                                       % (rc, (out + err).strip()[-120:])})
        elif rc == 0 and verdict.get("status") == "OK":
            results.append({"name": e["name"], "scope": e["scope"], "status": "OK",
                            "severity": "info", "message": verdict.get("message", "")})
        elif rc == 1 and verdict.get("status") == "FAIL":
            results.append({"name": e["name"], "scope": e["scope"], "status": "FAIL",
                            "severity": verdict.get("severity", "warn"),
                            "message": verdict.get("message", "")})
        else:
            results.append({"name": e["name"], "scope": e["scope"], "status": "ERROR",
                            "severity": "error",
                            "message": "退出码(%d)与结论(status=%s)不一致"
                                       % (rc, verdict.get("status"))})
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    state_file = STATE_DIR / ("last-run-%s.json" % hook)
    state_file.write_text(
        json.dumps({"ts": datetime.now().isoformat(timespec="seconds"),
                    "hook": hook, "results": results},
                   ensure_ascii=False, indent=2),
        encoding="utf-8")
    bad = [r for r in results if r["status"] != "OK"]
    if args.json:
        print(json.dumps({"hook": hook, "results": results}, ensure_ascii=False))
    elif not args.quiet:
        for r in bad:
            mark = "⚠" if r["status"] == "FAIL" else "✗"
            print("%s [%s/%s] %s: %s" % (mark, r["scope"], r["name"], r["status"], r["message"]))
    if args.notify and bad:
        Adapter().notify("toolbox %s: %d 项异常" % (hook, len(bad)))
    return 1 if any(r["status"] == "FAIL" for r in results) else 0

# ---------- run：按名称或短别名执行工具（参数注入 + 缺参提醒 + 台账） ----------

def load_param_values():
    """合并全局 params.env 与项目 .toolbox.env（项目覆盖全局，存在即用含空值）。
    返回 (values, file_used)；文件坏行静默跳过，故障绝不阻塞工具执行。"""
    values, used = {}, []
    pd = find_repo_root(Path.cwd())
    for f in ([PARAMS_FILE] + ([pd / PROJECT_PARAMS_NAME] if pd else [])):
        if not f.is_file():
            continue
        try:
            for line in f.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, _, v = line.partition("=")
                values[k.strip()] = v.strip()
            used.append(str(f))
        except OSError:
            pass
    return values, used


def inject_params(e, inline=None):
    """按头部 params: 声明注入环境变量；缺参打印提醒。返回缺参清单。
    inline：命令行内联 KEY=VALUE（灵活参数），优先级最高，不透传给脚本。"""
    inline = inline or {}
    declared = e.get("params") or []
    for k, v in inline.items():
        os.environ[k] = v
    if not declared:
        return []
    values, _ = load_param_values()
    missing = []
    for k in declared:
        if k in inline or k in values:
            if k not in inline:
                os.environ[k] = values[k]
        elif k not in os.environ:
            missing.append(k)
    if missing:
        pd = find_repo_root(Path.cwd())
        cfg = (str(pd / PROJECT_PARAMS_NAME) if pd else str(PARAMS_FILE))
        print("⚠ [%s] 缺参数: %s" % (e["name"], ", ".join(missing)))
        print("  请在 %s 添加（格式 KEY=value，一行一个；全局配置 %s）"
              % (cfg, PARAMS_FILE))
        print("  或临时内联: toolbox run %s KEY=value ..." % e["name"])
    return missing


def resolve_tool(key):
    """按 名称 > 别名 解析工具；重名/歧义返回 None 并打印原因。"""
    entries = [e for e in collect() if not e["overridden"]]
    exact = [e for e in entries if e["name"] == key]
    if len(exact) == 1:
        return exact[0]
    if len(exact) > 1:
        print("✗ 工具名重复: %s（项目池覆盖异常，请检查工具池）" % key)
        return None
    hits = [e for e in entries if key in e["alias"]]
    if len(hits) == 1:
        return hits[0]
    if len(hits) > 1:
        print("✗ 别名歧义: %s → %s" % (key, ", ".join(
            "%s/%s" % (h["scope"], h["name"]) for h in hits)))
        return None
    print("✗ 未找到工具或别名: %s（toolbox list 查看）" % key)
    return None


def cmd_run(args):
    key = args.tool
    e = resolve_tool(key)
    if e is None:
        return 2
    # REMAINDER 会保留字面 "--"，此处剔除以兼容旧写法 "toolbox run <tool> -- <args>"
    tool_args = list(args.tool_args)
    if tool_args and tool_args[0] == "--":
        tool_args.pop(0)
    if e["problems"]:
        print("✗ 工具不合规，禁止运行: [%s] %s\n  - %s"
              % (e["scope"], e["name"], "; ".join(e["problems"][:3])))
        return 2
    if not platform_ok(e):
        print("✗ 平台不匹配: %s 需要 platform=%s" % (e["name"], e["platform"]))
        return 2
    inline = {}
    passthrough = []
    for a in tool_args:
        m = re.match(r"^([A-Z][A-Z0-9_]*)=(.*)$", a, re.S)
        if m:
            inline[m.group(1)] = m.group(2)
        else:
            passthrough.append(a)
    inject_params(e, inline)
    t0 = time.monotonic()
    cmd = interpreter_for(e["file"], detect_lang(e["file"])) + [e["file"]] + passthrough
    try:
        p = subprocess.run(cmd)
        rc = p.returncode
    except OSError as err:
        print("✗ 启动失败: %s" % err)
        rc = 127
    record_usage(e["name"], e["scope"], rc,
                 int((time.monotonic() - t0) * 1000), "run")
    return rc if 0 <= rc <= 255 else (1 if rc > 0 else 2)


# ---------- install-hooks：幂等标记块接线 / 可逆卸载 ----------

PROFILE_BODY = ('if command -v toolbox >/dev/null 2>&1; then toolbox run-hooks bootstrap --quiet; '
                'else python3 "%s" run-hooks bootstrap --quiet; fi')
GIT_BODY = 'python3 "%s" run-hooks pre-commit --quiet || exit 1'


def upsert_block(path, body):
    text = path.read_text(encoding="utf-8") if path.is_file() else ""
    block = MARKER_BEGIN + "\n" + body + "\n" + MARKER_END + "\n"
    if MARKER_BEGIN in text:
        pat = re.escape(MARKER_BEGIN) + r".*?" + re.escape(MARKER_END) + r"\n?"
        text = re.sub(pat, block, text, flags=re.S)
    else:
        text = text.rstrip("\n") + "\n\n" + block
    path.write_text(text, encoding="utf-8")


def strip_block(path):
    if not path.is_file():
        return False
    text = path.read_text(encoding="utf-8")
    pat = re.escape(MARKER_BEGIN) + r".*?" + re.escape(MARKER_END) + r"\n?"
    new = re.sub(pat, "", text, flags=re.S)
    if new == text:
        return False
    path.write_text(new, encoding="utf-8")
    return True


def cmd_install_hooks(args):
    if args.remove:
        n = 0
        prof = Adapter().profile_file()
        if prof and strip_block(prof):
            print("✓ 已从 %s 移除 bootstrap 检查" % prof)
            n += 1
        if Adapter().cron_supported():
            rc, out, _ = run_cmd(["crontab", "-l"], 10)
            if rc == 0 and CRON_TAG in (out or ""):
                keep = [l for l in out.splitlines() if CRON_TAG not in l]
                p = subprocess.run(["crontab", "-"], input="\n".join(keep) + "\n",
                                   text=True, capture_output=True)
                if p.returncode == 0:
                    print("✓ 已从 crontab 移除巡检项")
                    n += 1
                else:
                    print("⚠ crontab 卸载失败: %s" % (p.stderr or "").strip()[:120])
        root = find_repo_root(Path.cwd())
        if root:
            hookf = root / ".git" / "hooks" / "pre-commit"
            if strip_block(hookf):
                remaining = hookf.read_text(encoding="utf-8").strip()
                if remaining in ("", "#!/bin/sh", "#!/bin/bash"):
                    hookf.unlink()
                print("✓ 已从 pre-commit 移除门禁")
                n += 1
        print(("完成（共 %d 处）" % n) if n else "未发现已安装的钩子")
        return 0
    prof = Adapter().profile_file()
    if prof:
        try:
            upsert_block(prof, PROFILE_BODY % MGR_PATH)
            print("✓ profile 登录检查 → %s" % prof)
        except OSError as e:
            print("⚠ profile 接线失败: %s" % e)
    else:
        print("⚠ 未识别 profile，跳过登录检查")
    if Adapter().cron_supported():
        rc, out, _ = run_cmd(["crontab", "-l"], 10)
        cur = out if rc == 0 else ""
        if CRON_TAG in cur:
            print("✓ cron 巡检已存在（幂等跳过）")
        else:
            line = '*/30 * * * * python3 "%s" run-hooks cron --quiet --notify %s' % (MGR_PATH, CRON_TAG)
            p = subprocess.run(["crontab", "-"],
                               input=(cur.rstrip("\n") + "\n" + line + "\n"),
                               text=True, capture_output=True)
            if p.returncode == 0:
                print("✓ cron 巡检（每 30 分钟）已安装")
            else:
                print("⚠ crontab 安装失败（沙盒/权限？）: %s" % (p.stderr or "").strip()[:120])
    else:
        print("⚠ 当前平台无 crontab，跳过 cron 巡检")
    root = find_repo_root(Path.cwd())
    if root is None:
        print("⚠ 当前不在 git 仓库内，跳过 pre-commit 门禁")
    else:
        try:
            hooks = root / ".git" / "hooks"
            hooks.mkdir(exist_ok=True)
            hookf = hooks / "pre-commit"
            if hookf.is_file() and MARKER_BEGIN not in hookf.read_text(encoding="utf-8"):
                print("⚠ 已存在非 toolbox 的 pre-commit，跳过（请手动合并）")
            else:
                if hookf.is_file():
                    strip_block(hookf)
                    text = hookf.read_text(encoding="utf-8")
                else:
                    text = "#!/bin/sh\n"
                text = text.rstrip("\n") + "\n" + MARKER_BEGIN + "\n" + (GIT_BODY % MGR_PATH) + "\n" + MARKER_END + "\n"
                hookf.write_text(text, encoding="utf-8")
                hookf.chmod(0o755)
                print("✓ pre-commit 门禁 → %s" % hookf)
        except OSError as e:
            print("⚠ pre-commit 接线失败（.git 只读/沙盒？）: %s" % e)
    print("提示: run-hooks exit 1 仅来自工具 FAIL（真实拦截）；工具自身故障 fail-open 不拦截。")
    return 0

# ---------- init / new ----------

README_TMPL = """# toolbox — 全局脚本工具箱

人类与 AI 共用的脚本管理运行时。管理器（规范 SSOT）:
~/.agents/skills/agent-toolbox/toolbox-mgr.py（只搬运，严禁重生/手改副本）

## 快速上手
  toolbox spec                 查看脚本编写规范
  toolbox new <name>           生成脚手架（默认 shell 语言、项目池；--lang python / --scope global 可选）
  toolbox check <path>         校验并登记（文件移入工具池）
  toolbox list                 派生清单（⚠ = 不合规）
  toolbox run-hooks <hook>     执行钩子（bootstrap/audit/cron/pre-commit）
  toolbox install-hooks        接线登录检查/cron/pre-commit（--remove 卸载）
  toolbox remove <name>        退役 → .trash/

## 目录
  scripts/   全局工具池（跨项目）
  state/     钩子运行状态 last-run-<hook>.json；使用台账 usage-ledger.jsonl（append-only）
  .trash/    退役脚本
项目池: <repo>/scripts/agent-tools/（同名覆盖全局）
"""


def cmd_init(args):
    for d in (TOOLBOX_DIR, SCRIPTS_DIR, STATE_DIR, TRASH_DIR):
        d.mkdir(parents=True, exist_ok=True)
    (TOOLBOX_DIR / "README.md").write_text(README_TMPL, encoding="utf-8")
    shim = install_shim()
    print("✓ 全局池: %s" % TOOLBOX_DIR)
    print("✓ shim: %s" % shim)
    if args.project:
        d = project_scripts_dir()
        if d is None:
            print("✗ 当前不在 git 仓库内，跳过项目池")
        else:
            d.mkdir(parents=True, exist_ok=True)
            print("✓ 项目池: %s" % d)
    print("下一步: toolbox spec 查看规范；toolbox new <name> 创建第一个工具")
    return 0


SCAFFOLD = '''#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""{summary}（脚手架——把占位实现替换为真实逻辑）

toolbox-script
format: v1
name: {name}
summary: {summary}
trigger: {trigger}
platform: any
self-test: --self-test
"""

import argparse
import json
import sys


def run_checks():
    """返回 (ok, severity, message)。在这里实现真实检查。"""
    # TODO: 实现检查逻辑；探测失败 → ok=False，message 里写人话与修复方向
    ok, severity, message = True, "info", "脚手架尚未实现检查逻辑"
    return ok, severity, message


def self_test():
    """金丝雀：必须构造已知坏样本，证明探测函数真的能抓到坏。"""
    # TODO: 注入坏样本（不存在路径/坏配置），断言探测函数返回未通过；好样本返回通过
    ok, _, _ = run_checks()
    if ok:
        print("self-test: 脚手架占位未实现真实检查，禁止登记")
        return 2
    print("self-test: OK")
    return 0


def main():
    ap = argparse.ArgumentParser(description="{summary}")
    ap.add_argument("--json", action="store_true", help="输出契约 JSON 结论")
    ap.add_argument("--self-test", action="store_true", help="金丝雀自检")
    args = ap.parse_args()
    if args.self_test:
        sys.exit(self_test())
    ok, severity, message = run_checks()
    if args.json:
        print(json.dumps({{"status": "OK" if ok else "FAIL",
                           "severity": severity, "message": message}},
                          ensure_ascii=False))
    else:
        print(("✓ " if ok else "✗ ") + message)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
'''

# shell 脚手架（@占位符替换，避免与 shell 语法冲突；$VAR 仅出现在文件内容中）
SCAFFOLD_SH = '''#!/bin/sh
# @@SUMMARY@@（脚手架——把占位实现替换为真实逻辑）
#
# toolbox-script
# format: v1
# name: @@NAME@@
# summary: @@SUMMARY@@
# trigger: @@TRIGGER@@
# platform: unix
# self-test: --self-test

set -eu
MSG=""

usage() {
  cat <<'EOF'
用法: @@NAME@@.sh [--json] [--self-test]
  --json       输出一行 JSON 契约结论（message 内禁双引号）
  --self-test  金丝雀自检（guard 类必实现）
EOF
}

run_checks() {
  # TODO: 实现真实检查；失败把人话（问题本身+修复方向）写入 MSG 并 return 1
  MSG="脚手架尚未实现检查逻辑"
  return 1
}

self_test() {
  # TODO: 金丝雀——构造已知坏样本断言能抓到坏；好样本应通过
  echo "self-test: 脚手架占位未实现真实检查，禁止登记"
  return 2
}

case "${1-}" in
  --self-test)
    self_test
    ;;
  --json)
    if run_checks; then
      printf '{"status":"OK","severity":"info","message":"%s"}\n' "$MSG"
      exit 0
    fi
    printf '{"status":"FAIL","severity":"warn","message":"%s"}\n' "$MSG"
    exit 1
    ;;
  --help|-h)
    usage
    ;;
  "")
    if run_checks; then
      echo "OK: $MSG"
    else
      echo "FAIL: $MSG"
      exit 1
    fi
    ;;
  *)
    usage
    exit 2
    ;;
esac
'''


def cmd_new(args):
    if not SCRIPTS_DIR.is_dir():
        print("✗ 全局池未初始化，先运行: toolbox init")
        return 2
    if not NAME_RE.match(args.name):
        print("✗ name 非法（小写字母开头，小写字母/数字/连字符，2-41 位）")
        return 1
    if args.scope == "project":
        d = project_scripts_dir()
        if d is None:
            print("✗ 当前不在 git 仓库内；用 --scope global")
            return 2
    else:
        d = SCRIPTS_DIR
    d.mkdir(parents=True, exist_ok=True)
    ext = ".sh" if args.lang == "sh" else ".py"
    dest = d / (args.name + ext)
    if dest.exists():
        print("✗ 已存在: %s" % dest)
        return 1
    summary = args.summary or args.name
    if args.lang == "sh":
        dest.write_text(SCAFFOLD_SH.replace("@@NAME@@", args.name)
                                   .replace("@@SUMMARY@@", summary)
                                   .replace("@@TRIGGER@@", args.trigger), encoding="utf-8")
        dest.chmod(0o755)
    else:
        dest.write_text(SCAFFOLD.format(name=args.name, summary=summary,
                                        trigger=args.trigger), encoding="utf-8")
    print("✓ 脚手架(%s): %s" % (args.lang, dest))
    print("下一步: 编辑实现 → toolbox check %s" % dest)
    return 0

# ---------- spec：脚本编写规范（唯一事实源，内嵌本文件） ----------

SPEC_TEXT = '''\
toolbox 脚本编写规范 v1.5（唯一事实源——由元工具内嵌，任何副本不具效力）

0. 宪法
  - 语言双通道，shell 优先：shell（POSIX sh / bash）为一等公民，优先实现；
    仅当 shell 无法合理实现（复杂文本/JSON 解析、跨平台探测等）才用 Python（>= 3.9、仅标准库）。
  - 单文件；禁交互输入；可重复执行结果一致（幂等）。
  - 文件写入仅限：当前仓库内，或参数显式指定的路径。
  - 网络仅在工具用途本身是网络检查时允许，且必须设短超时。
  - 严禁硬编码凭证：密钥/口令一律经环境变量注入；登记门禁做密钥形状扫描
    （AKIA / ghp_ / sk- / 私钥块 / 字面量口令等），命中即拒收。
  - 时长预算：钩子型（trigger != manual）单次执行 <= 10s（run-hooks 硬超时）；
    manual 类不限时（长任务允许，但须幂等、可安全重跑）。

1. 头部块（字段与语言无关；收集器只认 toolbox-script 标记行起的连续字段区，
   遇首个非字段行即结束——shell 头部块之后紧跟第一行代码收尾）
  Python（模块 docstring 内）:        shell（连续 # 注释内）:
    """                                # toolbox-script
    toolbox-script                     # format: v1
    format: v1                         # name: <小写-连字符>
    name: <小写-连字符>                 # summary: <一句话>
    summary: <一句话>                  # trigger: bootstrap|audit|cron|pre-commit|manual
    trigger: ...                       # platform: unix       # shell 必填 unix/linux/darwin
    platform: any                      # self-test: --self-test   # trigger != manual 必填
    self-test: --self-test
    """

2. 必须实现（与语言无关）
  - 标准 --help（shell 用 usage() + cat <<EOF 实现，退出码 0）；
  - --json：仅输出一行 JSON 结论 {"status":"OK|FAIL","severity":"info|warn|error","message":"..."}
    （shell 用 printf 实现；message 内禁双引号）；
  - 退出码契约：0=通过 1=检查未通过 2=自身故障（--json 时退出码必须与 status 一致）；
  - 长任务（manual 部署/回归类）的 --json 语义 = 快速预检结论，不执行任务本体；
    任务本体由裸跑触发，且必须在 usage 里写明两者区别；
  - guard 类（trigger != manual）必带 --self-test 金丝雀：内嵌已知坏样本，证明“能抓到坏”；
  - 短别名（可选）：头部块加 `alias: a|b|c`（逗号分隔，同 name 命名规则），
    经 `toolbox run <别名> [参数...]` 运行——解析、透传、计台账均由元工具承担；
    裸调脚本文件仍合法（别名只是附加通道，非强制）。
  - 参数声明（可选）：头部块加 `params: KEY1,KEY2`（大写/数字/下划线，逗号分隔），
    声明工具依赖的配置参数。参数值集中维护于全局 ~/.agents/toolbox/params.env 与
    项目 <repo>/.toolbox.env（KEY=value 一行一个，项目覆盖全局；手工添加，禁入 git）。
    `toolbox run` 运行前自动注入为同名环境变量（已导出的环境变量优先于配置文件）；
    缺参当场打印提醒（不阻塞——工具自身预检仍兜底）。脚本内取参应 env 优先、
    本地兜底（如 .env），与环境变量注入语义一致。
  - 类别声明（可选，v1.5）：头部块加 `cat: <类别>`（单个，同 name 命名规则；惯例类目
    build=构建/编译、test=测试/验证/冒烟/回归、deploy=部署/发布、env=环境体检/依赖探测、
    ops=服务起停/进程运维、docs=文档/索引校验，不强制枚举——类目由使用者约定，元工具只做
    精确匹配）。`toolbox list --cat <类别>` 按类别过滤，AI/人按需拉一小片清单而非全表，
    防提示词膨胀；查空类别时若类目不存在，list 会回显池内现有类别与惯例映射供自纠错。
  - 服务类动词声明（可选，v1.5，仅服务型工具）：头部块加 `verbs: run,stop,status,restart`
    （小写、逗号分隔，可子集，取值仅限这四个）。**工具分型口径**：拉起/管理长驻进程
    （应用、监工、代理）= 服务型，应声明 verbs；跑完即退（校验、巡检、构建、部署）
    = 一次性型，**不得声明 verbs**——一次性工具动词面只有 run。声明后元工具提供
    前置动词路由：`toolbox <verb> <tool> [args...]` 等价于 `toolbox run <tool> <verb> [args...]`，
    动词作为脚本首参传入；脚本须自行实现声明了的每个同名子命令（run 可省略——
    无动词即默认启动），且 stop 幂等（未运行 exit 0）、status 可安全重复执行、
    restart 单目标语义（无法单目标则报错）。**run 宜提供后台模式**（惯例参数
    `--daemon`/`-d`）：进程 nohup 脱终端存活、日志仍定向文件；启动后做存活
    确认（秒级 sleep + kill -0），即刻退出则回显日志尾部并 exit 1。stop/status
    按进程特征匹配（如命令行模式），对前台/后台两种启动方式行为一致，不依赖
    pidfile。未声明 verbs 的工具不受影响，
    任意参数仍经 REMAINDER 原样透传；对其用前置动词被拒绝（exit 2）。
  - 灵活参数（临时内联）：`toolbox run <工具> KEY=value [其他参数]`——KEY=value
    形式的实参被元工具识别为参数覆盖（优先级最高，一次性生效不落盘，不透传脚本），
    其余参数原样透传。适合临时换库口令/换目标等一次性场景；值含空格加引号。

3. 语言细则
  - shell（<name>.sh，优先）：shebang 必须为 #!/bin/sh 或 #!/usr/bin/env bash；
    依赖仅限 POSIX 工具链与用途所需的常规 CLI（git/docker/gcloud 等直接可用）；
    登记门禁含 sh -n / bash -n 语法检查；不支持 Windows（platform 必填 unix 或 linux/darwin）。
  - python（<name>.py，兜底）：shebang 指向 python；仅标准库（import 静态校验）；platform 默认 any。

4. 失败语义
  - FAIL 在 message 里写人话：问题本身 + 修复方向；不抛栈。自身故障才用退出码 2。

5. 生命周期
  - 无使用价值即 `toolbox remove`；epic 收尾时盘点 `toolbox list`，零使用项人工判退役。
'''


def cmd_spec(args):
    print(SPEC_TEXT)
    return 0


def cmd_remove(args):
    matches = [e for e in collect() if e["name"] == args.name]
    if not matches:
        print("✗ 未找到工具: %s" % args.name)
        return 1
    e = next((x for x in matches if x["scope"] == "project"), matches[0])
    if not args.yes:
        if not sys.stdin.isatty():
            print("✗ 非交互环境必须显式 --yes（将移入回收站: %s）" % e["file"])
            return 1
        ans = input("将 %s 移入 .trash，确认? [y/N] " % e["file"])
        if ans.strip().lower() not in ("y", "yes"):
            print("已取消")
            return 0
    TRASH_DIR.mkdir(parents=True, exist_ok=True)
    suffix = Path(e["file"]).suffix or ".py"
    dest = TRASH_DIR / ("%s-%s%s" % (args.name, time.strftime("%Y%m%d-%H%M%S"), suffix))
    shutil.move(e["file"], str(dest))
    print("✓ 已退役: %s → %s" % (args.name, dest))
    return 0


# ---------- 元工具自检（金丝雀：法官先过自己门禁） ----------

SAMPLE_OK = "\n".join([
    '"""demo',
    "",
    "toolbox-script",
    "format: v1",
    "name: demo-tool",
    "summary: demo",
    "trigger: audit",
    '"""',
])
SAMPLE_BAD = "x = 1\n"
SAMPLE_SH = "\n".join([
    "#!/bin/sh",
    "# demo",
    "#",
    "# toolbox-script",
    "# format: v1",
    "# name: demo-sh",
    "# summary: demo",
    "# trigger: manual",
    "# platform: unix",
])


def cmd_self_test(args):
    fails = []
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / "demo-tool.py"
        p.write_text(SAMPLE_OK, encoding="utf-8")
        meta, pr = parse_header(p)
        if pr or meta.get("name") != "demo-tool" or meta.get("trigger") != "audit":
            fails.append("头部解析合法样本失败: %r %r" % (meta, pr))
        q = Path(td) / "bad.py"
        q.write_text(SAMPLE_BAD, encoding="utf-8")
        _, prq = parse_header(q)
        if not prq:
            fails.append("头部解析未拒绝无头部样本")
        s = Path(td) / "demo-sh.sh"
        s.write_text(SAMPLE_SH, encoding="utf-8")
        sm, sp = parse_header(s)
        if sp or sm.get("name") != "demo-sh" or sm.get("platform") != "unix":
            fails.append("shell 头部解析失败: %r %r" % (sm, sp))
        if detect_lang(s) != "shell":
            fails.append("detect_lang 未识别 .sh")
        if shebang_problems(s, "shell"):
            fails.append("shebang 校验误拒合法 shell 样本: %r" % shebang_problems(s, "shell"))
        vpr = validate_meta({"format": "v1", "name": "demo-tool",
                             "summary": "x", "trigger": "nope"})
        if not any("trigger" in x for x in vpr):
            fails.append("validate_meta 未拒绝非法 trigger")
        vok = validate_meta({"format": "v1", "name": "demo-tool", "summary": "x",
                             "trigger": "audit", "alias": "dt, demo-t"})
        if vok:
            fails.append("validate_meta 误拒合法 alias: %r" % vok)
        vbad = validate_meta({"format": "v1", "name": "demo-tool", "summary": "x",
                              "trigger": "audit", "alias": "Bad_Alias"})
        if not any("alias" in x for x in vbad):
            fails.append("validate_meta 未拒绝非法 alias")
        pok = validate_meta({"format": "v1", "name": "demo-tool", "summary": "x",
                             "trigger": "audit", "params": "POSTGRES_PASS,RABBIT_USER"})
        if pok:
            fails.append("validate_meta 误拒合法 params: %r" % pok)
        pbad = validate_meta({"format": "v1", "name": "demo-tool", "summary": "x",
                              "trigger": "audit", "params": "bad-key"})
        if not any("params" in x for x in pbad):
            fails.append("validate_meta 未拒绝非法 params")
        if any("platform" in x for x in validate_meta(
                {"format": "v1", "name": "demo-tool", "summary": "x",
                 "trigger": "audit", "platform": "unix"})):
            fails.append("validate_meta 误拒 platform: unix")
        fake_gh = "ghp_" + "A1bC" * 6
        lk = Path(td) / "leak.py"
        lk.write_text('TOKEN = "%s"\npassword = "c0rrect-horse-9"\n' % fake_gh,
                      encoding="utf-8")
        hp = secret_problems(lk)
        if len(hp) != 2:
            fails.append("secret 扫描未抓到已知坏样本: %r" % hp)
        cl = Path(td) / "clean.py"
        cl.write_text('TOKEN = os.environ["GH_TOKEN"]\npassword = "${DB_PASS}"\n'
                      'api_key = config["api_key"]\n', encoding="utf-8")
        cp = secret_problems(cl)
        if cp:
            fails.append("secret 扫描误拒干净样本: %r" % cp)
    if "退出码" not in SPEC_TEXT:
        fails.append("SPEC_TEXT 缺少退出码契约")
    if "shell 优先" not in SPEC_TEXT:
        fails.append("SPEC_TEXT 未含 shell 优先条款")
    shim = Adapter().shim_file()
    if HOME not in shim.resolve().parents:
        fails.append("shim 路径不在用户目录下")
    if fails:
        print("✗ 元工具自检失败:")
        for f in fails:
            print("  - %s" % f)
        return 2
    print("✓ 元工具自检通过（双语言头部解析/校验/规范/适配层）")
    return 0


# ---------- 入口 ----------

def build_parser():
    ap = argparse.ArgumentParser(
        prog="toolbox",
        description="全局脚本工具箱管理器（规范 SSOT + 执行器）——toolbox spec 查看编写规范；"
                    "服务类动词 stop/status/restart 可前置：toolbox <verb> <tool> [args...]（工具须声明 verbs）")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("init", help="初始化全局池与 shim（幂等）")
    p.add_argument("--project", action="store_true",
                   help="同时初始化当前仓库项目池 scripts/agent-tools/")
    p.set_defaults(fn=cmd_init)

    p = sub.add_parser("new", help="生成脚本脚手架（默认 shell——一等公民优先）")
    p.add_argument("name")
    p.add_argument("--lang", choices=("sh", "python"), default="sh",
                   help="脚手架语言：sh 优先（一等公民），python 兜底")
    p.add_argument("--scope", choices=("global", "project"), default="project")
    p.add_argument("--trigger", choices=TRIGGERS, default="manual")
    p.add_argument("--summary", default="")
    p.set_defaults(fn=cmd_new)

    p = sub.add_parser("check", help="校验脚本合规并移入工具池")
    p.add_argument("path")
    p.add_argument("--scope", choices=("global", "project"), default="project")
    p.add_argument("--force", action="store_true")
    p.set_defaults(fn=cmd_check)

    p = sub.add_parser("list", help="派生工具清单")
    p.add_argument("--json", action="store_true")
    p.add_argument("--cat", help="按类别过滤（头部 cat 字段，如 build/test/deploy/env/ops）")
    p.set_defaults(fn=cmd_list)

    p = sub.add_parser("run", help="按名称或短别名运行工具（KEY=value 内联覆盖参数，其余原样透传）")
    p.add_argument("tool", help="工具名称或头部 alias 字段中的短别名")
    # REMAINDER：tool 之后的 token 全部原样透传（含 --stop 等选项样式，不再需要 -- 分隔）
    p.add_argument("tool_args", nargs=argparse.REMAINDER,
                   help="KEY=value 为参数覆盖（不透传）；其余参数原样透传给工具")
    p.set_defaults(fn=cmd_run)

    p = sub.add_parser("run-hooks", help="执行某钩子下全部工具")
    p.add_argument("hook")
    p.add_argument("--quiet", action="store_true")
    p.add_argument("--json", action="store_true")
    p.add_argument("--notify", action="store_true")
    p.set_defaults(fn=cmd_run_hooks)

    p = sub.add_parser("install-hooks", help="接线 profile/cron/pre-commit（--remove 卸载）")
    p.add_argument("--remove", action="store_true")
    p.set_defaults(fn=cmd_install_hooks)

    p = sub.add_parser("spec", help="打印脚本编写规范")
    p.set_defaults(fn=cmd_spec)

    p = sub.add_parser("remove", help="退役工具 → .trash")
    p.add_argument("name")
    p.add_argument("--yes", action="store_true")
    p.set_defaults(fn=cmd_remove)

    p = sub.add_parser("self-test", help="元工具自检")
    p.set_defaults(fn=cmd_self_test)
    return ap


def main(argv=None):
    if argv is None:
        argv = sys.argv[1:]
    # 动词路由（v1.5）：toolbox <verb> <tool> [args...] → toolbox run <tool> <verb> [args...]
    # 仅当工具头部声明了该 verbs 时生效；未声明动词的工具走既有透传，行为不变。
    if len(argv) >= 2 and argv[0] in VERBS and argv[0] != "run":
        verb, key = argv[0], argv[1]
        e = resolve_tool(key)
        if e is not None:
            if verb not in e["verbs"]:
                print("✗ 工具 %s 未声明 verbs（当前: %s）——请用 toolbox run %s <verb> ... 透传"
                      % (e["name"], ",".join(e["verbs"]) or "无", key))
                return 2
            argv = ["run", key, verb] + list(argv[2:])
    args = build_parser().parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
