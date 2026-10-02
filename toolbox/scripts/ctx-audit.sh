#!/bin/sh
# ctx-audit — dev-loop §7 @audit 12 项质检清单呈现（✓/⚠/❓）；机械项委托 context-lint 检测，人判项标 ❓
#
# toolbox-script
# format: v1
# name: ctx-audit
# summary: dev-loop §7 @audit 12 项质检清单（✓/⚠/❓）；机械项委托 context-lint，人判项标 ❓
# trigger: manual
# cat: docs
# platform: unix
# self-test: --self-test

set -u
ROOT=''
JSON=0
SELF_TEST=0
OUT=''
CL_RC=0
WARN_FLAG=0

usage() {
  cat <<'EOF'
ctx-audit —— dev-loop §7 @audit 12 项质检清单（✓/⚠/❓）

用法: ctx-audit.sh [--root <项目根>] [--json|--self-test|--help]

机械项委托 context-lint 检测；人判项（新旧并存/补记/去重/skill 卫生）标 ❓ 交人工。
逐项输出：编号 状态 项名 + 动作建议。

退出码: 0 无 ⚠ / 1 有 ⚠（机械项失败）/ 2 自身故障
EOF
}

SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
CL="$SCRIPT_DIR/context-lint.sh"
[ -f "$CL" ] || CL='toolbox-run-context-lint'

has() { printf '%s\n' "$OUT" | grep -q "\[$1\]"; }

run_cl() {
  if [ -f "$CL" ]; then
    OUT=$(sh "$CL" ${ROOT:+"--root" "$ROOT"} 2>&1) || CL_RC=$?
  else
    OUT=$(toolbox run context-lint ${ROOT:+"--root" "$ROOT"} 2>&1) || CL_RC=$?
  fi
  return 0
}

audit_core() {
  WARN_FLAG=0
  has CHECKPOINT && WARN_FLAG=1
  has CURRENT && WARN_FLAG=1
  has SSOT && WARN_FLAG=1
  has MERGE && WARN_FLAG=1
  has SIZE && WARN_FLAG=1
  has ORPHAN && WARN_FLAG=1
  has HDR && WARN_FLAG=1
  has POINTER && WARN_FLAG=1
  has VERIFY && WARN_FLAG=1
  has TODOS && WARN_FLAG=1
  has DONE && WARN_FLAG=1
  has RECLAIM && WARN_FLAG=1
  has ONCE && WARN_FLAG=1
  has LONG && WARN_FLAG=1
  has DECTIONS && WARN_FLAG=1
  [ "$CL_RC" -ne 0 ] && WARN_FLAG=1
}

render() {
  audit_core
  if has CHECKPOINT || has CURRENT; then
    echo '⚠ 1. 断点新鲜度/绑定：context-lint 报 CHECKPOINT/CURRENT 异常，转 @next 重写或重绑'
  else
    echo '✓ 1. 断点新鲜度（绑定正常）'
  fi
  echo '❓ 2. 新旧并存：通读 memory 正文，同主题矛盾结论按 [SSOT 修正] 收敛'
  if has SSOT; then
    echo '⚠ 3. devlog 积压高价值项：存在未归并 [SSOT 修正]，立即 §4 归并'
  else
    echo '✓ 3. devlog 积压高价值项（无 [SSOT 修正] 积压）'
  fi
  echo '❓ 4. 记忆补记审查：对照本窗口结论与 memory 正文，漏落盘按 @remember 补写'
  if has MERGE; then
    echo '⚠ 5. lessons/归并积压：待归并 ≥5，触发归并'
  else
    echo '✓ 5. lessons/归并积压（待归并 <5）'
  fi
  echo '❓ 5b. lessons 与规范去重：对照规范 skill，已覆盖条目降级 Ref:'
  if has SIZE; then
    echo '⚠ 6. 尺寸健康：memory >150 行，建议收尾/拆分'
  else
    echo '✓ 6. 尺寸健康（memory ≤150 行）'
  fi
  if has ORPHAN; then
    echo '⚠ 7. 孤儿 epic：devlog 30 天未动，提示 @done/搁置'
  else
    echo '✓ 7. 孤儿 epic（活跃）'
  fi
  if has HDR; then
    echo '⚠ 8. 头部校验：记忆文件头部字段缺失/角色不符'
  else
    echo '✓ 8. 头部校验（各文件头部合规）'
  fi
  if has POINTER; then
    echo '⚠ 9. 指针抽查：skill 引用锚点失效，当场修指针'
  else
    echo '✓ 9. 指针抽查（引用锚点存在）'
  fi
  echo '❓ 10. skill 卫生抽查：事实指针化 + description 预算（≤550 字符）'
  if [ "$CL_RC" -eq 0 ]; then
    echo '✓ 11. toolbox 巡检：context-lint 退出 0'
  else
    echo '⚠ 11. toolbox 巡检：context-lint 退出 1（见下方明细）'
  fi
  if has VERIFY; then
    echo '⚠ 12. 验证缺口抽查：[变更] 缺同日 [验证] 或 [验证] 无理由'
  else
    echo '✓ 12. 验证缺口抽查（[变更] 均有同日 [验证]）'
  fi
  if has TODOS || has DONE || has RECLAIM || has ONCE || has LONG || has DECTIONS; then
    echo '⚠ 附. todos/done/decisions 机械校验异常（见 context-lint 明细）'
  else
    echo '✓ 附. todos/done/decisions 机械校验（合规）'
  fi
  if [ "$WARN_FLAG" -eq 1 ]; then
    echo
    echo '—— context-lint 机械明细 ——'
    printf '%s\n' "$OUT"
  fi
}

self_test() {
  local td ok out
  ok=1
  td=$(mktemp -d)
  out=$(sh "$0" --root "$td" 2>&1)
  printf '%s' "$out" | grep -q '✓ 11' || { echo "self-test: 无 context 应全 ✓"; ok=0; }
  printf '%s' "$out" | grep -q '⚠' && { echo "self-test: 无 context 不应有 ⚠: $out"; ok=0; }
  mkdir -p "$td/b/context/epics/demo"
  printf 'epic: ghost\n' > "$td/b/context/CURRENT"
  cat > "$td/b/context/epics/demo/memory.md" <<'EOF'
---
dev-loop: memory
format: v1
epic: other
last-merge: none
---
正文无断点
EOF
  out=$(sh "$0" --root "$td/b" 2>&1)
  printf '%s' "$out" | grep -q '⚠ 1' || { echo "self-test: 坏样本应报 ⚠1: $out"; ok=0; }
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
  run_cl
  audit_core
  if [ "$WARN_FLAG" -eq 1 ]; then
    printf '{"status":"FAIL","severity":"warn","message":"有 ⚠ 机械审计项，请裸跑 ctx-audit 查看 12 项清单"}\n'
    exit 1
  fi
  printf '{"status":"OK","severity":"info","message":"12 项审计无机械 ⚠（人判项仍需人工核查）"}\n'
  exit 0
fi
run_cl
render
exit "$WARN_FLAG"
