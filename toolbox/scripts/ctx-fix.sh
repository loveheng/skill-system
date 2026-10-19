#!/bin/sh
# context 记忆体系存量债确定性修复：RECLAIM 人工打勾回收 / HDR 头部重建 / CHECKPOINT 断点结构重建。
# 专项清理第 3 步机械件——只做确定性事，语义类（归并/SSOT/断点内容）不代劳。
#
# toolbox-script
# format: v1
# name: ctx-fix
# summary: context 存量债确定性修复（人工打勾 [x] 回收进 done.md / 头部 YAML 重建 / 断点结构重建），默认干跑，--apply 落盘，幂等可重跑
# trigger: manual
# platform: unix
# self-test: --self-test
# cat: docs
# alias: cfx

set -u

ROOT=''; FIXES='all'; APPLY=0; BAK=''; JSON=0; SELFTEST=0
TODAY=$(date +%Y-%m-%d)
PLAN=''; DONE_N=0; SKIP_N=0; FIX_N=0; SKIP_CP=0

usage() {
  cat <<'EOF'
ctx-fix —— context 记忆体系存量债确定性修复（专项清理第 3 步机械件）

用法: ctx-fix.sh [--root <项目根>] [--fix <reclaim|hdr|checkpoint|all>] [--apply]
                 [--bak-dir <目录>] [--json] [--self-test] [--help]

默认干跑（dry-run）：只打印将做什么，不落盘；确认后加 --apply 才执行。
三类修复（--fix 逗号组合，默认 all）：
  reclaim      epics/*/todos.md 与全局 todos.md 中人工打勾的 `- [x]` 行搬入 done.md
               （格式 `- [YYYY-MM-DD] <正文> (域: <名>)`，剥行首旧版标签），并从源删除；
               done.md 已有同文条目自动跳过（幂等）
  hdr          重建缺失/不合规头部 YAML：memory/devlog（dev-loop 角色行 + format + epic 归属
               + total-merged/last-merge）、todos（memo: todos + format + epic 归属）；
               已有正确头部的文件不动，已有 total-merged/last-merge 值继承保留
  checkpoint   对缺 `- [断点]` 或缺 `## 断点` 章节的 epic 调 toolbox run devlog bp 重建结构
               （内容为占位，须 AI 下一轮回填真实下一步）；需 toolbox 在场，缺失则跳过并提示

退出码: 0=无待修项（干跑出计划亦算 0） / 1=有待修项（干跑）或修复后仍有残留 / 2=自身故障
安全:   --apply 落盘前备份到 ${TMPDIR:-/tmp}/ctx-fix-bak-<时间戳>/（--bak-dir 可改）；
       所有改写文件应入 git，回滚优先 git checkout，备份仅作双保险
EOF
  return 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT=${2:-}; shift 2 ;;
    --fix) FIXES=${2:-}; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --bak-dir) BAK=${2:-}; shift 2 ;;
    --json) JSON=1; shift ;;
    --self-test) SELFTEST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'FAIL: 未知参数: %s\n' "$1"; echo '[remedy] 见 --help'; exit 2 ;;
  esac
done

wants() { case ",$FIXES," in *",$1,"*|*",all,"*) return 0 ;; *) return 1 ;; esac; }

# ---------- reclaim ----------
# 剥 `- [x] ` 与行首连续的 (...) / [...] 旧版标签；遇 (src: 停（src 归属须保留）
reclaim_one() { # <file> → 干跑/落盘由 APPLY 决定
  f=$1
  case "$f" in
    */epics/*/todos.md) dom=$(basename "$(dirname "$f")") ;;
    *) dom='misc' ;;
  esac
  grep -c '^- \[[xX]\]' "$f" 2>/dev/null | grep -q '^0$' && return 0
  TMPD=$(mktemp -d 2>/dev/null) || { printf 'FAIL: mktemp 失败\n'; exit 2; }
  awk -v dom="$dom" '
    /^- \[[xX]\] / {
      line=$0
      sub(/^- \[[xX]\] /, "", line)
      while (1) {
        if (line ~ /^\(src:/) break
        if (line ~ /^\([^)]*\) +/) { sub(/^\([^)]*\) +/, "", line); continue }
        if (line ~ /^\[[^]]*\] +/) { sub(/^\[[^]]*\] +/, "", line); continue }
        break
      }
      printf "%d\t%s\t%s\n", NR, dom, line
    }
  ' "$f" > "$TMPD/plan"

  NUMS=''; : > "$TMPD/append"
  while IFS="$(printf '\t')" read -r num dm text; do
    [ -n "${num:-}" ] || continue
    core=$(printf '%s' "$text" | cut -c1-40)
    if grep -qF -- "$core" "$CTX/done.md" 2>/dev/null; then
      SKIP_N=$((SKIP_N + 1))
      NUMS="$NUMS $num"
      PLAN="$PLAN  [已在 done.md，仅删源不重复搬] $f:$num $core..."'\n'
      continue
    fi
    NUMS="$NUMS $num"
    printf -- '- [%s] %s (域: %s)\n' "$TODAY" "$text" "$dm" >> "$TMPD/append"
    DONE_N=$((DONE_N + 1))
    PLAN="$PLAN  [reclaim] $f:$num -> done.md (域: $dm)"'\n'
  done < "$TMPD/plan"

  if [ -n "$NUMS" ] && [ "$APPLY" -eq 1 ]; then
    mkdir -p "$BAK" 2>/dev/null
    rel=${f#"$ROOT"/}
    mkdir -p "$BAK/$(dirname "$rel")" 2>/dev/null
    cp -p "$f" "$BAK/$rel" 2>/dev/null
    awk -v nums="$NUMS" 'BEGIN{n=split(nums,a," "); for(i=1;i<=n;i++) del[a[i]]=1} !(NR in del)' "$f" > "$TMPD/new"
    awk '/^$/{if(p) next; p=1; print; next} {p=0; print}' "$TMPD/new" > "$TMPD/sq"
    cat "$TMPD/sq" > "$f"
    cat "$TMPD/append" >> "$CTX/done.md"
    FIX_N=$((FIX_N + 1))
  elif [ -n "$NUMS" ]; then
    PLAN="$PLAN  [dry-run 未落盘] $f 将删 $(printf '%s' "$NUMS" | wc -w | tr -d '[:space:]') 行"'\n'
  fi
  rm -rf "$TMPD"
  return 0
}

do_reclaim() {
  for f in "$CTX"/epics/*/todos.md "$CTX"/todos.md; do
    [ -f "$f" ] || continue
    reclaim_one "$f"
  done
  return 0
}

