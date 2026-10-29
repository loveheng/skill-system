#!/bin/sh
# toolbox-script
# format: v1
# name: mount-init
# summary: epic 挂载初始化单一入口：::bind 的机械件（校验 slug/墓碑/重复挂载/切换前置 → 模板渲染 memory/devlog 骨架（templates/epic/ 资产层）与挂载行/断点行 → 改写 CURRENT；--temp 建临时骨架内置 kind: temp/绑定即自动补标），AI 零猜测零拼装
# trigger: manual
# cat: ops
# alias: mi
# platform: unix
# self-test: --self-test
#
# 骨架格式 SSOT：dev-loop §0（文件头部声明/目录契约）、§3（文档锚定/绑定切换纪律）、
# docs-spec §1（底子文档 frontmatter）。本脚本只搬运规范、不定义规范；
# 文档首稿内容仍须 AI 提炼自讨论落盘（严禁占位文案）。
set -u
SELF=$0
ROOT=''; EPIC=''; DOC=''; TITLE=''; CREATE_DOC=0; CURRENT_ONLY=0; TEMP=0; RESTORE=0; MARK_TEMP=0; DRY=0; JSON=0

usage() {
  cat <<'EOF'
mount-init —— epic 挂载初始化（::bind 机械件；幂等安全：已有骨架即拒绝，绝不覆盖）

用法: mount-init [--root <目录>] --epic <名> --doc <docs/...md> [--create-doc] [--title <文档标题>]
                 [--current-only] [--dry-run] [--json] [--self-test] [--help]

做什么:
  校验（任一不过即 exit 1，附 remedy）:
    epic 名合法（字母/数字/-/_）且 ≠ misc（misc 常驻不挂载）
    slug 规则：文档 basename（去 .md）= epic 名（dev-loop §3 文档锚定写死）
    底子文档落点必须在 docs/ 下且存在（--create-doc 时改为必须不存在，防覆盖）
    墓碑拦截：doc frontmatter status: deprecated → 拒挂（docs-spec §1）
    重复挂载拦截：该文档已被其他 epic 挂载 → 拒（一文档一主线）
    切换前置拦截：CURRENT 指向其他 epic 且其 devlog 有未归并条目 → 拒（先 ::merge）
  创建（--create-doc 时含底子文档骨架）:
    docs/<...>/<slug>.md            frontmatter(status: draft, updated: 今天) + # 标题——首稿内容仍须 AI 本轮提炼落盘
    context/epics/<名>/memory.md    YAML 头部 + # <名> + - [挂载] <文档> + ## 断点 初始行「下一步：等待拆解」
    context/epics/<名>/devlog.md    YAML 头部
    context/CURRENT                 改写为 epic: <名>（个人指针，gitignore）

模式:
  --current-only   只改写 CURRENT 到已存在的 epic（切换/续绑，不建骨架）
  --temp           临时绑定（并行临时任务防日志错位）：原绑定记入 CURRENT 第二行 base:，
                   CURRENT 指向临时 epic；恢复走 --restore。禁止嵌套（已有 base 行先 --restore）
  --restore        恢复基础绑定：按 CURRENT 的 base 行改写回 epic 并清除临时态
  --mark-temp      临时 epic 标记：memory 头部写 kind: temp + H1 标「（临时）」（新建临时 epic
                   建骨架后与存量回填共用；幂等；misc/骨架缺失拒）——收尾走 devlog archive，不 reopen
  --create-doc     底子文档不存在时连骨架一起创建（候选空 → 先建文档再挂载的机械件）
  --dry-run        只打印将做什么，不落盘
  --json           预检结论（不落盘）：各校验项通过与否——AI 亮牌确认前先跑这个

退出码: 0 成功（含 --json 预检通过）/ 1 校验未通过 / 2 自身故障
EOF
}

json_out() {
  printf '{"status":"%s","severity":"%s","message":"%s"%s}\n' "$1" "$2" "$3" "${4:+,\"remedy\":\"$4\"}"
}

fail() { # fail <remedy> <message...>：校验未通过，exit 1
  if [ "$JSON" -eq 1 ]; then
    json_out FAIL error "$2" "$1"
  else
    echo "FAIL: $2"
    echo "[remedy] $1"
  fi
  exit 1
}

