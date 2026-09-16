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
                         校验脚本合规（头部/help/--json/self-test/语言门禁）并移入工具池
  list [--json]          派生工具清单（扫描两级池，⚠ 标记不合规项）
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

VERSION = "1.1"
HOME = Path.home()
TOOLBOX_DIR = HOME / ".agents" / "toolbox"
SCRIPTS_DIR = TOOLBOX_DIR / "scripts"
STATE_DIR = TOOLBOX_DIR / "state"
TRASH_DIR = TOOLBOX_DIR / ".trash"
MGR_PATH = Path(__file__).resolve()
MARKER_BEGIN = "# >>> toolbox-mgr >>>"
MARKER_END = "# <<< toolbox-mgr <<<"
CRON_TAG = "# toolbox-mgr:cron"
TRIGGERS = ("bootstrap", "audit", "cron", "pre-commit", "manual")
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
            name = meta.get("name") or ("?" + f.stem)
            e = {"name": name, "file": str(f), "scope": scope,
                 "trigger": meta.get("trigger", "?"),
                 "platform": meta.get("platform", "any"),
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


# ---------- list / check ----------

def cmd_list(args):
    entries = collect()
    if args.json:
        slim = [{k: e[k] for k in ("name", "scope", "trigger", "platform",
                                   "summary", "problems", "file")} for e in entries]
        print(json.dumps(slim, ensure_ascii=False, indent=2))
        return 0
    if not entries:
        print("(空) 工具池为空。用 `toolbox new <name>` 生成脚手架，或 `toolbox check <path>` 登记现有脚本。")
        return 0
    rows = []
    for e in entries:
        extra = ""
        if e["overridden"]:
            extra += "  (被项目池覆盖)"
        if e["problems"]:
            extra += "  ⚠ " + e["problems"][0]
        rows.append((e["name"], e["scope"], e["trigger"], e["summary"] + extra))
    if sys.stdout.isatty():
        w1 = max(len(r[0]) for r in rows + [("name", "", "", "")])
        w2 = max(len(r[1]) for r in rows + [("", "scope", "", "")])
        w3 = max(len(r[2]) for r in rows + [("", "", "trigger", "")])
        print("%-*s  %-*s  %-*s  %s" % (w1, "name", w2, "scope", w3, "trigger", "summary"))
        for r in rows:
            print("%-*s  %-*s  %-*s  %s" % (w1, r[0], w2, r[1], w3, r[2], r[3]))
    else:
        for r in rows:
            print("%s\t%s\t%s\t%s" % r)
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
            results.append({"name": e["name"], "scope": e["scope"], "status": "ERROR",
                            "severity": "error",
                            "message": "不合规: " + "; ".join(e["problems"][:2])})
            continue
        if not platform_ok(e):
            continue
        rc, out, err = run_cmd(
            interpreter_for(e["file"], detect_lang(e["file"])) + [e["file"], "--json"], 10)
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
  state/     钩子运行状态 last-run-<hook>.json
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
toolbox 脚本编写规范 v1.1（唯一事实源——由元工具内嵌，任何副本不具效力）

0. 宪法
  - 语言双通道，shell 优先：shell（POSIX sh / bash）为一等公民，优先实现；
    仅当 shell 无法合理实现（复杂文本/JSON 解析、跨平台探测等）才用 Python（>= 3.9、仅标准库）。
  - 单文件；禁交互输入；可重复执行结果一致（幂等）。
  - 文件写入仅限：当前仓库内，或参数显式指定的路径。
  - 网络仅在工具用途本身是网络检查时允许，且必须设短超时。
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
  - guard 类（trigger != manual）必带 --self-test 金丝雀：内嵌已知坏样本，证明“能抓到坏”。

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
        if any("platform" in x for x in validate_meta(
                {"format": "v1", "name": "demo-tool", "summary": "x",
                 "trigger": "audit", "platform": "unix"})):
            fails.append("validate_meta 误拒 platform: unix")
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
        description="全局脚本工具箱管理器（规范 SSOT + 执行器）——toolbox spec 查看编写规范")
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
    p.set_defaults(fn=cmd_list)

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
    args = build_parser().parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
