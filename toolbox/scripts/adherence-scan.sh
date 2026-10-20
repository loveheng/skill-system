#!/bin/sh
# adherence-scan —— dev-loop 账本面遵循率遥测（评估 P3 落地；机械可测三指标）
#   1) [变更]↔[验证] 配对率：全量 devlog 统计（::audit 第 12 项只抽查尾部 2~3 条，本工具补全量趋势）
#   2) 归并及时率：devlog 待归并条数 > 阈值 5 的 epic 数（dev-loop §3 自动重构违约面）
#   3) 待办时效：[once] 超 30 天逾期 + [long] 待重评条数（memo-collector 生命周期口径）
# 诚实边界（写死）：收集触发点附注 / dev-guide 卡点 / 面板判读等纯聊天行为无落盘痕迹，
#   本工具不测也不产假数据——仍归 ::audit 人工抽查（第 4/12 项）。
#
# toolbox-script
# format: v1
# name: adherence-scan
# summary: 账本面遵循率遥测（变更验证配对率/归并及时率/待办时效三指标），纯聊天行为不测不造假
# trigger: manual
# cat: env
# alias: adh
# platform: unix
# self-test: --self-test

set -u
THRESHOLD=5   # devlog 归并阈值（dev-loop §3 写死值，只读不改）
usage() {
  cat <<'EOF'
用法: adherence-scan [--root <项目根>] [--json] [--self-test] [--help]
  --root  项目根（默认当前目录，读 <root>/context/）
  --json  单行契约结论（message 禁双引号）
  --self-test  金丝雀自检（构造已知账本断言三指标判定）
退出码: 0=全指标健康 1=存在指标不达标 2=自身故障（无 context/ 视为 2）
EOF
}

scan() {
  # 输出指标到全局变量：CHG PAIRED PAIR_RATE OVER BP_BAD LONG OV
  ctx=$1
  CHG=0; PAIRED=0; OVER=0; BP_BAD=0
  for df in "$ctx"/epics/*/devlog.md; do
    [ -f "$df" ] || continue
    c=$(grep -c '^- \[.\{1,\}\] \[变更\]' "$df" 2>/dev/null); [ -n "$c" ] || c=0
    CHG=$((CHG + c))
    # 配对：每条 [变更] 行须有同日或其后出现的 [验证] 行（简化：文件级计数——验证行数 ≥ 变更行数视为全配对）
    v=$(grep -c '^- \[.\{1,\}\] \[验证\]' "$df" 2>/dev/null); [ -n "$v" ] || v=0
    [ "$v" -lt "$c" ] && PAIRED=$((PAIRED + v)) || PAIRED=$((PAIRED + c))
    # 归并及时：待归并条数（尾部 20 行计数口径同 ctx-ratio）
    n=$(tail -n 20 "$df" | grep -c '^- \[' || true)
    [ "${n:-0}" -gt "$THRESHOLD" ] && OVER=$((OVER + 1))
  done
  if [ "$CHG" -gt 0 ]; then PAIR_RATE=$((PAIRED * 100 / CHG)); else PAIR_RATE=100; fi
  # 待办时效（口径同 panel.sh #11）
  LONG=0; OV=0
  todofiles="$ctx/todos.md"
  for df in "$ctx"/epics/*/todos.md; do [ -f "$df" ] && todofiles="$todofiles $df"; done
  for tf in $todofiles; do
    c=$(grep -cE '^- \[ \].*\[long\]' "$tf" 2>/dev/null); [ -n "$c" ] || c=0
    LONG=$((LONG + c))
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      ts=$(date -d "$d" +%s 2>/dev/null) || continue
      [ $(( ($(date +%s) - ts) / 86400 )) -gt 30 ] && OV=$((OV + 1))
    done <<EOF2
$(grep -E '^- \[ \].*\[once\]' "$tf" 2>/dev/null | grep -oE '\[[0-9]{4}-[0-9]{2}-[0-9]{2}\]' | tr -d '[]')
EOF2
  done
  return 0
}

