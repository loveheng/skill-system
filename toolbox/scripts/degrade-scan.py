#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""degrade-scan — 收集 AI 留下的「静默降级 / 吞异常」路径，输出评估清单

约定：AI 写码遇到「失败时兜底而非上报」（返回默认值、只记日志、吞掉异常）
且该兜底是**猜测/未核实**的，统一在兜底处写注释 `// DEGRADE: <为何兜底 + 待谁核实>`。
与 UNCERTAIN（整个实现不确定）区分——DEGRADE 专指「错误被悄悄消化」的路径。

本工具两层收集：
1. 标记层：扫 `DEGRADE:` 注释（意图，AI 写码时附）；
2. 形状层：扫典型静默失败形状（无需标记，机械可扫）：
   - Java: 空 catch / catch 体仅 log / catch 后 return 默认值（null/false/空集合等）
   - Python: except 体仅 pass / except 裸吞
   - JS/TS: 空 catch / catch 体仅 console.*
   有 throw/rethrow 的 catch 不算降级，跳过。

白名单（防已定性项重复 triage）：命中路径命中内置意图词（有意降级/有意吞/预期）
或 仓库根 `.degrade-whitelist`（每行一个正则，# 注释行；--whitelist 可覆盖）即抑制。
匹配面 = 文件路径 或 命中块 ctx 窗口（catch 关键字前 3 行至块结束）任一含行。
报告输出「白名单抑制 N 处已知项」，只报未收录的增量。

用法: degrade-scan [--json] [--md <文件>] [--root <目录>] [--whitelist <文件>] [--self-test]
退出码: 0=无命中 1=有命中(需评估) 2=自身故障

toolbox-script
format: v1
name: degrade-scan
summary: 扫 DEGRADE 标记 + 空catch/吞异常/兜底返回默认值等静默降级路径，产出评估报告＋白名单存活（反事实 GC）探针（通用）
trigger: manual
cat: test
alias: dscan
platform: any
self-test: --self-test
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

EXCLUDE_DIRS = {
    ".git", "node_modules", "target", "build", "dist", "out",
    "__pycache__", ".venv", "venv", ".idea", ".trash", "third_party",
}

LANG_EXT = {
    "java": "java",
    "py": "py",
    "js": "js",
    "ts": "ts",
    "tsx": "tsx",
    "jsx": "jsx",
}

# 标记层：DEGRADE 意图注释（任何含注释/字符串的行）
DEGRADE_RE = re.compile(r"DEGRADE\s*[:：]")

# 形状层
JAVA_CATCH_RE = re.compile(r"\bcatch\s*\(")
PY_EXCEPT_RE = re.compile(r"\bexcept\s*[^:]*:")
JS_CATCH_RE = re.compile(r"\bcatch\s*(\(|{)")

# catch/except 体「仅日志」判定：语句以 log./logger./console./System.err 开头
LOG_STMT_RE = re.compile(r"^\s*(log|logger|loggers)\.|\bSystem\.err\.|\bconsole\.(log|warn|error|info|debug)\b")
# 默认值返回
DEFAULT_RETURN_RE = re.compile(
    r"return\s+(null|false|true|\"\"|''|Collections\.(emptyList|emptyMap|emptySet)|Optional\.empty\(\))"
)

# 白名单：内置（显式意图词）+ 仓库根 .degrade-whitelist（每行一个正则，# 注释）+ --whitelist <文件>。
# 正则命中「文件路径」或「命中块上下文（catch 行起至块结束）任一含行」即抑制——
# 用于收录已定性「有意降级」的路径，避免每次扫描重复 triage 同一批已知项。
BUILTIN_WHITELIST = [
    r"有意降级",
    r"有意吞",
    r"(?<!非)预期",
]
DEGRADE_WL_FILE = ".degrade-whitelist"


