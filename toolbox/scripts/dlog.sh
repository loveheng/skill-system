#!/bin/sh
# dlog — dev-loop 决策过程归档（SKILL §4/§8 机械件）：把绑定 epic devlog 中的决策类条目
# （[决策]/[SSOT 修正]，可扩展标签）原文复制进挂载底子文档的「## 决策日志」专节。
# 幂等：文档中已存在的行自动跳过；无挂载文档按规约跳过（exit 0 附 skip 消息）。
#
# toolbox-script
# format: v1
# name: dlog
# summary: devlog 决策条目 → 挂载文档「## 决策日志」专节的机械化归档（过滤+原文复制+去重幂等）
# trigger: manual
# cat: ops
# platform: unix
# self-test: --self-test

set -u

ROOT=""
JSON=0
EPIC=""
EXTRA_TAGS=""

usage() {
  cat <<'EOF'
dlog — devlog 决策条目机械化归档（归并/收尾清空 devlog 前的强制前置步）

用法:
  dlog [--root <项目根>] [--json] [--tag <名,名>] <epic>
  dlog [--root <项目根>] [--json] [--tag <名,名>] collect

子命令:
  collect  只读聚合全项目决策条目三段——[未归档]（各 epic devlog 内的决策行，
           = 归并欠账信号）/ [已归档-文档]（各挂载文档决策日志节）/ [已归档-杂项]
           （misc-decisions.md）——不落任何文件，供 AI/人复盘

行为:
  1. 读 context/epics/<epic>/devlog.md，筛出决策类条目行：
     - [YYYY-MM-DD] [决策]: …
     - [YYYY-MM-DD] [SSOT 修正]: …
     （--tag 可追加自定义标签，逗号分隔）
  2. 从 context/epics/<epic>/memory.md 的「- [挂载] <路径>」行解析底子文档；
     有挂载 → 追加进该文档「## 决策日志」专节（缺失则在文档尾部创建）；
     无挂载（散修/misc/未挂载 epic）→ 降级归档到 context/misc-decisions.md 的
     epic 节（misc 即常驻 ## misc 节；节缺失自动创建，新节保持在 ## misc 之前）。
  3. 条目**原文**追加进目标专节末尾（升序）；文档中已存在的相同行跳过
     （幂等，重复调用零重复）。
  4. 输出归档条数（copied/dup）。

全局选项:
  --root <dir>   项目根（默认当前目录；其下须有 context/）
  --json         仅输出一行 JSON 预检结论，不执行写入；裸跑才落盘
  --tag <列表>   追加参与筛选的自定义标签（默认仅 决策,SSOT 修正）
  --help / -h    本帮助
  --self-test    金丝雀自测：临时沙箱内全流程断言，不触碰真实 context/

退出码: 0=成功或按规约跳过 1=校验未通过 2=自身故障
EOF
}

esc() { printf '%s' "$1" | tr '"' "'"; }
json_out() { # $1=status $2=severity $3=message
  printf '{"status":"%s","severity":"%s","message":"%s"}\n' "$1" "$2" "$(esc "$3")"
}
die1() { if [ "$JSON" = 1 ]; then json_out FAIL error "$1"; else
  echo "FAIL: $1"; [ -n "${2-}" ] && echo "[remedy] $2"; fi; exit 1; }
die2() { if [ "$JSON" = 1 ]; then json_out FAIL error "自身故障: $1"; else
  echo "ERROR: $1"; echo "[remedy] 重跑一次；仍失败检查磁盘与权限"; fi; exit 2; }

# ---------- 参数解析 ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || die1 "--root 缺参数" "传入项目根目录"; ROOT="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    --tag)  [ $# -ge 2 ] || die1 "--tag 缺参数" "传入逗号分隔标签列表"; EXTRA_TAGS="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    --self-test) shift; EPIC="__selftest__"; break ;;
    -*) die1 "未知选项: $1" "用 --help 查看用法" ;;
    *)  [ -z "$EPIC" ] || die1 "多余参数: $1" "epic 只传一个"; EPIC="$1"; shift ;;
  esac
done
[ -n "$EPIC" ] || { usage; [ "$JSON" = 1 ] && json_out FAIL error "缺少 epic 参数"; exit 1; }

# ---------- 金丝雀自测（沙箱，不触碰真实 context/） ----------
if [ "$EPIC" = "__selftest__" ]; then
  SB="$(mktemp -d)" || die2 "mktemp 失败"
  trap 'rm -rf "$SB"' EXIT INT TERM
  mkdir -p "$SB/context/epics/e1" "$SB/docs"
  cat > "$SB/context/epics/e1/devlog.md" <<'EOF'
