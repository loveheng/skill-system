#!/usr/bin/env python3
# doc-domain-map —— 文档↔代码域 派生映射与缺口检测（project-index 配套 derive 脚本）
# 扫 docs/<域>/*.md 提取 文档→域，结合 project-index 归属表匹配 域→代码落点；
# 检测孤儿文档（域未在归属表登记）与缺失文档域（归属表文档落点为 — 或路径不存在）。
#
# toolbox-script
# format: v1
# name: doc-domain-map
# summary: 文档↔代码域 派生映射与缺口检测：扫 docs/<域> 提 文档→域，结合 project-index 归属表匹配 域→代码落点；报告孤儿文档与缺失文档域
# trigger: manual
# cat: docs
# platform: unix
# self-test: --self-test

import argparse
import json
import os
import re
import shutil
import sys
import tempfile


def find_index_skill(root):
    skills_dir = os.path.join(root, ".agents", "skills")
    if not os.path.isdir(skills_dir):
        return None
    cands = []
    for name in sorted(os.listdir(skills_dir)):
        if name.endswith("-index"):
            p = os.path.join(skills_dir, name, "SKILL.md")
            if os.path.isfile(p):
                cands.append(p)
    if cands:
        return cands[0]
    for name in sorted(os.listdir(skills_dir)):
        p = os.path.join(skills_dir, name, "SKILL.md")
        if os.path.isfile(p):
            try:
                with open(p, encoding="utf-8") as f:
                    if "归属表" in f.read():
                        return p
            except Exception:
                pass
    return None


def parse_ownership_table(path):
    rows = []
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.readlines()
    except Exception:
        return rows
    header_idx = -1
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith("|") and "领域" in s and "代码落点" in s and "文档落点" in s:
            header_idx = i
            break
    if header_idx == -1:
        return rows
    header = [c.strip() for c in lines[header_idx].split("|")]

    def col(name):
        for j, h in enumerate(header):
            if h and name in h:
                return j
        return -1

    di, ci, doi = col("领域"), col("代码落点"), col("文档落点")
    if -1 in (di, ci, doi):
        return rows
    for line in lines[header_idx + 1:]:
        s = line.strip()
        if not s.startswith("|"):
            if rows:
                break
            continue
        if re.match(r"^\|[\s:|-]+\|$", s):
            continue
        cells = [c.strip() for c in s.split("|")]
        if len(cells) <= max(di, ci, doi):
            continue
        domain = cells[di]
        if not domain or domain == "领域":
            continue
        rows.append({"domain": domain, "code": cells[ci], "doc": cells[doi]})
    return rows


def scan(root):
    docs_dir = os.path.join(root, "docs")
    mapping, orphan, missing = [], [], []
    index_path = find_index_skill(root)
    table = parse_ownership_table(index_path) if index_path else []
    code_by_domain = {r["domain"]: r["code"] for r in table}
    # 文档落点：(domain, token) —— 反向推导文档归属（多对一允许，如 ai-pipeline 被多域指向）
    doc_points = []
    for r in table:
        dp = r["doc"].strip()
        if dp in ("", "—", "-", "–"):
            missing.append({"domain": r["domain"], "doc_point": dp, "reason": "no-doc-point"})
            continue
        token = re.split(r"[（(]", dp)[0].strip().rstrip("/")
        if not token:
            missing.append({"domain": r["domain"], "doc_point": dp, "reason": "no-doc-point"})
            continue
        if not os.path.exists(os.path.join(root, token)):
            missing.append({"domain": r["domain"], "doc_point": dp, "reason": "path-not-found"})
            continue
        doc_points.append((r["domain"], token))
    if os.path.isdir(docs_dir):
        for dirpath, _, files in os.walk(docs_dir):
            for fn in files:
                if not fn.endswith(".md"):
                    continue
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, root)
                if rel == os.path.join("docs", "README.md"):
                    continue
                parts = rel.split(os.sep)
                if len(parts) < 3:
                    continue
                matched = [dom for dom, tok in doc_points
                           if rel == tok or rel.startswith(tok + "/")]
                if matched:
                    for dom in matched:
                        mapping.append({"doc": rel, "domain": dom,
                                        "code": code_by_domain.get(dom, "")})
                else:
                    orphan.append(rel)
    return {"mapping": mapping, "orphan_docs": sorted(orphan), "missing_doc_domains": missing}


