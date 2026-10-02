#!/bin/sh
# ctx-status — dev-loop §6 @status 运行态快照：CURRENT / 断点 / 待归并计数 / memory 行数（只读不写，≤5 行）
#
# toolbox-script
# format: v1
# name: ctx-status
# summary: dev-loop §6 @status 快照：CURRENT/断点/devlog+lessons 待归并计数/memory 行数（只读，≤5 行）
# trigger: manual
# cat: docs
# platform: unix
# self-test: --self-test

set -u
ROOT=''
JSON=0
SELF_TEST=0
MSG=''

usage() {
  cat <<'EOF'
ctx-status —— dev-loop §6 @status 运行态快照（只读不写，≤5 行）

用法: ctx-status.sh [--root <项目根>] [--json|--self-test|--help]

默认项目根: 当前目录（context/ 位于 <根>/context）

输出（≤5 行）:
  epic:   <当前绑定 epic，来自 context/CURRENT>
  断点:   <memory.md 中 - [断点] 行；缺失则提示>
  待归并: devlog(epic+misc)=N | lessons=L
  memory: <epic memory.md 行数> 行（软上限 150）

退出码: 0 正常（含无 context/ 跳过）/ 2 自身故障
EOF
}

scan() {
  local ctx epic bp d_epic d_misc les mlines pc
  ctx=${ROOT:-$(pwd)}/context
  if [ ! -d "$ctx" ]; then
    MSG="ℹ 无 context/ 目录（${ctx}）——快照跳过"
    return 0
  fi
  if [ -f "$ctx/CURRENT" ]; then
    epic=$(sed -n 's/^epic:[[:space:]]*//p' "$ctx/CURRENT" | head -n 1)
  else
    epic=''
  fi
  [ -z "$epic" ] && epic='(未绑定)'
  bp=$(grep -h '^-[[:space:]]*\[断点\]' "$ctx/epics/$epic/memory.md" "$ctx/epics/misc/memory.md" 2>/dev/null | head -n 1 | sed 's/^- \[断点\][[:space:]]*//')
  [ -z "$bp" ] && bp='（缺失，应恒为 1 条）'
  d_epic=$(tail -n 20 "$ctx/epics/$epic/devlog.md" 2>/dev/null | grep -c '^- \[' || true)
  d_misc=$(tail -n 20 "$ctx/epics/misc/devlog.md" 2>/dev/null | grep -c '^- \[' || true)
  les=$(grep -c '^- \[' "$ctx/lessons.md" 2>/dev/null || true)
  mlines=$(wc -l < "$ctx/epics/$epic/memory.md" 2>/dev/null | tr -d '[:space:]')
  [ -z "$mlines" ] && mlines=0
  pc=''
  if [ -f "$ctx/pending-confirm.md" ]; then
    pc=$(grep -c '^- \[ \]' "$ctx/pending-confirm.md" 2>/dev/null || true)
    [ "${pc:-0}" -gt 0 ] && pc=" | 挂起确认 ${pc} 项"
  fi
  MSG="epic: ${epic}\n断点: ${bp}\n待归并: devlog(epic+misc)=$((d_epic + d_misc)) (epic ${d_epic}/misc ${d_misc}) | lessons=${les}\nmemory: ${mlines} 行（软上限 150）${pc}"
  return 0
}

self_test() {
  local td ok out
  ok=1
  td=$(mktemp -d)
  if ! sh "$0" --root "$td" 2>/dev/null | grep -q '无 context'; then echo "self-test: 无 context 应跳过"; ok=0; fi
  mkdir -p "$td/c/context/epics/demo" "$td/c/context/epics/misc"
  printf 'epic: demo\n' > "$td/c/context/CURRENT"
  cat > "$td/c/context/epics/demo/memory.md" <<'EOF'
---
dev-loop: memory
format: v1
epic: demo
total-merged: 0
last-merge: none
---

# demo

## 断点
- [断点] 下一步：拆解任务
EOF
  printf -- '- [2026-09-19] [变更]: x\n- [2026-09-19] [验证]: y\n' > "$td/c/context/epics/demo/devlog.md"
  printf -- '- [2026-09-19] [变更]: m\n' > "$td/c/context/epics/misc/devlog.md"
  printf -- '- 一条 lessons\n' > "$td/c/context/lessons.md"
  out=$(sh "$0" --root "$td/c" 2>&1)
  printf '%s' "$out" | grep -q 'epic: demo' || { echo "self-test: 未输出 epic"; ok=0; }
  printf '%s' "$out" | grep -q 'devlog(epic+misc)=3' || { echo "self-test: 待归并计数错误: $out"; ok=0; }
  printf '%s' "$out" | grep -q 'memory: 12 行' || { echo "self-test: memory 行数错误: $out"; ok=0; }
  if [ "$ok" -eq 1 ]; then echo "self-test: OK"; rm -rf "$td"; return 0; fi
  rm -rf "$td"; return 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2;;
    --json) JSON=1; shift;;
    --self-test) SELF_TEST=1; shift;;
    --help|-h) usage; exit 0;;
    *) echo "未知参数: $1"; usage; exit 2;;
  esac
done

if [ "$SELF_TEST" -eq 1 ]; then self_test; exit $?; fi
if [ "$JSON" -eq 1 ]; then
  scan
  m=$(printf '%b' "$MSG" | tr '\n' ' ')
  printf '{"status":"OK","severity":"info","message":"%s"}\n' "$m"
  exit 0
fi
scan
printf '%b\n' "$MSG"
exit 0
