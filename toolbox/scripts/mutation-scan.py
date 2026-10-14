#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""mutation-scan — 最小变异测试：验证测试套件的断言能力（杀灭变异体才算有效测试）

对目标源码文件注入微小逻辑变异（条件反转 / 边界偏移 / 布尔翻转），
逐个变异体跑测试命令：测试变红 = 变异体被杀灭（断言有效）；
测试仍绿 = 变异体存活（该处测试是空心的，抓不住真 bug）。
支持语言: py / js / ts / java / dart（--lang 强制，默认按扩展名推断）。

用法:
  mutation-scan --files <文件,文件...> --test-cmd "<命令>" [--root <目录>]
  mutation-scan --root <目录> --test-cmd "<命令>"        # 自动扫非测试源码文件
  mutation-scan --json                                    # 预检结论（不执行变异本体）
  mutation-scan --dry-run ...                             # 只列将生成的变异点，不跑测试
  mutation-scan --self-test                               # 金丝雀自测
参数:
  --files        逗号分隔的目标源码文件（优先于 --root 扫描）
  --root         扫描根目录（默认当前目录）；自动排除 tests/spec/test_* 等测试路径
  --test-cmd     测试命令字符串（shell 执行），如 "pytest -q" / "npm test"
  --lang         强制语言 py|js|java（默认按扩展名推断）
  --max N        最多注入变异体数（默认 30，防测试套件慢时爆炸）
  --timeout S    单次测试运行超时秒数（默认 120）
  --md <文件>    导出 Markdown 报告
退出码: 0=全部变异被杀灭(或无变异点) 1=存在存活变异(测试空心) 2=自身故障
安全: 变异前备份原文件、finally 强制还原并校验字节一致；建议在干净 git 工作区运行。

toolbox-script
format: v1
name: mutation-scan
summary: 最小变异测试——注入条件/布尔变异体验证测试断言能力，存活即测试空心（通用）
trigger: manual
cat: test
alias: mscan
platform: any
self-test: --self-test
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

# ---------- 变异算子（按语言） ----------
# 每条: (算子名, 编译好的正则, 映射函数)；每个匹配点 = 一个变异体
def _mk_cmp(py=False):
    pairs = [("<=", "<"), (">=", ">"), ("==", "!="), ("!=", "==")]
    if py:
        pairs += [(r">", ">="), (r"<", "<=")]
    else:
        pairs += [(r">", ">="), (r"<", "<=")]
    def flip(m):
        tok = m.group(0)
        for a, b in pairs:
            if tok == a:
                return b
        return tok
    pat = r"(?<![<>=!])(<=|>=|==|!=|>|<)(?![<>=])"
    return ("边界/相等反转", re.compile(pat), flip)

PY_OPS = [
    _mk_cmp(True),
    ("and/or 反转", re.compile(r"\b(and|or)\b"), lambda m: "or" if m.group(0) == "and" else "and"),
    ("返回值翻转", re.compile(r"\breturn\s+(True|False)\b"), lambda m: "return False" if m.group(1) == "True" else "return True"),
    ("加减互换", re.compile(r"(?<![-+<>])\+(?![+=])"), lambda m: "-"),
    ("not 取反", re.compile(r"\bnot\s+(?=\w)"), lambda m: ""),
]
JS_JAVA_OPS = [
    _mk_cmp(False),
    ("&&/|| 反转", re.compile(r"&&|\|\|"), lambda m: "||" if m.group(0) == "&&" else "&&"),
    ("返回值翻转", re.compile(r"\breturn\s+(true|false)\b"), lambda m: "return false" if m.group(1) == "true" else "return true"),
]

