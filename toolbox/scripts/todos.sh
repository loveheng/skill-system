#!/bin/sh
# toolbox-script
# format: v1
# name: todos
# summary: 备忘台账机械件：域级 todos（epics/<名>/todos.md 按需创建）+ 全局兜底（misc/跨域）的 add/done/rm/move/list，::todo 五指令的执行器，AI 零手搓零漂移
# trigger: manual
# cat: ops
# platform: unix
# self-test: --self-test
#
# 格式 SSOT：memo-collector §0（两级落点/条目行格式/路由规则）、§2（完成流转）。
# 本脚本只搬运规范不定义规范；条目域归属判定（域内/全局）仍是 AI 按路由规则做的语义活。
set -u
SELF=$0
ROOT=''; OP=''; DEST=''; KW=''; JSON=0
TYPE='功能'; BLOCK=0; STATUS=''; LAYER=''; WEIGHT=''; LIFE=''; SRC='ai'

usage() {
  cat <<'EOF'
todos —— 备忘台账机械件（两级落点：域文件 epics/<名>/todos.md 按需创建 + 全局 misc/跨域兜底）

用法: todos.sh [--root <目录>] <子命令> [参数] [--json|--self-test|--help]

子命令:
  add --to <epic名|misc> [--type 功能|修复|优化|文档|环境|测试|风险] [--block]
      [--status 降级|暂缓|候] [--layer L0-L4] [--weight 轻|中|重] [--once|--long]
      [--src <ai|用户[, 说明]>] <事项文本>
      # 追加条目（域内 → epics/<名>/todos.md 文件不存在先建骨架；misc → 全局 ## misc 节）
      # 条目行格式与完整路由规则见 memo-collector §0；节内最新在上；同文条目已存在时提醒不拒绝
  done <关键词>      # 完成流转：从来源文件移入全局 done.md（行尾记 (域: 来源)，memo-collector §2）
  rm <关键词>        # 删除条目（破坏性——AI 须先经用户确认再执行）
  move <关键词> --to <epic名|misc>   # 跨域移动（整行原样迁移，节内最新在上）
  list [epic名|misc|all]             # 聚合视图：全局 + 全部域文件，带临时编号 #N（::todos 数据源）

关键词匹配: 仅匹配待办行（- [ ] 开头）的固定子串；唯一命中才执行，零命中/多命中 exit 1 并列明细。

退出码: 0 成功 / 1 未找到或歧义或校验未过 / 2 自身故障
EOF
}

json_out() {
  m=$(printf '%s' "$3" | tr -d '"')
  r=''
  if [ "$#" -ge 4 ]; then r=$(printf '%s' "$4" | tr -d '"'); fi
  printf '{"status":"%s","severity":"%s","message":"%s"%s}\n' "$1" "$2" "$m" "${r:+,\"remedy\":\"$r\"}"
}

die() { # die <exit码> <remedy> <message>
  if [ "$JSON" -eq 1 ]; then
    json_out FAIL error "$3" "$2"
  else
    echo "FAIL: $3"
    echo "[remedy] $2"
  fi
  exit "$1"
}