def load_whitelist(root, override_file=None):
    # 返回 [(compiled_re, raw_text), ...]——raw_text=None 为内置意图词，
    # 非 None 为白名单文件行（供逐行存活归因，raw_text 用于反事实 GC 报告）。
    entries = []
    for rx in BUILTIN_WHITELIST:
        try:
            entries.append((re.compile(rx), None))
        except re.error:
            continue
    wl_path = override_file if override_file else os.path.join(root, DEGRADE_WL_FILE)
    if wl_path and os.path.isfile(wl_path):
        with open(wl_path, encoding="utf-8", errors="replace") as f:
            for ln in f:
                t = ln.strip()
                if not t or t.startswith("#"):
                    continue
                try:
                    entries.append((re.compile(t), t))
                except re.error:
                    continue  # 非法正则跳过，不致整体扫描失败
    return entries


def is_whitelisted(rel, ctx_lines, wl):
    # 返回首个命中条目下标（-1=未命中）；raw_text 非 None 的条目才计入白名单存活归因
    for i, (w, _raw) in enumerate(wl):
        if w.search(rel):
            return i
        for ln in ctx_lines:
            if w.search(ln):
                return i
    return -1


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
    self_real = os.path.realpath(__file__)  # 自排除：扫描器不扫自身（文档/金丝雀样本属自指误报）
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
        for fn in sorted(filenames):
            ext = fn.rsplit(".", 1)[-1] if "." in fn else ""
            if ext in LANG_EXT:
                p = os.path.join(dirpath, fn)
                if os.path.realpath(p) != self_real:
                    yield p


def extract_block(lines, start_i, start_col):
    """从 (start_i, start_col) 的 { 起按花括号配平截取块文本（含行号列表）。"""
    depth = 0
    buf = []
    for i in range(start_i, len(lines)):
        line = lines[i]
        buf.append((i, line))
        for ch in line[start_col if i == start_i else 0:]:
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return buf
    return buf  # 未配平：取到文件尾


def find_catch_body_brace(lines, i, start_col, has_parens):
    """找 catch 体块开 { 的位置 (行, 列)；has_parens=True 为 catch(...) 形式。
    从 catch 关键字起括号配平找参数表闭 )，再取其后第一个 {，
    避免行前导 }（} catch ...）与字符串内括号干扰计数。"""
    n = len(lines)
    li, ci = i, start_col
    if has_parens:
        while li < n:  # ① 参数表第一个 '('
            idx = lines[li].find("(", ci)
            if idx != -1:
                ci = idx
                break
            li += 1
            ci = 0
        if li >= n:
            return None
        depth = 0  # ② 括号配平 → 匹配的 ')'
        closed = None
        while li < n:
            k = ci
            while k < len(lines[li]):
                ch = lines[li][k]
                if ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                    if depth == 0:
                        closed = k + 1
                        break
                k += 1
            if closed is not None:
                ci = closed
                break
            li += 1
            ci = 0
        if closed is None:
            return None
    while li < n:  # ③ 闭 )（或 catch 关键字）后第一个 '{' 即块开
        idx = lines[li].find("{", ci)
        if idx != -1:
            return (li, idx)
        li += 1
        ci = 0
    return None


def body_statements(block):
    """块（去掉首尾大括号所在片段）内的非空、非注释语句行。"""
    stmts = []
    for i, line in block:
        s = line.strip()
        if not s or s.startswith("//") or s.startswith("*") or s.startswith("#"):
            continue
        if s in ("{", "}", "} catch", "else", "finally {"):
            continue
        if "{" in s:
            s = s[s.index("{") + 1:]
            s = s.strip()
            if not s or s.startswith("//"):
                continue
        if s == "}":
            continue
        stmts.append((i, s))
    return stmts