LANG_OPS = {
    "py": PY_OPS,
    "js": JS_JAVA_OPS,
    "java": JS_JAVA_OPS,
    "dart": JS_JAVA_OPS,  # Dart 算子与 Java 同构（&&/||、true/false、比较符）
}
EXT_LANG = {".py": "py", ".js": "js", ".ts": "js", ".tsx": "js", ".jsx": "js", ".java": "java", ".dart": "dart"}
TEST_PATH_RE = re.compile(r"(^|/)(tests?|spec|__tests__)(/|$)")
TEST_FILE_RE = re.compile(r"(test_[^/]*\.py$|[^/]*_test\.py$|\.(test|spec)\.[A-Za-z]+$|Test[^/]*\.java$|[^/]*_test\.dart$)")

def is_test_path(rel):
    p = rel.replace(os.sep, "/")
    return bool(TEST_PATH_RE.search(p) or TEST_FILE_RE.search(p))

def detect_lang(path, forced):
    if forced:
        return forced
    return EXT_LANG.get(os.path.splitext(path)[1])

def line_is_comment(line, lang):
    s = line.lstrip()
    if lang == "py":
        return s.startswith("#") or s.startswith('"""') or s.startswith("'''")
    return s.startswith("//") or s.startswith("/*") or s.startswith("*")

# ---------- 变异点生成 ----------
def gen_mutants(path, lang):
    """返回 [(line_no, desc, new_line)]，每个元素即一个变异体（整行替换式）"""
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()
    ops = LANG_OPS[lang]
    out = []
    for i, line in enumerate(lines, 1):
        if line_is_comment(line, lang):
            continue
        for name, rx, fn in ops:
            if rx.search(line):
                new_line = rx.sub(fn, line)
                if new_line != line:
                    out.append((i, "%s: %s" % (name, line.strip()[:60]), new_line))
    return out

# ---------- 执行引擎 ----------
def run_tests(cmd, cwd, timeout):
    try:
        r = subprocess.run(cmd, shell=True, cwd=cwd,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           timeout=timeout)
        return r.returncode
    except subprocess.TimeoutExpired:
        return -9  # 超时视为测试未通过（杀灭）

def apply_and_test(path, new_line, line_no, test_cmd, root, timeout):
    """注入单个变异 → 跑测试 → 还原。返回 True=被杀灭（测试红/报错/超时）"""
    with open(path, "rb") as f:
        orig = f.read()
    orig_hash = hashlib.sha256(orig).hexdigest()
    lines = orig.decode("utf-8", errors="replace").splitlines(keepends=True)
    lines[line_no - 1] = new_line
    try:
        with open(path, "wb") as f:
            f.write("".join(lines).encode("utf-8"))
        rc = run_tests(test_cmd, root, timeout)
        return rc != 0
    finally:
        with open(path, "wb") as f:
            f.write(orig)
        with open(path, "rb") as f:
            assert hashlib.sha256(f.read()).hexdigest() == orig_hash, "还原校验失败: %s" % path

# ---------- 扫描目标 ----------
def collect_targets(root, files_arg, forced_lang):
    targets = []
    if files_arg:
        for p in files_arg.split(","):
            p = p.strip()
            if p and os.path.isfile(p):
                targets.append(p)
    else:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in (
                ".git", "node_modules", "target", "build", "dist", "out",
                "__pycache__", ".venv", "venv", ".idea")]
            for fn in filenames:
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, root)
                if is_test_path(rel):
                    continue
                if detect_lang(full, forced_lang) in LANG_OPS:
                    targets.append(full)
    return sorted(targets)