exec_self_test() {
  T=$(mktemp -d) || return 2
  cd "$T" || { rm -rf "$T"; return 2; }
  git init -q . 2>/dev/null
  mkdir -p context/epics/misc context/epics/demo docs
  printf 'epic: misc\n' > context/CURRENT
  printf -- '---\nmemo: todos\nformat: v3\n---\n\n# 待办列表\n\n## misc\n' > context/todos.md
  ok=1
  # T1 add 域文件按需创建
  sh "$SELF" --root "$T" add --to demo --type 功能 --layer L3 --weight 中 --src "ai, t" "测试条目甲" >/dev/null 2>&1 \
    || { echo 'fail: T1 add 域内应成功'; ok=0; }
  [ -f context/epics/demo/todos.md ] || { echo 'fail: T1 域文件未创建'; ok=0; }
  grep -qE '^- \[ \] \[[0-9-]+\] \(功能\) \(层:L3\) \(重:中\) 测试条目甲 \(src: ai, t\)$' context/epics/demo/todos.md \
    || { echo 'fail: T1 条目行格式不符'; ok=0; }
  grep -q '^epic: demo$' context/epics/demo/todos.md || { echo 'fail: T1 域文件头部缺 epic'; ok=0; }
  # T2 add misc 落全局 misc 节
  sh "$SELF" --root "$T" add --to misc --type 风险 --block "跨域风险乙" >/dev/null 2>&1 || { echo 'fail: T2 add misc 应成功'; ok=0; }
  awk '/^## misc$/{f=1} f && /跨域风险乙/{found=1} END{exit !found}' context/todos.md || { echo 'fail: T2 条目不在 misc 节内'; ok=0; }
  # T3 done 流转 done.md 记来源域（此时测试条目甲唯一）
  sh "$SELF" --root "$T" done "测试条目甲" >/dev/null 2>&1 || { echo 'fail: T3 done 应成功'; ok=0; }
  grep -q '测试条目甲' context/epics/demo/todos.md && { echo 'fail: T3 源文件未删除'; ok=0; }
  grep -qE '^- \[[0-9-]+\] .*测试条目甲.* \(域: demo\)$' context/done.md || { echo 'fail: T3 done.md 行格式不符'; ok=0; }
  # T4 同文提醒不拒绝（对全新文本连续两次 add）
  sh "$SELF" --root "$T" add --to misc --type 文档 "重复探测样例" >/dev/null 2>&1
  out=$(sh "$SELF" --root "$T" add --to misc --type 文档 "重复探测样例" 2>&1) || { echo "fail: T4 重复应放行: $out"; ok=0; }
  printf '%s' "$out" | grep -q '已存在' || { echo 'fail: T4 缺重复提醒'; ok=0; }
  # T5 move 原样迁移
  sh "$SELF" --root "$T" move "跨域风险乙" --to demo >/dev/null 2>&1 || { echo 'fail: T5 move 应成功'; ok=0; }
  grep -q '跨域风险乙' context/epics/demo/todos.md || { echo 'fail: T5 目标文件缺条目'; ok=0; }
  grep -q '跨域风险乙' context/todos.md && { echo 'fail: T5 源未删除'; ok=0; }
  # T6 歧义拦截
  sh "$SELF" --root "$T" add --to demo --type 测试 "回归样例一" >/dev/null 2>&1
  sh "$SELF" --root "$T" add --to misc --type 测试 "回归样例二" >/dev/null 2>&1
  sh "$SELF" --root "$T" rm "回归样例" >/dev/null 2>&1 && { echo 'fail: T6 多命中应拒'; ok=0; }
  # T7 rm 删除
  sh "$SELF" --root "$T" rm "回归样例二" >/dev/null 2>&1 || { echo 'fail: T7 rm 应成功'; ok=0; }
  grep -q '回归样例二' context/todos.md && { echo 'fail: T7 未删除'; ok=0; }
  # T8 零命中 exit 1
  sh "$SELF" --root "$T" done "不存在的条目" >/dev/null 2>&1 && { echo 'fail: T8 零命中应 exit 1'; ok=0; }
  # T9 list 聚合带编号
  out=$(sh "$SELF" --root "$T" list all 2>&1)
  printf '%s' "$out" | grep -qE '#[0-9]+ .*跨域风险乙' || { echo "fail: T9 list 缺编号条目: $out"; ok=0; }
  printf '%s' "$out" | grep -q '全局' || { echo 'fail: T9 list 缺全局分组'; ok=0; }
  # T10 --json 单行
  out=$(sh "$SELF" --root "$T" add --to misc --type 文档 "json样例" --json 2>/dev/null)
  printf '%s' "$out" | grep -q '"status":"OK"' || { echo "fail: T10 json 应 OK: $out"; ok=0; }
  [ "$(printf '%s\n' "$out" | wc -l)" -le 1 ] || { echo 'fail: T10 json 应单行'; ok=0; }
  # T11 域不存在拒
  sh "$SELF" --root "$T" add --to ghost "x" >/dev/null 2>&1 && { echo 'fail: T11 ghost 域应拒'; ok=0; }
  # T12 非法类型拒
  sh "$SELF" --root "$T" add --to misc --type 八卦 "x" >/dev/null 2>&1 && { echo 'fail: T12 非法类型应拒'; ok=0; }
  rm -rf "$T"
  if [ "$ok" -eq 1 ]; then echo 'self-test: OK（add/done/rm/move/list 全链路 + 歧义/零命中/非法值/重复提醒）'; return 0; fi
  return 2
}