exec_self_test() {
  # SELF 绝对化：本自测会 cd 进沙箱 $T，相对 $0（如 `sh mount-init.sh`）在沙箱内失路径
  case "$SELF" in
    /*) : ;;
    *)
      _d=$(cd "$(dirname "$SELF")" && pwd) || return 2
      SELF="$_d/$(basename "$SELF")"
      ;;
  esac
  T=$(mktemp -d) || return 2
  cd "$T" || { rm -rf "$T"; return 2; }
  git init -q . 2>/dev/null
  mkdir -p context/epics/misc context/epics/bar docs/design
  printf 'epic: misc\n' > context/CURRENT
  printf -- '---\ndev-loop: devlog\nformat: v1\nepic: misc\ntotal-merged: 0\nlast-merge: none\n---\n' > context/epics/misc/devlog.md
  printf -- '- [挂载] docs/design/foo.md\n' > context/epics/bar/memory.md
  printf -- '---\nstatus: active\nupdated: 2026-10-01\n---\n\n# demo\n' > docs/design/demo.md
  printf -- '---\nstatus: active\nupdated: 2026-10-01\n---\n\n# foo\n' > docs/design/foo.md
  printf -- '---\nstatus: deprecated\nupdated: 2026-10-01\n---\n\n# 旧\n' > docs/design/old.md
  ok=1
  # T1 挂已有文档全链路
  sh "$SELF" --root "$T" --epic demo --doc docs/design/demo.md >/dev/null 2>&1 \
    || { echo 'fail: T1 挂已有文档应成功'; ok=0; }
  grep -q '^epic: demo$' context/CURRENT || { echo 'fail: T1 CURRENT 未改写'; ok=0; }
  grep -qF -- '- [挂载] docs/design/demo.md' context/epics/demo/memory.md || { echo 'fail: T1 挂载行缺失'; ok=0; }
  grep -qxF -- '- [断点] 下一步：等待拆解' context/epics/demo/memory.md || { echo 'fail: T1 断点初始行缺失'; ok=0; }
  head -n 7 context/epics/demo/memory.md | grep -q '^epic: demo$' || { echo 'fail: T1 memory 头部 epic 不符'; ok=0; }
  head -n 7 context/epics/demo/devlog.md | grep -q '^dev-loop: devlog$' || { echo 'fail: T1 devlog 头部不符'; ok=0; }
  # T2 slug 不一致拒
  sh "$SELF" --root "$T" --epic other --doc docs/design/demo.md >/dev/null 2>&1 && { echo 'fail: T2 slug 不一致应拒'; ok=0; }
  # T3 墓碑拒
  sh "$SELF" --root "$T" --epic old --doc docs/design/old.md >/dev/null 2>&1 && { echo 'fail: T3 墓碑应拒'; ok=0; }
  # T4 重复挂载拒（bar 已挂 foo.md）
  sh "$SELF" --root "$T" --epic foo --doc docs/design/foo.md >/dev/null 2>&1 && { echo 'fail: T4 重复挂载应拒'; ok=0; }
  # T5 misc 建正式挂载拒
  sh "$SELF" --root "$T" --epic misc --doc docs/design/misc.md --create-doc >/dev/null 2>&1 && { echo 'fail: T5 misc 应拒'; ok=0; }
  # T6 已有 epic 骨架拒（防覆盖）
  sh "$SELF" --root "$T" --epic demo --doc docs/design/demo.md >/dev/null 2>&1 && { echo 'fail: T6 已有骨架应拒'; ok=0; }
  # T7 切换前置拦截：旧 epic（demo）devlog 有未归并条目时禁止切走；清账后可切回 misc
  printf -- '- [2026-10-02] [变更]: b\n' >> context/epics/demo/devlog.md
  sh "$SELF" --root "$T" --epic misc --current-only >/dev/null 2>&1 && { echo 'fail: T7 旧 epic 未归并应拦'; ok=0; }
  : > context/epics/demo/devlog.md
  sh "$SELF" --root "$T" --epic misc --current-only >/dev/null 2>&1 \
    || { echo 'fail: T7 清账后 --current-only 应成功'; ok=0; }
  grep -q '^epic: misc$' context/CURRENT || { echo 'fail: T7 CURRENT 未切回'; ok=0; }
  # T8 dry-run 不落盘
  sh "$SELF" --root "$T" --epic ghost --doc docs/design/ghost.md --create-doc --dry-run >/dev/null 2>&1 \
    || { echo 'fail: T8 dry-run 应 exit 0'; ok=0; }
  [ ! -f docs/design/ghost.md ] && [ ! -d context/epics/ghost ] || { echo 'fail: T8 dry-run 落了盘'; ok=0; }
  # T9 --json 预检单行
  out=$(sh "$SELF" --root "$T" --epic ghost --doc docs/design/ghost.md --create-doc --json 2>/dev/null)
  printf '%s' "$out" | grep -q '"status":"OK"' || { echo "fail: T9 json 预检应 OK: $out"; ok=0; }
  [ "$(printf '%s\n' "$out" | wc -l)" -le 1 ] || { echo 'fail: T9 json 应单行'; ok=0; }
  # T10 建文档+挂载实执行
  sh "$SELF" --root "$T" --epic ghost --doc docs/design/ghost.md --create-doc --title '幽灵文档' >/dev/null 2>&1 \
    || { echo 'fail: T10 建文档 bind 应成功'; ok=0; }
  grep -q '^status: draft$' docs/design/ghost.md || { echo 'fail: T10 文档骨架 frontmatter 缺失'; ok=0; }
  grep -q '^# 幽灵文档$' docs/design/ghost.md || { echo 'fail: T10 文档标题缺失'; ok=0; }
  grep -qF -- '- [挂载] docs/design/ghost.md' context/epics/ghost/memory.md || { echo 'fail: T10 挂载行缺失'; ok=0; }
  grep -q '^epic: ghost$' context/CURRENT || { echo 'fail: T10 CURRENT 未改写'; ok=0; }
  # T11 已存在空 epic 目录同样拒（原子 mkdir 闸门——并发先到者等价于已存在，且拒时不落骨架）
  mkdir -p context/epics/race
  sh "$SELF" --root "$T" --epic race --doc docs/design/race.md --create-doc >/dev/null 2>&1 && { echo 'fail: T11 已存在空目录应拒'; ok=0; }
  [ ! -f context/epics/race/memory.md ] || { echo 'fail: T11 被拒不得落骨架'; ok=0; }
  # T12 维护态拦截与续绑：memory 头部 state: maintenance 的 epic 完整挂载拒，--current-only 放行且不清标记
  mkdir -p context/epics/retired
  printf -- '---\ndev-loop: memory\nformat: v1\nepic: retired\ntotal-merged: 0\nlast-merge: none\nstate: maintenance\n---\n\n# retired\n\n- [挂载] docs/design/retired.md\n\n## 断点\n- [断点] 已完结：首轮交付\n' > context/epics/retired/memory.md
  printf -- '---\nstatus: active\nupdated: 2026-10-01\n---\n\n# retired\n' > docs/design/retired.md
  sh "$SELF" --root "$T" --epic retired --doc docs/design/retired.md >/dev/null 2>&1 && { echo 'fail: T12 维护态完整挂载应拒'; ok=0; }
  grep -q '^epic: ghost$' context/CURRENT || { echo 'fail: T12 被拒不得改 CURRENT'; ok=0; }
  sh "$SELF" --root "$T" --epic retired --current-only >/dev/null 2>&1 \
    || { echo 'fail: T12b 维护态续绑应成功'; ok=0; }
  grep -q '^epic: retired$' context/CURRENT || { echo 'fail: T12b CURRENT 未改写'; ok=0; }
  grep -q '^state: maintenance$' context/epics/retired/memory.md || { echo 'fail: T12b 续绑不得清维护标记'; ok=0; }
  # T13 临时绑定往返：base 行记原绑定，restore 恢复并清临时态（misc devlog 先清账，防切换前置误伤）
  : > context/epics/misc/devlog.md
  sh "$SELF" --root "$T" --epic demo --current-only >/dev/null 2>&1
  sh "$SELF" --root "$T" --epic misc --temp >/dev/null 2>&1 || { echo 'fail: T13 --temp 应成功'; ok=0; }
  grep -q '^epic: misc$' context/CURRENT || { echo 'fail: T13 CURRENT 未指向临时 epic'; ok=0; }
  grep -q '^base: demo$' context/CURRENT || { echo 'fail: T13 base 行缺失'; ok=0; }
  sh "$SELF" --root "$T" --epic retired --temp >/dev/null 2>&1 && { echo 'fail: T13 嵌套临时绑定应拒'; ok=0; }
  sh "$SELF" --root "$T" --restore >/dev/null 2>&1 || { echo 'fail: T13 --restore 应成功'; ok=0; }
  grep -q '^epic: demo$' context/CURRENT || { echo 'fail: T13 未恢复基础绑定'; ok=0; }
  grep -q '^base: ' context/CURRENT && { echo 'fail: T13 base 行残留'; ok=0; }
  sh "$SELF" --root "$T" --restore >/dev/null 2>&1 && { echo 'fail: T13 无临时绑定再 restore 应拒'; ok=0; }
  # T13b 临时 epic 有未归并日志时恢复被拦（切换前置）
  sh "$SELF" --root "$T" --epic misc --temp >/dev/null 2>&1
  printf -- '- [2026-10-02] [变更]: t\n' >> context/epics/misc/devlog.md
  sh "$SELF" --root "$T" --restore >/dev/null 2>&1 && { echo 'fail: T13b 临时 epic 未归并应拦'; ok=0; }
  : > context/epics/misc/devlog.md
  sh "$SELF" --root "$T" --restore >/dev/null 2>&1 || { echo 'fail: T13b 清账后 restore 应成功'; ok=0; }
  grep -q '^epic: demo$' context/CURRENT || { echo 'fail: T13b 未恢复基础绑定'; ok=0; }
  # T14 --mark-temp：kind: temp + H1 标注 + 幂等 + misc/不存在拒
  mkdir -p context/epics/tmpq
  printf -- '---\ndev-loop: memory\nformat: v1\nepic: tmpq\ntotal-merged: 0\nlast-merge: none\n---\n\n# tmpq\n\n## 断点\n- [断点] 下一步：等待拆解\n' > context/epics/tmpq/memory.md
  sh "$SELF" --root "$T" --mark-temp --epic tmpq >/dev/null 2>&1 || { echo 'fail: T14 mark-temp 应成功'; ok=0; }
  grep -q '^kind: temp$' context/epics/tmpq/memory.md || { echo 'fail: T14 kind 行缺失'; ok=0; }
  grep -qxF '# tmpq（临时）' context/epics/tmpq/memory.md || { echo 'fail: T14 H1 未标注'; ok=0; }
  sh "$SELF" --root "$T" --mark-temp --epic tmpq >/dev/null 2>&1 || { echo 'fail: T14 幂等应成功'; ok=0; }
  [ "$(grep -c '^kind: temp$' context/epics/tmpq/memory.md)" = 1 ] || { echo 'fail: T14 幂等产生重复 kind 行'; ok=0; }
  sh "$SELF" --root "$T" --mark-temp --epic misc >/dev/null 2>&1 && { echo 'fail: T14 misc 应拒'; ok=0; }
  sh "$SELF" --root "$T" --mark-temp --epic nope >/dev/null 2>&1 && { echo 'fail: T14 不存在应拒'; ok=0; }
  sh "$SELF" --root "$T" --mark-temp --epic tmpq --doc docs/design/tmpq.md >/dev/null 2>&1 && { echo 'fail: T14 带 --doc 应拒'; ok=0; }
  # T15 --temp 建临时 epic：目录不存在时骨架内置 kind: temp（单入口，无需 --doc/--mark-temp）
  sh "$SELF" --root "$T" --temp --epic tmpnew >/dev/null 2>&1 || { echo 'fail: T15 temp 建骨架应成功'; ok=0; }
  grep -q '^kind: temp$' context/epics/tmpnew/memory.md || { echo 'fail: T15 kind 行缺失'; ok=0; }
  grep -qxF '# tmpnew（临时）' context/epics/tmpnew/memory.md || { echo 'fail: T15 H1 未标注'; ok=0; }
  [ -f context/epics/tmpnew/devlog.md ] || { echo 'fail: T15 devlog 缺失'; ok=0; }
  grep -q '^base: demo$' context/CURRENT || { echo 'fail: T15 base 行缺失'; ok=0; }
  sh "$SELF" --root "$T" --restore >/dev/null 2>&1 || { echo 'fail: T15 restore 应成功'; ok=0; }
  # T16 --temp 绑定已存在无挂载行未标记 epic → 自动补标
  mkdir -p context/epics/tmold
  printf -- '---\ndev-loop: memory\nformat: v1\nepic: tmold\ntotal-merged: 0\nlast-merge: none\n---\n\n# tmold\n\n## 断点\n- [断点] 下一步：等待拆解\n' > context/epics/tmold/memory.md
  sh "$SELF" --root "$T" --temp --epic tmold >/dev/null 2>&1 || { echo 'fail: T16 temp 绑定应成功'; ok=0; }
  grep -q '^kind: temp$' context/epics/tmold/memory.md || { echo 'fail: T16 未自动补标'; ok=0; }
  sh "$SELF" --root "$T" --restore >/dev/null 2>&1
  # T17 正式 epic（有挂载行）不误标 + misc 不补标
  sh "$SELF" --root "$T" --temp --epic bar >/dev/null 2>&1 || { echo 'fail: T17 temp 绑定 bar 应成功'; ok=0; }
  grep -q '^kind: ' context/epics/bar/memory.md 2>/dev/null && { echo 'fail: T17 正式 epic 被误标'; ok=0; }
  sh "$SELF" --root "$T" --restore >/dev/null 2>&1
  sh "$SELF" --root "$T" --temp --epic misc >/dev/null 2>&1 || { echo 'fail: T17 temp 绑定 misc 应成功'; ok=0; }
  grep -q '^kind: ' context/epics/misc/memory.md 2>/dev/null && { echo 'fail: T17 misc 被误标'; ok=0; }
  sh "$SELF" --root "$T" --restore >/dev/null 2>&1
  rm -rf "$T"
  if [ "$ok" -eq 1 ]; then echo 'self-test: OK（全链路+五类拦截+切换前置+dry-run+json 预检+原子 mkdir 闸门）'; return 0; fi
  return 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo '[remedy] --root 缺参数'; exit 2; }; ROOT=$2; shift 2 ;;
    --epic) [ $# -ge 2 ] || { echo '[remedy] --epic 缺参数'; exit 2; }; EPIC=$2; shift 2 ;;
    --doc) [ $# -ge 2 ] || { echo '[remedy] --doc 缺参数'; exit 2; }; DOC=$2; shift 2 ;;
    --title) [ $# -ge 2 ] || { echo '[remedy] --title 缺参数'; exit 2; }; TITLE=$2; shift 2 ;;
    --create-doc) CREATE_DOC=1; shift ;;
    --current-only) CURRENT_ONLY=1; shift ;;
    --temp) TEMP=1; CURRENT_ONLY=1; shift ;;
    --mark-temp) MARK_TEMP=1; shift ;;
    --restore) RESTORE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --json) JSON=1; shift ;;
    --self-test) exec_self_test; exit $? ;;
    --help|-h) usage; exit 0 ;;
    *) echo "[remedy] 未知参数: $1（--help 看用法）"; exit 2 ;;
  esac
done

[ -n "$ROOT" ] || ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
  if [ "$JSON" -eq 1 ]; then
    json_out FAIL error '未定位到项目根（当前不在 git 仓库内）' '进入目标仓库后重跑，或显式 --root <目录>'
    exit 1
  fi
  echo '[remedy] 未定位到项目根：请在目标 git 仓库内运行，或用 --root <目录>'
  exit 2
fi
CTX="$ROOT/context"

# ---- 骨架模板（骨架格式=资产层：toolbox/templates/epic/，随 ~/.agents 仓库同步；脚本只留渲染落盘）----
# 渲染契约 = toolbox/lib/render.sh（render_tpl/render_std/tpl_check + 残留 {{ 校验 + 转义，占位符规格见 templates/README.md）
TPL_DIR="$(dirname "$SELF")/../templates/epic"
LIB_DIR="$(dirname "$SELF")/../lib"
[ -f "$LIB_DIR/render.sh" ] || { echo "ERROR: 渲染器缺失: $LIB_DIR/render.sh"; echo '[remedy] 渲染器应随 ~/.agents 仓库同步；重新同步或补齐后重跑'; exit 2; }
. "$LIB_DIR/render.sh"

# ---- 参数完整性 ----
if [ "$RESTORE" -eq 1 ]; then
  [ -z "$EPIC" ] || fail '--restore 不接受 --epic（恢复目标来自 CURRENT 的 base 行）' '去掉 --epic 重跑'
elif [ "$CURRENT_ONLY" -eq 1 ]; then
  [ -n "$EPIC" ] || fail '补 --epic <名>（--current-only/--temp 切换目标）' '--current-only/--temp 需要 --epic'
elif [ "$MARK_TEMP" -eq 1 ]; then
  [ -n "$EPIC" ] || fail '补 --epic <名>（标记目标）' '--mark-temp 需要 --epic'
  [ -z "$DOC" ] || fail '--mark-temp 不接受 --doc（临时 epic 无挂载文档）' '去掉 --doc 重跑'
else
  { [ -n "$EPIC" ] && [ -n "$DOC" ]; } || fail '补 --epic <名> 与 --doc <docs/...md>（候选列表跑 toolbox run panel --mounts）' '--epic 与 --doc 必填'
fi

# ---- epic 名校验（维护态 = epics/<名>/memory.md 头部 state: maintenance，目录不搬）----
if [ "$RESTORE" -eq 0 ]; then
case "$EPIC" in
  *[!A-Za-z0-9_-]*|'') fail 'epic 名仅限字母/数字/-/_（对齐 panel valid_epic）' "epic 名非法: $EPIC" ;;
esac
# misc 拒绝仅限完整挂载（建正式挂载骨架）；--current-only 切回 misc 是合法日常默认绑定
if [ "$CURRENT_ONLY" -eq 0 ] && [ "$EPIC" = 'misc' ]; then
  fail 'misc 是常驻散修挂靠点，不建正式挂载（散修直接落 misc，dev-loop §3）' 'misc 不可挂载'
fi
EPIC_DIR="$CTX/epics/$EPIC"
# 维护态 epic 完整挂载拦截：先解除维护标记再续绑（devlog reopen），或 --current-only 续绑
if [ "$CURRENT_ONLY" -eq 0 ] && [ "$MARK_TEMP" -eq 0 ] && [ -d "$EPIC_DIR" ] \
   && [ "$(sed -n '2,12{s/^state:[[:space:]]*//p}' "$EPIC_DIR/memory.md" 2>/dev/null | head -n 1)" = 'maintenance' ]; then
  fail "先重开（toolbox run devlog reopen $EPIC）再完整挂载；或续绑走 --current-only --epic $EPIC" "epic 处于维护态（memory 头部 state: maintenance）: $EPIC"
