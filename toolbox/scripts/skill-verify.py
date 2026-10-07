#!/usr/bin/env python3
# skill-verify —— project-local skill 锚点对仓库现实的批量机械校验（dev-init §1.5 第 1 项 / dev-loop §7 第 9 项配套）
# 从 <repo>/.agents/skills/*/SKILL.md 提取三类锚点并机械核验：
#   路径锚点（反引号内含 / 或扩展名的仓库相对路径 → test -e）
#   命令锚点（围栏块内命令首 token → ./wrapper 存在性或 PATH 可寻；内联 span 仅认 ./wrapper 形态）
#   符号锚点（反引号内 com.foo.Bar 形 FQN 且末段类名大写 → 全仓代码 grep 命中）
# 定位：机械半边自动化；语义核实（锚点该不该存在/命令含义/接口行为）仍归 AI 与人。
# 精度优先：判不准的一律不报（宁漏报不误报），⩾ 误报会摧毁机械校验的可信度。
#
# toolbox-script
# format: v1
# name: skill-verify
# summary: project-local skill 锚点批量校验（路径 test -e / 命令 PATH / 类名 FQN 全仓 grep），机械半边自动化，语义核实留 AI
# trigger: manual
# cat: docs
# alias: sver
# platform: any
# self-test: --self-test

import argparse
import json
import os
import re
import shutil
import sys
import tempfile

SPAN_RE = re.compile(r"`([^`\n]+)`")
FENCE_RE = re.compile(r"^\s*(```|~~~)")
FQN_RE = re.compile(r"^[a-z][a-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*){2,}$")
PATH_RE = re.compile(r"^\.?[\w][\w.@+-]*(/[\w.@+-]+)*/?$")
VER_RE = re.compile(r"^v?\d+(\.\d+)*$")
CMD_TOKEN_RE = re.compile(r"^[a-z][a-z0-9_-]+$")
CODE_EXTS = {".java", ".kt", ".py", ".ts", ".tsx", ".js", ".jsx", ".go", ".rs", ".cs",
             ".php", ".rb", ".scala", ".sh", ".sql", ".c", ".cpp", ".h"}
SKIP_DIRS = {".git", "node_modules", "target", "build", "dist", ".venv", "venv",
             "__pycache__", ".idea", "vendor", ".gradle", ".next"}
MAX_CODE_FILES = 8000
BUILTIN_OK = {"cd", "echo", "export", "source", "true", "false", "set", "sleep", "test"}


def iter_skill_files(root, only=None):
    sk = os.path.join(root, ".agents", "skills")
    if not os.path.isdir(sk):
        return
    for name in sorted(os.listdir(sk)):
        if name.startswith("."):
            continue
        if only and name != only:
            continue
        sm = os.path.join(sk, name, "SKILL.md")
        if os.path.isfile(sm):
            yield name, sm


