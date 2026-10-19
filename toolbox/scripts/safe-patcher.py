#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""safe-patcher — AI 安全写入守门员：唯一性匹配替换 / 原子写入+备份回滚 / 语法预检

解决 AI 直接改文件的三大事故：幻觉替换（search 块匹配失败/多义）、写入中断
截断文件、写入后语法损坏。四步闭环：
  1) 前置校验：路径越界/敏感文件阻断 + CRLF 归一 + search 块唯一性匹配
  2) 语法预检：写入前按扩展名做轻量解析（不跑编译器/类型检查）
  3) 原子写入：.bak 备份 + 同目录临时文件 + os.replace 原子替换
  4) 自动回滚：写失败恢复备份，成功才删备份
项目继承（全局为骨，项目为肉）：项目根存在 .agent-patch.json 时，在内置语法预检
之后执行其中的项目专属校验命令（hooks: [{match, run, timeout}]，{file} 占位），
正常执行但未通过仍拒绝写入（hook 判定权）；分流策略：hook 基础设施故障（配置损坏/缺 run/超时/命令
不可执行/执行异常）降级为 ⚠ 警告并放行，不阻塞写路径（fail-open）；内置语法检查器超时/
意外异常则硬阻断 SYNTAX_CHECK_TIMEOUT（fail-closed，内容完整性保护）。降级/阻断仅随消息输出
⚠ 警告（会话内自纠），不落盘留档——外层 compile/lint 才是权威闸门。语法预检与 hook 仅对
代码文件（CODE_EXTS）生效，其他文件（md/骨架/文案）直写不拦。骨架由 project-scaffold 按技术栈生成。

语法预检覆盖（优雅降级——未适配后缀直接放行，只靠原子性兜底）：
  .py ast.parse ｜ .json json.loads ｜ .toml tomllib(3.11+) ｜ .yaml/.yml pyyaml(可选)
  .sh/.bash bash -n ｜ .js/.mjs node --check(装了 node 才启用)
严禁做语义/类型级检查（tsc/mypy/cargo check）——太重且依赖项目上下文。

用法:
  safe-patcher patch <file> --search <block> --replace <block> [--ws <目录>] [--json]
  safe-patcher write <file> [--content-file <f> | stdin] [--ws <目录>] [--json]  # 全量覆盖,<=200 行
  safe-patcher verify <file> [--ws <目录>] [--json]                              # 仅语法预检
裸跑执行任务本体；--json 输出一行契约结论（{"status":"OK|FAIL",...}）。
退出码: 0=成功 1=拒绝写入(校验未过) 2=自身故障(含 SYNTAX_CHECK_TIMEOUT fail-closed 阻断)

