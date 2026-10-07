#!/bin/sh
# ctx-audit — dev-loop §7 @audit 12 项质检清单呈现（✓/⚠/❓）；机械项委托 context-lint 检测，人判项标 ❓
# --init = dev-init §2 接入验收机械档：骨架/gitignore/数据面/skill 在场/docs 卡点/白名单/项目池/机器件/锚点/description 逐条 ✓/⚠
#
# toolbox-script
# format: v1
# name: ctx-audit
# summary: dev-loop §7 @audit 12 项质检清单 + --init 接入验收机械档（dev-init §2 聚合）；机械项委托 context-lint/skill-verify，人判项标 ❓
# trigger: manual
# cat: docs
# platform: unix
# self-test: --self-test

set -u
ROOT=''
JSON=0
SELF_TEST=0
INIT_FLAG=0
OUT=''
CL_RC=0
WARN_FLAG=0

usage() {
  cat <<'EOF'
ctx-audit —— dev-loop §7 @audit 12 项质检清单（✓/⚠/❓）+ dev-init 接入验收机械档

用法: ctx-audit.sh [--root <项目根>] [--init] [--json|--self-test|--help]

默认: 12 项质检清单——机械项委托 context-lint 检测；人判项（新旧并存/补记/去重/skill 卫生）标 ❓ 交人工。
--init: 接入验收机械档（dev-init §2 聚合）——context/ 骨架、gitignore、记忆数据面、project-local skill
        在场、docs 硬卡点、白名单骨架、项目池、机器件（fail-open）、skill 锚点（skill-verify）、
        description 预算逐条 ✓/⚠；命令实测/索引语义/冷启动演练/事实指针化 4 项人判另计。
逐项输出：状态 项名 + 动作建议。

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

init_profile() {
  R="$ROOT"
  [ -n "$R" ] || R=.
  run_cl
  INIT_WARN=0
  ok_add() { printf '✓ %s\n' "$*"; }
  warn_add() { INIT_WARN=1; printf '⚠ %s\n' "$*"; }

  miss=''
  [ -f "$R/context/CURRENT" ] || miss="$miss CURRENT"
  ls "$R"/context/epics/*/memory.md >/dev/null 2>&1 || miss="$miss memory.md"
  ls "$R"/context/epics/*/devlog.md >/dev/null 2>&1 || miss="$miss devlog.md"
  [ -f "$R/context/lessons.md" ] || miss="$miss lessons.md"
  if [ -n "$miss" ]; then
    warn_add "A. context/ 骨架缺:$miss（toolbox run scaffold 幂等补齐）"
  else
    ok_add "A. context/ 骨架在位"
  fi

  if [ -d "$R/.git" ] && [ -f "$R/context/CURRENT" ]; then
    if git -C "$R" check-ignore -q context/CURRENT; then
      if git -C "$R" check-ignore -q context/lessons.md; then
        warn_add "B. gitignore：context/ 其余文件被忽略（仅 CURRENT 应忽略）"
      else
        ok_add "B. gitignore（CURRENT 忽略、其余入库）"
      fi
    else
      warn_add "B. gitignore：context/CURRENT 未被忽略（追加一行到 .gitignore）"
    fi
  else
    ok_add "B. gitignore（非 git 仓或无 CURRENT，跳过）"
  fi

  if [ "$CL_RC" -eq 0 ]; then
    ok_add "C. 记忆数据面 YAML/Schema（context-lint 通过）"
  else
    warn_add "C. 记忆数据面异常（见下方 context-lint 明细）"
  fi

  SKC=$(find "$R/.agents/skills" -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
  if [ "$SKC" -ge 1 ]; then
    ok_add "D. project-local skill ×$SKC"
  else
    warn_add "D. 无 project-local skill（dev-init §1 第 3/4 步建 workflow/索引）"
  fi

  if [ -d "$R/docs" ]; then
    if ls "$R"/.agents/skills/*-docs/SKILL.md >/dev/null 2>&1; then
      ok_add "E. docs 硬卡点（<repo>-docs skill 在场）"
    else
      warn_add "E. docs/ 在场但无 <repo>-docs skill（dev-init §1.5 第 4 项硬卡点）"
    fi
  else
    ok_add "E. docs 硬卡点（无 docs/，跳过）"
  fi

  WMISS=''
  [ -f "$R/.uncertainty-whitelist" ] || WMISS="$WMISS .uncertainty-whitelist"
  [ -f "$R/.degrade-whitelist" ] || WMISS="$WMISS .degrade-whitelist"
  if [ -n "$WMISS" ]; then
    warn_add "F. 白名单骨架缺:$WMISS（scaffold 幂等生成）"
  else
    ok_add "F. 白名单骨架在场"
  fi

  if [ -f "$R/scripts/agent-tools/README.md" ]; then
    ok_add "G. toolbox 项目池在场"
  else
    warn_add "G. 项目池缺（toolbox init --project 落 README 占位）"
  fi

  if command -v toolbox >/dev/null 2>&1; then
    MMISS=''
    toolbox list 2>/dev/null | grep -q 'panel' || MMISS="$MMISS panel"
    toolbox list 2>/dev/null | grep -q 'cmds' || MMISS="$MMISS cmds"
    if [ -n "$MMISS" ]; then
      warn_add "H. 机器件不在池:$MMISS（fail-open 不阻塞，修复见 toolbox README §1.5）"
    else
      ok_add "H. 机器件在场（panel/cmds）"
    fi
    if [ -f "$HOME/.zcode/AGENTS.md" ]; then
      ok_add "H2. 用户级开场协议在场"
    else
      warn_add "H2. 用户级开场协议缺（~/.zcode/AGENTS.md；fail-open 不阻塞）"
    fi
    if [ "$SKC" -ge 1 ]; then
      toolbox run skill-verify --root "$R" --json >/dev/null 2>&1
      rc=$?
      if [ "$rc" -eq 0 ]; then
        ok_add "I. skill 锚点存在性（skill-verify 通过）"
      elif [ "$rc" -eq 1 ]; then
        warn_add "I. skill 锚点存在 ⚠（裸跑 toolbox run skill-verify 看明细修指针）"
      else
        warn_add "I. skill-verify 自身故障（fail-open 不阻塞，rc=$rc）"
      fi
    else
      ok_add "I. skill 锚点校验（无 skill，跳过）"
    fi
  else
    warn_add "H. toolbox 不可用（fail-open 不阻塞，机器级依赖降级手推）"
    ok_add "I. skill 锚点校验（无 toolbox，跳过）"
  fi

  DMISS=''
  for f in "$R"/.agents/skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    L=$(awk 'FNR==3 && /^description:/{print length($0); exit}' "$f")
    [ -n "$L" ] || continue
    [ "$L" -gt 550 ] && DMISS="$DMISS $(basename "$(dirname "$f")")($L)"
  done
  if [ -n "$DMISS" ]; then
    warn_add "J. description 超预算:$DMISS（≤550）"
  else
    ok_add "J. description 预算（在场 skill 均 ≤550）"
  fi

  printf '%s\n' \
    '❓ 实测：workflow 候选命令 ≥1 条跑通（fact-probe 底稿可先取证）' \
    '❓ 索引归属表语义真实（≥1 行真实落点，非占位）' \
    '❓ 冷启动演练：空白窗口开场全路径（panel 绑定卡 → 按断点恢复）' \
    '❓ skill 正文无易漂移事实（事实指针化）'
  if [ "$INIT_WARN" -eq 1 ]; then
    echo '—— 机械项有 ⚠：修复后复跑；fail-open 项记待办不阻塞验收（dev-init §1 第 9 步） ——'
    if [ "$CL_RC" -ne 0 ]; then
      echo '—— context-lint 明细 ——'
      printf '%s\n' "$OUT"
    fi
    return 1
  fi
  echo '—— 机械项全 ✓，剩 4 项人判演练（dev-init §1 第 9 步 / §2）——'
  return 0
}

self_test() {
  local td ok out rc g
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
  out=$(sh "$0" --root "$td" --init 2>&1)
  rc=$?
  [ "$rc" -eq 1 ] || { echo "self-test: --init 空目录应 exit 1（骨架缺失）: $out"; ok=0; }
  g="$td/g"
  mkdir -p "$g/context/epics/misc" "$g/.agents/skills/demo-workflow" "$g/scripts/agent-tools"
  printf 'epic: misc\n' > "$g/context/CURRENT"
  cat > "$g/context/epics/misc/memory.md" <<'EOF'
---
dev-loop: memory
format: v1
epic: misc
total-merged: 0
last-merge: none
---

# misc

## 断点
- [断点] 下一步：等待散修任务
EOF
  printf -- '---\ndev-loop: devlog\nformat: v1\nepic: misc\ntotal-merged: 0\nlast-merge: none\n---\n' > "$g/context/epics/misc/devlog.md"
  printf -- '---\ndev-loop: lessons\nformat: v1\nepic: global\ntotal-merged: 0\nlast-merge: none\n---\n' > "$g/context/lessons.md"
  cat > "$g/.agents/skills/demo-workflow/SKILL.md" <<'EOF'
---
name: demo-workflow
description: demo workflow for ctx-audit init self test
format: v1
---

demo：锚点用 `context/CURRENT`。
EOF
  printf '# 白名单骨架（禁预置条目）\n' > "$g/.uncertainty-whitelist"
  printf '# 白名单骨架（禁预置条目）\n' > "$g/.degrade-whitelist"
  printf '项目池占位\n' > "$g/scripts/agent-tools/README.md"
  out=$(sh "$0" --root "$g" --init 2>&1)
  rc=$?
  [ "$rc" -eq 0 ] || { echo "self-test: --init 好样本应 exit 0: $out"; ok=0; }
  printf '%s' "$out" | grep -q '❓ 冷启动演练' || { echo "self-test: --init 好样本应含人判项: $out"; ok=0; }
  if [ "$ok" -eq 1 ]; then echo "self-test: OK"; rm -rf "$td"; return 0; fi
  rm -rf "$td"; return 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2;;
    --init) INIT_FLAG=1; shift;;
    --json) JSON=1; shift;;
    --self-test) SELF_TEST=1; shift;;
    --help|-h) usage; exit 0;;
    *) echo "未知参数: $1"; usage; exit 2;;
  esac
done

if [ "$SELF_TEST" -eq 1 ]; then self_test; exit $?; fi
if [ "$INIT_FLAG" -eq 1 ]; then
  if [ "$JSON" -eq 1 ]; then
    if init_profile >/dev/null 2>&1; then
      printf '{"status":"OK","severity":"info","message":"接入验收机械项全 ✓（人判 4 项另计）"}\n'
      exit 0
    fi
    printf '{"status":"FAIL","severity":"warn","message":"接入验收存在机械 ⚠","remedy":"裸跑 ctx-audit --init 看明细"}\n'
    exit 1
  fi
  init_profile
  exit $?
fi
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
