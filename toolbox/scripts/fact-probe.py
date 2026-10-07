#!/usr/bin/env python3
# fact-probe —— workflow 事实源取证底稿生成器（dev-init §1 第 3 步 / §1.5 第 1 项配套）
# 探测仓库的构建系统/候选命令/测试框架线索/CI/模块结构/环境线索/已有 skill 体系状态，
# 产出「候选事实底稿」供 AI 实测提炼 workflow skill——脚本只收集证据，严禁当结论直接采信。
# 新建接入（底稿→实测→提炼）与存量重验（重跑底稿→与 workflow 记载 diff→差异点核实）两路共用。
#
# toolbox-script
# format: v1
# name: fact-probe
# summary: workflow 事实源取证底稿：探测构建系统/候选命令/测试框架/CI/结构与环境线索 + skill 体系现状，供 AI 实测提炼，不代劳结论
# trigger: manual
# cat: env
# alias: fprobe
# platform: any
# self-test: --self-test

import argparse
import glob
import json
import os
import re
import shutil
import sys
import tempfile

BANNER = "候选事实底稿（fact-probe）—— 严禁直接采信：命令须实测跑通 ≥1 条、语义命名须 AI 提炼后方可落 workflow skill（dev-init §1 第 3 步）"

BUILD_FILES = [
    ("Maven", ["pom.xml"]),
    ("Gradle", ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]),
    ("npm/Node", ["package.json"]),
    ("Python(setuptools)", ["setup.py"]),
    ("Python(pyproject)", ["pyproject.toml"]),
    ("Python(requirements)", ["requirements.txt"]),
    ("Go", ["go.mod"]),
    ("Rust", ["Cargo.toml"]),
    ("CMake", ["CMakeLists.txt"]),
    ("Make", ["Makefile", "makefile", "GNUmakefile"]),
    ("Composer(PHP)", ["composer.json"]),
    ("Bundler(Ruby)", ["Gemfile"]),
]

TEST_DIRS = ["src/test", "tests", "test", "__tests__", "spec", "e2e", "testdata"]
TEST_FILES = ["pytest.ini", "conftest.py", "tox.ini", "phpunit.xml", "karma.conf.js",
              "jest.config.js", "jest.config.ts", "jest.config.mjs", "vitest.config.js",
              "vitest.config.ts", "playwright.config.ts", "playwright.config.js",
              "cypress.config.js", "cypress.json", ".mocharc.yml", ".mocharc.json"]
CI_FILES = [".gitlab-ci.yml", "Jenkinsfile", "azure-pipelines.yml", ".drone.yml",
            ".circleci/config.yml", ".travis.yml"]
ENV_FILES = [".nvmrc", ".node-version", ".python-version", ".java-version",
             ".tool-versions", ".sdkmanrc", ".ruby-version", ".go-version"]
COMPOSE_GLOBS = ["docker-compose.yml", "docker-compose.yaml", "compose.yml", "Dockerfile"]


def first_existing(root, names):
    for n in names:
        p = os.path.join(root, n)
        if os.path.exists(p):
            return p
    return None


def read_head(path, limit=6):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            lines = [l.strip() for l in f.readlines()[:limit] if l.strip()]
        return lines
    except OSError:
        return []


