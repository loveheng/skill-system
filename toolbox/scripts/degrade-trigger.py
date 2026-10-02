#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""degrade-trigger — 收集运行日志中实际触发的 DEGRADE 降级事件（静态「可能」→ 运行时「真触发」）

配套 degrade-scan 的第二条腿：degrade-scan 扫代码发现「这条路*能*静默降级」，
本工具扫运行日志算它*真*触发了几次——把潜在风险变成观测数据。

约定：DEGRADE 标记处的降级分支在抛/返回前打一条含 `[DEGRADE] <场景key>` 的日志
（如 log.warn("[DEGRADE] persona-redis-unavailable ...")）。场景 key 建议与
代码位置语义对齐（kebab-case 短语），便于跨日志文件聚合。

本工具：grep 指定日志目录/文件中的 [DEGRADE] 行，按 (文件, 场景key) 聚合计数，
输出总次数 / 各场景次数 / 最近触发时间。纯 grep 非 watch——无常驻进程，人可手动跑；
高频场景 = 该降级路径实际承载流量，应优先评估是否属「有意降级」或需告警升级。

用法: degrade-trigger [--logs <目录|文件> ...] [--json] [--md <文件>] [--self-test]
  --logs   日志文件或目录（可多个，目录内扫 *.log）；默认 /tmp/logs
退出码: 0=无触发 1=有触发(需评估) 2=自身故障