def scan_catch_family(lines, catch_re, is_py=False, is_js=False):
    """返回 [(行号, 分类, 摘要)]。"""
    hits = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        m = catch_re.search(line)
        if not m:
            i += 1
            continue
        catch_kw_i = i  # catch/except 关键字行（0-based），供 ctx 窗口起点
        if not is_py:
            has_parens = not (is_js and m.group(1) == "{")
            pos = find_catch_body_brace(lines, i, m.start(), has_parens)
            if pos is None:
                i += 1
                continue
            brace_i, brace_col = pos
            block = extract_block(lines, brace_i, brace_col)
            # 跳过本 catch 之后的行
            i = block[-1][0] + 1 if block else brace_i + 1
        else:
            # Python: except 行之后缩进块
            block = []
            base_indent = None
            for k in range(i + 1, n):
                raw = lines[k]
                if raw.strip() == "":
                    continue
                indent = len(raw) - len(raw.lstrip())
                if base_indent is None:
                    base_indent = indent
                if indent < base_indent:
                    break
                block.append((k, raw))
            i = (block[-1][0] + 1) if block else i + 1

        body = body_statements(block)
        catch_lineno = catch_kw_i  # 0-based，append 处 +1 转 1-based 指向 catch/except 关键字行
        text = "\n".join(s for _, s in body)
        block_end = block[-1][0] if block else catch_kw_i
        # ctx 窗口：catch 关键字前 3 行（覆盖上方注释）至块结束，供白名单匹配
        ctx = lines[max(0, catch_kw_i - 3):block_end + 1]
        if not body:
            inner = [s for _, s in block if s.strip().startswith(("//", "#"))]
            note = "（内含注释: %s）" % inner[0].strip()[:60] if inner else ""
            hits.append((catch_lineno + 1, "空catch(吞异常)", "catch 体为空" + note, ctx))
        elif "throw" in text:
            continue  # 有 rethrow，不算静默降级
        elif all(LOG_STMT_RE.match(s) for _, s in body):
            hits.append((catch_lineno + 1, "仅日志吞异常", "异常只被记录，未上报/未重抛", ctx))
        elif DEFAULT_RETURN_RE.search(text) and (not is_js):
            hits.append((catch_lineno + 1, "兜底返回默认值", "catch 后返回 null/false/空集合，调用方无感知", ctx))
        elif is_js and any("console." in s for _, s in body) and len(body) <= 2:
            hits.append((catch_lineno + 1, "JS仅console吞异常", "catch 体仅 console 输出", ctx))
        elif is_py and all(s.split("#", 1)[0].strip() == "pass" for _, s in body):
            hits.append((catch_lineno + 1, "except仅pass(吞异常)", "except 体仅 pass", ctx))
    return hits


def scan_file(path, rel, wl):
    hits = []
    suppressed = 0
    line_counts = {}  # 白名单文件行 raw → 该行抑制的发现数（存活归因）
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()
    ext = path.rsplit(".", 1)[-1]

    def _consider(ctx, lineno, tag, summary):
        nonlocal suppressed
        i = is_whitelisted(rel, ctx, wl)
        if i >= 0:
            suppressed += 1
            raw = wl[i][1]
            if raw is not None:
                line_counts[raw] = line_counts.get(raw, 0) + 1
        else:
            hits.append((rel, lineno, tag, summary))

    # 标记层
    for idx, line in enumerate(lines):
        if DEGRADE_RE.search(line):
            _consider([line], idx + 1, "DEGRADE标记", line.strip()[:100])
    # 形状层
    try:
        if ext == "java":
            raw = scan_catch_family(lines, JAVA_CATCH_RE)
        elif ext == "py":
            raw = scan_catch_family(lines, PY_EXCEPT_RE, is_py=True)
        elif ext in ("js", "ts", "tsx", "jsx"):
            raw = scan_catch_family(lines, JS_CATCH_RE, is_js=True)
        else:
            raw = []
        for lineno, tag, summary, ctx in raw:
            _consider(ctx, lineno, tag, summary)
    except Exception:
        pass  # 有意降级：单文件解析失败不中断全局扫描
    return hits, suppressed, line_counts