fi
fi

# ---- --mark-temp：临时 epic 标记（kind: temp YAML + H1 标注；新建建骨架后与存量回填共用，幂等）----
if [ "$MARK_TEMP" -eq 1 ]; then
  _mt_mem="$EPIC_DIR/memory.md"
  [ -f "$_mt_mem" ] || fail '核对 epic 拼写或重建骨架后重跑' 'memory.md 缺失（骨架不完整，标记无处落）'
  if grep -q '^kind: temp$' "$_mt_mem" 2>/dev/null; then
    if [ "$JSON" -eq 1 ]; then json_out OK info "已标记临时（幂等无动作）: $EPIC"; else echo "OK: $EPIC 已是临时标记（幂等无动作）"; fi
    exit 0
  fi
  if [ "$DRY" -eq 1 ]; then
    if [ "$JSON" -eq 1 ]; then json_out OK info "[dry-run] $EPIC → kind: temp + H1（临时）"; exit 0; fi
    echo "[dry-run] 将在 $_mt_mem 头部写 kind: temp 并标注 H1（临时）"
    exit 0
  fi
  if [ "$JSON" -eq 1 ]; then json_out OK info "预检通过: $EPIC → kind: temp——去掉 --json 执行"; exit 0; fi
  _mt_tmp="$_mt_mem.marktmp.tmp"
  awk -v epic="$EPIC" '
    /^---[[:space:]]*$/ { n++; if (n == 2 && !done) { print "kind: temp"; done = 1 } print; next }
    $0 == "# " epic { print "# " epic "（临时）"; next }
    { print }
  ' "$_mt_mem" > "$_mt_tmp" || fail 'awk 处理失败' "检查文件编码与完整性: $_mt_mem"
  mv "$_mt_tmp" "$_mt_mem" || fail '写回失败' "检查权限: $_mt_mem"
  echo "OK: $EPIC → kind: temp（YAML + H1（临时））——收尾走 devlog archive（终态），不 reopen"
  exit 0
