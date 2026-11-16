#!/bin/sh
# confirm —— dev-loop 决策点台账薄 CLI：登记即锚点校验，替代口头约定
#
# toolbox-script
# format: v1
# name: confirm
# summary: 决策点台账域内操作：add(登记即校验 todos 锚点)/list/resolve/list-all（dev-loop REFERENCE §2 台账）
# trigger: manual
# platform: unix
# self-test: --self-test

set -eu

usage() {
  cat <<'EOF'
用法: confirm [--root <path>] <epic> add "<todos序号> <问题>（默认建议: …）"
      confirm [--root <path>] <epic> list [--json]
      confirm [--root <path>] <epic> resolve <todos序号>
      confirm [--root <path>] list-all [--json]
      confirm --self-test | --help

域内唯一落点 context/epics/<epic>/pending-confirm.md（misc 同域内；全局文件已退役）。
add 登记前机械校验（任一不满足 exit 1 拒收，零写入）：
  ① epic 存在；② 锚点=条目首个 token，必须是域内 todos.md 真实存在的拆解序号；
  ③ 同锚点无未清条目。
resolve = 清零该锚点条目（台账清零须用户/裁决先行，工具只记账）。
退出码: 0=通过 1=检查未通过（锚点/重复/无条目/epic 缺失） 2=自身故障
--json: 一行 JSON 契约结论（message 内禁双引号）
EOF
}

JSON=0
ROOT_ARG=''

emit_ok() { # $1=message
  if [ "$JSON" = 1 ]; then
    printf '{"status":"OK","severity":"info","message":"%s"}\n' "$1"
  else
    echo "OK: $1"
  fi
  exit 0
}
emit_fail() { # $1=message
  if [ "$JSON" = 1 ]; then
    printf '{"status":"FAIL","severity":"warn","message":"%s"}\n' "$1"
  else
    echo "FAIL: $1" >&2
  fi
  exit 1
}

locate_ctx() { # $1=root_arg(可空) → 全局 CTX
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

op_add() { # $1=epic $2=text
  ed="$CTX/epics/$1"
  pf="$ed/pending-confirm.md"
  if [ ! -d "$ed" ]; then emit_fail "epic 不存在: context/epics/$1（先 ::bind）"; fi
  if [ -z "$2" ]; then emit_fail '缺条目文本: <epic> add "<锚点> <问题>（默认建议: …）"'; fi
  anchor=${2%% *}
  if ! printf '%s' "$anchor" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]*$'; then
    emit_fail "锚点须为 todos 拆解序号（首个 token），收到: $anchor"
  fi
  todos="$ed/todos.md"
  if [ ! -f "$todos" ]; then emit_fail "域内 todos.md 不存在（推进面未建）: $todos"; fi
  if ! grep -qF -- "$anchor" "$todos"; then
    emit_fail "锚点 $anchor 在 todos.md 不存在（先在拆解面登记该序号，或修正序号）"
  fi
  if [ -f "$pf" ] && grep -q -- "^- \[ \].*$anchor" "$pf"; then
    emit_fail "同锚点已有未清条目: $anchor（先 resolve 再登记）"
  fi
  printf -- '- [ ] [%s] %s\n' "$(date +%Y-%m-%d)" "$2" >> "$pf"
  emit_ok "已登记 $anchor → context/epics/$1/pending-confirm.md"
}

op_list() { # $1=epic
  pf="$CTX/epics/$1/pending-confirm.md"
  if [ ! -f "$pf" ] || [ ! -s "$pf" ]; then emit_ok "无未清条目: $1"; fi
  if [ "$JSON" = 1 ]; then
    n=$(grep -c '^- \[ \]' "$pf" || true)
    emit_ok "未清 $n 条: $1"
  fi
  cat "$pf"
  exit 0
}

op_resolve() { # $1=epic $2=anchor
  pf="$CTX/epics/$1/pending-confirm.md"
  if [ ! -f "$pf" ]; then emit_fail "台账文件缺失: $1"; fi
  if [ -z "$2" ]; then emit_fail '缺锚点: <epic> resolve <todos序号>'; fi
  n=$(grep -cF -- "$2" "$pf" || true)
  if [ "$n" -eq 0 ]; then emit_fail "无锚点 $2 的未清条目: $1"; fi
  tmp="$pf.tmp.$$"
  grep -vF -- "$2" "$pf" > "$tmp" || true
  mv "$tmp" "$pf"
  emit_ok "已清 $n 条（$2）: $1"
}

