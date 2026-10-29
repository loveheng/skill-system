#!/bin/sh
# toolbox-script
# format: v1
# name: bootstrap
# summary: 开场协议编排器：context/ 探测 → 环境钩子（run-hooks bootstrap）→ 面板数据 → CURRENT 三分支（绑定卡数据/未绑定候选/无 context 静默结束），绑定卡格式由 dev-loop SKILL §3 定，本工具只供数
# trigger: manual
# cat: ops
# alias: boot
# platform: unix
# self-test: --self-test
#
# 定位：把「会话开场协议」从 AGENTS.md 散文搬成命令——AI 跑本工具，按输出标记分支；
# 语义判断（epic 类型、要不要挂 dev-guide）仍是 AI 的活，机械数据（绑定/状态/挂载/候选/面板）全由本工具供。
# 降级：本工具缺失时按 AGENTS.md 手工流程（读 CURRENT → 只读 memory.md → 手推出卡），禁编造状态。
set -u
SELF=$0
SELF="$(cd "$(dirname "$SELF")" && pwd)/$(basename "$SELF")" # 绝对化（自测沙箱 cd 后子调用仍可达）

ROOT=''; JSON=0

usage() {
  cat <<'EOF'
bootstrap —— 开场协议编排器（context/ 探测 + 环境钩子 + 面板数据 + CURRENT 分支）

用法: bootstrap [--root <项目根>] [--json] [--self-test] [--help]

输出标记（AI 按首行标记分支）:
  NO-CONTEXT  根下无 context/ —— 开场协议静默结束（纯咨询/非项目目录，按用户实际请求正常响应，不出卡不跑工具）
  UNBOUND     CURRENT 缺失/none —— 列 epics/ 候选请用户 ::bind，严禁自选开工
  BOUND       正常绑定 —— 附 kind/state/挂载 + 面板数据，AI 按 dev-loop SKILL §3 组装 ≤4 行绑定卡（类型字段 AI 判断）

行为:
  钩子：cd 项目根跑 run-hooks bootstrap --quiet（非 0 仅附一行 ⚠，严禁阻塞恢复流程；
        元工具缺失则跳过钩子；TOOLBOX_MGR 可覆盖元工具路径——自测用）
  面板：调用同池 panel.sh --root 供绑定卡数据源
  --json：单行契约结论（bound/no-context → OK；unbound → FAIL warn + remedy；自身故障 → FAIL error）
        附加字段 root/epic/kind/state/hook（AI 解析依赖，勿改键名）

退出码: 0=通过（含 no-context） 1=未绑定需用户选择 2=自身故障
EOF
}

esc() { printf '%s' "$1" | tr '"' "'"; }

