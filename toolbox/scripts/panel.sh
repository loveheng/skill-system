#!/bin/sh
# panel — dev-loop §6 面板数据源：绑定/断点/任务活动/计数「事实块」（只读不写；事实脚本出、判断 AI 出）
#
# toolbox-script
# format: v1
# name: panel
# summary: dev-loop 面板数据源：绑定/断点/任务活动/计数/债面事实块（--board/--deep/--debt/--mounts；建议动作由 AI 产出）
# trigger: manual
# cat: docs
# platform: unix
# self-test: --self-test

set -u
ROOT=''
MODE=''           # ''=事实块 | board | deep | debt
DEEP_EPIC=''
JSON=0
SELF_TEST=0
RC=0
MSG=''

usage() {
  cat <<'EOF'
panel —— dev-loop §6 面板数据源（只读不写；事实脚本出、判断 AI 出）

用法: panel.sh [--root <项目根>] [--board | --deep <epic> | --debt] [--json|--self-test|--help]

默认项目根: 当前目录（context/ 位于 <根>/context）

数据档（裸跑 = 事实块；建议动作不由脚本产出——AI 按判读协议结合语境自产）:
  裸跑            dev 事实块 ~5 行: 绑定/断点 ｜ 任务活动表 ｜ 计数(待决/待办/待归并) ｜ 并行行(多任务交错活跃时条件出现) ｜ 债面(U/D/P 粗计数+体检时效) → dev-loop ::help 数据源
  --board         逐任务一行: <epic> ｜ 最后活动 <日期> ｜ 断点（▶=当前绑定；misc 标常驻；按最后活动降序；archive 不列）→ ::board 数据源
  --deep <epic>   单任务深挖: 断点/memory 行数/最后活动/devlog 尾 3 行/本节 todos+台账计数 → 追问时按需取数
  --debt          债面明细: UNCERTAIN/DEGRADE/PATCH 标记数与 top 文件 + 白名单行数 + 上次体检时效 → 债追问时按需取数
  --mounts        挂载对照 + docs 候选: epic 挂载表 ｜ docs 清单(status/最后活动,▶已挂标记,deprecated 墓碑不列) → ::bind 候选列表数据源
  --json          一行 JSON 契约结论（当前档位内容的压缩 message）

数据口径: 最后活动 = git log 最近提交日期（context/ 未纳 git 显示 ?）；计数 = tail/grep 现实推导，零缓存。
债面口径: git 仓内 git grep 标记行（排除 *.md 与系统仓工具池自匹配），非 git 仓 grep 兜底（排除 .md/构建目录）；粗计数不含白名单过滤与形状扫描——权威数字以 uscan/dscan/ascan --md 为准。
定位: ::status（ctx-status）仍是单 epic 点查工具；本工具是 dev 域 ::help/::board 的数据源。

退出码: 0 正常（含无 context/ 跳过）/ 1 检查未通过（如 --deep epic 不存在）/ 2 自身故障
EOF
}

json_out() { # $1=status $2=severity $3=message $4=remedy(可选)
  if [ "$#" -ge 4 ]; then
    printf '{"status":"%s","severity":"%s","message":"%s","remedy":"%s"}\n' "$1" "$2" "$3" "$4"
  else
    printf '{"status":"%s","severity":"%s","message":"%s"}\n' "$1" "$2" "$3"
  fi
}

valid_epic() { case "$1" in *[!A-Za-z0-9_-]*|'') return 1;; *) return 0;; esac; }

# 最后活动日期：git 最近提交（%cs=YYYY-MM-DD）；未纳 git/无提交 → ?
last_date() { # $1=仓库内相对路径
  local d
  d=$(git -C "$ROOT" --no-pager log -1 --format=%cs -- "$1" 2>/dev/null)
  printf '%s' "${d:-?}"
}
epic_date() { last_date "context/epics/$1"; }

bp_of() { # $1=epic → 该 epic 自己的断点行内容
  local b
  b=$(grep -h '^-[[:space:]]*\[断点\]' "$ROOT/context/epics/$1/memory.md" 2>/dev/null | head -n 1 | sed 's/^- \[断点\][[:space:]]*//')
  printf '%s' "${b:-（缺失，应恒为 1 条）}"
}

mount_of() { # $1=memory.md 路径 → 挂载行文档路径（无挂载输出空）
  sed -n 's/^-[[:space:]]*\[挂载\][[:space:]]*//p' "$1" 2>/dev/null | head -n 1
}

