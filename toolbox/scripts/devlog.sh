#!/bin/sh
# dev-loop 记账单一入口（「记账单一事实源」规约的工具化）：devlog 追加（变更/验证/自定义标签）、
# lessons 追加、memory 断点刷新、未归并条目计数。--json 为预检结论不落盘，裸跑才写入。
#
# toolbox-script
# format: v1
# name: devlog
# summary: dev-loop 记账单一入口：devlog 追加(变更强制配对验证/验证/自定义)/lessons 追加/断点刷新/未归并计数；--json 预检不落盘
# trigger: manual
# cat: ops
# platform: unix
# self-test: --self-test

# 无 set -e：grep -c 零匹配返回 1 属预期流程
set -u

THRESHOLD=5
ROOT=""
JSON=0
EPIC=""
TEXT=""

usage() {
  cat <<'EOF'
devlog — dev-loop 记账单一入口（devlog 追加 / lessons 追加 / 断点刷新 / 未归并计数）

用法:
  devlog [--root <项目根>] [--json] <子命令> [参数...]

子命令:
  change  <epic> [--verify "<命令 → 结果>" | --no-verify "<原因>"] <文本...>
                                    追加 - [日期] [变更]: 文本 → context/epics/<epic>/devlog.md
                                    并强制同轮配对追加 - [日期] [验证]: ...（配对合同，缺一 FAIL）：
                                    --verify 记真实验证结果；--no-verify 记「未执行: 原因」留痕
  verify  <epic> <文本...>          追加  - [日期] [验证]: 文本          → 同上（补记/复验用；change 已强制配对）
  note    <epic> <标签> <文本...>   追加  - [日期] [<标签>]: 文本        → 同上（决策 / SSOT 修正 / 环境坑…）
  lesson  <epic> <模块> <文本...>   追加  - [<模块>] 文本 (Ref: <epic>)  → context/lessons.md
  bp      <epic> <文本...>          刷新 context/epics/<epic>/memory.md 断点行
                                    （单趟替换+重复去重；章节缺失则重建，替换后校验恒为 1 行）
  count   <epic>                    devlog 尾部 20 行内未归并条目计数（阈值 5，达到应归并）

全局选项:
  --root <dir>   项目根（默认当前目录；其下须有 context/）
  --json         仅输出一行 JSON 预检结论，不执行写入（预检语义；裸跑才落盘）
  --help / -h    本帮助
  --self-test    金丝雀自测：临时沙箱内全流程断言，不触碰真实 context/

退出码: 0=成功 1=校验未通过 2=自身故障
幂等: 与最近 5 行内完全相同的追加自动跳过（重复调用不产生重复行）；bp 天然幂等。
EOF
}

esc() { printf '%s' "$1" | tr '"' "'"; }
json_ok() { printf '{"status":"OK","severity":"info","message":"%s"}\n' "$(esc "$1")"; }
json_fail() { printf '{"status":"FAIL","severity":"error","message":"%s","remedy":"%s"}\n' "$(esc "$1")" "$(esc "${2-检查参数后重试}")"; }
die1() {
  if [ "$JSON" = 1 ]; then json_fail "$1" "${2-检查参数后重试}"; else
    echo "FAIL: $1"; [ -n "${2-}" ] && echo "[remedy] $2"; fi
  exit 1
}
die2() {
  if [ "$JSON" = 1 ]; then json_fail "自身故障: $1" "重跑一次；仍失败检查磁盘与权限"; else
    echo "ERROR: $1"; echo "[remedy] 重跑一次；仍失败检查磁盘与权限"; fi
  exit 2
}

# $1=文本 $2=字段名：非空、非全空白、单行
check_single_line() {
  if [ -z "$1" ] || [ -z "$(printf '%s' "$1" | tr -d ' \t')" ]; then
    die1 "$2 为空或全空白" "传入要记录的内容"
  fi
  if [ "$(printf '%s' "$1" | wc -l)" -gt 0 ]; then
    die1 "$2 含换行（日志条目须单行）" "把内容压成一行再记"
  fi
}

# "$@" → TEXT：非空、非全空白、单行
validate_text() {
  TEXT="$*"
  check_single_line "$TEXT" "文本"
}