render() {
  echo "账本面遵循率（阈值: devlog 归并 ≤$THRESHOLD）"
  echo "1. 变更↔验证配对: $PAIRED/$CHG（${PAIR_RATE}%）——≥90% 为健康线"
  echo "2. 归并及时: 超阈 epic $OVER 个（>0 = §3 自动重构违约）"
  echo "3. 待办时效: [long] 待重评 $LONG ｜ [once] 逾期 $OV"
  echo "（边界：收集触发点/dev-guide 卡点/面板判读等聊天行为无落盘痕迹，不测——归 ::audit 第 4/12 项人工抽查）"
}

self_test() {
  T=$(mktemp -d) || return 2
  mkdir -p "$T/context/epics/alpha" "$T/context/epics/beta"
  # alpha：2 变更 2 验证 = 4 行（配对 100%，未超阈）｜beta：3 变更 1 验证（配对率拉低）+ note 凑到 11 行超阈 + once 逾期
  printf -- '- [2026-10-19] [变更]: a1\n- [2026-10-19] [验证]: pass\n- [2026-10-19] [变更]: a2\n- [2026-10-19] [验证]: pass\n' > "$T/context/epics/alpha/devlog.md"
  printf -- '- [2026-10-19] [变更]: b1\n- [2026-10-19] [验证]: fail 修复中\n- [2026-10-19] [变更]: b2\n- [2026-10-19] [变更]: b3\n' > "$T/context/epics/beta/devlog.md"
  i=0; while [ $i -lt 7 ]; do echo "- [2026-10-19] [note]: fill $i" >> "$T/context/epics/beta/devlog.md"; i=$((i + 1)); done
  printf -- '---\nmemo: todos\nformat: v3\n---\n\n# 待办列表\n\n## misc\n- [ ] [2026-06-01] (风险) [once] 过期盯守项\n- [ ] [2026-10-19] (风险) [long] 长期隐患\n' > "$T/context/todos.md"
  scan "$T/context" || return 2
  rm -rf "$T"
  if [ "$CHG" -eq 5 ] && [ "$PAIRED" -eq 3 ] && [ "$PAIR_RATE" -eq 60 ] \
     && [ "$OVER" -eq 1 ] && [ "$LONG" -eq 1 ] && [ "$OV" -eq 1 ]; then
    echo "self-test: OK（配对 3/5=60% ｜ 超阈 1 ｜ long 1/once逾期 1——三指标判定与预期一致）"
    return 0
  fi
  echo "self-test: fail 指标漂移 CHG=$CHG PAIRED=$PAIRED RATE=$PAIR_RATE OVER=$OVER LONG=$LONG OV=$OV"
  return 1
}

ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "[remedy] --root 缺参数"; exit 2; }; ROOT=$2; shift 2 ;;
    --json) JSON=1; shift ;;
    --self-test) self_test; exit $? ;;
    --help|-h) usage; exit 0 ;;
    *) usage; echo "[remedy] 未知参数: $1"; exit 2 ;;
  esac
done
[ -n "$ROOT" ] || ROOT=$(pwd)
[ -d "$ROOT/context" ] || { echo "FAIL: 无 context/（未接入 dev-init）"; [ "${JSON:-0}" = 1 ] && printf '{"status":"FAIL","severity":"error","message":"无 context 目录，先走 dev-init 接入"}\n'; exit 2; }

scan "$ROOT/context" || { echo "FAIL: 扫描自身故障"; exit 2; }
FAIL=0
[ "$PAIR_RATE" -lt 90 ] && FAIL=1
[ "$OVER" -gt 0 ] && FAIL=1
MSG="配对 ${PAIR_RATE}% ｜ 超阈 epic ${OVER} ｜ long待重评 ${LONG}/once逾期 ${OV}"
if [ "$FAIL" = 0 ]; then
  render
  [ "${JSON:-0}" = 1 ] && printf '{"status":"OK","severity":"info","message":"%s"}\n' "$MSG"
  exit 0
fi
[ "${JSON:-0}" = 1 ] && printf '{"status":"FAIL","severity":"warn","message":"%s"}\n' "$MSG" || { render; echo "FAIL: $MSG（配对率健康线 90%；超阈 epic 先 ::merge）"; }
exit 1