cnt_file() { # $1=file $2=pattern → 计数（缺失文件=0）
  grep -c "$2" "$1" 2>/dev/null || true
}

section_cnt() { # $1=file $2=epic → 该 epic 节内 '- [ ]' 计数（节缺失=0）
  [ -f "$1" ] || { printf 0; return; }
  sed -n "/^## ${2}\$/,/^## /p" "$1" 2>/dev/null | grep -c '^- \[ \]' || true
}

# ---- 债面（粗计数层）------------------------------------------------------
# 定位：把实现层债（UNCERTAIN/DEGRADE/PATCH 标记）提升到面板常显，让债「被看到」；
# 粗口径 = 标记行 grep（排除 *.md 与构建目录），不含白名单过滤与形状扫描——
# 权威数字与处置口径以 uscan/dscan/ascan（ai-sideeffect-guard §2/§4、solution-admission §5）为准。

marker_lines() { # $1=RE → 原始标记匹配行（path:line:content；git 仓用 git grep，非 git 用 grep 兜底）
  # 系统仓（~/.agents）内排除工具池源码的自匹配——扫描器源码里的标记字面量不是债
  local ex='' in_sys=0
  [ "$(cd "$ROOT" 2>/dev/null && pwd)" = "$HOME/.agents" ] && { in_sys=1; ex=':(exclude)toolbox/scripts/*'; }
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$ROOT" grep -I -E "$1" -- . ':(exclude)*.md' $ex 2>/dev/null
  else
    grep -rInE "$1" "$ROOT" --exclude='*.md' --exclude-dir=.git --exclude-dir=__pycache__ \
      --exclude-dir=node_modules --exclude-dir=target --exclude-dir=dist --exclude-dir=build 2>/dev/null \
      | { [ "$in_sys" -eq 1 ] && grep -v "^$HOME/.agents/toolbox/scripts/" || cat; }
  fi
  return 0
}

mk_stat() { # $1=RE → "命中数 文件数"（恒两数字）
  local out
  out=$(marker_lines "$1" | awk -F: '{c[$1]++} END{n=0;f=0;for(k in c){n+=c[k];f++} print n,f}')
  [ -n "$out" ] || out='0 0'
  printf '%s' "$out"
}

mk_files() { # $1=RE → 命中最多的 ≤3 个文件路径（每行一个）
  marker_lines "$1" | awk -F: '{c[$1]++} END{for(k in c) print c[k], k}' | sort -rn | head -n 3 | awk '{print $2}'
}

wl_count() { # $1=白名单文件 → 非注释非空行数（缺失=0）
  [ -f "$1" ] || { printf 0; return; }
  grep -cvE '^[[:space:]]*(#|$)' "$1" 2>/dev/null || true
}

audit_stamp() { # audit 钩上次运行 → "MM-DD✓/MM-DD⚠/未体检"（读 toolbox 全局 state）
  local f d mk
  f="$HOME/.agents/toolbox/state/last-run-audit.json"
  [ -f "$f" ] || { printf '未体检'; return 0; }
  d=$(sed -n 's/.*"ts"[[:space:]]*:[[:space:]]*"\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\).*/\1/p' "$f" 2>/dev/null | head -n 1)
  [ -n "$d" ] || { printf '未体检'; return 0; }
  if grep -q '"status"[[:space:]]*:[[:space:]]*"FAIL"' "$f" 2>/dev/null; then mk='⚠'; else mk='✓'; fi
  printf '%s%s' "$(printf '%s' "$d" | cut -d- -f2-3)" "$mk"
}

debt_summary() { # 债面单行（scan_fact 第 5 行用），结果落全局 DEBT
  local nu nd np
  set -- $(mk_stat 'UNCERTAIN[[:space:]]*:'); nu=$1
  set -- $(mk_stat 'DEGRADE[[:space:]]*:');  nd=$1
  set -- $(mk_stat 'PATCH[[:space:]]*:');    np=$1
  DEBT="债: U${nu} D${nd} P${np}（粗计数）｜ 白名单 u$(wl_count "$ROOT/.uncertainty-whitelist")/d$(wl_count "$ROOT/.degrade-whitelist")/a$(wl_count "$ROOT/.admission-whitelist") ｜ 体检: $(audit_stamp)"
}