toolbox-script
format: v1
name: safe-patcher
summary: AI 安全写入守门：唯一性匹配替换+原子写入备份回滚+按扩展名语法预检（py/json/toml/yaml/sh/js）（通用）
trigger: manual
cat: ops
alias: spatch
platform: any
self-test: --self-test
"""

import argparse
import ast
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

MAX_OVERWRITE_LINES = 200  # write 子命令全量覆盖的行数上限，大文件强制走 patch

PROTECTED_PARTS = {".git", ".env", ".ssh", "node_modules", "id_rsa", "credentials.json"}

# 拦截面：仅代码文件做语法预检与项目 hook（md/骨架/文案等非代码文件直写不拦）
CODE_EXTS = {".py", ".json", ".toml", ".yaml", ".yml", ".sh", ".bash", ".js", ".mjs"}

# fail-open 告警池：基础设施故障降级放行时收集，随 OK 消息输出
WARNINGS = []


def warn(msg: str) -> None:
    WARNINGS.append(msg)

try:
    import tomllib
except ImportError:
    tomllib = None


def _contract(status, severity, message, remedy=""):
    out = {"status": status, "severity": severity, "message": message}
    if remedy:
        out["remedy"] = remedy
    return json.dumps(out, ensure_ascii=False)


class Rejected(Exception):
    """校验拒绝——exit 1，message 面向 AI 自我纠错"""


class Fault(Exception):
    """自身故障——exit 2"""


# ---------- 前置校验 ----------

def resolve_target(ws: Path, file_arg: str) -> Path:
    target = Path(file_arg)
    if not target.is_absolute():
        target = ws / target
    target = target.resolve()
    if not (target == ws or target.is_relative_to(ws)):
        raise Rejected(f"路径越界: {file_arg} 不在工作区 {ws} 内")
    if any(part in PROTECTED_PARTS for part in target.parts):
        raise Rejected(f"受保护路径禁止修改: {file_arg}")
    return target


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise Rejected(f"文件不存在: {path}")
    except UnicodeDecodeError:
        raise Rejected(f"非 UTF-8 文本，拒绝处理: {path}")


def normalize(text: str) -> str:
    return text.replace("\r\n", "\n")


# ---------- 语法预检 ----------

def syntax_check(path: Path, content: str) -> None:
    ext = path.suffix.lower()
    try:
        if ext == ".py":
            ast.parse(content)
        elif ext == ".json":
            json.loads(content)
        elif ext == ".toml" and tomllib:
            tomllib.loads(content)
        elif ext in (".yaml", ".yml"):
            # 可选依赖 pyyaml：动态加载，未安装则该后缀优雅降级（不做语法拦截）
            import importlib.util
            spec = importlib.util.find_spec("yaml")
            if spec:
                try:
                    importlib.import_module("yaml").safe_load(content)
                except Exception as e:  # YAMLError 非 ValueError 子类，统一转语法错误
                    raise SyntaxError(str(e))
        elif ext in (".sh", ".bash") and shutil.which("bash"):
            r = subprocess.run(["bash", "-n"], input=content, text=True,
                               capture_output=True, timeout=10)
            if r.returncode != 0:
                raise SyntaxError(r.stderr.strip()[:500])
        elif ext in (".js", ".mjs") and shutil.which("node"):
            r = subprocess.run(["node", "--check"], input=content, text=True,
                               capture_output=True, timeout=10)
            if r.returncode != 0:
                raise SyntaxError(r.stderr.strip()[:500])
    except SyntaxError as e:
        raise Rejected(f"语法预检失败({ext}): {e}")
    except (json.JSONDecodeError, ValueError) as e:
        raise Rejected(f"语法预检失败({ext}): {str(e)[:300]}")
    except subprocess.TimeoutExpired:
        # fail-closed（内容完整性保护）：解析器超时/畸形大文件不得落盘
        raise Fault(f"SYNTAX_CHECK_TIMEOUT: 语法检查器超时({ext})——fail-closed 阻断，"
                    f"核实文件体量后重试或拆分编辑")
    except Exception as e:
        # fail-closed：判断不了 ≠ 放行
        raise Fault(f"SYNTAX_CHECKER_FATAL ({ext}): {str(e)[:120]}")


# ---------- 原子写入 ----------

def atomic_write(target: Path, new_content: str) -> None:
    backup = target.with_name(target.name + ".bak")
    tmp_fd, tmp_name = tempfile.mkstemp(dir=str(target.parent),
                                        prefix="." + target.name + ".", suffix=".tmp")
    tmp = Path(tmp_name)
    try:
        shutil.copy2(target, backup)
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            f.write(new_content)
        os.replace(tmp, target)
        backup.unlink()  # 写入确认无误才删备份
    except Exception as e:
        tmp.unlink(missing_ok=True)
        if backup.exists():
            os.replace(backup, target)  # 回滚
        raise Fault(f"写入失败已回滚: {e}")


# ---------- 项目 Hook（继承：全局为骨，项目为肉） ----------

HOOK_FILE = ".agent-patch.json"  # 项目根下的 Hook 配置，由 project-scaffold 生成骨架


def load_hooks(ws: Path) -> list:
    cfg = ws / HOOK_FILE
    if not cfg.exists():
        return []
    try:
        data = json.loads(cfg.read_text(encoding="utf-8"))
        hooks = data.get("hooks", [])
        if not isinstance(hooks, list):
            raise ValueError("hooks 须为数组")
        return hooks
    except (OSError, json.JSONDecodeError, ValueError) as e:
        raise Fault(f"{HOOK_FILE} 解析失败: {e}")


def run_project_hooks(ws: Path, target: Path, content: str) -> None:
    """写盘前执行项目专属校验（仅代码文件）。正常执行但未通过 → Rejected；
    fail-open：hook 基础设施故障（配置损坏/缺 run/超时/命令不可执行 127/执行异常）
    降级 ⚠ 放行，不阻塞写路径——判断权在 hook 的退出码，故障权不在。

    {file} 指向新内容的预写临时副本（同目录、同名后缀，跑完即删）——
    否则 hook 只能读到磁盘上的旧内容，校验形同虚设。
    """
    if target.suffix.lower() not in CODE_EXTS:
        return  # 非代码文件不跑 hook（语法预检同口径），直写
    rel = str(target.relative_to(ws))
    try:
        hooks = load_hooks(ws)
    except Fault as e:
        warn(f"fail-open 跳过项目 hook: {e}")
        return
    if not hooks:
        return
    tmp_fd, tmp_name = tempfile.mkstemp(dir=str(target.parent),
                                        prefix="." + target.name + ".hookcheck.",
                                        suffix=target.suffix)
    tmp = Path(tmp_name)
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            f.write(content)
        for i, h in enumerate(hooks):
            if not isinstance(h, dict) or "run" not in h:
                warn(f"fail-open 跳过项目 hook[{i}]: 缺 run 字段")
                continue
            pat = h.get("match", "")
            if pat and not re.search(pat, rel):
                continue
            cmd = h["run"].replace("{file}", str(tmp))
            try:
                timeout = int(h.get("timeout", 60))
                r = subprocess.run(cmd, shell=True, cwd=str(ws), text=True,
                                   capture_output=True, timeout=timeout)
            except subprocess.TimeoutExpired:
                warn(f"fail-open 跳过项目 hook[{i}] 超时: {cmd}")
                continue
            except Exception as e:
                warn(f"fail-open 跳过项目 hook[{i}] 执行故障: {str(e)[:120]}")
                continue
            if r.returncode == 127:
                # shell 无法执行命令（配置坏）= 基础设施故障；其余非 0 = hook 判定不通过
                warn(f"fail-open 跳过项目 hook[{i}] 命令不可执行(127): {cmd}")
                continue
            if r.returncode != 0:
                detail = (r.stderr or r.stdout).strip()[:300]
                raise Rejected(f"项目 hook[{i}] 未通过: {cmd}\n{detail}")
    finally:
        tmp.unlink(missing_ok=True)


# ---------- 动作 ----------

def do_patch(args, ws: Path) -> str:
    target = resolve_target(ws, args.file)
    original = normalize(read_text(target))
    search = normalize(args.search)
    replace = normalize(args.replace)

    count = original.count(search)
    if count == 0:
        hint = ""
        first_line = search.split("\n", 1)[0].strip()
        if first_line:
            for i, line in enumerate(original.split("\n"), 1):
                if first_line in line:
                    hint = f" 相似内容在第{i}行附近，请先读取最新文件再取块"
                    break
        raise Rejected(f"search 块未找到(0 处匹配)。{hint}")
    if count > 1:
        raise Rejected(f"search 块有 {count} 处匹配，需追加更多上下文行保证唯一")

    new_content = original.replace(search, replace, 1)
    syntax_check(target, new_content)
    run_project_hooks(ws, target, new_content)
    atomic_write(target, new_content)
    delta = new_content.count("\n") - original.count("\n")
    return f"OK 已写入 {args.file} (行差 {delta:+d})"


def do_write(args, ws: Path) -> str:
    if args.content_file:
        new_content = normalize(Path(args.content_file).read_text(encoding="utf-8"))
    else:
        new_content = normalize(sys.stdin.read())
    if len(new_content.split("\n")) > MAX_OVERWRITE_LINES:
        raise Rejected(f"超过 {MAX_OVERWRITE_LINES} 行，禁止全量覆盖，请改用 patch")
    target = resolve_target(ws, args.file)
    if not target.exists():
        target.parent.mkdir(parents=True, exist_ok=True)
    else:
        read_text(target)  # 存在则先过 UTF-8 检查
    syntax_check(target, new_content)
    run_project_hooks(ws, target, new_content)
    if not target.exists():
        tmp_fd, tmp_name = tempfile.mkstemp(dir=str(target.parent),
                                            prefix="." + target.name + ".", suffix=".tmp")
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            f.write(new_content)
        os.replace(tmp_name, target)
    else:
        atomic_write(target, new_content)
    return f"OK 已覆盖 {args.file}"


def do_verify(args, ws: Path) -> str:
    target = resolve_target(ws, args.file)
    syntax_check(target, normalize(read_text(target)))
    return f"OK 语法预检通过 {args.file}"


def main() -> int:
    p = argparse.ArgumentParser(prog="safe-patcher", add_help=True,
                                description="AI 安全写入守门员")
    sub = p.add_subparsers(dest="cmd")
    pp = sub.add_parser("patch", help="唯一性匹配替换+原子写入")
    pp.add_argument("file")
    pp.add_argument("--search", required=True)
    pp.add_argument("--replace", required=True)
    pp.add_argument("--ws", default=".")
    pw = sub.add_parser("write", help="全量覆盖(小文件)")
    pw.add_argument("file")
    pw.add_argument("--content-file")
    pw.add_argument("--ws", default=".")
    pv = sub.add_parser("verify", help="仅语法预检")
    pv.add_argument("file")
    pv.add_argument("--ws", default=".")

    argv = sys.argv[1:]
    as_json = "--json" in argv
    argv = [a for a in argv if a != "--json"]
    if as_json and not any(a in ("patch", "write", "verify") for a in argv):
        # --json 快速预检结论：不执行任务本体，报告守门能力就绪状态
        import importlib.util
        checks = {
            "toml": bool(tomllib),
            "pyyaml": bool(importlib.util.find_spec("yaml")),
            "bash": bool(shutil.which("bash")),
            "node": bool(shutil.which("node")),
        }
        n = sum(checks.values())
        print(_contract("OK", "info",
                        f"就绪 patch/write/verify 可用 语法器{n}/4启用",
                        ""))
        return 0
    args = p.parse_args(argv)
    if not args.cmd:
        p.print_help()
        return 0
    try:
        ws = Path(args.ws).resolve()
        if not ws.exists():
            raise Fault(f"工作区不存在: {args.ws}")
        msg = {"patch": do_patch, "write": do_write, "verify": do_verify}[args.cmd](args, ws)
        if WARNINGS:
            msg += "\n⚠ " + "\n⚠ ".join(WARNINGS)
        if as_json:
            print(_contract("OK", "info", msg))
        else:
            print(msg)
        return 0
    except Rejected as e:
        if as_json:
            print(_contract("FAIL", "warn", str(e)[:300], "按 message 修正后重试"))
        else:
            print(f"[remedy] {e}", file=sys.stderr)
        return 1
    except Fault as e:
        if as_json:
            print(_contract("FAIL", "error", str(e)[:300], "检查备份 .bak 与临时文件"))
        else:
            print(f"ERROR: {e}", file=sys.stderr)
        return 2


def self_test() -> int:
    """金丝雀：临时目录构造好/坏样本，证明能抓到坏。"""
    import shutil as _sh
    tmp = Path(tempfile.mkdtemp(prefix="safepatcher-test."))
    failures = []
    try:
        good = tmp / "mod.py"
        good.write_text("def add(a, b):\n    return a + b\n", encoding="utf-8")

        # 1) 好补丁应成功
        class A: pass
        a = A(); a.file = "mod.py"; a.search = "return a + b"; a.replace = "return a - b"; a.ws = str(tmp)
        try:
            r = do_patch(a, tmp)
            if "OK" not in r:
                failures.append(f"好补丁未成功: {r}")
        except Exception as e:
            failures.append(f"好补丁被误杀: {e}")

        # 2) 坏补丁（语法损坏）应被拦
        a.search = "return a - b"; a.replace = "return a - b)))"
        try:
            do_patch(a, tmp)
            failures.append("语法损坏补丁未被拦截")
        except Rejected:
            pass

        # 3) 多义匹配应被拦
        multi = tmp / "dup.py"
        multi.write_text("x = 1\nx = 1\n", encoding="utf-8")
        a.file = "dup.py"; a.search = "x = 1"; a.replace = "y = 2"
        try:
            do_patch(a, tmp)
            failures.append("多义匹配未被拦截")
        except Rejected:
            pass

        # 4) 未找到应被拦
        a.search = "zzz_not_exist"
        try:
            do_patch(a, tmp)
            failures.append("未找到块未被拦截")
        except Rejected:
            pass

        # 5) 路径越界应被拦
        try:
            resolve_target(tmp, "../outside.txt")
            failures.append("路径越界未被拦截")
        except Rejected:
            pass

        # 6) 敏感文件应被拦
        try:
            resolve_target(tmp, ".env")
            failures.append("敏感文件未被拦截")
        except Rejected:
            pass

        # 7) 项目 hook：通过的 hook 放行，失败的 hook 拦截，match 不命中跳过
        (tmp / ".agent-patch.json").write_text(json.dumps({
            "hooks": [
                {"match": r"\.py$", "run": "exit 0"},
                {"match": r"\.py$", "run": "grep -q x {file}"},
                {"match": r"\.never$", "run": "exit 1"},
            ]
        }), encoding="utf-8")
        a.file = "dup.py"; a.search = "x = 1\nx = 1"; a.replace = "x = 1\nx = 9"
        try:
            do_patch(a, tmp)  # hook[0] 放行、hook[1] grep 到 x=1 通过、hook[2] 不命中
        except Rejected as e:
            failures.append(f"通过的 hook 被误杀: {e}")
        a.search = "x = 1\nx = 9"; a.replace = "a = 1\nw = 4"  # 改后内容不含 x → hook[1] 应失败
        try:
            do_patch(a, tmp)
            failures.append("失败 hook 未拦截写入")
        except Rejected:
            pass

        # 8) hook 配置损坏应 fail-open：降级放行 + ⚠ 警告（上一用例已被拦，文件仍含 x = 1）
        (tmp / ".agent-patch.json").write_text("{bad json", encoding="utf-8")
        a.search = "x = 1"
        WARNINGS.clear()
        try:
            r = do_patch(a, tmp)
            if "OK" not in r or not WARNINGS:
                failures.append(f"坏 hook 配置未 fail-open 放行: r={r} warnings={WARNINGS}")
        except Exception as e:
            failures.append(f"坏 hook 配置仍阻塞写入: {e}")

        # 9) 非代码文件不跑 hook：配置必失败的 hook，md 直写应放行
        (tmp / ".agent-patch.json").write_text(json.dumps(
            {"hooks": [{"run": "exit 1"}]}
        ), encoding="utf-8")
        md = tmp / "note.md"
        md.write_text("# n\n", encoding="utf-8")
        a.file = "note.md"; a.search = "# n"; a.replace = "# n2"
        try:
            do_patch(a, tmp)  # hook 对非代码文件不生效
        except Rejected as e:
            failures.append(f"非代码文件被 hook 误拦: {e}")

        # 10) hook 命令不可执行(127) 应 fail-open：放行（⚠ 会话内自纠）
        (tmp / ".agent-patch.json").write_text(json.dumps(
            {"hooks": [{"match": r"\.py$", "run": "definitely_not_a_cmd_xyz"}]}
        ), encoding="utf-8")
        a.file = "mod.py"; a.search = "return a - b"; a.replace = "return a * b"
        try:
            r = do_patch(a, tmp)
            if "OK" not in r:
                failures.append(f"127 hook 未 fail-open 放行: {r}")
        except Exception as e:
            failures.append(f"127 hook 仍阻塞写入: {e}")

        # 11) 语法器超时应 fail-closed：阻断 + 文件不变
        shf = tmp / "t.sh"
        shf.write_text("echo ok\n", encoding="utf-8")
        a.file = "t.sh"; a.search = "echo ok"; a.replace = "echo ok2"
        _orig_run = subprocess.run
        def _boom(*args, **kwargs):
            raise subprocess.TimeoutExpired(cmd="bash -n", timeout=10)
        subprocess.run = _boom
        try:
            do_patch(a, tmp)
            failures.append("语法器超时未 fail-closed 阻断")
        except Fault as e:
            if "SYNTAX_CHECK_TIMEOUT" not in str(e):
                failures.append(f"超时阻断缺 SYNTAX_CHECK_TIMEOUT 标记: {e}")
        finally:
            subprocess.run = _orig_run
        if shf.read_text(encoding="utf-8") != "echo ok\n":
            failures.append("fail-closed 后文件被改动")

        if failures:
            for f in failures:
                print(f"self-test FAIL: {f}")
            return 1
        print("self-test: 11/11 通过（好补丁/hook 放行/fail-open 降级；坏补丁/多义/未找到/越界/敏感文件/失败 hook/命令缺失 处置正确；非代码文件不受 hook；语法超时 fail-closed 阻断）")
        return 0
    finally:
        _sh.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(self_test())
    sys.exit(main())