- [2026-01-01] [变更]: 加了功能A
- [2026-01-01] [验证]: 单测通过
- [2026-01-02] [决策]: 采纳方案甲（否决: 方案乙，成本高）
- [2026-01-03] [SSOT 修正]: 旧 使用HTTP轮询 ➔ 新 使用WebSocket
- [2026-01-04] [note]: 环境坑一条
EOF
  printf -- '- [挂载] docs/design.md\n' > "$SB/context/epics/e1/memory.md"
  printf '# 设计文档\n\n正文。\n' > "$SB/docs/design.md"
  OUT="$(sh "$0" --root "$SB" e1 2>&1)" || die2 "自测首次运行失败: $OUT"
  # 断言1：专节创建 + 仅决策行入档
  grep -q '^## 决策日志' "$SB/docs/design.md" || die2 "自测失败: 专节未创建"
  grep -q '采纳方案甲' "$SB/docs/design.md" || die2 "自测失败: [决策] 行未归档"
  grep -q '使用WebSocket' "$SB/docs/design.md" || die2 "自测失败: [SSOT 修正] 行未归档"
  grep -q '加了功能A' "$SB/docs/design.md" && die2 "自测失败: [变更] 行混入决策日志"
  grep -q '环境坑' "$SB/docs/design.md" && die2 "自测失败: [note] 行混入决策日志"
  # 断言2：重复调用幂等（无新增行）
  C1="$(grep -c '^- \[2026-' "$SB/docs/design.md")"
  OUT2="$(sh "$0" --root "$SB" e1 2>&1)" || die2 "自测二次运行失败: $OUT2"
  C2="$(grep -c '^- \[2026-' "$SB/docs/design.md")"
  [ "$C1" = "$C2" ] || die2 "自测失败: 重复调用产生重复行 ($C1 → $C2)"
  # 断言3：已有专节时追加到专节末尾且正文不动
  printf -- '- [2026-01-05] [决策]: 定稿接口命名\n' >> "$SB/context/epics/e1/devlog.md"
  sh "$0" --root "$SB" e1 >/dev/null 2>&1 || die2 "自测三次运行失败"
  grep -q '定稿接口命名' "$SB/docs/design.md" || die2 "自测失败: 增量条目未归档"
  grep -q '^正文。' "$SB/docs/design.md" || die2 "自测失败: 文档正文被破坏"
  # 断言4：无挂载行 → 降级归档到 context/misc-decisions.md 的 epic 节（节缺失自动创建）
  printf -- '## 断点\n- [断点] 等待\n' > "$SB/context/epics/e1/memory.md"
  sh "$0" --root "$SB" e1 >/dev/null 2>&1 || die2 "自测失败: 无挂载降级路径运行失败"
  grep -q '^## e1' "$SB/context/misc-decisions.md" || die2 "自测失败: misc-decisions.md 未建 epic 节"
  grep -q '采纳方案甲' "$SB/context/misc-decisions.md" || die2 "自测失败: 决策行未落 misc-decisions.md"
  # 断言5：dec 模式幂等 + epic 节保持在 ## misc 之前（misc 恒最后）+ 新节插在 ## misc 之前
  printf -- '\n## misc\n- [2026-01-01] [决策]: 旧杂项\n' >> "$SB/context/misc-decisions.md"
  C3="$(grep -c '^- \[2026-' "$SB/context/misc-decisions.md")"
  sh "$0" --root "$SB" e1 >/dev/null 2>&1 || die2 "自测失败: dec 模式二次运行失败"
  C4="$(grep -c '^- \[2026-' "$SB/context/misc-decisions.md")"
  [ "$C3" = "$C4" ] || die2 "自测失败: dec 模式幂等破坏 ($C3 → $C4)"
  mkdir -p "$SB/context/epics/e2"
  printf -- '- [2026-02-01] [决策]: e2 的决策一条\n' > "$SB/context/epics/e2/devlog.md"
  printf -- '## 断点\n' > "$SB/context/epics/e2/memory.md"
  sh "$0" --root "$SB" e2 >/dev/null 2>&1 || die2 "自测失败: e2 降级路径失败"
  grep -q 'e2 的决策一条' "$SB/context/misc-decisions.md" || die2 "自测失败: e2 条目未落 misc-decisions.md"
  MLINE="$(grep -n '^## misc' "$SB/context/misc-decisions.md" | tail -1 | cut -d: -f1)"
  E2LINE="$(grep -n '^## e2' "$SB/context/misc-decisions.md" | tail -1 | cut -d: -f1)"
  [ -n "$MLINE" ] && [ -n "$E2LINE" ] && [ "$E2LINE" -lt "$MLINE" ] || die2 "自测失败: e2 节未插在 ## misc 之前"
  # 断言6：collect 只读聚合（三段齐全）且不修改任何文件；--tag 扩展标签生效
  mkdir -p "$SB/context/epics/e3"
  printf -- '- [2026-03-01] [决策]: e3 未归档决策\n- [2026-03-02] [权衡]: 自定义标签一条\n' > "$SB/context/epics/e3/devlog.md"
  printf -- '## 断点\n' > "$SB/context/epics/e3/memory.md"
  SUM1="$(cd "$SB" && find context -type f -exec md5sum {} + | sort)"
  OUTC="$(sh "$0" --root "$SB" collect)" || die2 "自测失败: collect 运行失败"
  SUM2="$(cd "$SB" && find context -type f -exec md5sum {} + | sort)"
  [ "$SUM1" = "$SUM2" ] || die2 "自测失败: collect 修改了文件"
  printf '%s\n' "$OUTC" | grep -q 'e3 未归档决策' || die2 "自测失败: collect 缺未归档段"
  printf '%s\n' "$OUTC" | grep -q '采纳方案甲' || die2 "自测失败: collect 缺文档归档段"
  printf '%s\n' "$OUTC" | grep -q 'e2 的决策一条' || die2 "自测失败: collect 缺杂项段"
  printf '%s\n' "$OUTC" | grep -q '自定义标签一条' && die2 "自测失败: collect 未配 --tag 却收了扩展标签行"
  OUTT="$(sh "$0" --root "$SB" --tag 权衡 collect)" || die2 "自测失败: --tag collect 运行失败"
  printf '%s\n' "$OUTT" | grep -q '自定义标签一条' || die2 "自测失败: --tag 扩展标签未生效"
  if [ "$JSON" = 1 ]; then json_out OK info "self-test: 6/6 断言通过"; else
    echo "self-test: OK（专节创建/标签过滤/幂等/增量追加/无挂载降级misc-decisions/节序/dec幂等/collect只读聚合+--tag）"; fi
  exit 0