scan_debt() { # 债面明细档
  local nu nd np fu fd fp uf df pf
  set -- $(mk_stat 'UNCERTAIN[[:space:]]*:'); nu=$1; fu=$2
  set -- $(mk_stat 'DEGRADE[[:space:]]*:');  nd=$1; fd=$2
  set -- $(mk_stat 'PATCH[[:space:]]*:');    np=$1; fp=$2
  uf=$(mk_files 'UNCERTAIN[[:space:]]*:'); df=$(mk_files 'DEGRADE[[:space:]]*:'); pf=$(mk_files 'PATCH[[:space:]]*:')
  MSG="债面（粗计数——不含白名单过滤与形状扫描，权威数字以 uscan/dscan/ascan 为准）
UNCERTAIN: ${nu} 处 / ${fu} 文件"
  for f in $uf; do MSG="${MSG}
  ${f}"; done
  MSG="${MSG}
DEGRADE: ${nd} 处 / ${fd} 文件"
  for f in $df; do MSG="${MSG}
  ${f}"; done
  MSG="${MSG}
PATCH: ${np} 处 / ${fp} 文件"
  for f in $pf; do MSG="${MSG}
  ${f}"; done
  MSG="${MSG}
白名单: uncertainty $(wl_count "$ROOT/.uncertainty-whitelist") ｜ degrade $(wl_count "$ROOT/.degrade-whitelist") ｜ admission $(wl_count "$ROOT/.admission-whitelist")
上次体检: $(audit_stamp)（toolbox audit 钩 last-run）
处置: 高危转 (风险) 待办——ai-sideeffect-guard §4 ｜ PATCH 债与补丁密度——solution-admission §5"
  return 0
}