def extract_anchors(md_path):
    """返回 (paths, cmds, fqns)，元素均为 (锚点, 行号)。"""
    paths, cmds, fqns = [], [], []
    try:
        with open(md_path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except OSError:
        return paths, cmds, fqns
    state = "body"  # front=frontmatter 内 | code=围栏代码块内 | body
    for lineno, raw in enumerate(lines, 1):
        line = raw.rstrip("\n")
        if state == "front":
            if line.strip() == "---":
                state = "body"
            continue
        if FENCE_RE.match(line):
            state = "body" if state == "code" else "code"
            continue
        in_code = state == "code"
        for span in SPAN_RE.findall(line):
            s = span.strip().rstrip(".,;:)")
            if not s:
                continue
            if FQN_RE.match(s) and s.rsplit(".", 1)[1][:1].isupper():
                fqns.append((s, lineno))
                continue
            if PATH_RE.match(s) and ("/" in s or "." in s) and not s.isupper() \
                    and not ("/" not in s and VER_RE.match(s)):
                paths.append((s.rstrip("/"), lineno))
                continue
            if s.startswith(("./", "bin/")):
                cmds.append((s.split()[0], lineno))
        if in_code:
            t = line.strip()
            if t and not t.startswith(("#", "$", "//")):
                tok = t.split()[0]
                if tok.startswith(("./", "bin/")) or CMD_TOKEN_RE.match(tok):
                    cmds.append((tok, lineno))
    return paths, cmds, fqns


def check_path(root, anchor):
    return os.path.exists(os.path.join(root, anchor))


def check_cmd(root, tok):
    if tok.startswith(("./", "bin/")):
        return os.path.exists(os.path.join(root, tok))
    if tok in BUILTIN_OK or shutil.which(tok):
        return True
    return False


def build_code_index(root):
    files = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
        for fn in filenames:
            if os.path.splitext(fn)[1] in CODE_EXTS:
                files.append(os.path.join(dirpath, fn))
                if len(files) >= MAX_CODE_FILES:
                    return files
    return files


def check_fqn(fqn, index):
    needle = fqn.rsplit(".", 1)[1]
    for p in index:
        try:
            with open(p, "r", encoding="utf-8", errors="replace") as f:
                if needle in f.read():
                    return True
        except OSError:
            continue
    return False


def verify(root, only=None):
    """返回 (rows, stats, exit 码)；rows=[(skill 名, [(ok, 类型, 锚点, 行号, 备注)])]。"""
    rows, stats = [], {"路径": [0, 0], "命令": [0, 0], "符号": [0, 0]}
    skills = list(iter_skill_files(root, only))
    if not skills:
        return rows, stats, 1
    index = None
    for name, sm in skills:
        paths, cmds, fqns = extract_anchors(sm)
        srows, seen = [], set()
        for a, ln in paths:
            if a in seen:
                continue
            seen.add(a)
            ok = check_path(root, a)
            stats["路径"][0 if ok else 1] += 1
            srows.append((ok, "路径", a, ln, ""))
        for a, ln in cmds:
            if a in seen:
                continue
            seen.add(a)
            ok = check_cmd(root, a)
            stats["命令"][0 if ok else 1] += 1
            srows.append((ok, "命令", a, ln, ""))
        if fqns and index is None:
            index = build_code_index(root)
        for a, ln in fqns:
            if a in seen:
                continue
            seen.add(a)
            ok = check_fqn(a, index or [])
            stats["符号"][0 if ok else 1] += 1
            srows.append((ok, "符号", a, ln, ""))
        rows.append((name, srows))
    warn = stats["路径"][1] + stats["命令"][1] + stats["符号"][1]
    return rows, stats, (0 if warn == 0 else 1)


def render(root, rows, stats):
    out = ["# skill-verify — %s" % root, ""]
    for name, srows in rows:
        out.append("## %s" % name)
        warn = [r for r in srows if not r[0]]
        for ok, kind, a, ln, extra in warn:
            note = {"路径": "不存在（指针过期或仓内已移位）",
                    "命令": "不可寻——环境缺配、CI-only 或文档过期，人工判定",
                    "符号": "代码中未命中（跨仓/生成物/拼写漂移？）"}.get(kind, "")
            out.append("- ⚠ %s `%s` :%d — %s" % (kind, a, ln, note))
        okcnt = len(srows) - len(warn)
        out.append("- ✓ %d 项命中（略）" % okcnt if okcnt else "- （无 ✓ 项）")
        out.append("")
    out.append("小结: 路径 %d✓/%d⚠ ｜ 命令 %d✓/%d⚠ ｜ 符号 %d✓/%d⚠" %
               (stats["路径"][0], stats["路径"][1], stats["命令"][0], stats["命令"][1],
                stats["符号"][0], stats["符号"][1]))
    out.append("> 机械半边结论——语义核实仍归 AI 与人（dev-init §1.5 第 1 项）")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("--root", default=".")
    ap.add_argument("--skill")
    ap.add_argument("--md")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--help", action="store_true")
    args = ap.parse_args()

    if args.help:
        print(__doc__.strip() if __doc__ else "skill-verify")
        print("""
用法: skill-verify [--root <项目根>] [--skill <名>] [--md <文件>] [--json] [--self-test] [--help]

裸跑 = 全量校验并输出明细（--md 可同时落盘）；--json = 单行契约结论。
退出码: 0=机械锚点全命中 1=存在 ⚠ 锚点（或无 project-local skill）2=自身故障
""")
        return 0

    if args.self_test:
        ok = True
        tmp = tempfile.mkdtemp(prefix="sver-pos-")
        try:
            sk = os.path.join(tmp, ".agents", "skills", "demo-workflow")
            os.makedirs(os.path.join(tmp, "docs"))
            os.makedirs(os.path.join(tmp, "src", "main", "java", "com", "demo"))
            os.makedirs(sk)
            with open(os.path.join(tmp, "pom.xml"), "w") as f:
                f.write("<project/>")
            with open(os.path.join(tmp, "docs", "real.md"), "w") as f:
                f.write("x")
            with open(os.path.join(tmp, "demo-build"), "w") as f:
                f.write("#!/bin/sh\n")
            os.chmod(os.path.join(tmp, "demo-build"), 0o755)
            with open(os.path.join(tmp, "src", "main", "java", "com", "demo", "Hello.java"), "w") as f:
                f.write("package com.demo;\nclass Hello {}\n")
            with open(os.path.join(sk, "SKILL.md"), "w") as f:
                f.write("---\nformat: v1.5\n---\n# demo\n"
                        "构建 `pom.xml`，文档 `docs/real.md`，入口 `com.demo.Hello`。\n"
                        "命令 `./demo-build --fast`；版本见 `v1.5`。\n"
                        "```sh\nsver-ghost-cmd --version\n```\n"
                        "缺失锚点 `docs/gone.md`，节引用 `memo-collector §0` 不算命令。\n")
            rows, stats, rc = verify(tmp)
            flat = {r[2]: r[0] for _, sr in rows for r in sr}
            expect_bad = {"docs/gone.md", "sver-ghost-cmd"}
            expect_good = {"pom.xml", "docs/real.md", "com.demo.Hello", "./demo-build"}
            absent = {"v1.5", "memo-collector"}
            if rc == 1 and all(flat.get(k) is False for k in expect_bad) \
                    and all(flat.get(k) is True for k in expect_good) \
                    and all(k not in flat for k in absent):
                print("ok: 正例（4✓ 命中 + 2⚠ 缺失 + 噪音零误报零漏判入册）")
            else:
                print("fail: 正例判定漂移 flat=%s rc=%s" % (flat, rc))
                ok = False
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        tmp = tempfile.mkdtemp(prefix="sver-neg-")
        try:
            sk = os.path.join(tmp, ".agents", "skills", "demo-index")
            os.makedirs(sk)
            with open(os.path.join(tmp, "README.md"), "w") as f:
                f.write("x")
            with open(os.path.join(sk, "SKILL.md"), "w") as f:
                f.write("---\nformat: v1\n---\n# demo\n全对锚点 `README.md`。\n")
            _, stats, rc = verify(tmp)
            if rc == 0:
                print("ok: 负例（全对锚点）exit 0")
            else:
                print("fail: 负例误报 stats=%s" % stats)
                ok = False
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        return 0 if ok else 1

    root = os.path.abspath(args.root)
    if not os.path.isdir(root):
        print("[remedy] 核对 --root 路径")
        print(json.dumps({"status": "FAIL", "severity": "error",
                          "message": "root 目录不存在", "remedy": "核对 --root 路径"}, ensure_ascii=False))
        return 2

    rows, stats, rc = verify(root, args.skill)
    text = render(root, rows, stats)
    if args.md:
        with open(args.md, "w", encoding="utf-8") as f:
            f.write(text)
    if not args.json:
        print(text)
        if args.md:
            print("[md] 报告已写入: %s" % args.md)
    if rc == 1 and rows:
        print("[remedy] ⚠ 锚点当场修指针或确认语义后保留；同卡点两轮修不动按 dev-loop 护栏 3 熔断")
    if not rows:
        print("[remedy] 未发现 project-local skill（<root>/.agents/skills/*/SKILL.md）——dev-init §1 第 4 步先建")
    if args.json:
        warn = stats["路径"][1] + stats["命令"][1] + stats["符号"][1]
        if not rows:
            print(json.dumps({"status": "FAIL", "severity": "warn",
                              "message": "无 project-local skill 可校验",
                              "remedy": "dev-init §1 第 4 步先建索引/workflow"}, ensure_ascii=False))
        else:
            print(json.dumps({"status": "FAIL" if warn else "OK",
                              "severity": "warn" if warn else "info",
                              "message": "路径 %d⚠ 命令 %d⚠ 符号 %d⚠" %
                                         (stats["路径"][1], stats["命令"][1], stats["符号"][1]),
                              "remedy": "按明细修指针后重跑" if warn else None},
                             ensure_ascii=False))
    return rc


if __name__ == "__main__":
    sys.exit(main())
