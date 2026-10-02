#!/bin/sh
# breakpoint — memory.md 断点行维护（dev-loop §3）：sed 改写 + grep 计数校验（非1即异常）
#
# toolbox-script
# format: v1
# name: breakpoint
# summary: memory.md 断点行维护：set 改写 / get 读取 / check 校验 / fix 去重（dev-loop §3）
# trigger: manual
# cat: docs
# platform: unix
# self-test: --self-test

set -u
JSON=0
SELF_TEST=0
SUB=''
FILE=''
TEXT=''

usage() {
  cat <<'EOF'
breakpoint —— memory.md 断点行维护（dev-loop §3）

用法: breakpoint.sh <子命令> <memory.md> [文本] [--json|--self-test|--help]

子命令:
  get  <memory.md>          读取当前断点行
  set  <memory.md> <文本>   改写断点（确保 ## 断点 章节存在；sed 替换 / 缺失则追加）
  check <memory.md>         校验断点行恰为 1 条（0=缺失, >1=重复）
  fix  <memory.md>          重复行去重(保留末条)；缺失则报错请用 set

退出码: 0 通过 / 1 校验未通过 / 2 自身故障
EOF
}

count_bp() { grep -c '^-[[:space:]]*\[断点\]' "$1" 2>/dev/null || true; }

do_get() {
  if [ ! -f "$FILE" ]; then echo "✗ 文件不存在: $FILE"; return 2; fi
  local line; line=$(grep '^-[[:space:]]*\[断点\]' "$FILE" 2>/dev/null || true)
  if [ -z "$line" ]; then echo "✗ 无断点行（- [断点]）"; return 1; fi
  printf '%s\n' "$line"; return 0
}

do_set() {
  if [ -z "$TEXT" ]; then echo "✗ set 需要断点文本"; return 2; fi
  if [ ! -f "$FILE" ]; then echo "✗ 文件不存在: $FILE"; return 2; fi
  if ! grep -q '^##[[:space:]]*断点' "$FILE"; then printf '\n## 断点\n' >> "$FILE"; fi
  if grep -q '^-[[:space:]]*\[断点\]' "$FILE"; then
    sed -i "s|^-[[:space:]]*\[断点\].*|- [断点] 下一步：$TEXT|" "$FILE"
  else
    printf -- '- [断点] 下一步：%s\n' "$TEXT" >> "$FILE"
  fi
  local cnt; cnt=$(count_bp "$FILE")
  if [ "$cnt" -eq 1 ]; then echo "✓ 断点已更新"; return 0; fi
  echo "✗ 断点行数异常: $cnt（预期 1）"; return 1
}

do_check() {
  if [ ! -f "$FILE" ]; then echo "✗ 文件不存在: $FILE"; return 2; fi
  local cnt; cnt=$(count_bp "$FILE")
  if [ "$cnt" -eq 1 ]; then echo "✓ 断点行恰 1 条"; return 0; fi
  if [ "$cnt" -eq 0 ]; then echo "✗ 断点缺失（- [断点] 行 / ## 断点 章节）"; return 1; fi
  echo "✗ 断点行重复: $cnt 条（应去重）"; return 1
}

do_fix() {
  if [ ! -f "$FILE" ]; then echo "✗ 文件不存在: $FILE"; return 2; fi
  local cnt last
  cnt=$(count_bp "$FILE")
  if [ "$cnt" -eq 0 ]; then echo "✗ 断点缺失，请用 set 提供内容"; return 1; fi
  if [ "$cnt" -eq 1 ]; then echo "✓ 断点正常，无需修复"; return 0; fi
  last=$(grep '^-[[:space:]]*\[断点\]' "$FILE" | tail -n 1)
  grep -v '^-[[:space:]]*\[断点\]' "$FILE" > "$FILE.tmp"
  mv "$FILE.tmp" "$FILE"
  if ! grep -q '^##[[:space:]]*断点' "$FILE"; then printf '\n## 断点\n' >> "$FILE"; fi
  printf '%s\n' "$last" >> "$FILE"
  cnt=$(count_bp "$FILE")
  if [ "$cnt" -eq 1 ]; then echo "✓ 断点已去重（保留末条）"; return 0; fi
  echo "✗ 去重后仍异常: $cnt"; return 1
}

