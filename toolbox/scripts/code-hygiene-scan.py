#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""code-hygiene-scan — 收集 AI 编码残留：调试语句 / 注释掉的代码 / 依赖膨胀

三类残留（均为 AI 写完就忘、随复杂度积累的典型副作用）：
1. 调试残留：System.out.println / System.err.println / printStackTrace /
   Python print( / console.log 等 / DEBUG=true 类开关；
2. 注释掉的代码：以 // 或 # 开头但呈代码形态的行（含代码关键字 + 括号/分号/赋值），
   连续 ≥1 行即报（保留注释头说明性文字不误报——须同时含代码形态特征）；
3. 依赖膨胀（可选 --deps）：pom.xml 存在时跑 mvn dependency:analyze，
   报「used undeclared（实际用了没声明）」与「unused declared（声明了没用）」。

用法: code-hygiene-scan [--json] [--md <文件>] [--root <目录>] [--deps] [--include-tests] [--self-test]
  --deps   追加依赖膨胀分析（调用 mvn/./mvnw dependency:analyze，较慢，默认不跑）
退出码: 0=无命中 1=有命中(需清理) 2=自身故障

toolbox-script
format: v1
name: code-hygiene-scan
summary: 扫调试残留/注释掉的代码/依赖膨胀（--deps），产出清理清单（通用）
trigger: manual
cat: test
alias: hyg
platform: any
self-test: --self-test
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import datetime

EXCLUDE_DIRS = {
    ".git", "node_modules", "target", "build", "dist", "out",
    "__pycache__", ".venv", "venv", ".idea", ".trash", "third_party",
}

SCAN_EXT = ("java", "py", "js", "ts", "tsx", "jsx")

# 测试代码默认跳过：src/test、__tests__、*.test.* / *.spec.* 里的调试输出与样本数据属常态，
# 误报率远高于收益；确需一并清理时加 --include-tests。
TEST_PATH_RE = re.compile(r"(^|/)(tests?|__tests__|spec)(/|$)")
TEST_FILE_RE = re.compile(r"\.(test|spec)\.[A-Za-z]+$")
INCLUDE_TESTS = False


def is_test_path(rel):
    p = rel.replace(os.sep, "/")
    return bool(TEST_PATH_RE.search(p) or TEST_FILE_RE.search(p))

# 调试输出：独立脚本/CLI 里 print/console 是正常输出通道，只在应用源码树
# （路径含 src/lib/app 等段）扫描；printStackTrace / DEBUG 开关在任意文件都异常。
APP_DEBUG_PATTERNS = [
    (re.compile(r"System\.(out|err)\.println"), "Java println"),
    (re.compile(r"^\s*print\("), "Python print"),
    (re.compile(r"\bconsole\.(log|warn|error|info|debug)\s*\("), "console.*"),
]
ALWAYS_DEBUG_PATTERNS = [
    (re.compile(r"\.printStackTrace\(\)"), "printStackTrace"),
    (re.compile(r"\b(DEBUG|DEBUG_MODE|IS_DEBUG)\s*[:=]\s*(true|True|1)\b"), "DEBUG 开关开启"),
]
APP_SEGMENTS = {"src", "lib", "app", "apps", "internal", "server", "client"}

# 注释掉的代码：须呈代码形态（关键字/调用/赋值/分号结尾）；提及方法名+括号的
# 描述性注释不误报——调用形态要求行尾为 ; 或 )；含中文的行一律不判（中文行几乎总为说明）。
_CODE_KW = r"(?:return|if|for|while|throw|new|try|catch|import|else|elif|break|continue|def|pass|raise)"
CODE_COMMENT_PATTERNS = [
    (re.compile(r"^\s*(//|#)\s*(?:%s)\b" % _CODE_KW), "注释代码(关键字)"),
    (re.compile(r"^\s*(//|#)\s*[A-Za-z_]\w*(?:\.\w+)*\s*\("), "注释代码(调用)"),
    (re.compile(r"^\s*(//|#)\s*[A-Za-z_][\w<>,.\[\]]*\s*=\s*\S"), "注释代码(赋值)"),
    (re.compile(r"^\s*//\s*\S.*;\s*$"), "注释代码(分号结尾)"),
]
_CJK_RE = re.compile(r"[\u4e00-\u9fff]")
_CODE_TAIL_RE = re.compile(r"[;)]\s*$")


def find_root(explicit):
    if explicit:
        return os.path.abspath(explicit)
    try:
        r = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        )
        return r.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return os.getcwd()