# ---- 参数解析 ----
POS=''
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo '[remedy] --root 缺参数'; exit 2; }; ROOT=$2; shift 2 ;;
    --to) [ $# -ge 2 ] || { echo '[remedy] --to 缺参数'; exit 2; }; DEST=$2; shift 2 ;;
    --type) [ $# -ge 2 ] || { echo '[remedy] --type 缺参数'; exit 2; }; TYPE=$2; shift 2 ;;
    --status) [ $# -ge 2 ] || { echo '[remedy] --status 缺参数'; exit 2; }; STATUS=$2; shift 2 ;;
    --layer) [ $# -ge 2 ] || { echo '[remedy] --layer 缺参数'; exit 2; }; LAYER=$2; shift 2 ;;
    --weight) [ $# -ge 2 ] || { echo '[remedy] --weight 缺参数'; exit 2; }; WEIGHT=$2; shift 2 ;;
    --src) [ $# -ge 2 ] || { echo '[remedy] --src 缺参数'; exit 2; }; SRC=$2; shift 2 ;;
    --block) BLOCK=1; shift ;;
    --once) LIFE='[once]'; shift ;;
    --long) LIFE='[long]'; shift ;;
    --json) JSON=1; shift ;;
    --self-test) exec_self_test; exit $? ;;
    --help|-h) usage; exit 0 ;;
    -*) echo "[remedy] 未知参数: $1（--help 看用法）"; exit 2 ;;
    *) if [ -z "$OP" ]; then OP=$1; elif [ -z "$KW" ] && [ "$OP" != 'add' ]; then KW=$1; else POS="$POS $1"; fi; shift ;;
  esac
done
if [ -n "$OP" ]; then :; else
  if [ "$JSON" -eq 1 ]; then
    json_out OK info 'todos 工具就绪（add/done/rm/move/list）——加子命令执行'
    exit 0
  fi
  usage
  exit 2
fi
[ -n "$KW" ] || KW=$(printf '%s' "$POS" | sed 's/^ //')

[ -n "$ROOT" ] || ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -d "$ROOT" ] || die 2 '进入目标仓库后重跑，或显式 --root <目录>' '未定位到项目根'
CTX="$ROOT/context"
TODAY=$(date +%F)

# ---- 值校验 ----
case "$TYPE" in 功能|修复|优化|文档|环境|测试|风险) : ;; *) die 1 '类型限七种：功能/修复/优化/文档/环境/测试/风险（memo-collector §0）' "非法类型: $TYPE" ;; esac
[ -z "$STATUS" ] || case "$STATUS" in 降级|暂缓|候) : ;; *) die 1 '状态限：降级/暂缓/候（memo-collector §0）' "非法状态: $STATUS" ;; esac
[ -z "$LAYER" ] || case "$LAYER" in L0|L1|L2|L3|L4) : ;; *) die 1 '层限 L0-L4' "非法层: $LAYER" ;; esac
[ -z "$WEIGHT" ] || case "$WEIGHT" in 轻|中|重) : ;; *) die 1 '权重限：轻/中/重' "非法权重: $WEIGHT" ;; esac
case "$SRC" in ai|用户|ai,*|用户,*) : ;; *) die 1 'src 须以 ai 或 用户 起头（可带 ", 说明" 后缀）' "非法 src: $SRC" ;; esac

# 落点解析：misc → 全局；其余 → 域文件（epic 目录必须已存在）
GLOBAL_T="$CTX/todos.md"
is_misc=0; DOMAIN_FILE=''
if [ "$DEST" = 'misc' ]; then
  is_misc=1
elif [ "$OP" = 'add' ] || [ "$OP" = 'move' ]; then
  case "$DEST" in
    ''|*[!A-Za-z0-9_-]*) die 1 '落点须为 epic 名（字母/数字/-/_）或 misc' "非法落点: $DEST" ;;
  esac
  [ -d "$CTX/epics/$DEST" ] || die 1 "先建 epic（::bind / toolbox run mount-init）或将条目落 --to misc" "epic 不存在: $DEST"
  DOMAIN_FILE="$CTX/epics/$DEST/todos.md"
fi

ensure_global() {
  [ -f "$GLOBAL_T" ] && return 0
  mkdir -p "$CTX"
  cat > "$GLOBAL_T" <<'EOF'
---
memo: todos
format: v3
---

# 待办列表

## misc
EOF
  return 0
}

ensure_domain() {
  [ -f "$DOMAIN_FILE" ] && return 0
  cat > "$DOMAIN_FILE" <<EOF
---
memo: todos
format: v3
epic: $DEST
---

# $DEST · 域内待办
EOF
  return 0
}