self_test() {
  local td f cnt ok
  ok=1
  td=$(mktemp -d)
  f="$td/m.md"
  printf -- '---\ndev-loop: memory\nformat: v1\n---\n\n# 正文\n\n## 断点\n- [断点] 下一步：旧\n' > "$f"
  TEXT="新任务"; FILE="$f"; do_set >/dev/null 2>&1; cnt=$(count_bp "$f")
  if [ "$cnt" -ne 1 ] || ! grep -q '下一步：新任务' "$f"; then echo "self-test: set 失败 (cnt=$cnt)"; ok=0; fi
  printf -- '- [断点] 下一步：重复1\n- [断点] 下一步：重复2\n' >> "$f"
  FILE="$f"; do_fix >/dev/null 2>&1; cnt=$(count_bp "$f")
  if [ "$cnt" -ne 1 ] || ! grep -q '下一步：重复2' "$f"; then echo "self-test: fix 去重失败 (cnt=$cnt)"; ok=0; fi
  FILE="$f"; do_check >/dev/null 2>&1 || { echo "self-test: check 误报正常文件"; ok=0; }
  printf -- '---\n---\n# 无断点\n' > "$td/nobp.md"
  FILE="$td/nobp.md"; if do_check >/dev/null 2>&1; then echo "self-test: 缺失场景未报 FAIL"; ok=0; fi
  if [ "$ok" -eq 1 ]; then echo "self-test: OK"; rm -rf "$td"; return 0; fi
  rm -rf "$td"; return 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1; shift;;
    --self-test) SELF_TEST=1; shift;;
    --help|-h) usage; exit 0;;
    *)
      if [ -z "$SUB" ]; then SUB="$1";
      elif [ -z "$FILE" ]; then FILE="$1";
      elif [ -z "$TEXT" ]; then TEXT="$1";
      else echo "多余参数: $1"; usage; exit 2; fi
      shift;;
  esac
done

if [ "$SELF_TEST" -eq 1 ]; then self_test; exit $?; fi

if [ "$JSON" -eq 1 ]; then
  if [ -z "$SUB" ]; then
    printf '{"status":"OK","severity":"info","message":"breakpoint 契约就绪; 用法: breakpoint.sh <get|set|check|fix> <memory.md> [文本]"}\n'
    exit 0
  fi
  rc=0
  case "$SUB" in
    get) do_get >/dev/null 2>&1; rc=$?;;
    set) do_set >/dev/null 2>&1; rc=$?;;
    check) do_check >/dev/null 2>&1; rc=$?;;
    fix) do_fix >/dev/null 2>&1; rc=$?;;
    *) echo "✗ 未知子命令: $SUB"; usage; exit 2;;
  esac
  if [ "$rc" -eq 0 ]; then printf '{"status":"OK","severity":"info","message":"断点操作通过"}\n';
  elif [ "$rc" -eq 1 ]; then printf '{"status":"FAIL","severity":"warn","message":"断点校验未通过"}\n';
  else printf '{"status":"FAIL","severity":"error","message":"断点操作自身故障"}\n'; fi
  exit "$rc"
fi

if [ -z "$SUB" ]; then usage; exit 2; fi
if [ -z "$FILE" ]; then echo "✗ 缺少 <memory.md>"; usage; exit 2; fi

rc=0
case "$SUB" in
  get) do_get; rc=$?;;
  set) do_set; rc=$?;;
  check) do_check; rc=$?;;
  fix) do_fix; rc=$?;;
  *) echo "✗ 未知子命令: $SUB"; usage; exit 2;;
esac
exit "$rc"