# change 配对合同（验证账本，dev-loop §2.4）：--verify 与 --no-verify 二选一，缺一 FAIL
check_pairing() {
  if [ -n "$VERIFY_TXT" ] && [ -n "$NOVERIFY_TXT" ]; then
    die1 "--verify 与 --no-verify 互斥（二选一）" "真实验证用 --verify；未执行留痕用 --no-verify"
  fi
  if [ -z "$VERIFY_TXT" ] && [ -z "$NOVERIFY_TXT" ]; then
    die1 "change 缺验证配对：[变更] 必须同轮带 [验证]" \
      'devlog change <epic> --verify "<命令 → 结果>" <文本> ｜ 未验证时 --no-verify "<原因>"'
  fi
}

# change 配对追加：[变更] 行 + 同轮 [验证] 行（走 append_dedupe；TEXT/VERIFY_TXT/NOVERIFY_TXT/TODAY 已就绪）
append_change_pair() {
  _f="$1"
  if [ -n "$VERIFY_TXT" ]; then
    append_dedupe "$_f" "- [$TODAY] [变更]: $TEXT"
    append_dedupe "$_f" "- [$TODAY] [验证]: $VERIFY_TXT"
  else
    append_dedupe "$_f" "- [$TODAY] [变更]: $TEXT"
    append_dedupe "$_f" "- [$TODAY] [验证]: 未执行: $NOVERIFY_TXT"
  fi
}

