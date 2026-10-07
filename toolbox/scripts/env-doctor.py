#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""跨项目开发机环境体检：探测 Java/GraalVM/docker/git 工具链与用户级开场协议部署的「损坏状态」。

只把「已配置但损坏」判为 FAIL（如 JAVA_HOME 指向不存在目录、docker 装了但守护进程不可达、
开场协议部署副本与 SSOT 漂移）；单纯未安装属于信息（INFO），不算失败——工具应在任何开发机上无噪音运行。

toolbox-script
format: v1
name: env-doctor
summary: 开发机环境体检（Java/GraalVM/docker/git 损坏 + 开场协议部署一致性）
trigger: bootstrap
cat: env
alias: envdoc
platform: any
self-test: --self-test
"""

import argparse
import glob
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

IS_WIN = os.name == "nt"
JAVA_BIN = "java.exe" if IS_WIN else "java"
NI_BIN = "native-image.cmd" if IS_WIN else "native-image"


def run_cmd(args, timeout=8):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return p.returncode
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return 127


def probe_java(java_home):
    """java_home: 环境变量值或 None。返回 (status, detail)，status ∈ OK|FAIL|INFO。"""
    if java_home:
        if not Path(java_home).is_dir():
            return "FAIL", "JAVA_HOME 指向不存在的目录: %s" % java_home
        if not (Path(java_home) / "bin" / JAVA_BIN).exists():
            return "FAIL", "JAVA_HOME 缺少 bin/%s: %s" % (JAVA_BIN, java_home)
        return "OK", "JAVA_HOME=%s" % java_home
    w = shutil.which("java")
    if w:
        return "INFO", "java(PATH): %s" % w
    return "INFO", "java 未安装"


def probe_graal():
    cands = []
    for env in ("TOOLBOX_GRAALVM_HOME", "GRAALVM_HOME", "JAVA_HOME"):
        v = os.environ.get(env)
        if v:
            cands.append(Path(v))
    for pat in ("/opt/GraalVM*", "/usr/lib/jvm/*graal*",
                "/Library/Java/JavaVirtualMachines/*graal*"):
        cands.extend(Path(x) for x in glob.glob(pat))
    seen, out = [], []
    for c in cands:
        if c.is_dir() and c not in seen:
            seen.append(c)
    for c in seen[:4]:
        has_ni = (c / "bin" / NI_BIN).exists()
        out.append("%s%s" % (c, "" if has_ni else "（无 native-image）"))
    if not out:
        return "INFO", "未发现 GraalVM（需要 native 构建时设 TOOLBOX_GRAALVM_HOME）"
    return "INFO", "GraalVM: " + "; ".join(out)


def probe_docker():
    w = shutil.which("docker")
    if not w:
        return "INFO", "docker 未安装"
    if run_cmd(["docker", "info", "--format", "ok"]) != 0:
        return "FAIL", "docker 已安装但守护进程不可达（服务未启动？）"
    return "OK", "docker 守护进程正常"


def probe_git():
    w = shutil.which("git")
    if not w:
        return "FAIL", "git 未安装（开发机必备）"
    return "OK", "git: %s" % w


def probe_agentsmd(ssot=None, deploy=None):
    """用户级开场协议 SSOT 与部署副本一致性（README §1.5 / dev-init §2）。参数供金丝雀注入。"""
    ssot = Path(ssot) if ssot else Path.home() / ".agents" / "AGENTS.md"
    deploy = Path(deploy) if deploy else Path.home() / ".zcode" / "AGENTS.md"
    if not ssot.exists():
        return "INFO", "无用户级开场协议 SSOT（~/.agents/AGENTS.md）——机制单仓未就位，跳过"
    if not deploy.exists():
        return "FAIL", ("开场协议部署副本缺失: %s"
                        "（同步: cp ~/.agents/AGENTS.md ~/.zcode/AGENTS.md）" % deploy)
    try:
        same = ssot.read_bytes() == deploy.read_bytes()
    except OSError:
        return "FAIL", "开场协议部署副本不可读: %s" % deploy
    if not same:
        return "FAIL", ("开场协议部署副本与 SSOT 漂移: %s"
                        "（同步: cp ~/.agents/AGENTS.md ~/.zcode/AGENTS.md）" % deploy)
    return "OK", "开场协议部署副本与 SSOT 一致"


def run_checks(java_home=None):
    """返回 (ok, severity, message)。java_home 供金丝雀注入坏样本。"""
    probes = [
        ("java", lambda: probe_java(java_home if java_home is not None
                                    else os.environ.get("JAVA_HOME"))),
        ("graalvm", probe_graal),
        ("docker", probe_docker),
        ("git", probe_git),
        ("agentsmd", probe_agentsmd),
    ]
    lines, ok = [], True
    for tag, fn in probes:
        status, detail = fn()
        if status == "FAIL":
            ok = False
            lines.append("[%s] FAIL %s" % (tag, detail))
        else:
            lines.append("[%s] %s" % (tag, detail))
    return ok, ("warn" if not ok else "info"), " | ".join(lines)


def self_test():
    """金丝雀：构造已知坏样本，证明探测函数真的能抓到坏。"""
    import tempfile
    problems = []
    with tempfile.TemporaryDirectory() as td:
        st, _ = probe_java(str(Path(td) / "ghost-jdk"))
        if st != "FAIL":
            problems.append("幽灵 JAVA_HOME 未被判 FAIL")
        empty = Path(td) / "empty-jdk"
        empty.mkdir()
        st, _ = probe_java(str(empty))
        if st != "FAIL":
            problems.append("缺 bin/java 的 JAVA_HOME 未被判 FAIL")
        good = Path(td) / "fake-jdk"
        (good / "bin").mkdir(parents=True)
        (good / "bin" / JAVA_BIN).write_text("", encoding="utf-8")
        st, _ = probe_java(str(good))
        if st != "OK":
            problems.append("合法 JAVA_HOME 未被判 OK")
        # agentsmd 探针：缺失/漂移必抓 FAIL，一致必放 OK，SSOT 缺失降 INFO
        tssot = Path(td) / "AGENTS.md"
        tssot.write_text("v1", encoding="utf-8")
        tdep = Path(td) / "deploy" / "AGENTS.md"
        st, _ = probe_agentsmd(str(tssot), str(tdep))
        if st != "FAIL":
            problems.append("部署副本缺失未被判 FAIL")
        tdep.parent.mkdir(parents=True)
        tdep.write_text("v2", encoding="utf-8")
        st, _ = probe_agentsmd(str(tssot), str(tdep))
        if st != "FAIL":
            problems.append("部署副本漂移未被判 FAIL")
        tdep.write_text("v1", encoding="utf-8")
        st, _ = probe_agentsmd(str(tssot), str(tdep))
        if st != "OK":
            problems.append("一致的部署副本未被判 OK")
        st, _ = probe_agentsmd(str(Path(td) / "ghost.md"), str(tdep))
        if st != "INFO":
            problems.append("SSOT 缺失未被判 INFO")
    if problems:
        for p in problems:
            print("self-test ✗ %s" % p)
        return 2
    print("self-test ✓ 金丝雀通过（坏样本必被抓、好样本必被放）")
    return 0


def main():
    ap = argparse.ArgumentParser(description="开发机环境体检（Java/GraalVM/docker/git + 开场协议部署一致性）")
    ap.add_argument("--json", action="store_true", help="输出契约 JSON 结论")
    ap.add_argument("--self-test", action="store_true", help="金丝雀自检")
    args = ap.parse_args()
    if args.self_test:
        sys.exit(self_test())
    ok, severity, message = run_checks()
    if args.json:
        print(json.dumps({"status": "OK" if ok else "FAIL",
                          "severity": severity, "message": message},
                         ensure_ascii=False))
    else:
        for part in message.split(" | "):
            print(part)
        print("✓ 环境体检通过" if ok else "✗ 发现损坏状态（见上 FAIL 项）")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