# 全量 epic 按最后活动降序输出 "日期 epic"（? 排序位置不保证，量少可忽略）
epics_sorted() {
  local tmp d e
  tmp=$(mktemp) || return 0
  for dir in "$ROOT"/context/epics/*/; do
    [ -d "$dir" ] || continue
    e=$(basename "$dir")
    d=$(epic_date "$e")
    printf '%s %s\n' "$d" "$e" >> "$tmp"
  done
  LC_ALL=C sort -r "$tmp"
  rm -f "$tmp"
}

scan_fact() {
  local ctx epic bp pc tdg tdd d1 d2 les line d e mark tasks dir par par_n newest ts PAR
  ctx="$ROOT/context"
  if [ ! -d "$ctx" ]; then
    MSG="ℹ 无 context/ 目录（${ctx}）——面板跳过（新项目先走 dev-init 初始化）"
    return 0
  fi
  epic=$(sed -n 's/^epic:[[:space:]]*//p' "$ctx/CURRENT" 2>/dev/null | head -n 1)
  [ -z "$epic" ] && epic='(未绑定)'
  bp=$(grep -h '^-[[:space:]]*\[断点\]' "$ctx/epics/$epic/memory.md" "$ctx/epics/misc/memory.md" 2>/dev/null | head -n 1 | sed 's/^- \[断点\][[:space:]]*//')
  [ -z "$bp" ] && bp='（缺失，应恒为 1 条）'
  tasks=$(epics_sorted | while read -r d e; do
    [ -n "$e" ] || continue
    mark=''
    [ "$e" = "$epic" ] && mark='▶'
    [ "$e" = "misc" ] && mark="${mark}·常驻"
    printf '%s(%s)%s ' "$e" "$d" "$mark"
  done)
  [ -n "$tasks" ] || tasks='（无 epic）'
  pc=$(cnt_file "$ctx/pending-confirm.md" '^- \[ \]')
  tdg=$(cnt_file "$ctx/todos.md" '^- \[ \]')
  tdd=0
  for df in "$ctx"/epics/*/todos.md; do
    [ -f "$df" ] || continue
    tdd=$((tdd + $(cnt_file "$df" '^- \[ \]')))
  done
  d1=$(tail -n 20 "$ctx/epics/$epic/devlog.md" 2>/dev/null | grep -c '^- \[' || true)
  if [ "$epic" = misc ]; then
    d2=0   # 绑定 epic 即 misc 时不重复计数（同一文件）
  else
    d2=$(tail -n 20 "$ctx/epics/misc/devlog.md" 2>/dev/null | grep -c '^- \[' || true)
  fi
  les=$(cnt_file "$ctx/lessons.md" '^- \[')
  debt_summary
  # 并行信号（零缓存，git 活动现场推导）：非 misc epic 中与最近活跃窗 ≤2 天的 ≥2 个 → 恢复须点名
  par=''; par_n=0; newest=0
  for dir in "$ctx"/epics/*/; do
    [ -d "$dir" ] || continue
    e=$(basename "$dir")
    [ "$e" = 'misc' ] && continue
    d=$(epic_date "$e")
    [ "$d" = '?' ] && continue
    ts=$(date -d "$d" +%s 2>/dev/null || date -j -f '%Y-%m-%d' "$d" +%s 2>/dev/null)
    [ -n "$ts" ] || continue
    [ "$ts" -gt "$newest" ] && newest=$ts
  done
  if [ "$newest" -gt 0 ]; then
    for dir in "$ctx"/epics/*/; do
      [ -d "$dir" ] || continue
      e=$(basename "$dir")
      [ "$e" = 'misc' ] && continue
      d=$(epic_date "$e")
      [ "$d" = '?' ] && continue
      ts=$(date -d "$d" +%s 2>/dev/null || date -j -f '%Y-%m-%d' "$d" +%s 2>/dev/null)
      [ -n "$ts" ] || continue
      if [ $((newest - ts)) -le 172800 ]; then par="$par$e・"; par_n=$((par_n + 1)); fi
    done
  fi
  PAR=''
  [ "$par_n" -ge 2 ] && PAR="\n并行: ${par%・} 近期交错活跃（≤2 天窗）——恢复请点名任务，CURRENT 仅最近绑定"
  MSG="绑定: ▶ ${epic}\n断点: ${bp}\n任务: ${tasks}｜ 计数: 待决 ${pc:-0} ｜ 待办 全局 ${tdg:-0}/域内 ${tdd} ｜ 待归并 devlog $((d1 + d2))/lessons ${les:-0}${PAR}\n${DEBT}"
  return 0
}

scan_board() {
  local ctx epic d e mark b
  ctx="$ROOT/context"
  if [ ! -d "$ctx" ]; then
    MSG="ℹ 无 context/ 目录（${ctx}）——面板跳过（新项目先走 dev-init 初始化）"
    return 0
  fi
  epic=$(sed -n 's/^epic:[[:space:]]*//p' "$ctx/CURRENT" 2>/dev/null | head -n 1)
  MSG=$(epics_sorted | while read -r d e; do
    [ -n "$e" ] || continue
    mark=''
    [ "$e" = "$epic" ] && mark='▶ '
    disp="$e"
    [ "$e" = "misc" ] && disp="${e}(常驻)"
    b=$(bp_of "$e")
    printf '%s%s ｜ 最后活动 %s ｜ 断点: %s\n' "$mark" "$disp" "$d" "$b"
  done)
  [ -n "$MSG" ] || MSG='（无 epic——::bind <名> 创建第一个任务）'
  return 0
}

scan_deep() {
  local ctx e mem mlines d tdc pcc tail3
  ctx="$ROOT/context"
  e="$DEEP_EPIC"
  if ! valid_epic "$e"; then
    MSG='FAIL: epic 名非法（仅限字母/数字/-/_）'
    RC=2
    return 0
  fi
  if [ ! -d "$ctx/epics/$e" ]; then
    MSG="FAIL: epic 不存在: context/epics/${e}"
    RC=1
    return 0
  fi
  mem="$ctx/epics/$e/memory.md"
  mlines=$(wc -l < "$mem" 2>/dev/null | tr -d '[:space:]')
  [ -z "$mlines" ] && mlines=0
  d=$(epic_date "$e")
  tail3=$(tail -n 3 "$ctx/epics/$e/devlog.md" 2>/dev/null)
  [ -n "$tail3" ] || tail3='（devlog 为空或缺失）'
  tdc=$(cnt_file "$ctx/epics/$e/todos.md" '^- \[ \]')
  pcc=$(section_cnt "$ctx/pending-confirm.md" "$e")
  MSG="epic: ${e} ｜ 最后活动: ${d} ｜ memory: ${mlines} 行（软上限 150）\n断点: $(bp_of "$e")\ndevlog 尾 3:\n${tail3}\ntodos(本域): ${tdc:-0} ｜ 台账(本节): ${pcc:-0}"
  return 0
}