# ---------- hdr ----------
hdr_ok() { # <file> <角色行> <epic> <full>
  head -n 1 "$1" 2>/dev/null | grep -q '^--- *$' || return 1
  head -n 7 "$1" 2>/dev/null | grep -qF "$2" || return 1
  head -n 7 "$1" 2>/dev/null | grep -q '^format: v' || return 1
  head -n 7 "$1" 2>/dev/null | grep -qE "^epic: $3 *$" || return 1
  if [ "$4" = yes ]; then
    head -n 7 "$1" 2>/dev/null | grep -qE 'total-merged: [0-9]+' || return 1
    head -n 7 "$1" 2>/dev/null | grep -qE 'last-merge: (none|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])' || return 1
  fi
  return 0
}

rebuild_hdr() { # <file> <角色行 memory|devlog|memo: todos> <epic> <full>
  f=$1; role=$2; epic=$3; full=$4
  tm=$(head -n 7 "$f" 2>/dev/null | sed -n 's/^total-merged: *//p' | head -n 1); [ -n "$tm" ] || tm=0
  lm=$(head -n 7 "$f" 2>/dev/null | sed -n 's/^last-merge: *//p' | head -n 1); [ -n "$lm" ] || lm=none
  fmt=$(head -n 7 "$f" 2>/dev/null | sed -n 's/^format: *//p' | head -n 1)
  if [ "$role" = 'memo: todos' ]; then [ -n "$fmt" ] || fmt=v2; else [ -n "$fmt" ] || fmt=v1; fi
  TMPD=$(mktemp -d 2>/dev/null) || { printf 'FAIL: mktemp 失败\n'; exit 2; }
  if head -n 1 "$f" 2>/dev/null | grep -q '^--- *$'; then
    e=$(awk 'NR>1 && /^--- *$/{print NR; exit}' "$f" 2>/dev/null)
    [ -n "$e" ] && bs=$((e + 1)) || bs=1
  else
    bs=1
  fi
  tail -n +"$bs" "$f" > "$TMPD/body" 2>/dev/null
  if [ "$role" = 'memo: todos' ]; then
    printf -- '---\nmemo: todos\nformat: %s\nepic: %s\n---\n' "$fmt" "$epic" > "$TMPD/hdr"
  else
    printf -- '---\ndev-loop: %s\nformat: %s\nepic: %s\ntotal-merged: %s\nlast-merge: %s\n---\n' "$role" "$fmt" "$epic" "$tm" "$lm" > "$TMPD/hdr"
  fi
  if [ "$APPLY" -eq 1 ]; then
    mkdir -p "$BAK" 2>/dev/null
    rel=${f#"$ROOT"/}
    mkdir -p "$BAK/$(dirname "$rel")" 2>/dev/null
    cp -p "$f" "$BAK/$rel" 2>/dev/null
    cat "$TMPD/hdr" "$TMPD/body" > "$TMPD/out"
    cat "$TMPD/out" > "$f"
    FIX_N=$((FIX_N + 1))
  fi
  PLAN="$PLAN  [hdr] $f 角色=$role epic=$epic format=$fmt"'\n'
  rm -rf "$TMPD"
  return 0
}

do_hdr() {
  for d in "$CTX"/epics/*/; do
    [ -d "$d" ] || continue
    e=$(basename "$d")
    m=${d}memory.md; g=${d}devlog.md; t=${d}todos.md
    [ -f "$m" ] && { hdr_ok "$m" 'dev-loop: memory' "$e" yes || rebuild_hdr "$m" 'memory' "$e" yes; }
    [ -f "$g" ] && { hdr_ok "$g" 'dev-loop: devlog' "$e" yes || rebuild_hdr "$g" 'devlog' "$e" yes; }
    [ -f "$t" ] && { hdr_ok "$t" 'memo: todos' "$e" no || rebuild_hdr "$t" 'memo: todos' "$e" no; }
  done
  return 0
}

# ---------- checkpoint ----------
do_checkpoint() {
  if ! command -v toolbox >/dev/null 2>&1; then
    PLAN="$PLAN  [checkpoint 跳过] toolbox 不在 PATH，无法调 devlog bp 重建断点结构"'\n'
    SKIP_CP=$((SKIP_CP + 1))
    return 0
  fi
  for d in "$CTX"/epics/*/; do
    [ -d "$d" ] || continue
    e=$(basename "$d")
    [ "$e" = misc ] && continue
    m=${d}memory.md
    [ -f "$m" ] || continue
    if ! grep -q '^- \[断点\]' "$m" 2>/dev/null || ! grep -q '^## 断点' "$m" 2>/dev/null; then
      if [ "$APPLY" -eq 1 ]; then
        toolbox run devlog --root "$ROOT" bp "$e" "待 AI 回填：该 epic 断点由 ctx-fix 结构重建（专项清理），须下一轮读 devlog 尾部补真实下一步" >/dev/null 2>&1
        FIX_N=$((FIX_N + 1))
        PLAN="$PLAN  [checkpoint] $m 已重建断点结构（内容占位待回填）"'\n'
      else
        PLAN="$PLAN  [checkpoint] $m 缺断点行，将调 devlog bp 重建结构（内容占位待 AI 回填）"'\n'
      fi
    fi
  done
  return 0
}

# ---------- self-test ----------
selftest() {
  T=$(mktemp -d 2>/dev/null) || { printf 'FAIL: mktemp 失败\n'; exit 2; }
  mkdir -p "$T/context/epics/a" "$T/context/epics/b"
  printf '正文无头部无断点\n- [2026-10-19] 初始结论\n' > "$T/context/epics/a/memory.md"
  printf 'devlog 无头部\n- [2026-10-19] [变更]: x\n' > "$T/context/epics/a/devlog.md"
  printf '# a 待办\n- [x] (联调) [P1] 样例甲 done (src: agent, 序 #1)\n- [x] 样例乙 (src: agent)\n- [ ] (风险) 未完成项 (src: ai)\n' > "$T/context/epics/a/todos.md"
  printf '# b 待办\n- [x] 样例丙 (src: agent)\n' > "$T/context/epics/b/todos.md"
  printf -- '---\nmemo: done\nformat: v2\n---\n\n# 完成列表\n' > "$T/context/done.md"
  printf 'epic: b\n' > "$T/context/CURRENT"

  ok=1
  sh "$SELF" --root "$T" --fix all --apply >/dev/null 2>&1 || { echo 'fail: --apply 应 exit 0'; ok=0; }

  head -n 1 "$T/context/epics/a/memory.md" | grep -q '^--- *$' || { echo 'fail: a/memory.md 未建 YAML 头'; ok=0; }
  head -n 7 "$T/context/epics/a/memory.md" | grep -qF 'dev-loop: memory' || { echo 'fail: a/memory.md 缺角色行'; ok=0; }
  head -n 7 "$T/context/epics/a/memory.md" | grep -qE '^epic: a *$' || { echo 'fail: a/memory.md 缺 epic 归属'; ok=0; }
  grep -q '^- \[断点\]' "$T/context/epics/a/memory.md" || { echo 'fail: a/memory.md 未重建断点'; ok=0; }
  head -n 7 "$T/context/epics/a/devlog.md" | grep -qF 'dev-loop: devlog' || { echo 'fail: a/devlog.md 未建头部'; ok=0; }
  head -n 7 "$T/context/epics/a/todos.md" | grep -qF 'memo: todos' || { echo 'fail: a/todos.md 未建头部'; ok=0; }
  head -n 7 "$T/context/epics/a/todos.md" | grep -qE '^epic: a *$' || { echo 'fail: a/todos.md 缺 epic 归属'; ok=0; }

  grep -qE "^- \[[0-9-]+\] 样例甲 done \(src: agent, 序 #1\) \(域: a\)$" "$T/context/done.md" || { echo 'fail: done.md 样例甲格式不符（旧版标签未剥净）'; ok=0; }
  grep -qE "^- \[[0-9-]+\] 样例乙 \(src: agent\) \(域: a\)$" "$T/context/done.md" || { echo 'fail: done.md 样例乙格式不符'; ok=0; }
  grep -qE "^- \[[0-9-]+\] 样例丙 \(src: agent\) \(域: b\)$" "$T/context/done.md" || { echo 'fail: done.md 样例丙格式不符'; ok=0; }
  grep -q '样例甲' "$T/context/epics/a/todos.md" && { echo 'fail: a/todos.md 仍残留样例甲'; ok=0; }
  grep -q '样例丙' "$T/context/epics/b/todos.md" && { echo 'fail: b/todos.md 仍残留样例丙'; ok=0; }
  grep -q '未完成项' "$T/context/epics/a/todos.md" || { echo 'fail: a/todos.md 误删未完成项'; ok=0; }

  # 幂等：二次 apply 不得新增
  before=$(wc -l < "$T/context/done.md" | tr -d '[:space:]')
  sh "$SELF" --root "$T" --fix all --apply >/dev/null 2>&1
  after=$(wc -l < "$T/context/done.md" | tr -d '[:space:]')
  [ "$before" = "$after" ] || { echo "fail: 幂等失败 done.md $before -> $after"; ok=0; }

  # 去重：done.md 已有同文时跳过
  printf -- '- [2026-10-19] 样例乙 (src: agent) (域: a)\n' >> "$T/context/done.md"
  printf -- '- [x] 样例乙 (src: agent)\n' >> "$T/context/epics/a/todos.md"
  sh "$SELF" --root "$T" --fix all --apply >/dev/null 2>&1
  grep -q '样例乙' "$T/context/epics/a/todos.md" && { echo 'fail: 去重失败（done.md 已有同文，应仅删源不重复搬）'; ok=0; }

  if [ "$ok" -eq 1 ]; then echo 'pass: ctx-fix 金丝雀全绿（reclaim 剥离/域派生/done 格式/源删除/未完成项保护/幂等/去重）'; fi
  rm -rf "$T"
  [ "$ok" -eq 1 ] && exit 0
  exit 1
}

SELF=$0
case "$0" in *ctx-fix.sh) ;; *) SELF=$(command -v ctx-fix.sh 2>/dev/null || printf '%s' "$0") ;; esac