def probe_build(root):
    """返回 [(系统名, 证据文件, 该系统的候选命令与备注行)]"""
    found = []
    for name, files in BUILD_FILES:
        hit = first_existing(root, files)
        if not hit:
            continue
        notes = []
        if name == "Maven":
            try:
                with open(hit, "r", encoding="utf-8", errors="replace") as f:
                    txt = f.read()
                aid = re.search(r"<artifactId>([^<]+)</artifactId>", txt)
                mods = re.findall(r"<module>([^<]+)</module>", txt)
                if aid:
                    notes.append("artifactId: %s" % aid.group(1))
                if mods:
                    notes.append("modules: %s" % ",".join(mods[:12]))
            except OSError:
                pass
            notes.append("候选命令: %s" % ("./mvnw -q compile" if os.path.exists(os.path.join(root, "mvnw")) else "mvn -q compile"))
            notes.append("候选命令: %s" % ("./mvnw test" if os.path.exists(os.path.join(root, "mvnw")) else "mvn test"))
        elif name == "Gradle":
            gw = os.path.exists(os.path.join(root, "gradlew"))
            notes.append("候选命令: %s" % ("./gradlew build" if gw else "gradle build"))
            notes.append("候选命令: %s" % ("./gradlew test" if gw else "gradle test"))
        elif name == "npm/Node":
            try:
                with open(hit, "r", encoding="utf-8", errors="replace") as f:
                    pkg = json.load(f)
                if pkg.get("name"):
                    notes.append("name: %s" % pkg["name"])
                scripts = pkg.get("scripts") or {}
                for k in list(scripts)[:10]:
                    notes.append("候选命令: npm run %s  (scripts: %s)" % (k, scripts[k][:80]))
                ws = pkg.get("workspaces")
                if ws:
                    notes.append("workspaces(monorepo): %s" % json.dumps(ws)[:120])
            except (OSError, ValueError):
                notes.append("package.json 解析失败（JSON 非法？）——需人工核查")
        elif name == "Go":
            head = read_head(hit, 3)
            for l in head:
                if l.startswith("module "):
                    notes.append(l)
            notes.append("候选命令: go build ./... | go test ./...")
        elif name == "Rust":
            notes.append("候选命令: cargo build | cargo test")
        elif name == "Make":
            try:
                with open(hit, "r", encoding="utf-8", errors="replace") as f:
                    targets = re.findall(r"^([a-zA-Z0-9][a-zA-Z0-9_.-]*):", f.read(), re.M)
                if targets:
                    notes.append("顶层目标: %s" % ",".join(dict.fromkeys(targets[:12])))
                    notes.append("候选命令: make <目标>")
            except OSError:
                pass
        found.append((name, os.path.relpath(hit, root), notes))
    dotnet = glob.glob(os.path.join(root, "*.sln")) + glob.glob(os.path.join(root, "**", "*.csproj"), recursive=True)
    if dotnet:
        found.append(("dotnet", os.path.relpath(dotnet[0], root), ["候选命令: dotnet build | dotnet test"]))
    return found


def probe_ci(root):
    hits = []
    wf = sorted(glob.glob(os.path.join(root, ".github", "workflows", "*")))
    if wf:
        hits.append((".github/workflows", ", ".join(os.path.basename(w) for w in wf[:10])))
    for f in CI_FILES:
        if os.path.exists(os.path.join(root, f)):
            hits.append((f, "在场"))
    return hits


def probe_tests(root):
    lines = []
    for d in TEST_DIRS:
        p = os.path.join(root, d)
        if os.path.isdir(p):
            n = sum(len(fs) for _, _, fs in os.walk(p))
            lines.append("测试目录: %s/（%d 文件）" % (d, n))
    for f in TEST_FILES:
        if os.path.exists(os.path.join(root, f)):
            lines.append("测试配置: %s" % f)
    return lines


def probe_structure(root):
    lines = []
    try:
        entries = sorted(e for e in os.listdir(root)
                         if os.path.isdir(os.path.join(root, e)) and not e.startswith("."))
    except OSError:
        return lines
    counted = []
    for e in entries[:40]:
        n = sum(len(fs) for _, _, fs in os.walk(os.path.join(root, e)))
        counted.append((e, n))
    counted.sort(key=lambda x: -x[1])
    if counted:
        lines.append("顶层目录（按文件数前 12）: " + ", ".join("%s(%d)" % (e, n) for e, n in counted[:12]))
    if os.path.exists(os.path.join(root, ".gitmodules")):
        lines.append("git submodules 在场（.gitmodules）——子仓需单独接入评估")
    return lines


def probe_env(root):
    lines = []
    for f in ENV_FILES:
        p = os.path.join(root, f)
        if os.path.exists(p):
            lines.append("%s: %s" % (f, " ".join(read_head(p, 1)) or "(空)"))
    for f in COMPOSE_GLOBS:
        if os.path.exists(os.path.join(root, f)):
            lines.append("容器化: %s 在场" % f)
    return lines


def probe_skills(root):
    lines = []
    cur = os.path.join(root, "context", "CURRENT")
    if os.path.exists(cur):
        lines.append("context/ 在场（CURRENT: %s）——存量项目走 §1.5 对账" % (" ".join(read_head(cur, 1)) or "?"))
    sk = os.path.join(root, ".agents", "skills")
    if os.path.isdir(sk):
        names = sorted(d for d in os.listdir(sk) if not d.startswith("."))
        if names:
            lines.append("project-local skills: %s" % ", ".join(names))
    if os.path.isdir(os.path.join(root, "docs")):
        lines.append("docs/ 在场——dev-init §1 第 5 步走「已有 docs/」分支")
    return lines