toolbox-script
format: v1
name: degrade-trigger
summary: grep 运行日志 [DEGRADE] 标记，按场景聚合实际触发频次（运行时降级观测，通用）
trigger: manual
cat: test
alias: dtrig
platform: any
self-test: --self-test
"""

import argparse
import json
import os
import re
import sys
import tempfile
import datetime

MARK_RE = re.compile(r"\[DEGRADE\][\s:：]*([A-Za-z0-9_\-]+)?")
# 时间戳前缀（best-effort 提取，兼容常见 logback/log4j 格式）
TS_RE = re.compile(r"^\[?(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2})")
DEFAULT_LOG_DIR = "/tmp/logs"


def collect_paths(logs):
    """把 (目录|文件) 参数展开为文件列表；目录扫 *.log。"""
    paths = []
    for p in logs:
        if os.path.isdir(p):
            for fn in sorted(os.listdir(p)):
                if fn.endswith(".log") and os.path.isfile(os.path.join(p, fn)):
                    paths.append(os.path.join(p, fn))
        elif os.path.isfile(p):
            paths.append(p)
        # 不存在的路径静默跳过（日志轮转/服务未起是常态，不属故障）
    return paths


def scan(paths):
    """返回 {场景key: {"count": n, "files": set, "last": ts, "sample": line}}。"""
    agg = {}
    for path in paths:
        base = os.path.basename(path)
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                for line in f:
                    m = MARK_RE.search(line)
                    if not m:
                        continue
                    key = m.group(1) or "(未命名场景)"
                    ts = TS_RE.match(line.strip())
                    ts = ts.group(1) if ts else ""
                    e = agg.setdefault(key, {"count": 0, "files": set(), "last": "", "sample": ""})
                    e["count"] += 1
                    e["files"].add(base)
                    if ts > e["last"]:
                        e["last"] = ts
                    if not e["sample"]:
                        e["sample"] = line.strip()[:140]
        except OSError:
            continue
    return agg


def run_checks(logs, md_out):
    paths = collect_paths(logs)
    if not paths:
        return True, "info", "无可读日志（默认 %s，--logs 可指定）" % DEFAULT_LOG_DIR
    agg = scan(paths)
    total = sum(e["count"] for e in agg.values())
    if total == 0:
        return True, "info", "运行日志中未发现 [DEGRADE] 实际触发（%d 个日志文件）" % len(paths)

    lines = sorted(agg.items(), key=lambda kv: -kv[1]["count"])
    msg = "运行日志中 [DEGRADE] 实际触发 %d 次（%d 个场景，%d 个日志文件），高频场景应优先评估" % (
        total, len(lines), len(paths))
    if md_out:
        with open(md_out, "w", encoding="utf-8") as f:
            f.write("# DEGRADE 实际触发报告\n\n")
            f.write("- 日期: %s\n- 日志来源: %d 个文件\n- 总触发: %d 次 / %d 场景\n\n" % (
                datetime.date.today(), len(paths), total, len(lines)))
            f.write("| 场景 | 次数 | 最近触发 | 出现于 | 样例 |\n|---|---|---|---|---|\n")
            for key, e in lines:
                f.write("| %s | %d | %s | %s | %s |\n" % (
                    key, e["count"], e["last"] or "-",
                    ",".join(sorted(e["files"])), e["sample"].replace("|", "\\|")))
            f.write("\n> 处置: 高频场景（占大头）先定性——有意降级 → 确认降级文案合理即可；\n")
            f.write("> 未核实猜测 → 升级处理（补告警/转 todos 风险类）；零触发的静态命中可降级观察。\n")
    return False, "warn", msg


def self_test():
    d = tempfile.mkdtemp()
    try:
        # 坏样本（应抓到）：两个日志文件、两个场景 key、时间戳
        with open(os.path.join(d, "main.log"), "w", encoding="utf-8") as f:
            f.write("2026-09-25 10:00:01 INFO normal line\n")
            f.write("2026-09-25 10:00:02 WARN [DEGRADE] persona-redis-unavailable fallback to code\n")
            f.write("2026-09-25 10:05:03 WARN [DEGRADE] persona-redis-unavailable fallback to code\n")
        with open(os.path.join(d, "data.log"), "w", encoding="utf-8") as f:
            f.write("[2026-09-25 11:00:00] WARN [DEGRADE]: notify-spec-parse skipped reminder\n")
        # 好样本（不应误报）：无标记
        with open(os.path.join(d, "clean.log"), "w", encoding="utf-8") as f:
            f.write("2026-09-25 12:00:00 INFO all fine\n")
        agg = scan(collect_paths([d]))
        if agg.get("persona-redis-unavailable", {}).get("count") != 2:
            print("self-test: 场景 persona-redis-unavailable 计数错误: %s" % agg.get("persona-redis-unavailable"))
            return 2
        if agg.get("notify-spec-parse", {}).get("count") != 1:
            print("self-test: 场景 notify-spec-parse 未抓到（冒号变体）")
            return 2
        if agg["persona-redis-unavailable"]["last"] != "2026-09-25 10:05:03":
            print("self-test: 最近触发时间提取错误")
            return 2
        ok, _, _ = run_checks([os.path.join(d, "clean.log")], None)
        if not ok:
            print("self-test: 无标记日志被误报")
            return 2
        ok, _, _ = run_checks([d], None)
        if ok:
            print("self-test: 有标记日志未判为需评估")
            return 2
        print("self-test: OK（场景聚合/时间戳/冒号变体可抓，干净日志不误报）")
        return 0
    finally:
        import shutil
        shutil.rmtree(d, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser(description="degrade-trigger")
    ap.add_argument("--logs", nargs="*", default=[DEFAULT_LOG_DIR],
                    help="日志文件或目录（可多个，目录内扫 *.log），默认 /tmp/logs")
    ap.add_argument("--json", action="store_true", help="输出契约 JSON 结论")
    ap.add_argument("--md", help="明细报告输出文件")
    ap.add_argument("--self-test", action="store_true", help="金丝雀自检")
    args = ap.parse_args()
    if args.self_test:
        sys.exit(self_test())
    ok, severity, message = run_checks(args.logs, args.md)
    if args.json:
        print(json.dumps({"status": "OK" if ok else "FAIL",
                          "severity": severity, "message": message}, ensure_ascii=False))
    else:
        print(("✓ " if ok else "✗ ") + message)
        if args.md:
            print("报告已写入 %s" % args.md)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