fi

# ---- 底子文档校验（--current-only/--restore 跳过）----
if [ "$CURRENT_ONLY" -eq 0 ] && [ "$RESTORE" -eq 0 ]; then
  case "$DOC" in
    docs/*.md) : ;;
    *) fail '底子文档落点写死 docs/ 下（dev-loop §3 文档锚定）' "doc 不在 docs/ 下: $DOC" ;;
  esac
  case "$DOC" in
    *..*) fail '文档路径禁含 ..（防越出仓库）' "doc 路径含 ..: $DOC" ;;
  esac
  slug=${DOC##*/}; slug=${slug%.md}
  [ "$slug" = "$EPIC" ] || fail 'epic 名 = 文档 slug（dev-loop §3 写死）；改名或另选文档' "slug 不一致: epic=$EPIC vs doc=$DOC"
  DOC_PATH="$ROOT/$DOC"
  DOC_EPIC=$(grep -rlF -- "- [挂载] $DOC" "$CTX"/epics/*/memory.md "$CTX"/archive/*/memory.md 2>/dev/null | head -n 1)
  if [ -n "$DOC_EPIC" ]; then
    holder=$(basename "$(dirname "$DOC_EPIC")")
    holder_dir=$(dirname "$DOC_EPIC")
    case "$holder_dir" in
      */archive/*) holder="$holder（已退役归档）" ;;
    esac
    fail "续绑该 epic（::bind $holder）（一文档一主线）" "文档已被挂载: $DOC → epic $holder"
  fi
  if [ -f "$DOC_PATH" ]; then
    if [ "$CREATE_DOC" -eq 1 ]; then
      fail '去掉 --create-doc 直接挂载（文档已存在，拒绝覆盖）' "doc 已存在: $DOC"
    fi
    st=$(sed -n '2,12{s/^status:[[:space:]]*//p}' "$DOC_PATH" 2>/dev/null | head -n 1)
    case "$st" in
      deprecated*) fail '按墓碑指向的继任文档重挂（docs-spec §1 废弃不可挂）' "doc 已 deprecated: $DOC" ;;
    esac
  else
    [ "$CREATE_DOC" -eq 1 ] || fail '文档不存在：加 --create-doc 连骨架一起建（或先跑 panel --mounts 核对候选）' "doc 不存在: $DOC（--create-doc 可建骨架）"
  fi