# ===================== 自测（前置定义：参数解析循环内直接调用） =====================
exec_self_test() {
  T=$(mktemp -d 2>/dev/null) || { echo 'self-test: mktemp 失败'; return 2; }
  (cd "$T" && git init -q . 2>/dev/null) || { rm -rf "$T"; echo 'self-test: git init 失败'; return 2; }
  B="sh $SELF"
  TOOLBOX_MGR=/nonexistent-mgr
  export TOOLBOX_MGR
  pass=0; failed=0
  chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else failed=$((failed+1)); echo "SELF-TEST FAIL: $1 (期望[$3] 实得[$2])"; fi; }

  # T1 no-context：根下无 context/ → NO-CONTEXT，exit 0
  out=$($B --root "$T" 2>&1); rc=$?
  chk "T1 no-context 退出码" "$rc" "0"
  printf '%s' "$out" | head -n 1 | grep -q '^NO-CONTEXT' || { echo "SELF-TEST FAIL: T1 缺 NO-CONTEXT 标记: $out"; failed=$((failed+1)); }
  jout=$($B --root "$T" --json 2>&1)
  printf '%s' "$jout" | grep -q '"status":"OK"' && printf '%s' "$jout" | grep -q 'no-context' || { echo "SELF-TEST FAIL: T1 json 不符: $jout"; failed=$((failed+1)); }
  pass=$((pass+2))

  # T2 unbound：CURRENT=none → UNBOUND + 候选列出，exit 1
  mkdir -p "$T/context/epics/demo" "$T/context/epics/misc"
  printf 'epic: none\n' > "$T/context/CURRENT"
  printf -- '---\ndev-loop: memory\nformat: v1\nepic: demo\ntotal-merged: 0\nlast-merge: none\n---\n\n# demo\n\n- [挂载] docs/design/demo.md\n\n## 断点\n- [断点] 下一步：等待拆解\n' > "$T/context/epics/demo/memory.md"
  printf -- '---\ndev-loop: devlog\nformat: v1\nepic: demo\ntotal-merged: 0\nlast-merge: none\n---\n' > "$T/context/epics/demo/devlog.md"
  out=$($B --root "$T" 2>&1); rc=$?
  chk "T2 unbound 退出码" "$rc" "1"
  printf '%s' "$out" | head -n 1 | grep -q '^UNBOUND' || { echo "SELF-TEST FAIL: T2 缺 UNBOUND 标记: $out"; failed=$((failed+1)); }
  printf '%s' "$out" | grep -q 'demo ｜ 最后活动' || { echo "SELF-TEST FAIL: T2 候选缺 demo: $out"; failed=$((failed+1)); }
  printf '%s' "$out" | grep -q '严禁 AI 自选开工' || { echo "SELF-TEST FAIL: T2 缺禁自选提示: $out"; failed=$((failed+1)); }
  jout=$($B --root "$T" --json 2>&1)
  printf '%s' "$jout" | grep -q '"status":"FAIL"' && printf '%s' "$jout" | grep -q '"severity":"warn"' || { echo "SELF-TEST FAIL: T2 json 不符: $jout"; failed=$((failed+1)); }
  pass=$((pass+4))

  # T3 bound：临时 epic → BOUND + kind: temp，exit 0
  printf 'epic: demo\n' > "$T/context/CURRENT"
  awk '/^total-merged: /&&!d{print "kind: temp"; d=1} {print}' "$T/context/epics/demo/memory.md" > "$T/context/epics/demo/memory.md.k" \
    && mv "$T/context/epics/demo/memory.md.k" "$T/context/epics/demo/memory.md"
  out=$($B --root "$T" 2>&1); rc=$?
  chk "T3 bound 退出码" "$rc" "0"
  printf '%s' "$out" | head -n 1 | grep -q '^BOUND: demo ｜ kind: temp' || { echo "SELF-TEST FAIL: T3 缺 BOUND/kind 行: $out"; failed=$((failed+1)); }
  printf '%s' "$out" | grep -q '挂载: docs/design/demo.md' || { echo "SELF-TEST FAIL: T3 缺挂载行: $out"; failed=$((failed+1)); }
  printf '%s' "$out" | grep -q '面板数据' || { echo "SELF-TEST FAIL: T3 缺面板数据节: $out"; failed=$((failed+1)); }
  jout=$($B --root "$T" --json 2>&1)
  printf '%s' "$jout" | grep -q '"kind":"temp"' && printf '%s' "$jout" | grep -q '"status":"OK"' || { echo "SELF-TEST FAIL: T3 json 不符: $jout"; failed=$((failed+1)); }
  pass=$((pass+4))

  # T4 hook fail 分支：MGR 指向一个返回 1 的假脚本 → 附 ⚠ 行但不阻塞
  H="$T/fake-mgr.py"
  printf '#!/usr/bin/env python3\nimport sys; sys.exit(1)\n' > "$H"
  TOOLBOX_MGR="$H" $B --root "$T" 2>&1 | grep -q '^⚠ hook:' || { echo "SELF-TEST FAIL: T4 缺 hook 异常提示"; failed=$((failed+1)); }
  pass=$((pass+1))
  TOOLBOX_MGR=/nonexistent-mgr

  rm -rf "$T"
  if [ "$failed" -eq 0 ]; then echo "self-test: OK（no-context/unbound/bound 三分支 + json 契约 + hook 降级，$pass 断言）"; return 0; fi
  return 2
}