fi

# ---------- 标签模式（collect 与正式路径共用） ----------
TAGS="决策|SSOT 修正"
[ -n "$EXTRA_TAGS" ] && TAGS="$TAGS|$(printf '%s' "$EXTRA_TAGS" | tr ',' '|')"
ENT_RE="^- \[[0-9]{4}-[0-9]{2}-[0-9]{2}\] \[($TAGS)\]: "

# ---------- collect 子命令（只读聚合，供 AI/人复盘；不落任何文件） ----------
if [ "$EPIC" = "collect" ]; then
  [ -n "$ROOT" ] || ROOT="$PWD"
  [ -d "$ROOT/context" ] || die1 "$ROOT 下无 context/" "确认项目根或用 --root 指定"
  UNA=0; DOCC=0; MISC=0
  [ "$JSON" = 1 ] || echo "== dlog collect（只读）: $ROOT =="
  for d in "$ROOT/context/epics"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    if [ -f "$d/devlog.md" ]; then
      ENT="$(grep -E "$ENT_RE" "$d/devlog.md" || true)"
      if [ -n "$ENT" ]; then
        [ "$JSON" = 1 ] || { echo "[未归档] $name"; printf '%s\n' "$ENT"; }
        UNA=$((UNA + $(printf '%s\n' "$ENT" | grep -c .)))
      fi
    fi
    if [ -f "$d/memory.md" ]; then
      M="$(grep -m1 '^- \[挂载\]' "$d/memory.md" | sed 's/^- \[挂载\][[:space:]]*//' | awk '{print $1}')"
      if [ -n "$M" ] && [ -f "$ROOT/$M" ]; then
        SECC="$(awk '/^## 决策日志[[:space:]]*$/{f=1;next} f&&/^## /{exit} f' "$ROOT/$M" || true)"
        if [ -n "$SECC" ]; then
          [ "$JSON" = 1 ] || { echo "[已归档-文档] $name → $M"; printf '%s\n' "$SECC"; }
          DOCC=$((DOCC + $(printf '%s\n' "$SECC" | grep -c .)))
        fi
      fi
    fi
  done
  MD="$ROOT/context/misc-decisions.md"
  if [ -f "$MD" ]; then
    MEN="$(grep -E '^- \[[0-9]{4}-' "$MD" || true)"
    if [ -n "$MEN" ]; then
      [ "$JSON" = 1 ] || { echo "[已归档-杂项] context/misc-decisions.md"; printf '%s\n' "$MEN"; }
      MISC=$((MISC + $(printf '%s\n' "$MEN" | grep -c .)))
    fi
  fi
  if [ "$JSON" = 1 ]; then
    json_out OK info "collect unarchived=$UNA archived_doc=$DOCC archived_misc=$MISC"
  else
    echo "-- 未归档 $UNA 条 ｜ 已归档-文档 $DOCC 条 ｜ 已归档-杂项 $MISC 条 --"
  fi
  exit 0
fi

