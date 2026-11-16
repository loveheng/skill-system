#!/bin/sh
# autocheck —— ::auto 启动门禁薄 CLI：推进面健康检查+缺省目标推导（纯读取推导，零业务胶水）
#
# toolbox-script
# format: v1
# name: autocheck
# summary: ::auto 启动门禁：拆解面健康/缺省目标推导/断点锚一致性/台账聚合（dev-loop REFERENCE §2）
# trigger: manual
# platform: unix
# self-test: --self-test

set -eu

usage() {
  cat <<'EOF'
用法: autocheck [--root <path>] <epic> [--json]
      autocheck --self-test | --help

::auto 启动门禁（纯读取推导，message 即启动报目标推导结果）：
  ① 拆解面健康——未清子步行（v3 格式内带 T<节点>.<步> 锚点）必须含「｜ 验收:」段（无验收不连走）
  ② 缺省目标推导——首个含未清子步的大节点=缺省目标，该节点全部子步锚点=机械判定清单
  ③ 断点锚一致性——断点行含 T<节点>.<步> 锚须在推进面真实存在（防漂移）
  ④ 台账聚合——epics/*/pending-confirm.md 未清计数
退出码: 0=通过 1=检查未通过（失锚/漂移/缺验收/epic 缺失——先修再 ::auto） 2=自身故障
EOF
}

JSON=0
ROOT_ARG=''

emit_ok() {
  if [ "$JSON" = 1 ]; then
    printf '{"status":"OK","severity":"info","message":"%s"}\n' "$1"
  else
    echo "OK: $1"
  fi
  exit 0
}

emit_fail() {
  if [ "$JSON" = 1 ]; then
    printf '{"status":"FAIL","severity":"warn","message":"%s"}\n' "$1"
  else
    echo "FAIL: $1" >&2
  fi
  exit 1
}

locate_ctx() {
  CTX=''
  if [ -n "$1" ]; then
    if [ -d "$1/context" ]; then CTX="$1/context"; fi
  else
    d="$PWD"
    while :; do
      if [ -d "$d/context" ]; then CTX="$d/context"; break; fi
      [ "$d" = '/' ] && break
      d=$(dirname "$d")
    done
  fi
  [ -n "$CTX" ] || return 1
  return 0
}

op_check() { # $1=epic
  ed="$CTX/epics/$1"
  if [ ! -d "$ed" ]; then emit_fail "epic 不存在: context/epics/$1（先 ::bind）"; fi
  todos="$ed/todos.md"
  if [ ! -f "$todos" ]; then emit_fail "域内 todos.md 缺失（推进面未建——先 ::next 拆解再 ::auto）"; fi

  # ① 未清子步行（v3 格式内带 T 锚点）——验收段门禁
  anchor_rows=$(grep -E '^- \[ \] \[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\] \([^)]+\) T[0-9]+\.[0-9]+ ' "$todos" 2>/dev/null || true)
  open_anchors=''
  if [ -n "$anchor_rows" ]; then
    open_anchors=$(printf '%s\n' "$anchor_rows" | sed -n 's/^- \[ \] \[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\] ([^)]*) \(T[0-9][0-9.]*\) .*/\1/p' | tr '\n' ' ')
    noacc=$(printf '%s\n' "$anchor_rows" | grep -cv '｜ 验收:' || true)
    if [ "$noacc" -gt 0 ]; then
      emit_fail "拆解面有 $noacc 条未清子步缺「｜ 验收:」段（无验收不连走——先补验收，dev-loop REFERENCE §2）"
    fi
  fi

  tcount=0
  for pf in "$CTX"/epics/*/pending-confirm.md; do
    [ -f "$pf" ] || continue
    c=$(grep -c '^- \[ \]' "$pf" 2>/dev/null || true)
    tcount=$((tcount + c))
  done

  # ② ④ 整流程完结（无未清子步）
  if [ -z "$open_anchors" ]; then
    emit_ok "整流程完结 拆解面全[x] 台账=$tcount"
  fi

  # 缺省目标推导：首个未清锚的节点=当前大节点，该节点全部子步（含 [x]）=判定清单
  first_a=$(printf '%s' "$open_anchors" | tr ' ' '\n' | grep -m1 . || true)
  node=${first_a%%.*}
  node_all=$(grep -E "\) ${node}\.[0-9]+ " "$todos" 2>/dev/null | sed -n 's/^- \[.\] \[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\] ([^)]*) \(T[0-9][0-9.]*\) .*/\1/p' | tr '\n' ' ')
  done_anchors=$(grep -E '^- \[[xX]\] \[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\] \([^)]+\) T[0-9]+\.[0-9]+ ' "$todos" 2>/dev/null | sed -n 's/^- \[[xX]\] \[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\] ([^)]*) \(T[0-9][0-9.]*\) .*/\1/p' | tr '\n' ' ')

  # ③ 断点锚一致性
  bp=$(grep '^- \[断点\]' "$ed/memory.md" 2>/dev/null | head -n 1 | sed 's/^- \[断点\][[:space:]]*//' || true)
  bp_anchor=$(printf '%s' "$bp" | grep -oE 'T[0-9]+\.[0-9]+' 2>/dev/null | head -n 1 || true)
  if [ -n "$bp_anchor" ]; then
    if ! grep -qE "\) ${bp_anchor} " "$todos" 2>/dev/null; then
      emit_fail "断点漂移: 断点锚 ${bp_anchor} 在推进面不存在（拆解重编号或笔误——重写断点对齐推进面，dev-loop REFERENCE §2）"
    fi
  fi

  bp_show=$bp_anchor
  [ -n "$bp_show" ] || bp_show=$(printf '%s' "$bp" | cut -c1-30)
  emit_ok "推进面健康 大节点=${node} 未清=${open_anchors% } 缺省目标=${node} 判定=${node_all% } 断点=${bp_show} 台账=$tcount"
}