# ===================== 参数解析 =====================
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo '[remedy] --root 缺参数'; exit 2; }; ROOT=$2; shift 2 ;;
    --json) JSON=1; shift ;;
    --self-test) exec_self_test; exit $? ;;
    --help|-h) usage; exit 0 ;;
    *) echo "[remedy] 未知参数: $1（--help 看用法）"; exit 2 ;;
  esac
done

# 项目根：--root > git toplevel > cwd（开场协议口径：工作目录向上至项目根）
[ -n "$ROOT" ] || ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$ROOT" ] || ROOT=$(pwd)
if [ ! -d "$ROOT" ]; then
  if [ "$JSON" -eq 1 ]; then
    printf '{"status":"FAIL","severity":"error","message":"自身故障: 项目根不存在 %s","remedy":"--root 传存在的目录"}\n' "$(esc "$ROOT")"
  else
    echo "ERROR: 项目根不存在: $ROOT"; echo '[remedy] --root 传存在的目录'
  fi
  exit 2
fi

CTXT="$ROOT/context"

# ---- 无 context/：协议静默结束（纯咨询/非项目目录）----
if [ ! -d "$CTXT" ]; then
  if [ "$JSON" -eq 1 ]; then
    printf '{"status":"OK","severity":"info","message":"no-context: %s 无 context/，开场协议静默结束","root":"%s"}\n' "$(esc "$ROOT")" "$(esc "$ROOT")"
  else
    echo "NO-CONTEXT: $ROOT 无 context/ —— 开场协议静默结束（纯咨询/非项目目录，按用户实际请求正常响应，不出卡不跑工具）"
  fi
  exit 0
fi

# ---- 环境钩子：cd 项目根跑 run-hooks bootstrap --quiet（非 0 仅 ⚠ 不阻塞；元工具缺失跳过）----
MGR="${TOOLBOX_MGR:-$(cd "$(dirname "$SELF")/../.." && pwd)/skills/agent-toolbox/toolbox-mgr.py}"
HOOK=skip
if [ -f "$MGR" ] && command -v python3 >/dev/null 2>&1; then
  if (cd "$ROOT" && python3 "$MGR" run-hooks bootstrap --quiet >/dev/null 2>&1); then
    HOOK=ok
  else
    HOOK=fail
  fi
fi

PANEL_SH="$(dirname "$SELF")/panel.sh"
if [ -f "$PANEL_SH" ]; then
  PANEL_OUT=$(sh "$PANEL_SH" --root "$ROOT" 2>/dev/null)
else
  PANEL_OUT='（panel 缺失，绑定卡降级手推：读 CURRENT → 只读 memory.md）'
fi

# ---- CURRENT 解析 ----
CUR_RAW=$(sed -n 's/^epic:[[:space:]]*//p' "$CTXT/CURRENT" 2>/dev/null | head -n 1)
case "$CUR_RAW" in '(未绑定)'|'') CUR_RAW='none' ;; esac

epic_tag() { # 候选行：名 + 最后活动 + 状态标注（维护/临时）
  _ed="$CTXT/epics/$1"
  _d='?'
  _ts=$(find "$_ed" -type f -printf '%T@\n' 2>/dev/null | sort -rn | head -n 1 | cut -d. -f1)
  [ -n "$_ts" ] && _d=$(date -d "@$_ts" +%m-%d 2>/dev/null || echo '?')
  _st=''
  [ "$(sed -n '2,12{s/^state:[[:space:]]*//p}' "$_ed/memory.md" 2>/dev/null | head -n 1)" = maintenance ] && _st='维护'
  [ "$(sed -n '2,12{s/^kind:[[:space:]]*//p}' "$_ed/memory.md" 2>/dev/null | head -n 1)" = temp ] && _st="${_st}${_st:+/}临时"
  printf '%s ｜ 最后活动 %s%s' "$1" "$_d" "${_st:+ ｜ $_st}"
}