def render(root, report):
    out = ["# fact-probe 取证底稿 — %s" % root, "", "> %s" % BANNER, ""]
    sections = [
        ("构建系统与候选命令", report["build"]),
        ("CI/CD", report["ci"]),
        ("测试框架线索", report["tests"]),
        ("结构线索", report["structure"]),
        ("环境线索", report["env"]),
        ("skill 体系现状", report["skills"]),
    ]
    for title, items in sections:
        out.append("## %s" % title)
        if not items:
            out.append("- （未探测到）")
        for it in items:
            if isinstance(it, tuple):
                name, ev = it[0], it[1]
                out.append("- %s ← %s" % (name, ev))
                for note in (it[2] if len(it) > 2 else []):
                    out.append("  - %s" % note)
            else:
                out.append("- %s" % it)
        out.append("")
    out.append("## 下一步（AI 义务，脚本不代劳）")
    out.append("- 实测候选命令 ≥1 条跑通（护栏 2：严禁虚构）→ 提炼模块结构语义命名 → 落 project-local workflow skill")
    out.append("- 存量项目：将本底稿与既有 workflow skill 逐条 diff，差异点走 §1.5 第 1 项核实")
    return "\n".join(out) + "\n"


def summarize(report):
    builds = [b[0] for b in report["build"]]
    ncmd = sum(len(b[2]) for b in report["build"])
    return builds, ncmd


def main():
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("--root", default=".")
    ap.add_argument("--md")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--help", action="store_true")
    args = ap.parse_args()

    if args.help:
        print(__doc__.strip() if __doc__ else "fact-probe")
        print("""
用法: fact-probe [--root <目录>] [--md <文件>] [--json] [--self-test] [--help]

裸跑 = 全量探测并输出底稿（--md 可同时落盘）；--json = 单行契约预检结论（不输出底稿本体）。
退出码: 0=探测到构建系统，底稿已产出 1=未探测到构建系统（无底稿价值）2=自身故障
""")
        return 0

    if args.self_test:
        ok = True
        tmp = tempfile.mkdtemp(prefix="fprobe-pos-")
        try:
            os.makedirs(os.path.join(tmp, ".github", "workflows"))
            os.makedirs(os.path.join(tmp, "src", "main"))
            with open(os.path.join(tmp, "pom.xml"), "w") as f:
                f.write("<project><artifactId>demo</artifactId></project>")
            with open(os.path.join(tmp, "package.json"), "w") as f:
                json.dump({"name": "demo", "scripts": {"build": "tsc", "test": "jest"}}, f)
            with open(os.path.join(tmp, ".github", "workflows", "ci.yml"), "w") as f:
                f.write("on: push\njobs: {}\n")
            rep = collect(tmp)
            builds, ncmd = summarize(rep)
            if "Maven" in builds and "npm/Node" in builds and rep["ci"] and ncmd >= 2:
                print("ok: 正例（Maven+npm+CI+候选命令）全部命中")
            else:
                print("fail: 正例漏检 builds=%s" % builds)
                ok = False
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        tmp = tempfile.mkdtemp(prefix="fprobe-neg-")
        try:
            rep = collect(tmp)
            if not rep["build"]:
                print("ok: 负例（空目录）零构建系统")
            else:
                print("fail: 负例误报 %s" % [b[0] for b in rep["build"]])
                ok = False
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        return 0 if ok else 1

    root = os.path.abspath(args.root)
    if not os.path.isdir(root):
        print('[remedy] --root 指向不存在的目录: %s' % args.root)
        print(json.dumps({"status": "FAIL", "severity": "error",
                          "message": "root 目录不存在", "remedy": "核对 --root 路径"}, ensure_ascii=False))
        return 2

    report = collect(root)
    builds, ncmd = summarize(report)

    if not builds:
        msg = "未探测到任何构建系统标记文件"
        print("[remedy] 确认项目形态（dev-init §1 第 1 步：非编码工作区不接入）或人工取证后建 workflow skill")
        if args.json:
            print(json.dumps({"status": "FAIL", "severity": "warn", "message": msg,
                              "remedy": "确认项目形态（dev-init §1 第 1 步）或人工取证"}, ensure_ascii=False))
        else:
            print(render(root, report))
        return 1

    draft = render(root, report)
    if args.md:
        with open(args.md, "w", encoding="utf-8") as f:
            f.write(draft)
        if not args.json:
            print(draft)
            print("[md] 底稿已写入: %s" % args.md)
    elif not args.json:
        print(draft)

    if args.json:
        print(json.dumps({"status": "OK", "severity": "info",
                          "message": "构建系统: %s; 候选命令 %d 条; 底稿已产出" % (",".join(builds), ncmd)},
                         ensure_ascii=False))
    return 0


def collect(root):
    return {
        "build": probe_build(root),
        "ci": probe_ci(root),
        "tests": probe_tests(root),
        "structure": probe_structure(root),
        "env": probe_env(root),
        "skills": probe_skills(root),
    }


if __name__ == "__main__":
    sys.exit(main())