# ---------- 报告与结论 ----------
def emit(args, targets, mutants_planned, killed, survived, results):
    lines = ["# mutation-scan 报告", ""]
    lines.append("- 目标文件: %d" % len(targets))
    lines.append("- 变异体: 计划 %d / 已执行 %d ｜ 杀灭 %d ｜ 存活 %d" % (
        mutants_planned, len(results), killed, survived))
    if survived:
        lines.append("")
        lines.append("## 存活变异（测试盲区，断言空心）")
        for path, line_no, desc in results:
            if desc[0] == "SURVIVED":
                lines.append("- `%s:%d` %s" % (path, line_no, desc[1]))
    if args.md:
        with open(args.md, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")

def json_out(status, severity, message, remedy=None):
    obj = {"status": status, "severity": severity, "message": message}
    if remedy:
        obj["remedy"] = remedy
    print(json.dumps(obj, ensure_ascii=False))
    sys.exit(0 if status == "OK" else (1 if status == "FAIL" else 2))

# ---------- 主流程 ----------
def main():
    ap = argparse.ArgumentParser(add_help=True, description="最小变异测试（见模块 docstring）")
    ap.add_argument("--files", help="逗号分隔的目标源码文件")
    ap.add_argument("--root", default=".", help="扫描根目录")
    ap.add_argument("--test-cmd", help="测试命令字符串")
    ap.add_argument("--lang", choices=["py", "js", "java", "dart"], help="强制语言")
    ap.add_argument("--max", type=int, default=30, help="最多变异体数")
    ap.add_argument("--timeout", type=int, default=120, help="单次测试超时秒")
    ap.add_argument("--md", help="导出 Markdown 报告路径")
    ap.add_argument("--dry-run", action="store_true", help="只列变异点，不跑测试")
    ap.add_argument("--json", action="store_true", help="单行 JSON 预检结论（不执行变异本体）")
    ap.add_argument("--self-test", action="store_true", help="金丝雀自测")
    args = ap.parse_args()

    if args.self_test:
        sys.exit(self_test())

    root = os.path.abspath(args.root)
    if not os.path.isdir(root):
        json_out("FAIL", "error", "root 不存在: %s" % root, "确认 --root 路径")

    if args.json:
        # 预检语义：只验证前置条件，不跑变异本体
        targets = collect_targets(root, args.files, args.lang)
        cmd = args.test_cmd or guess_test_cmd(targets)
        if not targets:
            json_out("FAIL", "warn", "未找到可变异的源码文件",
                     "用 --files 指定文件或确认 --root 下存在 py/js/ts/java 源码")
        if not cmd:
            json_out("FAIL", "warn", "未指定 --test-cmd 且无法自动探测测试命令",
                     "显式传 --test-cmd，如 \"pytest -q\"")
        json_out("OK", "info", "预检通过: 目标 %d 文件, 测试命令 %s" % (len(targets), cmd))

    if not args.test_cmd:
        targets0 = collect_targets(root, args.files, args.lang)
        args.test_cmd = guess_test_cmd(targets0)
        if not args.test_cmd:
            print("[remedy] 未指定 --test-cmd 且无法自动探测；显式传如 --test-cmd \"pytest -q\"", file=sys.stderr)
            sys.exit(2)

    targets = collect_targets(root, args.files, args.lang)
    if not targets:
        print("未找到可变异的源码文件 [remedy] 用 --files 指定文件", file=sys.stderr)
        sys.exit(2)

    # 生成变异点并截断
    plan = []  # (path, lang, line_no, desc, new_line)
    for path in targets:
        lang = detect_lang(path, args.lang)
        for line_no, desc, new_line in gen_mutants(path, lang):
            plan.append((path, lang, line_no, desc, new_line))
    if len(plan) > args.max:
        plan = plan[:args.max]

    if args.dry_run:
        for path, lang, line_no, desc, _ in plan:
            print("%s:%d  %s" % (os.path.relpath(path, root), line_no, desc))
        print("共 %d 个变异点 [dry-run] 未执行测试" % len(plan))
        sys.exit(0)
    if not plan:
        print("无可用变异点（目标全为测试文件或无可变异行）")
        sys.exit(0)

    # 基线门禁：变异前测试必须全绿——基线红了，杀灭统计无意义（命令缺失/已有失败都会假绿）
    base_rc = run_tests(args.test_cmd, root, args.timeout)
    if base_rc != 0:
        print("[remedy] 测试基线非绿 (rc=%d)：先修复测试套件或确认 --test-cmd 可用，再跑变异测试" % base_rc, file=sys.stderr)
        sys.exit(2)

    killed = survived = errors = 0
    results = []  # (relpath, line_no, ("SURVIVED"|"KILLED", desc))
    for path, lang, line_no, desc, new_line in plan:
        try:
            killed_i = apply_and_test(path, new_line, line_no, args.test_cmd, root, args.timeout)
        except (OSError, AssertionError) as e:
            print("[remedy] 变异执行异常 %s:%d: %s" % (path, line_no, e), file=sys.stderr)
            errors += 1
            continue
        rel = os.path.relpath(path, root)
        if killed_i:
            killed += 1
            results.append((rel, line_no, ("KILLED", desc)))
        else:
            survived += 1
            results.append((rel, line_no, ("SURVIVED", desc)))

    emit(args, targets, len(plan), killed, survived, results)
    print("变异测试完成: 执行 %d ｜ 杀灭 %d ｜ 存活 %d%s" % (
        len(results), killed, survived,
        (" ｜ 报告: %s" % args.md) if args.md else ""))
    if errors:
        print("[remedy] %d 个变异体执行异常未计入，检查 --test-cmd 与工作区状态" % errors, file=sys.stderr)
    sys.exit(1 if survived else 0)

def guess_test_cmd(targets):
    """按目标文件类型探测默认测试命令"""
    has = lambda ext: any(p.endswith(ext) for p in targets)
    if has(".py") and shutil.which("pytest"):
        return "pytest -q"
    if (has(".js") or has(".ts")) and shutil.which("npx"):
        return "npx jest --silent"
    return None

# ---------- 金丝雀自测 ----------
def self_test():
    """坏样本必须被杀灭判定为空心（存活>0 且 exit 1），好样本必须全杀灭（exit 0）"""
    tmp = tempfile.mkdtemp(prefix="mscan-selftest-")
    try:
        # 样本 1：真测试（实断言）→ 变异应被杀灭（测试命令用纯 stdlib 断言脚本，不依赖 pytest）
        # 注意样本设计：变异体必须非语义等价——如 `a > 0` 在加减法下翻 `>=` 时 a=0 是不动点，杀不死
        d1 = os.path.join(tmp, "good"); os.makedirs(d1)
        with open(os.path.join(d1, "calc.py"), "w") as f:
            f.write("def score(a):\n    if a > 10:\n        return 100\n    return a\n\n\n"
                    "def enabled(flag):\n    if flag:\n        return True\n    return False\n")
        with open(os.path.join(d1, "run_test.py"), "w") as f:
            f.write("import sys\nfrom calc import score, enabled\n"
                    "ok = (score(5) == 5) and (score(10) == 10) and (score(20) == 100) "
                    "and (enabled(True) is True) and (enabled(False) is False)\n"
                    "print('PASS' if ok else 'FAIL')\nsys.exit(0 if ok else 1)\n")
        rc = run_case(d1, "python3 run_test.py")
        if rc != 0:
            print("金丝雀失败: 真测试场景未全杀灭（存活被误报）", file=sys.stderr)
            return 1
        # 样本 2：空心测试（永真断言）→ 变异应存活（score(5) 不受 `>`→`>=` 边界变异影响）
        d2 = os.path.join(tmp, "hollow"); os.makedirs(d2)
        with open(os.path.join(d2, "calc.py"), "w") as f:
            f.write("def score(a):\n    if a > 10:\n        return 100\n    return a\n")
        with open(os.path.join(d2, "run_test.py"), "w") as f:
            f.write("import sys\nfrom calc import score\nr = score(5)\nok = r is not None\n"
                    "print('PASS' if ok else 'FAIL')\nsys.exit(0 if ok else 1)\n")
        rc = run_case(d2, "python3 run_test.py")
        if rc != 1:
            print("金丝雀失败: 空心测试场景未检出存活变异", file=sys.stderr)
            return 1
        print("self-test 通过: 真测试全杀灭 / 空心测试检出存活")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

def run_case(cwd, cmd):
    p = subprocess.run([sys.executable, os.path.abspath(__file__),
                        "--files", os.path.join(cwd, "calc.py"),
                        "--test-cmd", cmd, "--root", cwd],
                       cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
    return p.returncode

if __name__ == "__main__":
    main()