fi

# ---- 切换前置（dev-loop §3：旧 epic 未归并先 ::merge）----
old_epic=''
[ -f "$CTX/CURRENT" ] && old_epic=$(sed -n 's/^epic:[[:space:]]*//p' "$CTX/CURRENT" 2>/dev/null | head -n 1)
if [ -n "$old_epic" ] && [ "$old_epic" != "$EPIC" ] && [ "$old_epic" != 'none' ]; then
  case "$old_epic" in
    archive/*) OLD_DIR="$CTX/$old_epic" ;;
    *)         OLD_DIR="$CTX/epics/$old_epic" ;;
  esac
  pending=$(grep -c '^- \[' "$OLD_DIR/devlog.md" 2>/dev/null || true)
  [ "${pending:-0}" -gt 0 ] && fail "先对旧 epic 执行 ::merge 归并（待归并 $pending 条）再绑定" "切换前置未过: $old_epic devlog 待归并 $pending 条"
fi

# ---- --restore：恢复基础绑定（清临时态；临时 epic 有未归并日志被切换前置拦在上一步）----
if [ "$RESTORE" -eq 1 ]; then
  base_val=$(sed -n 's/^base:[[:space:]]*//p' "$CTX/CURRENT" 2>/dev/null | head -n 1)
  [ -n "$base_val" ] || fail '当前无临时绑定（CURRENT 无 base 行）' '仅在临时绑定态使用 --restore'
  if [ "$DRY" -eq 1 ]; then
    [ "$JSON" -eq 1 ] && { json_out OK info "[dry-run] 恢复基础绑定: epic: $base_val"; exit 0; }
    echo "[dry-run] CURRENT → epic: $base_val（清除临时态）"
    exit 0
  fi
  if [ "$JSON" -eq 1 ]; then json_out OK info "预检通过: 恢复基础绑定 $base_val——去掉 --json 执行"; exit 0; fi
  case "$base_val" in
    none) printf 'epic: none\n' > "$CTX/CURRENT" ;;
    *)
      [ -d "$CTX/epics/$base_val" ] || fail "基础绑定 epic 不存在: epics/$base_val（可能已退役/改名）" '核对后手工改写 CURRENT'
      printf 'epic: %s\n' "$base_val" > "$CTX/CURRENT"
      ;;
  esac
  echo "OK: 已恢复基础绑定 $base_val（临时态清除）"
  exit 0