self_test() {
  td=$(mktemp -d)
  mkdir -p "$td/context/epics/demo"
  printf 'epic: demo\n' > "$td/context/CURRENT" 2>/dev/null || true
  cat > "$td/context/epics/demo/todos.md" <<'EOF'
---
memo: todos
format: v3
epic: demo
---

# demo · 拆解面

## T1 骨架
- [x] [2026-11-16] (功能) T1.1 add 落盘 ｜ 验收: t1 (src: ai)
- [ ] [2026-11-16] (功能) T1.2 list 打印 ｜ 验收: t2 (src: ai)

## T2 done
- [ ] [2026-11-16] (功能) T2.1 done 标记 ｜ 验收: t3 (src: ai)
EOF
  printf -- '---\ndev-loop: memory\nformat: v1\nepic: demo\ntotal-merged: 0\nlast-merge: none\n---\n\n# demo\n\n- [挂载] docs/demo.md\n\n## 断点\n- [断点] 下一步：T1.2 list 打印\n' > "$td/context/epics/demo/memory.md"
  pf="$td/context/epics/demo/pending-confirm.md"
  okc=0
  # 1 好样本：健康+推导（大节点=T1 缺省判定=T1.1 T1.2 断点=T1.2）
  out=$(sh "$0" --root "$td" demo 2>&1) || true
  case "$out" in
    *'大节点=T1 未清=T1.2 T2.1 缺省目标=T1 判定=T1.1 T1.2 断点=T1.2 台账=0'*) okc=$((okc + 1)) ;;
    *) echo "self-test: 好样本推导不符: $out" ;;
  esac
  # 2 断点漂移（坏样本——证明能抓到）
  printf -- '---\ndev-loop: memory\nformat: v1\nepic: demo\ntotal-merged: 0\nlast-merge: none\n---\n\n# demo\n\n## 断点\n- [断点] 下一步：T9.9 幽灵锚\n' > "$td/context/epics/demo/memory.md"
  if sh "$0" --root "$td" demo 2>/dev/null; then
    echo 'self-test: 断点漂移应拒收'
  else
    okc=$((okc + 1))
  fi
  # 3 缺验收拒收
  printf -- '---\ndev-loop: memory\nformat: v1\nepic: demo\ntotal-merged: 0\nlast-merge: none\n---\n\n# demo\n\n## 断点\n- [断点] 下一步：T1.2\n' > "$td/context/epics/demo/memory.md"
  sed -i 's/ ｜ 验收: t2//' "$td/context/epics/demo/todos.md"
  if sh "$0" --root "$td" demo 2>/dev/null; then
    echo 'self-test: 缺验收应拒收'
  else
    okc=$((okc + 1))
  fi
  # 4 台账聚合在场（先恢复健康拆解面——case 3 的缺验收变异须撤销）
  cat > "$td/context/epics/demo/todos.md" <<'EOF'