# ---- UNBOUND：列候选请用户选（严禁自选开工）----
if [ "$CUR_RAW" = none ]; then
  CANDS=''
  for _d in "$CTXT"/epics/*/; do
    [ -d "$_d" ] || continue
    _n=$(basename "$_d")
    CANDS="${CANDS}  - $(epic_tag "$_n")"$'\n'
  done
  if [ "$JSON" -eq 1 ]; then
    printf '{"status":"FAIL","severity":"warn","message":"unbound: 当前无绑定（CURRENT: %s），须用户选择候选 ::bind","remedy":"::bind <候选名>（严禁 AI 自选开工）","root":"%s","epic":"none","hook":"%s"}\n' \
      "$(esc "$CUR_RAW")" "$(esc "$ROOT")" "$HOOK"
    exit 1
  fi
  echo "UNBOUND: 当前无绑定（CURRENT: $CUR_RAW）"
  echo '候选（请用户选一 ::bind，严禁 AI 自选开工）:'
  [ -n "$CANDS" ] && printf '%s' "$CANDS" || echo '  （epics/ 为空——先 ::bind <新名> 建首个 epic）'
  [ "$HOOK" = fail ] && echo '⚠ hook: bootstrap 钩子有异常（明细 toolbox run-hooks bootstrap；不阻塞恢复流程）'
  echo '面板数据:'
  printf '%s\n' "$PANEL_OUT"
  exit 1
fi

# ---- BOUND：绑定卡数据 ----
E="$CUR_RAW"
case "$E" in
  archive/*) EDIR="$CTXT/$E" ;;
  *)         EDIR="$CTXT/epics/$E" ;;
esac
KIND=''; STATE=''
if [ -f "$EDIR/memory.md" ]; then
  KIND=$(sed -n '2,12{s/^kind:[[:space:]]*//p}' "$EDIR/memory.md" | head -n 1)
  STATE=$(sed -n '2,12{s/^state:[[:space:]]*//p}' "$EDIR/memory.md" | head -n 1)
  [ "$STATE" = '' ] && STATE=active
else
  STATE='骨架缺失'
fi
MOUNT=$(grep -m1 '^- \[挂载\]' "$EDIR/memory.md" 2>/dev/null | sed 's/^- \[挂载\][[:space:]]*//')

if [ "$JSON" -eq 1 ]; then
  printf '{"status":"OK","severity":"info","message":"bound: %s（kind: %s, state: %s）——绑定卡按 dev-loop SKILL §3 组装","root":"%s","epic":"%s","kind":"%s","state":"%s","hook":"%s"}\n' \
    "$(esc "$E")" "$(esc "${KIND:-formal}")" "$(esc "$STATE")" "$(esc "$ROOT")" "$(esc "$E")" "$(esc "${KIND:-formal}")" "$(esc "$STATE")" "$HOOK"
  exit 0
fi
echo "BOUND: $E ｜ kind: ${KIND:-formal} ｜ state: $STATE ｜ 挂载: ${MOUNT:-无}"
[ "$HOOK" = fail ] && echo '⚠ hook: bootstrap 钩子有异常（明细 toolbox run-hooks bootstrap；不阻塞恢复流程）'
echo '面板数据:'
printf '%s\n' "$PANEL_OUT"
echo '绑定卡按 dev-loop SKILL.md §3 组装（≤4 行，数据源=上面面板输出；类型字段由 AI 判断，建议挂 dev-guide 与否同轮定）'
exit 0