def verdict(result):
    if result["orphan_docs"]:
        return "FAIL", "warning", "孤儿文档 %d 个（未被任何归属表文档落点覆盖，可能为跨域架构/部署文档或索引缺口）" % len(result["orphan_docs"])
    if result["missing_doc_domains"]:
        return "FAIL", "warning", "缺失文档域 %d 个（归属表文档落点为 — 或路径不存在）" % len(result["missing_doc_domains"])
    return "OK", "info", "文档↔代码域映射完整，无缺口"


def human(result, index_found):
    out = []
    out.append("== 正向映射（文档 → 域 → 代码落点）==")
    if result["mapping"]:
        for m in sorted(result["mapping"], key=lambda x: x["doc"]):
            out.append("  %s → %s → %s" % (m["doc"], m["domain"], m["code"] or "(无)"))
    else:
        out.append("  （无）")
    out.append("")
    out.append("== 孤儿文档（缺口：域未在归属表登记）==")
    if result["orphan_docs"]:
        for d in result["orphan_docs"]:
            out.append("  %s" % d)
    else:
        out.append("  （无）")
    out.append("")
    out.append("== 缺失文档域（缺口：归属表文档落点为 — 或路径不存在）==")
    if result["missing_doc_domains"]:
        for m in result["missing_doc_domains"]:
            out.append("  域=%s doc_point=%s reason=%s" % (m["domain"], m["doc_point"], m["reason"]))
    else:
        out.append("  （无）")
    out.append("")
    out.append("归属表: %s" % ("已找到" if index_found else "未找到（无法匹配代码落点，仅能检测孤儿）"))
    return "\n".join(out)


def self_test():
    tmp = tempfile.mkdtemp(prefix="ddm-self-")
    try:
        os.makedirs(os.path.join(tmp, "docs", "orphan"))
        os.makedirs(os.path.join(tmp, "docs", "known"))
        os.makedirs(os.path.join(tmp, ".agents", "skills", "test-index"))
        with open(os.path.join(tmp, "docs", "orphan", "foo.md"), "w") as f:
            f.write("# orphan\n")
        with open(os.path.join(tmp, "docs", "known", "bar.md"), "w") as f:
            f.write("# known\n")
        idx = ("# test-index\n\n## 归属表\n\n"
               "| 领域 | 覆盖功能 | 代码落点 | 文档落点 |\n"
               "|---|---|---|---|\n"
               "| known | k | src/known/ | docs/known/ |\n"
               "| nocode | n | src/nocode/ | — |\n")
        with open(os.path.join(tmp, ".agents", "skills", "test-index", "SKILL.md"), "w") as f:
            f.write(idx)
        res = scan(tmp)
        problems = []
        if "docs/orphan/foo.md" not in res["orphan_docs"]:
            problems.append("未检测到孤儿文档 docs/orphan/foo.md")
        if not any(m["doc"] == "docs/known/bar.md" for m in res["mapping"]):
            problems.append("未映射 known 域文档")
        if not any(d["domain"] == "nocode" for d in res["missing_doc_domains"]):
            problems.append("未检测缺失文档域 nocode")
        if problems:
            for p in problems:
                print("self-test FAIL: " + p)
            return 1
        print("self-test OK")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="doc-domain-map",
        description="文档↔代码域 派生映射与缺口检测（project-index 配套 derive 脚本）")
    ap.add_argument("--root", default=".", help="项目根目录（默认当前目录）")
    ap.add_argument("--json", action="store_true", help="仅输出一行契约结论 JSON")
    ap.add_argument("--self-test", action="store_true", help="金丝雀自测（构造已知坏样本验证能抓到缺口）")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()

    if not os.path.isdir(args.root):
        sys.stderr.write("错误: 项目根不存在: %s\n" % args.root)
        return 2

    index_found = find_index_skill(args.root) is not None
    result = scan(args.root)
    status, severity, message = verdict(result)

    if args.json:
        print(json.dumps({"status": status, "severity": severity,
                          "message": message, "data": result},
                         ensure_ascii=False))
    else:
        print(human(result, index_found))
        print("\n结论: %s (%s) — %s" % (status, severity, message))
    return 0 if status == "OK" else 1


if __name__ == "__main__":
    sys.exit(main())