scan_mounts() {
  local ctx dir e m mounts mall docs f rel st d mark
  ctx="$ROOT/context"
  mounts=''
  mall='|'
  if [ -d "$ctx/epics" ]; then
    for dir in "$ctx"/epics/*/; do
      [ -d "$dir" ] || continue
      e=$(basename "$dir")
      [ "$e" = 'misc' ] && continue
      m=$(mount_of "$dir/memory.md")
      [ -n "$m" ] || continue
      mounts="${mounts}epic ${e} → ${m}\n"
      mall="${mall}${m}|"
    done
  fi
  if [ -n "$mounts" ]; then :; else mounts='（无挂载 epic——misc 散修兜底不列）\n'; fi
  if [ -d "$ROOT/docs" ]; then
    docs=$(find "$ROOT/docs" -type f -name '*.md' | LC_ALL=C sort | while IFS= read -r f; do
      rel=${f#"$ROOT"/}
      st=$(sed -n '2,12{s/^status:[[:space:]]*//p}' "$f" 2>/dev/null | head -n 1)
      case "$st" in deprecated*) continue;; esac
      d=$(last_date "$rel")
      mark=''
      case "$mall" in *"|$rel|"*) mark=' ▶已挂';; esac
      printf '%s [status:%s|%s]%s\n' "$rel" "${st:-无}" "$d" "$mark"
    done)
    [ -n "$docs" ] || docs='（docs/ 仅剩 deprecated 墓碑或无 .md）'
  else
    docs='（无 docs/ 目录——先建底子文档再挂载；散修挂 misc）'
  fi
  MSG="挂载对照:\n${mounts}docs 候选（deprecated 墓碑不列；▶已挂=已有主线，续绑或归档重开）:\n${docs}"
  return 0
}