fi

# ---- --current-only：只切指针 ----
if [ "$CURRENT_ONLY" -eq 1 ]; then
  if [ ! -d "$EPIC_DIR" ] && [ "$TEMP" -eq 0 ]; then
    fail "epic 不存在，去掉 --current-only 走完整挂载（--doc <docs/...md>）" "epic 不存在: $EPIC"
  fi
  if [ "$old_epic" = "$EPIC" ] && [ "$TEMP" -eq 0 ]; then
    if [ "$JSON" -eq 1 ]; then json_out OK info "已绑定 $EPIC（幂等无动作）"; else echo "OK: 已绑定 $EPIC，无动作"; fi
    exit 0
  fi
  if [ "$TEMP" -eq 1 ]; then
    grep -q '^base: ' "$CTX/CURRENT" 2>/dev/null \
      && fail '已有临时绑定未恢复——禁止嵌套临时绑定' '先 toolbox run mount-init --restore 恢复基础绑定'
    base_val="${old_epic:-none}"
    case "$base_val" in '(未绑定)'|'') base_val='none' ;; esac
    # 单入口分流：目录不存在 → 建临时骨架（模板内置 kind: temp，无需 --doc）；
    # 已存在且「无 kind 行 + 无挂载行 + ≠ misc」→ 绑定时自动补标（幂等收敛，无存量批量脚本）；
    # 有挂载行 = 正式 epic（含过渡态），不误标。
    _t_new=0; _t_stamp=0
    if [ ! -d "$EPIC_DIR" ]; then
      _t_new=1
    elif [ "$EPIC" != 'misc' ] \
      && ! grep -q '^kind: ' "$EPIC_DIR/memory.md" 2>/dev/null \
      && ! grep -q '^- \[挂载\]' "$EPIC_DIR/memory.md" 2>/dev/null; then
      _t_stamp=1
    fi
    _t_extra=''
    [ "$_t_new" -eq 1 ] && _t_extra='＋建临时骨架（kind: temp）'
    [ "$_t_stamp" -eq 1 ] && _t_extra="${_t_extra}＋补 kind: temp 标记"
    if [ "$DRY" -eq 1 ]; then
      [ "$JSON" -eq 1 ] && { json_out OK info "[dry-run] 临时绑定: CURRENT → epic: $EPIC（base: $base_val）$_t_extra"; exit 0; }
      echo "[dry-run] CURRENT → epic: $EPIC（base: $base_val 记入 CURRENT 第二行）$_t_extra"
      exit 0
    fi
    if [ "$JSON" -eq 1 ]; then json_out OK info "预检通过: 临时绑定 $EPIC（基础: $base_val）$_t_extra——去掉 --json 执行"; exit 0; fi
    if [ "$_t_new" -eq 1 ]; then
      mkdir -p "$EPIC_DIR" || fail '检查项目根与权限（--root）' "epic 目录创建失败: $EPIC_DIR"
      tpl_check "$TPL_DIR/memory-temp.md" "$TPL_DIR/devlog.md"
      render_tpl "$EPIC_DIR/memory.md" "$TPL_DIR/memory-temp.md" "EPIC=$EPIC"
      render_tpl "$EPIC_DIR/devlog.md" "$TPL_DIR/devlog.md" "EPIC=$EPIC"
      echo "  create context/epics/$EPIC/memory.md（kind: temp，模板渲染）"
      echo "  create context/epics/$EPIC/devlog.md"
    fi
    if [ "$_t_stamp" -eq 1 ]; then
      _ts_tmp="$EPIC_DIR/memory.md.autotmp.tmp"
      awk -v epic="$EPIC" '
        /^---[[:space:]]*$/ { n++; if (n == 2 && !done) { print "kind: temp"; done = 1 } print; next }
        $0 == "# " epic { print "# " epic "（临时）"; next }
        { print }
      ' "$EPIC_DIR/memory.md" > "$_ts_tmp" \
        && mv "$_ts_tmp" "$EPIC_DIR/memory.md" \
        || fail '自动补标写回失败' "手工修复或重跑: $EPIC_DIR/memory.md"
      echo "  mark    context/epics/$EPIC/memory.md → kind: temp（绑定即补，无挂载行的未标记 epic）"
    fi
    { printf 'epic: %s\n' "$EPIC"; printf 'base: %s\n' "$base_val"; } > "$CTX/CURRENT"
    echo "OK: 临时绑定 $EPIC（基础: $base_val）——收尾后 toolbox run mount-init --restore 恢复"
    exit 0
  fi
  if [ "$DRY" -eq 1 ]; then
    [ "$JSON" -eq 1 ] && { json_out OK info "[dry-run] 将改写 CURRENT: epic: $EPIC"; exit 0; }
    echo "[dry-run] 改写 $CTX/CURRENT → epic: $EPIC"
    exit 0
  fi
  printf 'epic: %s\n' "$EPIC" > "$CTX/CURRENT"
  if [ "$JSON" -eq 1 ]; then json_out OK info "CURRENT → $EPIC（切换完成，骨架未动）"; else echo "OK: CURRENT → $EPIC"; fi
  exit 0