op_list_all() {
  total=0
  detail=''
  for d in "$CTX"/epics/*/; do
    [ -d "$d" ] || continue
    pf="${d}pending-confirm.md"
    [ -f "$pf" ] || continue
    c=$(grep -c '^- \[ \]' "$pf" || true)
    if [ "$c" -gt 0 ]; then
      total=$((total + c))
      detail="$detail $(basename "$d"):$c"
    fi
  done
  emit_ok "未清 total=${total}${detail}"
}

self_test() {
  td=$(mktemp -d)
  mkdir -p "$td/context/epics/demo"
  printf -- '## T3 大节点\n- [ ] T3.1 a ｜ 验收: t\n- [ ] T3.2 b ｜ 验收: t\n' > "$td/context/epics/demo/todos.md"
  pf="$td/context/epics/demo/pending-confirm.md"
  okc=0
  # 1 合法锚点登记通过
  if sh "$0" --root "$td" demo add 'T3.2 问题一（默认建议: x）' 2>/dev/null && grep -q 'T3.2 问题一' "$pf"; then
    okc=$((okc + 1))
  else
    echo 'self-test: 合法锚点应通过并落盘'
  fi
  # 2 幽灵锚点拒收（坏样本——证明能抓到）
  if sh "$0" --root "$td" demo add 'T9.9 幽灵' 2>/dev/null; then
    echo 'self-test: 幽灵锚点应拒收'
  else
    okc=$((okc + 1))
  fi
  # 3 拒收零写入
  if grep -q 'T9.9' "$pf" 2>/dev/null; then
    echo 'self-test: 拒收应零写入'
  else
    okc=$((okc + 1))
  fi
  # 4 同锚点重复拒收
  if sh "$0" --root "$td" demo add 'T3.2 问题一（默认建议: x）' 2>/dev/null; then
    echo 'self-test: 同锚点未清应拒收'
  else
    okc=$((okc + 1))
  fi
  # 5 resolve 清零
  if sh "$0" --root "$td" demo resolve T3.2 2>/dev/null && ! grep -q 'T3.2' "$pf"; then
    okc=$((okc + 1))
  else
    echo 'self-test: resolve 应清零该锚点'
  fi
  # 6 list-all --json 计数契约
  out=$(sh "$0" --root "$td" list-all --json 2>/dev/null)
  case "$out" in
    *'未清 total=0'*) okc=$((okc + 1)) ;;
    *) echo "self-test: list-all 计数错误: $out" ;;
  esac
  # 7 不存在 epic 拒收
  if sh "$0" --root "$td" ghost add 'T3.2 x' 2>/dev/null; then
    echo 'self-test: 不存在 epic 应拒收'
  else
    okc=$((okc + 1))
  fi
  if [ "$okc" -eq 7 ]; then
    echo 'self-test: OK'
    return 0
  fi
  echo "self-test: 通过 $okc/7"
  return 1
}

# ---- 参数解析 ----
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

if [ "${SELFTEST-0}" = 1 ]; then
  self_test
  exit $?
fi

if [ $# -eq 0 ]; then
  if [ "$JSON" = 1 ]; then emit_ok 'confirm 就绪（op 级 --json 输出契约结论）'; fi
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

verb=${1-}
if [ "$verb" = 'list-all' ]; then
  shift
  for a in "$@"; do
    if [ "$a" = '--json' ]; then JSON=1; fi
  done
  op_list_all
fi

if [ $# -ge 3 ]; then
  epic="$1"; op="$2"; text="$3"; shift 3
else
  epic="$1"; op="${2-}"; text=''
  shift $#
fi
for a in "$@"; do
  if [ "$a" = '--json' ]; then JSON=1; fi
done

case "$op" in
  add) op_add "$epic" "$text" ;;
  list) op_list "$epic" ;;
  resolve)
    if [ -n "$text" ]; then op_resolve "$epic" "$text"; else emit_fail '缺锚点: <epic> resolve <todos序号>'; fi
    ;;
  *) usage; exit 2 ;;
esac