def walk_files(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
        for fn in sorted(filenames):
            if "." in fn and fn.rsplit(".", 1)[-1] in SCAN_EXT:
                yield os.path.join(dirpath, fn)


def is_app_source(rel):
    parts = rel.replace(os.sep, "/").split("/")
    return any(p in APP_SEGMENTS for p in parts[:-1])


def scan_source_file(path, rel):
    hits = []
    app = is_app_source(rel)
    with open(path, encoding="utf-8", errors="replace") as f:
        for idx, line in enumerate(f, 1):
            for rx, tag in (APP_DEBUG_PATTERNS if app else []) + ALWAYS_DEBUG_PATTERNS:
                if rx.search(line):
                    hits.append((rel, idx, tag, line.strip()[:100]))
                    break
            cjk = bool(_CJK_RE.search(line))
            for rx, tag in CODE_COMMENT_PATTERNS:
                if not rx.search(line) or cjk:
                    continue
                if "调用" in tag and not _CODE_TAIL_RE.search(line):
                    continue
                hits.append((rel, idx, tag, line.strip()[:100]))
                break
    return hits


def analyze_deps(root):
    """跑 mvn dependency:analyze（best-effort），返回 (ok, lines)。"""
    mvn = None
    for cand in (os.path.join(root, "mvnw"), "mvn"):
        if os.path.exists(cand) or shutil.which(cand):
            mvn = cand
            break
    if not mvn:
        return True, ["(未找到 mvn/./mvnw，跳过依赖分析)"]
    try:
        r = subprocess.run(
            [mvn, "dependency:analyze", "-q", "-B", "-ntp"],
            cwd=root, capture_output=True, text=True, timeout=280,
        )
    except subprocess.TimeoutExpired:
        return False, ["(mvn dependency:analyze 超时，跳过)"]
    except Exception as e:
        return False, ["(mvn dependency:analyze 执行失败: %s)" % e]
    out = (r.stdout or "") + (r.stderr or "")
    lines = []
    for m in re.finditer(r"^\s*(WARNING|ERROR).*?(undeclared|declared).*", out, re.I | re.M):
        lines.append(m.group(0).strip()[:160])
    if not lines and r.returncode == 0:
        lines = ["(dependency:analyze 无 undeclared/unused 报告)"]
    return r.returncode == 0, lines


def run_checks(root, md_out, with_deps):
    results = []
    for path in walk_files(root):
        rel = os.path.relpath(path, root)
        if not INCLUDE_TESTS and is_test_path(rel):
            continue
        results += scan_source_file(path, rel)
    results.sort(key=lambda r: (r[0], r[1]))

    dep_lines = []
    dep_ok = True
    if with_deps and os.path.exists(os.path.join(root, "pom.xml")):
        dep_ok, dep_lines = analyze_deps(root)

    if not results and (not with_deps or not dep_lines or dep_lines[0].startswith("(")):
        return True, "info", "未发现调试残留/注释代码（%s）" % ("含依赖分析" if with_deps else "未含依赖分析，--deps 可启用")

    msg = "发现 %d 处调试残留/注释代码%s，建议清理" % (
        len(results),
        "；依赖分析: %d 条" % len(dep_lines) if dep_lines and not dep_lines[0].startswith("(") else "",
    )
    if md_out:
        with open(md_out, "w", encoding="utf-8") as f:
            f.write("# 代码卫生扫描报告\n\n")
            f.write("- 日期: %s\n- 扫描根: %s\n\n" % (
                datetime.date.today(), root))
            if results:
                f.write("## 调试残留 / 注释代码（%d 处）\n\n" % len(results))
                f.write("| 位置 | 类型 | 内容 |\n|---|---|---|\n")
                for rel, ln, tag, summary in results:
                    f.write("| %s:%d | %s | %s |\n" % (rel, ln, tag, summary))
            if with_deps and dep_lines:
                f.write("\n## 依赖膨胀（dependency:analyze）\n\n")
                for l in dep_lines:
                    f.write("- %s\n" % l)
            f.write("\n> 清理建议: 调试语句删除或降级为受控日志；注释代码整段删除（git 有历史）；\n")
            f.write("> 依赖 undeclared → 补声明，unused → 移除（先确认非反射/AOT 需要）。\n")
    return (not results) and dep_ok, "warn" if results else "info", msg


def self_test():
    d = tempfile.mkdtemp()
    try:
        bad = os.path.join(d, "Bad.java")
        with open(bad, "w", encoding="utf-8") as f:
            f.write(
                "class Bad {\n"
                "  void m() {\n"
                "    System.out.println(\"debug here\");\n"
                "    // int x = compute();\n"
                "    e.printStackTrace();\n"
                "  }\n"
                "}\n"
            )
        good = os.path.join(d, "Good.java")
        with open(good, "w", encoding="utf-8") as f:
            f.write(
                "class Good {\n"
                "  // 说明性注释：这里记录了设计理由，不是代码。\n"
                "  void m() { log.info(\"ok\"); }\n"
                "}\n"
            )
        bad_rel = "src/main/java/Bad.java"
        hits = scan_source_file(bad, bad_rel)
        tags = [h[2] for h in hits]
        if "Java println" not in tags or "printStackTrace" not in tags:
            print("self-test: 调试语句未抓全: %s" % tags)
            return 2
        if not any("注释代码" in t for t in tags):
            print("self-test: 注释代码未抓到")
            return 2
        good_hits = scan_source_file(good, "src/main/java/Good.java")
        if good_hits:
            print("self-test: 好样本被误报: %s" % good_hits)
            return 2
        # 独立脚本 print 属正常输出通道 → 不误报
        tool = os.path.join(d, "tool.py")
        with open(tool, "w", encoding="utf-8") as f:
            f.write("print('hello from tool')\n")
        if scan_source_file(tool, "tool.py"):
            print("self-test: 独立脚本 print 被误报")
            return 2
        # 提及方法名+括号的英文描述注释（行尾非 ; / )）→ 不误报
        desc = os.path.join(d, "Desc.java")
        with open(desc, "w", encoding="utf-8") as f:
            f.write("class Desc {\n"
                    "  // FooBar(param) is the legacy interface, deprecated later\n"
                    "  void m() {}\n}\n")
        if scan_source_file(desc, "src/main/java/Desc.java"):
            print("self-test: 描述性注释被误报")
            return 2
        ok, _, _ = run_checks(d, None, False)
        if ok:
            print("self-test: 未能抓到已知坏样本")
            return 2
        print("self-test: OK（调试语句/注释代码可抓；说明性注释/脚本print不误报）")
        return 0
    finally:
        shutil.rmtree(d, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser(description="code-hygiene-scan")
    ap.add_argument("--json", action="store_true", help="输出契约 JSON 结论")
    ap.add_argument("--md", help="明细报告输出文件")
    ap.add_argument("--root", help="扫描根目录（默认：当前 git 仓库根）")
    ap.add_argument("--deps", action="store_true", help="追加 mvn dependency:analyze 依赖膨胀分析")
    ap.add_argument("--include-tests", action="store_true",
                    help="连测试代码一起扫（默认跳过 test/__tests__/spec 与 *.test.* / *.spec.*）")
    ap.add_argument("--self-test", action="store_true", help="金丝雀自检")
    args = ap.parse_args()
    global INCLUDE_TESTS
    INCLUDE_TESTS = args.include_tests
    if args.self_test:
        sys.exit(self_test())
    root = find_root(args.root)
    if not os.path.isdir(root):
        print("✗ 扫描根目录不存在: %s" % root)
        sys.exit(2)
    ok, severity, message = run_checks(root, args.md, args.deps)
    if args.json:
        print(json.dumps({"status": "OK" if ok else "FAIL",
                          "severity": severity, "message": message},
                         ensure_ascii=False))
    else:
        print(("✓ " if ok else "✗ ") + message)
        if args.md:
            print("报告已写入 %s" % args.md)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