fi

# ---- 完整挂载：骨架 + 指针 ----
# 原子认领（ADR 轻量级防御 2026-10-15）：mkdir 即唯一闸门——失败即已存在（并发先到者），
# 消除「检查后创建」的 TOCTOU 窗；dry-run/--json 只读预检不认领。
if [ "$DRY" -eq 1 ] || [ "$JSON" -eq 1 ]; then
  [ -d "$EPIC_DIR" ] && fail '该 epic 已有骨架（续绑走 --current-only，或换名；拒绝覆盖）' "epic 已存在: $EPIC"
else
  mkdir -p "$(dirname "$EPIC_DIR")" 2>/dev/null || fail '检查项目根与权限（--root）' "epics 父目录创建失败: $(dirname "$EPIC_DIR")"
  if ! mkdir "$EPIC_DIR" 2>/dev/null; then
    if [ -d "$EPIC_DIR" ]; then
      fail '该 epic 已有骨架（续绑走 --current-only，或换名；拒绝覆盖）' "epic 已存在: $EPIC"
    fi
    fail '检查项目根与权限（--root）' "epic 目录创建失败: $EPIC_DIR"
  fi
fi

CREATED=''
do_write() { # do_write <rel路径>（内容自 stdin）
  if [ "$DRY" -eq 1 ]; then
    echo "  [dry-run] 创建 $1"
  else
    mkdir -p "$(dirname "$ROOT/$1")"
    cat > "$ROOT/$1"
    echo "  create $1"
  fi
  CREATED="$CREATED $1"
}
do_current() {
  if [ "$DRY" -eq 1 ]; then
    echo "  [dry-run] 改写 context/CURRENT → epic: $EPIC"
  else
    printf 'epic: %s\n' "$EPIC" > "$CTX/CURRENT"
    echo "  write   context/CURRENT → epic: $EPIC"
  fi
  CREATED="$CREATED context/CURRENT"
}