if [ "$SELFTEST" -eq 1 ]; then
  [ -n "$SELF" ] && [ -f "$SELF" ] || { echo 'FAIL: self-test 需以脚本路径调用'; exit 2; }
  selftest
fi

[ -n "$ROOT" ] || ROOT=$(pwd)
CTX=$ROOT/context
if [ ! -d "$CTX" ]; then
  if [ "$JSON" -eq 1 ]; then
    printf '{"status":"FAIL","severity":"error","message":"未找到 context/ 目录: %s","remedy":"传 --root 指定含 context/ 的项目根"}\n' "$CTX"
    exit 1
  fi
  printf 'FAIL: 未找到 context/ 目录: %s\n' "$CTX"; echo '[remedy] 传 --root <含 context/ 的项目根>'; exit 1
fi

# ---------- 主流程 ----------
if [ -z "$BAK" ] && [ "$APPLY" -eq 1 ]; then
  BAK="${TMPDIR:-/tmp}/ctx-fix-bak-$(date +%Y%m%d-%H%M%S)"
fi

wants reclaim && do_reclaim
wants hdr && do_hdr
wants checkpoint && do_checkpoint

REMAIN_R=$(grep -c '^- \[[xX]\]' "$CTX"/epics/*/todos.md "$CTX"/todos.md 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
REMAIN_H=0
for f in "$CTX"/epics/*/memory.md "$CTX"/epics/*/devlog.md; do
  [ -f "$f" ] || continue
  e=$(basename "$(dirname "$f")")
  if head -n 1 "$f" | grep -q '^--- *$' && head -n 7 "$f" | grep -qF 'dev-loop:' && head -n 7 "$f" | grep -qE "^epic: $e *$"; then :; else REMAIN_H=$((REMAIN_H + 1)); fi
done

if [ "$JSON" -eq 1 ]; then
  if [ "$APPLY" -eq 0 ]; then
    st=OK; sv=info
    msg="干跑：待修 reclaim=$DONE_N skip=$SKIP_N hdr=$REMAIN_H checkpoint_skip=$SKIP_CP"
    printf '{"status":"%s","severity":"%s","message":"%s"}\n' "$st" "$sv" "$msg"
  else
    st=OK; sv=info
    printf '{"status":"%s","severity":"%s","message":"已修复 reclaim=%d hdr等=%d 残留 reclaim=%d hdr=%d checkpoint_skip=%d"}\n' "$st" "$sv" "$DONE_N" "$FIX_N" "$REMAIN_R" "$REMAIN_H" "$SKIP_CP"
  fi
  exit 0
fi

if [ "$APPLY" -eq 0 ]; then
  echo "[dry-run] 计划（未落盘，加 --apply 执行；备份目录将为 ${TMPDIR:-/tmp}/ctx-fix-bak-<时间戳>/）："
else
  echo "[apply] 已落盘（备份: $BAK）："
fi
printf '%b' "$PLAN"
echo "汇总: reclaim 搬移 $DONE_N 条（跳过已在 done.md $SKIP_N 条）｜文件修复 $FIX_N 个｜残留 reclaim $REMAIN_R 条｜残留 hdr $REMAIN_H 处｜checkpoint 跳过 $SKIP_CP 个"

if [ "$APPLY" -eq 0 ] && [ "$DONE_N" -gt 0 -o "$REMAIN_H" -gt 0 -o "$SKIP_CP" -gt 0 ]; then exit 1; fi
if [ "$APPLY" -eq 1 ] && [ "$REMAIN_R" -gt 0 -o "$REMAIN_H" -gt 0 ]; then exit 1; fi
exit 0