self_test() {
  local td ok out c
  ok=1
  td=$(mktemp -d)
  c="$td/c"
  # 用例 1: 无 context/ → 跳过
  if ! sh "$0" --root "$td" 2>/dev/null | grep -q '无 context'; then echo "self-test: 无 context 应跳过"; ok=0; fi
  # 脚手架: demo(绑定)+misc，todos/台账/lessons/devlog 各计数
  mkdir -p "$c/context/epics/demo" "$c/context/epics/misc"
  printf 'epic: demo\n' > "$c/context/CURRENT"
  cat > "$c/context/epics/demo/memory.md" <<'EOF'
---
dev-loop: memory
format: v1
epic: demo
total-merged: 0
last-merge: none
---

# demo

- [挂载] docs/architecture/demo.md

## 断点
- [断点] 下一步：完成重连握手
EOF
  printf -- '- [断点] 等待散修任务\n' > "$c/context/epics/misc/memory.md"
  printf -- '- [2026-10-01] [变更]: a\n- [2026-10-01] [验证]: b\n- [2026-10-01] [变更]: c\n' > "$c/context/epics/demo/devlog.md"
  printf -- '- [2026-10-01] [变更]: m\n' > "$c/context/epics/misc/devlog.md"
  # 第二活跃 epic（与 demo 同批 commit 同日 → 触发并行信号）
  mkdir -p "$c/context/epics/work"
  printf -- '- [断点] 等待排期\n' > "$c/context/epics/work/memory.md"
  printf -- '- [2026-10-01] [变更]: w\n' > "$c/context/epics/work/devlog.md"
  printf -- '- [模块] x ➔ y ➔ z\n' > "$c/context/lessons.md"
  printf -- '- [ ] [2026-10-01] D1 问题一\n- [ ] [2026-10-01] D2 问题二\n' > "$c/context/pending-confirm.md"
  printf '# 待办\n\n## misc\n\n- [ ] [2026-10-01] (文档) C\n- [ ] [2026-10-01] (风险) R\n' > "$c/context/todos.md"
  printf -- '---\nmemo: todos\nformat: v3\nepic: demo\n---\n\n# demo · 域内待办\n- [ ] [2026-10-01] (功能) A\n- [ ] [2026-10-01] (修复) B\n' > "$c/context/epics/demo/todos.md"
  # docs 候选脚手架（demo 可挂，old 废弃不列）
  mkdir -p "$c/docs/architecture" "$c/docs/guide"
  printf -- '---\nstatus: active\nupdated: 2026-10-01\n---\n\n# demo 底子\n' > "$c/docs/architecture/demo.md"
  printf -- '---\nstatus: deprecated\nupdated: 2026-10-01\n---\n\n# 旧文档\n' > "$c/docs/guide/old.md"
  # 债面脚手架（三种标记各 1 处，供 git grep 粗计数与 --debt 明细用例）
  mkdir -p "$c/src"
  printf '# UNCERTAIN: 未实证的接口行为\n# DEGRADE: 猜测兜底\n# PATCH: 权宜实现\n' > "$c/src/app.py"
  if command -v git >/dev/null 2>&1; then
    git -C "$c" init -q >/dev/null 2>&1
    git -C "$c" add -A >/dev/null 2>&1
    git -C "$c" -c user.email=t@local -c user.name=t commit -qm init >/dev/null 2>&1
  fi
  # 用例 2: 事实块
  out=$(sh "$0" --root "$c" 2>&1)
  printf '%s' "$out" | grep -q '绑定: ▶ demo' || { echo "self-test: 绑定行错误: $out"; ok=0; }
  printf '%s' "$out" | grep -q '断点: 下一步：完成重连握手' || { echo "self-test: 断点行错误"; ok=0; }
  printf '%s' "$out" | grep -q 'demo(' || { echo "self-test: 任务表缺 demo: $out"; ok=0; }
  printf '%s' "$out" | grep -q 'misc(.*常驻' || { echo "self-test: 任务表 misc 未标常驻: $out"; ok=0; }
  printf '%s' "$out" | grep -q '待决 2' || { echo "self-test: 待决计数错误: $out"; ok=0; }
  printf '%s' "$out" | grep -q '待办 全局 2/域内 2' || { echo "self-test: 待办计数错误: $out"; ok=0; }
  printf '%s' "$out" | grep -q '并行: demo・work' || { echo "self-test: 并行信号缺失: $out"; ok=0; }
  # 用例 2b: 单活跃 epic → 并行行不出现（防常驻噪音）
  rm -rf "$c/context/epics/work"
  out=$(sh "$0" --root "$c" 2>&1)
  printf '%s' "$out" | grep -q '并行:' && { echo "self-test: 单 epic 不应有并行信号: $out"; ok=0; }
  printf '%s' "$out" | grep -q '待归并 devlog 4/lessons 1' || { echo "self-test: 待归并计数错误: $out"; ok=0; }
  printf '%s' "$out" | grep -q '债: U1 D1 P1' || { echo "self-test: 债行缺失或粗计数错误: $out"; ok=0; }
  printf '%s' "$out" | grep -q '体检:' || { echo "self-test: 债行缺体检时效"; ok=0; }
  # 用例 3: --board
  out=$(sh "$0" --root "$c" --board 2>&1)
  printf '%s' "$out" | grep -qE '▶ demo ｜ 最后活动 (20[0-9]{2}-[0-9]{2}-[0-9]{2}|\?)' || { echo "self-test: board 绑定标记/日期错误: $out"; ok=0; }
  printf '%s' "$out" | grep -q 'misc(常驻)' || { echo "self-test: board misc 常驻标记错误: $out"; ok=0; }
  printf '%s' "$out" | grep -q '等待散修任务' || { echo "self-test: board 断点缺失: $out"; ok=0; }
  # 用例 4: --deep demo
  out=$(sh "$0" --root "$c" --deep demo 2>&1)
  printf '%s' "$out" | grep -q 'devlog 尾 3' || { echo "self-test: deep 缺 devlog 尾: $out"; ok=0; }
  printf '%s' "$out" | grep -q 'todos(本域): 2' || { echo "self-test: deep 本域 todos 计数错误: $out"; ok=0; }
  printf '%s' "$out" | grep -q '\[变更\]: a' || { echo "self-test: deep devlog 尾内容缺失: $out"; ok=0; }
  # 用例 5: --deep 不存在 → exit 1
  sh "$0" --root "$c" --deep ghost >/dev/null 2>&1 && { echo "self-test: ghost epic 应 exit 1"; ok=0; }
  # 用例 6: --json 单行契约
  out=$(sh "$0" --root "$c" --json 2>/dev/null)
  printf '%s' "$out" | grep -q '"status":"OK"' || { echo "self-test: json 状态错误: $out"; ok=0; }
  [ "$(printf '%s\n' "$out" | wc -l)" -le 1 ] || { echo "self-test: json 应单行"; ok=0; }
  # 用例 7: --mounts 挂载对照 + docs 候选
  out=$(sh "$0" --root "$c" --mounts 2>&1)
  printf '%s' "$out" | grep -q '挂载对照' || { echo "self-test: mounts 缺挂载对照节: $out"; ok=0; }
  printf '%s' "$out" | grep -q 'epic demo → docs/architecture/demo.md' || { echo "self-test: mounts 缺 epic 挂载: $out"; ok=0; }
  printf '%s' "$out" | grep -q 'docs/architecture/demo.md.*▶已挂' || { echo "self-test: mounts 已挂标记缺失: $out"; ok=0; }
  printf '%s' "$out" | grep -q 'status:deprecated' && { echo "self-test: mounts 废弃文档应不列: $out"; ok=0; }
  # 用例 8: --debt 债面明细（三标记计数 + top 文件 + 体检时效）
  out=$(sh "$0" --root "$c" --debt 2>&1)
  printf '%s' "$out" | grep -q 'UNCERTAIN: 1 处 / 1 文件' || { echo "self-test: debt UNCERTAIN 计数错误: $out"; ok=0; }
  printf '%s' "$out" | grep -q 'DEGRADE: 1 处 / 1 文件' || { echo "self-test: debt DEGRADE 计数错误: $out"; ok=0; }
  printf '%s' "$out" | grep -q 'PATCH: 1 处 / 1 文件' || { echo "self-test: debt PATCH 计数错误: $out"; ok=0; }
  printf '%s' "$out" | grep -qF 'src/app.py' || { echo "self-test: debt 未列 top 文件: $out"; ok=0; }
  printf '%s' "$out" | grep -q '上次体检:' || { echo "self-test: debt 缺体检时效行: $out"; ok=0; }
  printf '%s' "$out" | grep -q '白名单: uncertainty 0' || { echo "self-test: debt 白名单计数错误: $out"; ok=0; }
  # 用例 9: --debt --json 单行契约
  out=$(sh "$0" --root "$c" --debt --json 2>/dev/null)
  printf '%s' "$out" | grep -q '"status":"OK"' || { echo "self-test: debt json 状态错误: $out"; ok=0; }
  [ "$(printf '%s\n' "$out" | wc -l)" -le 1 ] || { echo "self-test: debt json 应单行"; ok=0; }
  if [ "$ok" -eq 1 ]; then echo "self-test: OK"; rm -rf "$td"; return 0; fi
  rm -rf "$td"; return 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2;;
    --board) MODE='board'; shift;;
    --mounts) MODE='mounts'; shift;;
    --debt) MODE='debt'; shift;;
    --deep) MODE='deep'; DEEP_EPIC="${2:-}"; shift 2;;
    --json) JSON=1; shift;;
    --self-test) SELF_TEST=1; shift;;
    --help|-h) usage; exit 0;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 2;;
  esac