# 横幅注记：CREATE_DOC/DRY 默认值 0 非空，${VAR:+} 会误展开（D5 实测 2026-10-07），改数值比较拼串
CDN=''; [ "$CREATE_DOC" -eq 1 ] && CDN='（含建文档）'
DRYN=''; [ "$DRY" -eq 1 ] && DRYN='（dry-run）'
if [ "$JSON" -eq 1 ]; then
  json_out OK info "预检通过: epic $EPIC ← $DOC$CDN$DRYN——去掉 --json 执行"
  exit 0
fi

echo "==> 挂载初始化: $EPIC ← $DOC$CDN$DRYN"
TODAY=$(date +%F)

if [ "$CREATE_DOC" -eq 1 ] && [ ! -f "$DOC_PATH" ]; then
  do_write "$DOC" <<EOF
---
status: draft
updated: $TODAY
---

# ${TITLE:-$slug}
EOF
fi

tpl_check "$TPL_DIR/memory-formal.md" "$TPL_DIR/devlog.md"
if [ "$DRY" -eq 1 ]; then
  echo "  [dry-run] 创建 context/epics/$EPIC/memory.md（模板渲染）"
  echo "  [dry-run] 创建 context/epics/$EPIC/devlog.md（模板渲染）"
  CREATED="$CREATED context/epics/$EPIC/memory.md context/epics/$EPIC/devlog.md"
else
  render_tpl "$ROOT/context/epics/$EPIC/memory.md" "$TPL_DIR/memory-formal.md" "EPIC=$EPIC" "MOUNT=$DOC"
  echo "  create context/epics/$EPIC/memory.md"
  CREATED="$CREATED context/epics/$EPIC/memory.md"
  render_tpl "$ROOT/context/epics/$EPIC/devlog.md" "$TPL_DIR/devlog.md" "EPIC=$EPIC"
  echo "  create context/epics/$EPIC/devlog.md"
  CREATED="$CREATED context/epics/$EPIC/devlog.md"
fi

do_current

echo "==> 完成：$CREATED"
if [ "$CREATE_DOC" -eq 1 ] && [ ! -f "$DOC_PATH" ] && [ "$DRY" -eq 0 ]; then
  echo "==> 待 AI 本轮完成（严禁留空占位）：$DOC 首稿内容提炼自需求讨论落盘（dev-loop §3 冷 bind 口径）"
fi
echo "==> 下一步：断点为「等待拆解」——用 ::next 拆解首个子任务开工；恢复口径：读 context/epics/$EPIC/memory.md 按断点继续"
exit 0