# $1 → EPIC：非路径成分且目录存在
validate_epic() {
  EPIC="${1-}"
  case "$EPIC" in
    ""|.|..|*/*) die1 "epic 名非法: ${EPIC-空}" "传 context/epics 下已存在的 epic 名（如 goodshare / misc）" ;;
  esac
  [ -d "$ROOT/context/epics/$EPIC" ] || die1 "epic 目录不存在: context/epics/$EPIC" "先 @file/@bind 绑定 epic（会创建骨架），或检查拼写"
}

# $1=文件 $2=行：追加（最近 5 行内有完全相同条目则幂等跳过）
append_dedupe() {
  _f="$1"; _line="$2"
  if tail -n 5 "$_f" 2>/dev/null | grep -Fqx -- "$_line" >/dev/null 2>&1; then
    echo "SKIP（最近已有同条目，幂等跳过）"
    return 0
  fi
  printf '%s\n' "$_line" >> "$_f" || die2 "写入失败: $_f"
  echo "APPEND: $_line"
}

# 断点刷新：单趟 awk 替换（首个匹配替换、其余去重）；无既有断点行则重建章节；
# 结束后校验断点行恒为 1。EPIC/TEXT/ROOT 已就绪。
run_bp() {
  FILE="$ROOT/context/epics/$EPIC/memory.md"
  TMP="$FILE.bp.tmp"
  awk -v repl="- [断点] 下一步：$TEXT" '/^- \[断点\]/{if(!done){print repl;done=1};next}{print}' "$FILE" > "$TMP" \
    || die2 "awk 写临时文件失败"
  if grep -Fqx -- "- [断点] 下一步：$TEXT" "$TMP" >/dev/null 2>&1; then
    mv "$TMP" "$FILE" || die2 "替换断点行失败"
    echo "BP-REPLACED: - [断点] 下一步：$TEXT"
  else
    rm -f "$TMP"
    { printf '\n## 断点\n%s\n' "- [断点] 下一步：$TEXT"; } >> "$FILE" || die2 "重建断点章节失败"
    echo "BP-CREATED: - [断点] 下一步：$TEXT"
  fi
  _n=$(grep -c '^- \[断点\]' "$FILE")
  [ "$_n" -eq 1 ] || die2 "断点行数异常: $_n（应恰为 1）"
}

self_test() {
  T=$(mktemp -d 2>/dev/null) || { echo "self-test: mktemp 失败"; exit 2; }
  E="t-self"
  mkdir -p "$T/context/epics/$E" || exit 2
  D="$T/context/epics/$E/devlog.md"
  M="$T/context/epics/$E/memory.md"
  L="$T/context/lessons.md"
  printf -- '---\ndev-loop: devlog\nformat: v1\n---\n\n# log\n' > "$D" || exit 2
  printf -- '---\ndev-loop: memory\nformat: v1\n---\n\n# mem\n\n## 断点\n- [断点] 下一步：旧断点\n' > "$M" || exit 2
  printf -- '# lessons\n\n## flutter/ui\n\n正文行\n' > "$L" || exit 2

  pass=0; failed=0
  chk() {
    if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
      failed=$((failed + 1)); echo "SELF-TEST FAIL: $1 (期望[$3] 实得[$2])"; fi
  }
  ROOT="$T"; JSON=0
  TODAY=$(date +%F)

  # 1 change 追加
  validate_epic "$E"; validate_text "变更一"
  append_dedupe "$D" "- [$TODAY] [变更]: $TEXT" >/dev/null
  chk "change 追加" "$(grep -c '\[变更\]' "$D")" "1"
  # 2 重复追加幂等跳过
  append_dedupe "$D" "- [$TODAY] [变更]: $TEXT" >/dev/null
  chk "重复追加幂等跳过" "$(grep -c '\[变更\]' "$D")" "1"
  # 3 verify / 4 note
  validate_text "analyze 0"
  append_dedupe "$D" "- [$TODAY] [验证]: $TEXT" >/dev/null
  chk "verify 追加" "$(grep -c '\[验证\]' "$D")" "1"
  validate_epic "$E"; validate_text "推翻旧结论"
  append_dedupe "$D" "- [$TODAY] [SSOT 修正]: $TEXT" >/dev/null
  chk "note 自定义标签" "$(grep -c '\[SSOT 修正\]' "$D")" "1"
  # 5 lesson
  validate_epic "$E"; validate_text "现象 ➔ 根因 ➔ 规则"
  append_dedupe "$L" "- [flutter/ui] $TEXT (Ref: $EPIC)" >/dev/null
  chk "lesson 追加" "$(grep -c '(Ref: t-self)' "$L")" "1"
  # 6 bp 替换（旧断点消失、去重后恰 1 行）——走与主流程相同的 run_bp 函数
  validate_epic "$E"; validate_text "新断点甲"
  run_bp >/dev/null
  _m="$ROOT/context/epics/$E/memory.md"
  chk "bp 替换生效" "$(grep -c '旧断点' "$_m")" "0"
  chk "bp 替换后恒 1 行" "$(grep -c '^- \[断点\]' "$_m")" "1"
  # 7 bp 再刷新
  validate_text "新断点乙"
  run_bp >/dev/null
  chk "bp 二次刷新" "$(grep -c '新断点乙' "$_m")" "1"
  # 8 章节缺失重建
  printf -- '---\ndev-loop: memory\nformat: v1\n---\n\n无章节\n' > "$_m"
  validate_text "重建丙"
  run_bp >/dev/null
  chk "bp 章节缺失重建" "$(grep -c '^- \[断点\]' "$_m")" "1"
  # 9 count
  _n=$(tail -n 20 "$D" | grep -c '^- \[')
  chk "count 计数（变更+验证+SSOT=3）" "$_n" "3"
  # 10 多行文本被拒（子Shell 断言退出码，不中止自测）
  ( ROOT="$T"; JSON=0; validate_epic "$E"; validate_text "$(printf 'a\nb')" ) >/dev/null 2>&1
  chk "多行文本被拒" "$?" "1"
  # 11 change 配对合同：缺配对被拒
  VERIFY_TXT=""; NOVERIFY_TXT=""
  ( ROOT="$T"; JSON=0; validate_epic "$E"; validate_text "无配对变更"; check_pairing ) >/dev/null 2>&1
  chk "change 缺配对被拒" "$?" "1"
  # 12 --verify 配对：[变更]+[验证] 各 +1
  VERIFY_TXT="t.sh → 通过"; NOVERIFY_TXT=""
  validate_text "配对变更甲"
  append_change_pair "$D" >/dev/null
  chk "verify 配对 [变更] 计数" "$(grep -c '\[变更\]' "$D")" "2"
  chk "verify 配对 [验证] 计数" "$(grep -c '\[验证\]' "$D")" "2"
  # 13 --no-verify 配对：未执行留痕
  VERIFY_TXT=""; NOVERIFY_TXT="纯文档轮"
  validate_text "配对变更乙"
  append_change_pair "$D" >/dev/null
  chk "no-verify 未执行留痕" "$(grep -c '\[验证\]: 未执行:' "$D")" "1"
  chk "no-verify [变更] 计数" "$(grep -c '\[变更\]' "$D")" "3"
  # 14 互斥被拒
  VERIFY_TXT="a → 通过"; NOVERIFY_TXT="原因"
  ( ROOT="$T"; JSON=0; check_pairing ) >/dev/null 2>&1
  chk "verify/no-verify 互斥被拒" "$?" "1"
  # 15 JSON 预检缺配对 FAIL
  VERIFY_TXT=""; NOVERIFY_TXT=""
  ( ROOT="$T"; JSON=1; validate_epic "$E"; validate_text "预检变更"; check_pairing ) >/dev/null 2>&1
  chk "JSON 预检缺配对 FAIL" "$?" "1"

  rm -rf "$T"
  echo "self-test: $pass 通过 / $failed 失败"
  [ "$failed" -eq 0 ]
}

# ---- 参数解析 ----
SELFTEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || die1 "--root 缺参数" "传项目根路径"
      ROOT="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    --help|-h) usage; exit 0 ;;
    --self-test) SELFTEST=1; shift; break ;;
    --) shift; break ;;
    -*) die1 "未知选项: $1" "见 devlog --help" ;;
    *) break ;;
  esac
done

if [ "$SELFTEST" = 1 ]; then self_test; exit $?; fi

[ -n "$ROOT" ] || ROOT="$PWD"
[ -d "$ROOT/context" ] || die1 "项目根无 context/ 目录: $ROOT" "cd 到项目根，或传 --root <项目路径>"
ROOT=$(cd "$ROOT" && pwd) || die2 "解析项目根失败"

if [ $# -eq 0 ]; then
  [ "$JSON" = 1 ] && die1 "缺少子命令" "见 devlog --help"
  usage; exit 1
fi
OP="$1"; shift
case "$OP" in
  change|verify|note|lesson|bp|count) ;;
  *) die1 "未知子命令: $OP" "见 devlog --help" ;;
esac

TODAY=$(date +%F)

case "$OP" in
  change)
    [ $# -ge 2 ] || die1 "change 需要 <epic> 与 <文本...>" "devlog change <epic> [--verify <账本> | --no-verify <原因>] <文本...>"
    validate_epic "$1"; shift
    VERIFY_TXT=""; NOVERIFY_TXT=""
    _orig=$#; _seen=0
    while [ "$_seen" -lt "$_orig" ]; do
      case "$1" in
        --verify)    [ $# -ge 2 ] || die1 "--verify 缺参数" '传 "<命令 → 结果>"'; VERIFY_TXT="$2"; shift 2; _orig=$((_orig-2)); continue ;;
        --no-verify) [ $# -ge 2 ] || die1 "--no-verify 缺参数" "传未执行原因"; NOVERIFY_TXT="$2"; shift 2; _orig=$((_orig-2)); continue ;;
        *) set -- "$@" "$1"; shift; _seen=$((_seen+1)) ;;
      esac
    done
    validate_text "$@"
    check_pairing
    FILE="$ROOT/context/epics/$EPIC/devlog.md"
    [ -f "$FILE" ] || die1 "devlog.md 不存在: $FILE" "先 @file/@bind 绑定 epic（会创建骨架）"
    if [ -n "$VERIFY_TXT" ]; then
      check_single_line "$VERIFY_TXT" "--verify 文本"
    else
      check_single_line "$NOVERIFY_TXT" "--no-verify 原因"
    fi
    if [ "$JSON" = 1 ]; then
      if [ -n "$VERIFY_TXT" ]; then json_ok "预检通过: 将配对追加 [变更]+[验证] 到 ${FILE#"$ROOT"/}"
      else json_ok "预检通过: 将追加 [变更]+[验证]未执行留痕 到 ${FILE#"$ROOT"/}"; fi
      exit 0
    fi
    append_change_pair "$FILE"
    ;;
  verify)
    [ $# -ge 2 ] || die1 "verify 需要 <epic> 与 <文本...>" "devlog verify <epic> <文本...>"
    validate_epic "$1"; shift
    validate_text "$@"
    FILE="$ROOT/context/epics/$EPIC/devlog.md"
    [ -f "$FILE" ] || die1 "devlog.md 不存在: $FILE" "先 @file/@bind 绑定 epic（会创建骨架）"
    LINE="- [$TODAY] [验证]: $TEXT"
    if [ "$JSON" = 1 ]; then json_ok "预检通过: 将追加到 ${FILE#"$ROOT"/}"; exit 0; fi
    append_dedupe "$FILE" "$LINE"
    ;;
  note)
    [ $# -ge 3 ] || die1 "note 需要 <epic> <标签> <文本...>" "devlog note <epic> <标签> <文本...>"
    validate_epic "$1"; shift
    TAG="$1"; shift
    case "$TAG" in ""|*" "*) die1 "标签非法（非空且不含空格）" "如 决策 / 环境坑";; esac
    validate_text "$@"
    FILE="$ROOT/context/epics/$EPIC/devlog.md"
    [ -f "$FILE" ] || die1 "devlog.md 不存在: $FILE" "先 @file/@bind 绑定 epic（会创建骨架）"
    LINE="- [$TODAY] [$TAG]: $TEXT"
    if [ "$JSON" = 1 ]; then json_ok "预检通过: 将追加到 ${FILE#"$ROOT"/}"; exit 0; fi
    append_dedupe "$FILE" "$LINE"
    ;;
  lesson)
    [ $# -ge 3 ] || die1 "lesson 需要 <epic> <模块> <文本...>" "devlog lesson <epic> <模块> <现象> ➔ <根因> ➔ <规则>"
    validate_epic "$1"; shift
    MODULE="$1"; shift
    case "$MODULE" in ""|*" "*) die1 "模块名非法（非空且不含空格）" "如 flutter/ui";; esac
    validate_text "$@"
    FILE="$ROOT/context/lessons.md"
    [ -f "$FILE" ] || die1 "lessons.md 不存在: $FILE" "先经 dev-init 初始化 context/ 体系"
    LINE="- [$MODULE] $TEXT (Ref: $EPIC)"
    if [ "$JSON" = 1 ]; then json_ok "预检通过: 将追加到 ${FILE#"$ROOT"/}"; exit 0; fi
    append_dedupe "$FILE" "$LINE"
    ;;
  bp)
    [ $# -ge 2 ] || die1 "bp 需要 <epic> 与 <文本...>" "devlog bp <epic> <下一步内容>"
    validate_epic "$1"; shift
    validate_text "$@"
    FILE="$ROOT/context/epics/$EPIC/memory.md"
    [ -f "$FILE" ] || die1 "memory.md 不存在: $FILE" "先 @file/@bind 绑定 epic（会创建骨架）"
    NEW="- [断点] 下一步：$TEXT"
    if [ "$JSON" = 1 ]; then json_ok "预检通过: 将刷新 $EPIC 断点行"; exit 0; fi
    run_bp
    ;;
  count)
    [ $# -ge 1 ] || die1 "count 需要 <epic>" "devlog count <epic>"
    validate_epic "$1"; shift
    FILE="$ROOT/context/epics/$EPIC/devlog.md"
    [ -f "$FILE" ] || die1 "devlog.md 不存在: $FILE" "先 @file/@bind 绑定 epic（会创建骨架）"
    _n=$(tail -n 20 "$FILE" 2>/dev/null | grep -c '^- \[')
    if [ "$_n" -ge "$THRESHOLD" ]; then
      if [ "$JSON" = 1 ]; then printf '{"status":"OK","severity":"warn","message":"count=%s 达归并阈值 %s，应执行归并"}\n' "$_n" "$THRESHOLD"; else
        echo "count=$_n（阈值 $THRESHOLD）→ 触发 §4 归并（自动或 @merge）"; fi
    else
      if [ "$JSON" = 1 ]; then json_ok "count=$_n（阈值 $THRESHOLD）"; else
        echo "count=$_n（阈值 $THRESHOLD）"; fi
    fi
    ;;
esac
exit 0