# ---------- 正式路径 ----------
[ -n "$ROOT" ] || ROOT="$PWD"
[ -d "$ROOT/context" ] || die1 "$ROOT 下无 context/" "确认项目根或用 --root 指定"
EDIR="$ROOT/context/epics/$EPIC"
[ -d "$EDIR" ] || die1 "epic 目录不存在: context/epics/$EPIC" "ls context/epics/ 确认名称"
DEVLOG="$EDIR/devlog.md"
MEMORY="$EDIR/memory.md"
[ -f "$DEVLOG" ] || die1 "devlog 不存在: $DEVLOG" "epic 尚无日志，无事可归档"

# 1) 目标解析：优先挂载文档；无挂载（散修/misc/未挂载 epic）→ 降级 context/misc-decisions.md 的 epic 节
MOUNT=""
[ -f "$MEMORY" ] && MOUNT="$(grep -m1 '^- \[挂载\]' "$MEMORY" | sed 's/^- \[挂载\][[:space:]]*//' | awk '{print $1}')"
MODE="doc"
if [ -n "$MOUNT" ]; then
  DOC="$ROOT/$MOUNT"
  [ -f "$DOC" ] || die1 "挂载文档不存在: $MOUNT" "核对 memory.md [挂载] 行或先建文档"
else
  MODE="dec"
  DOC="$ROOT/context/misc-decisions.md"
  [ -f "$DOC" ] || { : > "$DOC"; } || die2 "无法创建 $DOC"
fi
SEC="## 决策日志"
[ "$MODE" = "dec" ] && SEC="## $EPIC"

# 2) 筛决策条目（原文，逐行）——TAGS 已在 collect 分支前统一构建
TMP_ENT="$(mktemp)" || die2 "mktemp 失败"
TMP_NEW="$(mktemp)" || die2 "mktemp 失败"
trap 'rm -f "$TMP_ENT" "$TMP_NEW" "$TMP_NEW.new" 2>/dev/null' EXIT INT TERM
grep -E "^- \[[0-9]{4}-[0-9]{2}-[0-9]{2}\] \[($TAGS)\]: " "$DEVLOG" > "$TMP_ENT" || true

# 3) 去重（文档已有同文行 → 跳过）
COPIED=0; DUP=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  if grep -qF -- "$line" "$DOC"; then DUP=$((DUP+1)); else
    printf '%s\n' "$line" >> "$TMP_NEW"; COPIED=$((COPIED+1)); fi
done < "$TMP_ENT"

# 4) 追加进目标专节末尾（升序）；缺失则创建——doc 模式在文档尾部建「## 决策日志」，
#    dec 模式在 misc-decisions.md 建 epic 节（已存在 ## misc 时新节插在 ## misc 之前，保持 misc 恒最后）
if [ "$COPIED" -gt 0 ]; then
  if [ "$MODE" = "doc" ]; then
    awk -v sec="$SEC" -v insfile="$TMP_NEW" '
      BEGIN { insec = 0; done = 0 }
      $0 == sec { print; insec = 1; next }
      insec && /^## / {
        while ((getline l < insfile) > 0) print l
        close(insfile); insec = 0; done = 1; print; next
      }
      { print }
      END {
        if (insec) { while ((getline l < insfile) > 0) print l; close(insfile) }
        else if (!done) { print ""; print sec; while ((getline l < insfile) > 0) print l; close(insfile) }
      }
    ' "$DOC" > "$DOC.new" || die2 "awk 处理挂载文档失败"
  else
    awk -v sec="$SEC" -v insfile="$TMP_NEW" '
      BEGIN { insec = 0; done = 0 }
      $0 == sec { print; insec = 1; next }
      insec && /^## / {
        while ((getline l < insfile) > 0) print l
        close(insfile); insec = 0; done = 1; print; next
      }
      /^## / && !insec && !done && index($0, "## misc") == 1 {
        print sec; print ""
        while ((getline l < insfile) > 0) print l
        close(insfile); done = 1; print; next
      }
      { print }
      END {
        if (insec) { while ((getline l < insfile) > 0) print l; close(insfile) }
        else if (!done) { print ""; print sec; while ((getline l < insfile) > 0) print l; close(insfile) }
      }
    ' "$DOC" > "$DOC.new" || die2 "awk 处理 misc-decisions.md 失败"
  fi
  mv "$DOC.new" "$DOC" || die2 "写回失败: $DOC"
fi

TARGET="$MOUNT ## 决策日志"
[ "$MODE" = "dec" ] && TARGET="context/misc-decisions.md $SEC"
if [ "$JSON" = 1 ]; then
  json_out OK info "copied=$COPIED dup=$DUP target=$TARGET"
else
  echo "OK: 归档 $COPIED 条（已有跳过 $DUP 条）→ $TARGET"
fi
exit 0