def run_checks(root, md_out, wl_file=None):
    wl = load_whitelist(root, wl_file)
    results = []
    suppressed = 0
    line_counts = {}
    for path in walk_files(root):
        rel = os.path.relpath(path, root)
        h, s, lc = scan_file(path, rel, wl)
        results += h
        suppressed += s
        for k, v in lc.items():
            line_counts[k] = line_counts.get(k, 0) + v
    # 结果统一为 (rel, lineno, tag, summary)
    results = [r for r in results if len(r) == 4]
    results.sort(key=lambda r: (r[0], r[1]))

    # 白名单存活（反事实 GC 探针）：某文件行当前抑制 0 处发现
    # = 删掉它不会多报任何一条 → 失效白名单（僵尸行），建议清理恢复监控。
    file_lines = [raw for (_rx, raw) in wl if raw is not None]
    stale = [ln for ln in file_lines if line_counts.get(ln, 0) == 0]
    stale_note = ""
    if stale:
        stale_note = "；失效白名单 %d 行（当前未抑制任何发现，建议清理）" % len(stale)

    if not results:
        return True, "info", "未发现静默降级/吞异常路径（白名单抑制 %d 处已知项）%s" % (suppressed, stale_note), stale

    msg = "发现 %d 处静默降级/吞异常路径（%s），白名单抑制 %d 处已知项，建议逐处评估是否应上报 (md 可导出明细)%s" % (
        len(results),
        "标记" if all(r[2] == "DEGRADE标记" for r in results) else "标记+形状",
        suppressed,
        stale_note,
    )
    if md_out:
        with open(md_out, "w", encoding="utf-8") as f:
            f.write("# 静默降级扫描报告\n\n")
            f.write("- 日期: %s\n- 扫描根: %s\n- 命中: %d 处（白名单抑制 %d 处已知有意降级）\n\n" % (
                __import__("datetime").date.today(), root, len(results), suppressed))
            f.write("| 位置 | 类型 | 内容 |\n|---|---|---|\n")
            for rel, ln, tag, summary in results:
                f.write("| %s:%d | %s | %s |\n" % (rel, ln, tag, summary))
            if stale:
                f.write("\n## 失效白名单（反事实：删此行不会多报任何发现，建议清理恢复监控）\n\n")
                f.write("| 白名单行 | 当前抑制 |\n|---|---|\n")
                for ln in stale:
                    f.write("| %s | 0 |\n" % ln)
            f.write("\n> 评估建议: 兜底路径若属「有意降级」补注释说明理由；若属「未核实的猜测」\n")
            f.write("> 升级为 UNCERTAIN/DEGRADE 标记，高危项（正确性/数据一致性）转 todos 风险类。\n")
    return False, "warn", msg, stale


