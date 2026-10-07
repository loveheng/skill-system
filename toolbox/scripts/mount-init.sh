#!/bin/sh
# toolbox-script
# format: v1
# name: mount-init
# summary: epic 挂载初始化单一入口：::bind 的机械件（校验 slug/墓碑/重复挂载/切换前置 → 生成 memory/devlog 骨架与挂载行/断点行 → 改写 CURRENT），AI 零猜测零拼装
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
ROOT=''; EPIC=''; DOC=''; TITLE=''; CREATE_DOC=0; CURRENT_ONLY=0; DRY=0; JSON=0

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
  rm -rf "$T"
  if [ "$ok" -eq 1 ]; then echo 'self-test: OK（全链路+五类拦截+切换前置+dry-run+json 预检）'; return 0; fi
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

# ---- 参数完整性 ----
if [ "$CURRENT_ONLY" -eq 1 ]; then
  [ -n "$EPIC" ] || fail '补 --epic <名>（--current-only 切换目标）' '--current-only 需要 --epic'
else
  { [ -n "$EPIC" ] && [ -n "$DOC" ]; } || fail '补 --epic <名> 与 --doc <docs/...md>（候选列表跑 toolbox run panel --mounts）' '--epic 与 --doc 必填'
fi

# ---- epic 名校验 ----
case "$EPIC" in
  *[!A-Za-z0-9_-]*|'') fail 'epic 名仅限字母/数字/-/_（对齐 panel valid_epic）' "epic 名非法: $EPIC" ;;
esac
# misc 拒绝仅限完整挂载（建正式挂载骨架）；--current-only 切回 misc 是合法日常默认绑定
if [ "$CURRENT_ONLY" -eq 0 ] && [ "$EPIC" = 'misc' ]; then
  fail 'misc 是常驻散修挂靠点，不建正式挂载（散修直接落 misc，dev-loop §3）' 'misc 不可挂载'
fi
EPIC_DIR="$CTX/epics/$EPIC"

# ---- 底子文档校验（--current-only 跳过）----
if [ "$CURRENT_ONLY" -eq 0 ]; then
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
  DOC_EPIC=$(grep -rlF -- "- [挂载] $DOC" "$CTX"/epics/*/memory.md 2>/dev/null | head -n 1)
  if [ -n "$DOC_EPIC" ]; then
    holder=$(basename "$(dirname "$DOC_EPIC")")
    fail "续绑该 epic（::bind $holder）或其 ::done 归档后重开（一文档一主线）" "文档已被挂载: $DOC → epic $holder"
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
  pending=$(grep -c '^- \[' "$CTX/epics/$old_epic/devlog.md" 2>/dev/null || true)
  [ "${pending:-0}" -gt 0 ] && fail "先对旧 epic 执行 ::merge 归并（待归并 $pending 条）再绑定" "切换前置未过: $old_epic devlog 待归并 $pending 条"
fi

# ---- --current-only：只切指针 ----
if [ "$CURRENT_ONLY" -eq 1 ]; then
  [ -d "$EPIC_DIR" ] || fail "epic 不存在，去掉 --current-only 走完整挂载（--doc <docs/...md>）" "epic 不存在: $EPIC"
  if [ "$old_epic" = "$EPIC" ]; then
    if [ "$JSON" -eq 1 ]; then json_out OK info "已绑定 $EPIC（幂等无动作）"; else echo "OK: 已绑定 $EPIC，无动作"; fi
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
[ -d "$EPIC_DIR" ] && fail '该 epic 已有骨架（续绑走 --current-only，或换名；拒绝覆盖）' "epic 已存在: $EPIC"

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

if [ "$JSON" -eq 1 ]; then
  json_out OK info "预检通过: epic $EPIC ← $DOC${CREATE_DOC:+（含建文档骨架）}${DRY:+（dry-run）}——去掉 --json 执行"
  exit 0
fi

echo "==> 挂载初始化: $EPIC ← $DOC${CREATE_DOC:+（含建文档）}${DRY:+（dry-run，不落盘）}"
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

do_write "context/epics/$EPIC/memory.md" <<EOF
---
dev-loop: memory
format: v1
epic: $EPIC
total-merged: 0
last-merge: none
---

# $EPIC

- [挂载] $DOC

## 断点
- [断点] 下一步：等待拆解
EOF

do_write "context/epics/$EPIC/devlog.md" <<EOF
---
dev-loop: devlog
format: v1
epic: $EPIC
total-merged: 0
last-merge: none
---

（开发过程日志按行追加：[变更]/[验证]/[note]/[承诺]/[SSOT 修正]；≥5 条自动归并进 memory.md——dev-loop §2）
EOF

do_current

echo "==> 完成：$CREATED"
if [ "$CREATE_DOC" -eq 1 ] && [ ! -f "$DOC_PATH" ] && [ "$DRY" -eq 0 ]; then
  echo "==> 待 AI 本轮完成（严禁留空占位）：$DOC 首稿内容提炼自需求讨论落盘（dev-loop §3 冷 bind 口径）"
fi
echo "==> 下一步：断点为「等待拆解」——用 ::next 拆解首个子任务开工；恢复口径：读 context/epics/$EPIC/memory.md 按断点继续"
exit 0