done

[ -n "$ROOT" ] || ROOT=$(pwd)

if [ "$SELF_TEST" -eq 1 ]; then self_test; exit $?; fi

if [ "$MODE" = 'board' ]; then
  scan_board
elif [ "$MODE" = 'mounts' ]; then
  scan_mounts
elif [ "$MODE" = 'debt' ]; then
  scan_debt
elif [ "$MODE" = 'deep' ]; then
  if [ -z "$DEEP_EPIC" ]; then
    if [ "$JSON" -eq 1 ]; then json_out FAIL error 'FAIL: --deep 需要 epic 参数' '用法: panel --deep <epic>'; else echo 'FAIL: --deep 需要 epic 参数（用法: panel --deep <epic>）' >&2; fi
    exit 2
  fi
  scan_deep
else
  scan_fact
fi

M=$(printf '%b' "$MSG" | tr '\n' ' ' | tr -d '"')
if [ "$JSON" -eq 1 ]; then
  if [ "$RC" -eq 0 ]; then json_out OK info "$M"
  else json_out FAIL error "$M" 'deep: 先 ::bind <名> 创建骨架，或 panel --board 查看现有任务'; fi
  exit "$RC"
fi
printf '%b\n' "$MSG"
if [ "$RC" -ne 0 ]; then
  printf '[remedy] deep 目标不存在时: 先 ::bind <名> 创建骨架，或 panel --board 查看现有任务\n' >&2
fi
exit "$RC"