def self_test():
    d = tempfile.mkdtemp()
    try:
        # 坏样本：空 catch + DEGRADE 标记 + 仅日志 catch
        bad = os.path.join(d, "Bad.java")
        with open(bad, "w", encoding="utf-8") as f:
            f.write(
                "class Bad {\n"
                "  void m() {\n"
                "    try { x(); }\n"
                "    catch (Exception e) {}\n"
                "    try { y(); }\n"
                "    // DEGRADE: 渠道不可用时兜底返回空，待产品确认\n"
                "    catch (Exception e) { log.warn(e); }\n"
                "  }\n"
                "}\n"
            )
        good = os.path.join(d, "Good.java")
        with open(good, "w", encoding="utf-8") as f:
            f.write(
                "class Good {\n"
                "  void m() {\n"
                "    try { x(); }\n"
                "    catch (Exception e) { throw new RuntimeException(e); }\n"
                "  }\n"
                "}\n"
            )
        wl = load_whitelist(d)
        hits = []
        for path in (bad, good):
            h, _s, _lc = scan_file(path, path, wl)
            hits += h
        tags = [h[2] for h in hits]
        if not any(t == "空catch(吞异常)" for t in tags):
            print("self-test: 空 catch 未抓到")
            return 2
        if not any(t == "DEGRADE标记" for t in tags):
            print("self-test: DEGRADE 标记未抓到")
            return 2
        if not any(t == "仅日志吞异常" for t in tags):
            print("self-test: 仅日志 catch 未抓到")
            return 2
        good_tags = [h[2] for h in hits if h[0].endswith("Good.java")]
        if good_tags:
            print("self-test: 好样本（有 rethrow）被误报")
            return 2
        # 白名单：块内含「有意降级」注释的路径应被抑制
        wled = os.path.join(d, "Wled.java")
        with open(wled, "w", encoding="utf-8") as f:
            f.write(
                "class Wled {\n"
                "  void m() {\n"
                "    try { x(); }\n"
                "    // 有意降级：渠道不可用时兜底返回空\n"
                "    catch (Exception e) { log.warn(e); return null; }\n"
                "  }\n"
                "}\n"
            )
        wh, _ws, _wlc = scan_file(wled, "Wled.java", wl)
        if wh:
            print("self-test: 内置白名单（有意降级注释）未抑制: %s" % wh)
            return 2
        # 白名单：.degrade-whitelist 文件按路径抑制
        with open(os.path.join(d, DEGRADE_WL_FILE), "w", encoding="utf-8") as f:
            f.write("# 已定性有意降级\nGood.java\n")
        wl2 = load_whitelist(d)
        h2, _s2, _lc2 = scan_file(good, "Good.java", wl2)
        # Good.java 有 rethrow 本就不报；改用 Wled 路径验证路径抑制
        h3, _s3, _lc3 = scan_file(wled, "Wled.java", wl2)
        if h3:
            print("self-test: .degrade-whitelist 路径抑制未生效: %s" % h3)
            return 2
        # 白名单存活（反事实 GC）：存活行（抑制发现）不列，失效行（零命中）被识别
        zed = os.path.join(d, "Zed.java")
        with open(zed, "w", encoding="utf-8") as f:
            f.write(
                "class Zed {\n"
                "  void m() {\n"
                "    try { x(); }\n"
                "    catch (Exception e) { log.warn(e); return null; }\n"
                "  }\n"
                "}\n"
            )
        with open(os.path.join(d, DEGRADE_WL_FILE), "w", encoding="utf-8") as f:
            f.write("# 存活/失效各一行\nZed.java\nNoSuchPath\\.java\n")
        wl3 = load_whitelist(d)
        _hz, _sz, lc = scan_file(zed, "Zed.java", wl3)
        if _hz:
            print("self-test: Zed.java 应被白名单行抑制: %s" % _hz)
            return 2
        file_lines3 = [raw for (_rx, raw) in wl3 if raw is not None]
        stale3 = [ln for ln in file_lines3 if lc.get(ln, 0) == 0]
        if "Zed.java" in stale3:
            print("self-test: 存活白名单行（Zed.java）被误判失效: %s" % stale3)
            return 2
        if "NoSuchPath\\.java" not in stale3:
            print("self-test: 失效白名单行未被识别为失效: %s" % stale3)
            return 2
        print("self-test: OK（空catch/仅日志/DEGRADE 可抓，rethrow 不误报，白名单抑制生效，存活探针可分存活/失效行）")
        return 0
    finally:
        import shutil
        shutil.rmtree(d, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser(description="degrade-scan")
    ap.add_argument("--json", action="store_true", help="输出契约 JSON 结论")
    ap.add_argument("--md", help="明细报告输出文件")
    ap.add_argument("--root", help="扫描根目录（默认：当前 git 仓库根）")
    ap.add_argument("--whitelist", help="自定义白名单文件（每行一个正则，# 注释行；默认用仓库根 .degrade-whitelist）")
    ap.add_argument("--self-test", action="store_true", help="金丝雀自检")
    args = ap.parse_args()
    if args.self_test:
        sys.exit(self_test())
    root = find_root(args.root)
    if not os.path.isdir(root):
        print("✗ 扫描根目录不存在: %s" % root)
        sys.exit(2)
    ok, severity, message, stale = run_checks(root, args.md, args.whitelist)
    if args.json:
        print(json.dumps({"status": "OK" if ok else "FAIL",
                          "severity": severity, "message": message,
                          "stale_whitelist": stale},
                         ensure_ascii=False))
    else:
        print(("✓ " if ok else "✗ ") + message)
        if args.md:
            print("报告已写入 %s" % args.md)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