# 原样插入（ENVIRON 传值防任意文本被转义）：插入到锚定行之后
insert_after() { # insert_after <目标文件> <锚定行ERE>
  ITEM_LINE=$ITEM_LINE awk -v t="$1" -v a="$2" '
    { print }
    !done && $0 ~ a { print ENVIRON["ITEM_LINE"]; done=1 }
    END { if (!done) exit 3 }
  ' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# ---- add ----
if [ "$OP" = 'add' ]; then
  [ -n "$DEST" ] || die 1 '补 --to <epic名|misc>（路由规则见 memo-collector §0）' 'add 缺 --to 落点'
  text=$(printf '%s' "$POS" | sed 's/^ //')
  [ -n "$text" ] || die 1 '补事项文本（一句话可执行/可核对，memo-collector §4 防漂移）' 'add 缺事项文本'
  item="- [ ] [$TODAY] ($TYPE)"
  [ -n "$LIFE" ] && item="$item $LIFE"
  [ "$BLOCK" -eq 1 ] && item="$item (block)"
  [ -n "$STATUS" ] && item="$item ($STATUS)"
  [ -n "$LAYER" ] && item="$item (层:$LAYER)"
  [ -n "$WEIGHT" ] && item="$item (重:$WEIGHT)"
  item="$item $text (src: $SRC)"
  if [ "$is_misc" -eq 1 ]; then
    ensure_global
    ITEM_LINE=$item insert_after "$GLOBAL_T" '^## misc([[:space:]].*)?$' || die 2 '全局 todos.md 缺 ## misc 兜底节——先补节或重建模板' '插入失败'
    dest_show='全局 todos.md(misc)'
    dup=$(grep -cF -- "$text" "$GLOBAL_T" 2>/dev/null || true)
  else
    ensure_domain
    ITEM_LINE=$item insert_after "$DOMAIN_FILE" "^# $DEST · 域内待办\$" || die 2 "域文件缺标题行（应含 '# $DEST · 域内待办'）——检查文件是否被手改" '插入失败'
    dest_show="epics/$DEST/todos.md"
    dup=$(grep -cF -- "$text" "$DOMAIN_FILE" 2>/dev/null || true)
  fi
  msg="已落 $dest_show：${text}"
  [ "${dup:-1}" -gt 1 ] && msg="$msg（提醒：同文条目已存在，判重语义归 AI——memo-collector §1）"
  if [ "$JSON" -eq 1 ]; then json_out OK info "$msg"; else echo "OK: $msg"; fi
  exit 0
fi

# ---- 关键词定位（done/rm/move 共用）：设 FLOC/FNUM 全局变量；唯一命中才动 ----
find_line() {
  kw=$1
  hits=$(mktemp)
  [ -f "$GLOBAL_T" ] && grep -nF -- "$kw" "$GLOBAL_T" 2>/dev/null | grep -E '^[0-9]+:- \[ \]' | sed "s|^|$GLOBAL_T\t|" >> "$hits"
  for df in "$CTX"/epics/*/todos.md; do
    [ -f "$df" ] || continue
    grep -nF -- "$kw" "$df" 2>/dev/null | grep -E '^[0-9]+:- \[ \]' | sed "s|^|$df\t|" >> "$hits"
  done
  n=$(wc -l < "$hits" | tr -d '[:space:]')
  if [ "$n" -eq 0 ]; then rm -f "$hits"; die 1 '核对关键词或先 list all 查看现有条目' "未命中任何待办行: $kw"; fi
  if [ "$n" -gt 1 ]; then
    if [ "$JSON" -eq 1 ]; then
      json_out FAIL error "关键词多命中 $n 处，补更精确关键词" '先 list all 看全量，或用更长的唯一子串'
    else
      echo "FAIL: 关键词多命中 $n 处，补更精确关键词："
      sed 's|\t|:|' "$hits" | while IFS= read -r l; do echo "  $l"; done
      echo "[remedy] 先 list all 看全量，或用更长的唯一子串"
    fi
    rm -f "$hits"; exit 1
  fi
  first=$(head -n 1 "$hits")
  FLOC=$(printf '%s' "$first" | cut -f1)
  FNUM=$(printf '%s' "$first" | cut -f2 | cut -d: -f1)
  rm -f "$hits"
  return 0
}

strip_tags() { # 剥待办行首部标签（复选框/日期/类型/生命周期/block/状态/层/重），保留事项文本与 (src)
  printf '%s' "$1" | sed -E \
    -e 's/^- \[ \] //' \
    -e 's/^\[[0-9]{4}-[0-9]{2}-[0-9]{2}\] *//' \
    -e 's/^\((功能|修复|优化|文档|环境|测试|风险)\) *//' \
    -e 's/^\[once\] *//' -e 's/^\[long\] *//' \
    -e 's/^\(block\) *//' -e 's/^\((降级|暂缓|候)\) *//' \
    -e 's/^\(层:L[0-4]\) *//' -e 's/^\(重:(轻|中|重)\) *//'
}

# ---- done ----
if [ "$OP" = 'done' ]; then
  [ -n "$KW" ] || die 1 '补完成条目的关键词（唯一子串）' 'done 缺关键词'
  find_line "$KW"
  line=$(sed -n "${FNUM}p" "$FLOC")
  domain=$(basename "$(dirname "$FLOC")")
  [ "$FLOC" = "$GLOBAL_T" ] && domain='misc'
  text=$(strip_tags "$line")
  [ -f "$CTX/done.md" ] || printf -- '---\nmemo: done\nformat: v2\n---\n\n# 完成列表\n' > "$CTX/done.md"
  printf -- '- [%s] %s (域: %s)\n' "$TODAY" "$text" "$domain" >> "$CTX/done.md"
  sed -i "${FNUM}d" "$FLOC"
  if [ "$JSON" -eq 1 ]; then json_out OK info "已完成 → done.md（域: $domain）：$text"; else echo "OK: 已完成 → done.md（域: $domain）"; fi
  exit 0
fi

# ---- rm ----
if [ "$OP" = 'rm' ]; then
  [ -n "$KW" ] || die 1 '补待删条目的关键词（唯一子串；破坏性操作须先经用户确认——memo-collector §3）' 'rm 缺关键词'
  find_line "$KW"
  sed -i "${FNUM}d" "$FLOC"
  if [ "$JSON" -eq 1 ]; then json_out OK info "已删除（$FLOC:$FNUM）"; else echo "OK: 已删除（$FLOC:$FNUM）"; fi
  exit 0
fi

# ---- move ----
if [ "$OP" = 'move' ]; then
  { [ -n "$KW" ] && [ -n "$DEST" ]; } || die 1 '补关键词与 --to <epic名|misc>（落点须已存在）' 'move 缺关键词或 --to'
  find_line "$KW"
  if [ "$is_misc" -eq 1 ] && [ "$FLOC" = "$GLOBAL_T" ]; then die 1 '条目已在全局 misc 内，无需移动' '原地移动'; fi
  line=$(sed -n "${FNUM}p" "$FLOC")
  if [ "$is_misc" -eq 1 ]; then
    ensure_global
    ITEM_LINE=$line insert_after "$GLOBAL_T" '^## misc([[:space:]].*)?$' || die 2 '全局 todos.md 缺 ## misc 兜底节' '插入失败'
    to_show='全局(misc)'
  else
    ensure_domain
    ITEM_LINE=$line insert_after "$DOMAIN_FILE" "^# $DEST · 域内待办\$" || die 2 "域文件缺标题行" '插入失败'
    to_show="$DEST"
  fi
  sed -i "${FNUM}d" "$FLOC"
  if [ "$JSON" -eq 1 ]; then json_out OK info "已移动 → $to_show（原样保留元数据）"; else echo "OK: 已移动 → $to_show"; fi
  exit 0
fi

# ---- list ----
if [ "$OP" = 'list' ]; then
  scope=$KW
  [ -n "$scope" ] || scope='all'
  ensure_global
  n=0; g=0; d=0
  out=''
  if [ "$scope" = 'all' ] || [ "$scope" = 'misc' ]; then
    c=$(grep -c '^- \[ \]' "$GLOBAL_T" 2>/dev/null || true)
    out="${out}== 全局（misc/跨域兜底）｜ ${c:-0} 条 ==\n"
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      n=$((n + 1)); g=$((g + 1))
      out="${out}#$n ${l#- [ ] }\n"
    done <<EOF
$(grep '^- \[ \]' "$GLOBAL_T" 2>/dev/null)
EOF
  fi
  if [ "$scope" = 'all' ] || { [ "$scope" != 'misc' ] && [ "$scope" != 'global' ]; }; then
    for df in "$CTX"/epics/*/todos.md; do
      [ -f "$df" ] || continue
      e=$(basename "$(dirname "$df")")
      [ "$scope" = 'all' ] || [ "$scope" = "$e" ] || continue
      c=$(grep -c '^- \[ \]' "$df" 2>/dev/null || true)
      out="${out}== 域内 $e ｜ ${c:-0} 条 ==\n"
      while IFS= read -r l; do
        [ -n "$l" ] || continue
        n=$((n + 1)); d=$((d + 1))
        out="${out}#$n ${l#- [ ] }\n"
      done <<EOF
$(grep '^- \[ \]' "$df" 2>/dev/null)
EOF
    done
  fi
  total=$((g + d))
  out="${out}-- 合计 ${total} 条（全局 ${g}/域内 ${d}）--"
  if [ "$JSON" -eq 1 ]; then
    json_out OK info "待办合计 ${total} 条（全局 ${g}/域内 ${d}）——明细跑裸 list"
  else
    printf '%b\n' "$out"
  fi
  exit 0
fi

die 1 '子命令限 add/done/rm/move/list（--help 看用法）' "未知子命令: $OP"