---
memo: todos
format: v3
epic: demo
---

## T1 骨架
- [x] [2026-11-16] (功能) T1.1 add 落盘 ｜ 验收: t1 (src: ai)
- [ ] [2026-11-16] (功能) T1.2 list 打印 ｜ 验收: t2 (src: ai)

## T2 done
- [ ] [2026-11-16] (功能) T2.1 done 标记 ｜ 验收: t3 (src: ai)
EOF
  printf -- '- [ ] [2026-11-16] T1.2 裁决样例（默认建议: x）\n' > "$pf"
  out=$(sh "$0" --root "$td" demo 2>&1) || true
  case "$out" in
    *'台账=1'*) okc=$((okc + 1)) ;;
    *) echo "self-test: 台账聚合不符: $out" ;;
  esac
  # 5 整流程完结（全部 [x]）
  sed -i 's/^- \[ \]/- [x]/' "$td/context/epics/demo/todos.md"
  out=$(sh "$0" --root "$td" demo 2>&1) || true
  case "$out" in
    *'整流程完结 拆解面全[x] 台账=1'*) okc=$((okc + 1)) ;;
    *) echo "self-test: 整流程完结推导不符: $out" ;;
  esac
  # 6 不存在 epic 拒收
  if sh "$0" --root "$td" ghost 2>/dev/null; then
    echo 'self-test: 不存在 epic 应拒收'
  else
    okc=$((okc + 1))
  fi
  # 7 --json 契约
  out=$(sh "$0" --json --root "$td" ghost 2>&1) || true
  case "$out" in
    *'"status":"FAIL"'*) okc=$((okc + 1)) ;;
    *) echo "self-test: --json 契约不符: $out" ;;
  esac
  if [ "$okc" -eq 7 ]; then
    echo 'self-test: OK'
    return 0
  fi
  echo "self-test: 通过 $okc/7"
  return 1
}

# ---- 参数解析 ----
SELFTEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1; shift ;;
    --self-test) SELFTEST=1; shift ;;
    --help|-h) usage; exit 0 ;;
    --root)
      if [ $# -ge 2 ]; then ROOT_ARG="$2"; shift 2; else usage; exit 2; fi
      ;;
    *) break ;;
  esac
done

if [ "$SELFTEST" = 1 ]; then
  self_test
  exit $?
fi

if [ $# -eq 0 ]; then
  if [ "$JSON" = 1 ]; then emit_ok 'autocheck 就绪（--json 输出契约结论）'; fi
  usage
  exit 2
fi

if ! locate_ctx "$ROOT_ARG"; then
  if [ "$JSON" = 1 ]; then
    printf '{"status":"FAIL","severity":"error","message":"未找到 context/（用 --root 指定仓库根）"}\n'
  else
    echo 'FAIL: 未找到 context/（用 --root 指定仓库根）' >&2
  fi
  exit 2
fi

epic=${1-}
shift || true
for a in "$@"; do
  if [ "$a" = '--json' ]; then JSON=1; fi
done

op_check "$epic"
