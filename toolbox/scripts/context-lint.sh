#!/bin/sh
# context 记忆体系机械校验：数据面（CURRENT/头部/断点/挂载行/积压/尺寸/孤儿/todos/done/decisions）
# + 指针面（<skill> §N 与 <skill>「节名」引用锚点存在性）。audit 钩工具，供 @audit 机械项代跑。
#
# toolbox-script
# format: v1
# name: context-lint
# summary: context 记忆体系机械校验：CURRENT/头部/断点/挂载行/积压/尺寸/孤儿/devlog [验证] 缺口/todos 格式(v2/v3 含状态/层/重 元数据)与 [once]/[long] 时效 + skill 指针存在性
# trigger: audit
# cat: docs
# alias: cl
# platform: unix
# self-test: --self-test

# 无 set -e：grep -c 零匹配返回 1 属预期流程，需自行吞掉
set -u

ROOT=''; SKILLS_ROOT=''; MSG=''; FINDINGS=''; NOTE=''; ERR=0; WARN=0

usage() {
  cat <<'EOF'
context-lint —— context/ 记忆体系 + skill 指针面机械校验（agent-toolbox audit 钩工具）

用法: context-lint.sh [--root <项目根>] [--skills-root <目录>] [--json|--self-test|--help]

模式区别:
  裸跑（无 --json）  逐条输出发现明细（✗ 违规 / ⚠ 告警），供人与 AI 阅读整改
  --json             仅输出一行契约结论 {status,severity,message}（run-hooks / @audit 用）

参数:
  --root <dir>        context/ 所在项目根（默认当前目录）
  --skills-root <dir> skill 本体目录（默认 ~/.agents/skills；金丝雀夹具用）

检查面:
  数据面  context/CURRENT 格式与悬空；epics/* 头部字段与角色一致；断点行恰 1 条；
          挂载行（epic memory.md 首部恰 1 条且路径存在、非 deprecated，misc 豁免——
          dev-loop §3 文档锚定）；
          devlog 待归并 >=5 与未归并 [SSOT 修正]；memory >150 行软上限；
          devlog 最近 [变更] 的同日 [验证] 账本缺口（dev-loop §7 第 12 项）；
          孤儿 epic（devlog 30 天未动）；lessons 待归并；
          todos 两级（全局 misc 兜底 + epics/<名>/todos.md 域文件）头部、行格式
          与域归属一致，全局节序（## misc 恒为末节）；
          todos [once] 过 30 天事件窗口 / [long] 超 90 天未重评
          done/decisions 头部与行格式；
  指针面  各 SKILL.md / README.md / COMMANDS.md 中 <skill> §N 与
          <skill>「节名」引用（含 stock-calculator- 前缀别名）的锚点存在性；
          中文数字节号（如 §八）与裸 § 自引用保守跳过，仍归人工抽查

退出码: 0 合规 / 1 有发现 / 2 自身故障
挂载:   trigger=audit —— @audit 第 11 项 run-hooks audit 自动执行
EOF
  return 0
}

count() { # count <regex> <file> → 匹配行数（文件缺失/零匹配均 0）
  [ -f "$2" ] || { printf '0'; return 0; }
  grep -c "$1" "$2" 2>/dev/null || true
}

add() { # add <error|warn> <CODE> <一句话描述>
  if [ "$1" = error ]; then
    ERR=$((ERR + 1))
    FINDINGS="$FINDINGS"'✗ ['"$2"'] '"$3"'\n'
  else
    WARN=$((WARN + 1))
    FINDINGS="$FINDINGS"'⚠ ['"$2"'] '"$3"'\n'
  fi
  return 0
}

hdr_has() { # hdr_has <file> <fixed串> → 头部 7 行内含该串则为真
  head -n 7 "$1" 2>/dev/null | grep -qF "$2"
}

check_hdr() { # check_hdr <file> <角色行> <归属RE锚定行> <合并头 yes|no>
  f=$1; role=$2; owner=$3; full=$4
  if ! head -n 7 "$f" 2>/dev/null | head -n 1 | grep -q '^--- *$'; then
    add error HDR "$f 头部缺 YAML 起始 ---"
    return 0
  fi
  hdr_has "$f" "$role" || add error HDR "$f 头部缺 $role"
  hdr_has "$f" 'format: v' || add error HDR "$f 头部缺 format 版本行"
  head -n 7 "$f" 2>/dev/null | grep -qE "^$owner *$" || add error HDR "$f 头部归属非 $owner"
  if [ "$full" = yes ]; then
    head -n 7 "$f" 2>/dev/null | grep -qE 'total-merged: [0-9]+' || add error HDR "$f 头部 total-merged 缺失或非数字"
    head -n 7 "$f" 2>/dev/null | grep -qE 'last-merge: (none|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])' || add error HDR "$f 头部 last-merge 缺失或非法"
  fi
  return 0
}

bad_lines() { # bad_lines <file> <行首过滤RE> <整行完整RE> → 违规行号串
  # grep -n 输出带 "行号:" 前缀，完整 RE 的 ^ 锚定需移植到前缀之后
  fullre=${3#^}
  grep -n "$2" "$1" 2>/dev/null | grep -Ev "^[0-9]*:$fullre" | sed 's/:.*//' | tr '\n' ' '
  return 0
}

lint_epic() { # lint_epic <epic目录(带尾斜杠)> <当前epic名|空> <epic名>
  d=$1; cur=$2; name=$3
  m=${d}memory.md; g=${d}devlog.md
  if [ ! -f "$m" ]; then
    add error SKELETON "epics/$name/memory.md 缺失（骨架损坏，@file 重建）"
  else
    check_hdr "$m" 'dev-loop: memory' "epic: $name" yes
    c=$(count '^- \[断点\]' "$m")
    if [ "$c" -eq 0 ]; then
      add error CHECKPOINT "epics/$name/memory.md 断点行缺失（应恒为 1 条）"
    elif [ "$c" -gt 1 ]; then
      add error CHECKPOINT "epics/$name/memory.md 断点行 $c 条重复（去重保留最新）"
    fi
    [ "$(count '^## 断点' "$m")" -eq 0 ] && add error CHECKPOINT "epics/$name/memory.md 缺 ## 断点 章节"
    lines=$(wc -l < "$m" | tr -d '[:space:]')
    [ "$lines" -gt 150 ] && add warn SIZE "epics/$name/memory.md $lines 行 > 150 软上限（考虑 @done 收尾或拆分）"
  fi
  if [ ! -f "$g" ]; then
    add error SKELETON "epics/$name/devlog.md 缺失（骨架损坏）"
    return 0
  fi
  check_hdr "$g" 'dev-loop: devlog' "epic: $name" yes
  p=$(tail -n 20 "$g" 2>/dev/null | grep -c '^- \[' || true)
  [ "$p" -ge 5 ] && add warn MERGE "epics/$name/devlog.md 待归并 $p 条（>=5 触发归并）"
  # 只数日志行（^- [日期] [类型]），骨架样板行含该字面量但不算条目（D1 误报复核 2026-10-07）
  s=$(count '^- \[.*\[SSOT 修正\]' "$g")
  [ "$s" -gt 0 ] && add warn SSOT "epics/$name/devlog.md 有未归并 [SSOT 修正] $s 条（应立即归并）"
  if [ "$name" != misc ] && [ "$name" != "$cur" ]; then
    [ -n "$(find "$g" -mtime +30 -print 2>/dev/null)" ] && add warn ORPHAN "epics/$name 疑似孤儿（devlog 30 天未动）——提示 @done 或确认搁置"
  fi
  # [验证] 缺口（dev-loop §7 第 12 项机械化）：最近 3 条 [变更] 是否各有同日 [验证] 账本
  chg=$(grep '\[变更\]' "$g" 2>/dev/null | tail -n 3)
  if [ -n "$chg" ]; then
    miss=0
    OIFS=$IFS; IFS='
'
    for cl in $chg; do
      dt=$(printf '%s' "$cl" | sed -n 's/^[^0-9]*\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\).*/\1/p')
      [ -n "$dt" ] || continue
      grep -q "\[$dt\] \[验证\]" "$g" || miss=$((miss + 1))
    done
    IFS=$OIFS
    [ "$miss" -gt 0 ] && add warn VERIFY "epics/$name/devlog.md 最近 [变更] 有 $miss 条缺同日 [验证] 账本（声称完成 vs 实际验证，dev-loop §7 第 12 项）"
    bad_v=$(grep '\[验证\]' "$g" 2>/dev/null | grep '未执行' | grep -cv '未执行:' || true)
    [ "$bad_v" -gt 0 ] && add warn VERIFY "epics/$name/devlog.md 有 $bad_v 条 [验证] 写「未执行」未附理由（严禁虚构，须写原因）"
  fi
  return 0
}

lint_mounts() { # 挂载行校验（dev-loop §3 文档锚定）：非 misc epic 挂载行恰 1 条且路径真实存在
  for d in "$CTX"/epics/*/; do
    [ -d "$d" ] || continue
    e=$(basename "$d")
    [ "$e" = misc ] && continue
    m=${d}memory.md
    [ -f "$m" ] || continue   # 骨架缺失已由 lint_epic 报，此处不重复
    n=$(count '^- \[挂载\]' "$m")
    if [ "$n" -eq 0 ]; then
      add warn MOUNT "$e/memory.md 无挂载行（正式主线须文档锚定；存量缺挂载不强制补，提示级）"
    elif [ "$n" -gt 1 ]; then
      add error MOUNT "$e/memory.md 挂载行 $n 条（应恒 1 条，去重保留）"
    else
      mp=$(sed -n 's/^-[[:space:]]*\[挂载\][[:space:]]*//p' "$m" 2>/dev/null | head -n 1)
      case "$mp" in
        /*) tp=$mp ;;
        *) tp="$ROOT/$mp" ;;
      esac
      if [ -z "$mp" ]; then
        add error MOUNT "$e/memory.md 挂载行缺文档路径"
      elif [ ! -f "$tp" ]; then
        add warn MOUNT "$e/memory.md 挂载失效：$mp 不存在（修复路径或经确认迁移）"
      else
        st=$(sed -n '2,12{s/^status:[[:space:]]*//p}' "$tp" 2>/dev/null | head -n 1)
        case "$st" in
          deprecated*) add warn MOUNT "$e/memory.md 挂载文档 $mp 已 deprecated（墓碑不可挂，::bind 重挂继任文档）" ;;
        esac
      fi
    fi
  done
  return 0
}

TODO_RE='^- \[ \] (\[[0-9]{4}-[0-9]{2}-[0-9]{2}\] )?\((功能|修复|优化|文档|环境|测试|风险)\) ?(\[once\]|\[long\])? ?(\(block\))? ?(\((降级|暂缓|候)\))? ?(\(层:L[0-4]\))? ?(\(重:(轻|中|重)\))? .+ ?(\(src: (ai|用户)(, [A-Za-z0-9_-]+)?\))? *$'

lint_todos_file() { # lint_todos_file <文件>：单文件共享检查（头部/行格式/emoji/[x]/生命周期）
  f=$1
  hdr_has "$f" 'memo: todos' || add error HDR "$f 头部缺 memo: todos"
  head -n 7 "$f" 2>/dev/null | grep -qE 'format: v(2|3)' || add error HDR "$f 头部 format 非 v2/v3（memo-collector §0）"
  bad=$(bad_lines "$f" '^- \[ \]' "$TODO_RE")
  [ -n "$bad" ] && add error TODOS "$f 待办行格式违规 行号: $bad（口径见 memo-collector §0）"
  emoji=$(grep -nE '^- \[ \] .*🅿' "$f" 2>/dev/null | sed 's/:.*//' | tr '\n' ' ')
  [ -n "$emoji" ] && add error TODOS "$f 含 emoji 状态（🅿）行号: $emoji（v3 禁用 emoji，改用 (降级)/(暂缓)/(候)，口径 memo-collector §0）"
  x=$(count '^- \[[xX]\]' "$f")
  [ "$x" -gt 0 ] && add warn RECLAIM "$f 有 $x 条人工打勾 [x] 待回收（移入 done.md 并从列表删除）"
  c30=$(date -d '30 days ago' +%Y-%m-%d 2>/dev/null || date -v-30d +%Y-%m-%d 2>/dev/null || printf '')
  c90=$(date -d '90 days ago' +%Y-%m-%d 2>/dev/null || date -v-90d +%Y-%m-%d 2>/dev/null || printf '')
  if [ -n "$c30" ]; then
    once_old=$(grep '\[once\]' "$f" 2>/dev/null | sed -n 's/^- \[ \] \[\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\)\].*/\1/p' | awk -v c="$c30" '$0 <= c' | wc -l | tr -d '[:space:]')
    [ "$once_old" -gt 0 ] && add warn ONCE "$f 有 $once_old 条 [once] 已过 30 天事件窗口（确认完成转 done 或过期清除）"
  fi
  if [ -n "$c90" ]; then
    long_old=$(grep '\[long\]' "$f" 2>/dev/null | sed -n 's/^- \[ \] \[\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\)\].*/\1/p' | awk -v c="$c90" '$0 <= c' | wc -l | tr -d '[:space:]')
    [ "$long_old" -gt 0 ] && add warn LONG "$f 有 $long_old 条 [long] 超 90 天未重评（下个 @done 逐条重评：保留/转动作/关闭）"
  fi
  return 0
}

lint_todos() {
  # 域文件：epics/<名>/todos.md（头部 epic 须与目录一致）
  total=0
  for f in "$CTX"/epics/*/todos.md; do
    [ -f "$f" ] || continue
    lint_todos_file "$f"
    e=$(basename "$(dirname "$f")")
    head -n 7 "$f" 2>/dev/null | grep -qE "^epic: $e *$" || add error HDR "$f 头部 epic 与目录不符（应 epic: $e）"
    total=$((total + $(count '^- \[ \]' "$f")))
  done
  # 全局兜底：仅 ## misc 一节（节序 + 迁移残留检查）
  f=$CTX/todos.md
  [ -f "$f" ] || return 0
  lint_todos_file "$f"
  total=$((total + $(count '^- \[ \]' "$f")))
  lasth=$(grep -n '^## ' "$f" 2>/dev/null | tail -n 1)
  if [ -z "$lasth" ]; then
    add error TODOS 'todos.md 无任何节（缺 ## misc 兜底节）'
  else
    ht=$(printf '%s' "$lasth" | sed 's/^[0-9]*://')
    case "$ht" in
      '## misc'*) : ;;   # misc 行允许尾随文字
      *) add error TODOS 'todos.md 最后一节非 ## misc（misc 恒为末节）' ;;
    esac
    stray=$(grep -c '^## ' "$f" 2>/dev/null || true)
    [ "${stray:-0}" -gt 1 ] && add warn MIGRATE "todos.md 含非 misc 节 $((stray - 1)) 个（v3 域级迁移残留——epic 节迁 epics/<名>/todos.md，memo-collector §0）"
  fi
  [ "$total" -gt 30 ] && add warn GROOM "待办总量 $total 条 > 30（全局+域文件聚合，建议 @todo-groom 洗盘）"
  return 0
}

lint_done() {
  f=$CTX/done.md
  [ -f "$f" ] || return 0
  hdr_has "$f" 'memo: done' || add error HDR "done.md 头部缺 memo: done"
  hdr_has "$f" 'format: v2' || add error HDR "done.md 头部 format 非 v2"
  DONE_RE='^- \[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\] .+ ?\(域: .+\)'
  bad=$(bad_lines "$f" '^- \[' "$DONE_RE")
  [ -n "$bad" ] && add error DONE "done.md 行格式违规 行号: $bad（口径见 memo-collector §0）"
  return 0
}

lint_lessons() {
  f=$CTX/lessons.md
  [ -f "$f" ] || return 0
  check_hdr "$f" 'dev-loop: lessons' 'epic: global' yes
  p=$(count '^- \[' "$f")
  [ "$p" -ge 5 ] && add warn MERGE "lessons.md 待归并 $p 条（>=5 触发归并）"
  return 0
}

lint_decisions() {
  f=$CTX/decisions.md
  [ -f "$f" ] || return 0
  check_hdr "$f" 'dev-loop: decisions' 'epic: global' yes
  lasth=$(grep -n '^## ' "$f" 2>/dev/null | tail -n 1)
  [ -n "$lasth" ] || return 0
  ht=$(printf '%s' "$lasth" | sed 's/^[0-9]*://')
  case "$ht" in
    '## misc'|'## misc'[' ']*) : ;;
    *) add error DECTIONS 'decisions.md 末节非 ## misc（misc 兜底恒为末节）' ;;
  esac
  return 0
}

lint_data() {
  R=${ROOT:-$(pwd)}
  CTX=$R/context
  if [ ! -d "$CTX" ]; then
    NOTE='ℹ 无 context/ 目录——数据面跳过（新 clone 常态，不视为违规）'
    return 0
  fi
  cur=''
  if [ -f "$CTX/CURRENT" ]; then
    n=$(grep -c . "$CTX/CURRENT" || true)
    [ "$n" -le 1 ] || add error CURRENT "CURRENT 多于一行（应恒为 epic: <名> 单行）"
    v=$(sed -n 's/^epic:[[:space:]]*//p' "$CTX/CURRENT" 2>/dev/null | head -n 1)
    if [ -z "$v" ]; then
      add error CURRENT "CURRENT 内容非 epic: <名> 格式（或为空文件）"
    elif [ "$v" != none ]; then
      case "$v" in
        *[!A-Za-z0-9_-]*)
          add error CURRENT "CURRENT epic 名含非法字符（只允许字母/数字/连字符/下划线）" ;;
        *) if [ ! -d "$CTX/epics/$v" ]; then
             add error CURRENT "CURRENT 指向的 epics/$v 目录不存在（重新 @file 绑定）"
           else
             cur=$v
           fi ;;
      esac
    fi
  fi
  if [ -d "$CTX/epics" ]; then
    for d in "$CTX/epics"/*/; do
      [ -d "$d" ] || continue
      lint_epic "$d" "$cur" "$(basename "$d")"
    done
  fi
  lint_mounts
  lint_lessons
  lint_todos
  lint_done
  lint_decisions
  return 0
}

resolve_skill() { # resolve_skill <引用名> → 目标 SKILL.md 路径（遍历 SKILL_ROOTS，未知名输出空）
  # 注意：调用方（指针循环）已把 IFS 改为换行，此处须显式设回默认空白才能按空格分词
  nm=$1; out=''
  RIFS=$IFS; IFS=' 	
'
  for sr in $SKILL_ROOTS; do
    for dd in "$sr"/*/; do
      [ -d "$dd" ] || continue
      bn=$(basename "$dd")
      if { [ "$bn" = "$nm" ] || [ "$bn" = "stock-calculator-$nm" ]; } && [ -f "${dd}SKILL.md" ]; then
        out="${dd}SKILL.md"
        break
      fi
    done
    [ -n "$out" ] && break
  done
  IFS=$RIFS
  printf '%s' "$out"
  return 0
}

lint_pointers() {
  # 技能根两级：项目根 <repo>/.agents/skills（project-local，优先） + 全局技能根（--skills-root 覆盖）
  SKILL_ROOTS=''
  [ -n "$ROOT" ] && [ -d "$ROOT/.agents/skills" ] && SKILL_ROOTS="$ROOT/.agents/skills"
  gsr=${SKILLS_ROOT:-$HOME/.agents/skills}
  [ -d "$gsr" ] && SKILL_ROOTS="$SKILL_ROOTS $gsr"
  [ -n "$SKILL_ROOTS" ] || return 0
  SKILL_ROOTS=$(printf '%s' "$SKILL_ROOTS" | sed 's/^ *//;s/ *$//')
  files=''
  for sr in $SKILL_ROOTS; do
    for f in "$sr"/*/SKILL.md; do [ -f "$f" ] && files="$files $f"; done
    base=$(dirname "$sr")
    [ -f "$base/README.md" ] && files="$files $base/README.md"
    [ -f "$base/COMMANDS.md" ] && files="$files $base/COMMANDS.md"
  done
  [ -n "$files" ] || return 0
  # —— 数字节号引用：<skill> §N（N 仅 ASCII 数字与点；中文数字节号保守跳过）
  # 两个 grep 须在 IFS 改为换行前执行：$files 依赖空格分词
  refs=$(grep -HonE '[A-Za-z][A-Za-z0-9-]+ *§[0-9][0-9.]*' $files 2>/dev/null || true)
  nrefs=$(grep -HonE '[A-Za-z][A-Za-z0-9-]+ *(SKILL\.md)?`?「[^」]+」' $files 2>/dev/null || true)
  OIFS=$IFS
  IFS='
'
  for r in $refs; do
    [ -n "$r" ] || continue
    rn=$(printf '%s' "$r" | sed 's/^[^:]*:[0-9]*://')
    nm=$(printf '%s' "$rn" | sed 's/ *§.*//')
    num=$(printf '%s' "$rn" | sed 's/^.*§//')
    tgt=$(resolve_skill "$nm")
    [ -n "$tgt" ] || continue
    ne=$(printf '%s' "$num" | sed 's/\./\\./g')
    if ! grep -qE "^#{1,6} *$ne($| |、|：|（|\.([^0-9]|$))" "$tgt" 2>/dev/null; then
      add error POINTER "引用 $rn 失效：$nm/SKILL.md 无 §$num 对应章节标题（改节号需当轮同步引用方）"
    fi
  done
  # —— 命名节引用：<skill>[ SKILL.md]`?「节名」
  for r in $nrefs; do
    [ -n "$r" ] || continue
    rn=$(printf '%s' "$r" | sed 's/^[^:]*:[0-9]*://')
    sec=${rn##*「}
    sec=${sec%」}
    hd=${rn%%「*}
    hd=${hd##*:}
    nm=$(printf '%s' "$hd" | sed -e 's/` *$//' -e 's/ *SKILL\.md$//' -e 's/ *$//')
    tgt=$(resolve_skill "$nm")
    [ -n "$tgt" ] || continue
    grep -qF "$sec" "$tgt" 2>/dev/null || add error POINTER "引用 $nm「$sec」失效：目标文件无该节名（改节名需当轮同步引用方）"
  done
  IFS=$OIFS
  return 0
}

run_all() {
  ERR=0; WARN=0; FINDINGS=''; NOTE=''
  lint_data
  lint_pointers
  if [ "$ERR" -eq 0 ] && [ "$WARN" -eq 0 ]; then
    MSG='context 数据面与 skill 指针面均合规'
    return 0
  fi
  codes=$(printf '%b' "$FINDINGS" | sed 's/^[^[]*\[\([A-Z]*\)\].*/\1/' | grep -v '^$' | sort -u | tr '\n' '/')
  MSG="$ERR 违规 $WARN 告警: $codes"
  return 1
}

self_test() {
  SELF=$0
  T=$(mktemp -d 2>/dev/null) || { echo 'self-test: mktemp 失败'; return 2; }
  trap 'rm -rf "$T"' EXIT INT TERM
  fail=0
  mkdir -p "$T/emptyskills" "$T/clean/context/epics/demo" "$T/clean/context/epics/misc" "$T/p/skills/alpha" "$T/pgood" "$T/pbad"
  # ---------- 夹具 1：合规样本 ----------
  c=$T/clean/context
  printf 'epic: demo\n' > "$c/CURRENT"
  cat > "$c/epics/demo/memory.md" <<'EOF'
---
dev-loop: memory
format: v1
epic: demo
total-merged: 0
last-merge: none
---

- [挂载] docs/demo/spec.md

# demo

- [2026-09-19] 初始结论

## 断点
- [断点] 下一步：等待拆解
EOF
  mkdir -p "$T/clean/docs/demo"
  printf -- '---\nstatus: active\nupdated: 2026-09-19\n---\n\n# demo spec\n' > "$T/clean/docs/demo/spec.md"
  cat > "$c/epics/demo/devlog.md" <<'EOF'
---
dev-loop: devlog
format: v1
epic: demo
total-merged: 0
last-merge: none
---

- [2026-09-19] [变更]: 初始化骨架
- [2026-09-19] [验证]: 骨架校验 → 通过
EOF
  cat > "$c/epics/misc/memory.md" <<'EOF'
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
  cat > "$c/epics/misc/devlog.md" <<'EOF'
---
dev-loop: devlog
format: v1
epic: misc
total-merged: 0
last-merge: none
---

- [2026-09-19] [变更]: misc 初始化
- [2026-09-19] [验证]: misc 初始化校验 → 通过
EOF
  cat > "$c/lessons.md" <<'EOF'
---
dev-loop: lessons
format: v1
epic: global
total-merged: 0
last-merge: none
---

# lessons

按模块归类的避坑规则正文行（不以流水前缀开头）
EOF
  cat > "$c/todos.md" <<'EOF'
---
memo: todos
format: v3
---

# 待办列表

## misc
- [ ] [2026-09-19] (风险) 项目级风险样例（跨域兜底落全局） (src: ai)
EOF
  cat > "$c/epics/demo/todos.md" <<'EOF'
---
memo: todos
format: v3
epic: demo
---

# demo · 域内待办
- [ ] [2026-09-19] (功能) 示例待办一 (src: 用户)
- [ ] [2026-09-19] (修复) (block) 示例阻塞项 (src: ai)
- [ ] [2026-09-19] (优化) [long] 长期事项样例（近期不应触发重评提示） (src: ai)
- [ ] [2026-09-19] (功能)(层:L4)(重:中) v3 元数据样例 (src: ai)
EOF
  cat > "$c/done.md" <<'EOF'
---
memo: done
format: v2
---

# 完成列表
- [2026-09-18] 已完成示例条目 (域: misc)
EOF
  cat > "$c/decisions.md" <<'EOF'
---
dev-loop: decisions
format: v1
epic: global
total-merged: 0
last-merge: none
---

# decisions

## misc
EOF
  # ---------- 夹具 2：坏样本（每类违规一种） ----------
  b=$T/bad/context
  mkdir -p "$b/epics/demo"
  printf 'epic: ghost\n' > "$b/CURRENT"
  cat > "$b/epics/demo/memory.md" <<'EOF'
---
dev-loop: memory
format: v1
epic: other
last-merge: none
---

- [挂载] docs/ghost.md

正文无断点
EOF
  cat > "$b/epics/demo/devlog.md" <<'EOF'
---
dev-loop: devlog
format: v1
epic: demo
total-merged: 0
last-merge: none
---

- [2026-09-19] [SSOT 修正]: 旧 ➔ 新
- [2026-09-19] [变更]: 一
- [2026-09-19] [变更]: 二
- [2026-09-19] [变更]: 三
- [2026-09-19] [变更]: 四
- [2026-09-19] [变更]: 五
EOF
  cat > "$b/todos.md" <<'EOF'
---
memo: todos
format: v2
---

# 待办列表

## demo
- [ ] 2026-09-19 乱来的行 (src: robot)
- [x] [2026-09-19] (风险) 人工打勾样例 (src: 用户)
- [ ] [2025-01-01] (风险) [once] 过期一次性事项样例 (src: ai)

## misc

## 尾巴
EOF
  cat > "$b/done.md" <<'EOF'
---
memo: done
format: v2
---

- [完成条目缺日期与域标注]
EOF
  # ---------- 夹具 3：指针面（好/坏引用；README 须与 skills/ 同级，对齐真实布局） ----------
  mkdir -p "$T/pgood/skills/alpha" "$T/pbad/skills/alpha"
  for tree in pgood pbad; do
    cat > "$T/$tree/skills/alpha/SKILL.md" <<'EOF'
# alpha

## 1. 目标
内容

## 2. 探索
存在节内容
EOF
  done
  cat > "$T/pgood/README.md" <<'EOF'
对照 alpha §1 与 alpha §2；命名节见 alpha「存在节」
EOF
  cat > "$T/pbad/README.md" <<'EOF'
对照 alpha §1 与 alpha §9；命名节见 alpha「缺失节」
EOF
  # ---------- 断言 ----------
  rc=0; sh "$SELF" --root "$T/clean" --skills-root "$T/emptyskills" >"$T/o1" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ] && grep -q 'OK' "$T/o1"; then
    echo 'pass: 合规样本通过（exit 0）'
  else
    echo 'fail: 合规样本应通过却报违规:'; sed 's/^/  /' "$T/o1"; fail=1
  fi
  rc=0; sh "$SELF" --json --root "$T/clean" --skills-root "$T/emptyskills" >"$T/o2" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ] && grep -q '"status":"OK"' "$T/o2"; then
    echo 'pass: 合规样本 --json OK（exit 0）'
  else
    echo 'fail: 合规样本 --json 应 OK:'; sed 's/^/  /' "$T/o2"; fail=1
  fi
  rc=0; sh "$SELF" --root "$T/bad" --skills-root "$T/emptyskills" >"$T/o3" 2>&1 || rc=$?
  if [ "$rc" -eq 1 ]; then
    echo 'pass: 坏样本被拒（exit 1）'
  else
    echo "fail: 坏样本应 exit 1，实际 $rc:"; sed 's/^/  /' "$T/o3"; fail=1
  fi
  for needle in '[CURRENT]' '[HDR]' '[CHECKPOINT]' '[MOUNT]' '[MERGE]' '[SSOT]' '[TODOS]' '[DONE]' '[RECLAIM]' '[VERIFY]' '[ONCE]'; do
    if grep -qF "$needle" "$T/o3"; then
      echo "pass: 坏样本抓到 $needle"
    else
      echo "fail: 坏样本未抓到 $needle"; sed 's/^/  /' "$T/o3"; fail=1
    fi
  done
  rc=0; sh "$SELF" --json --root "$T/bad" --skills-root "$T/emptyskills" >"$T/o4" 2>&1 || rc=$?
  if [ "$rc" -eq 1 ] && grep -q '"status":"FAIL"' "$T/o4"; then
    echo 'pass: 坏样本 --json FAIL（exit 1，契约一致）'
  else
    echo 'fail: 坏样本 --json 契约不符:'; sed 's/^/  /' "$T/o4"; fail=1
  fi
  rc=0; sh "$SELF" --root "$T/pgood" --skills-root "$T/pgood/skills" >"$T/o5" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo 'pass: 指针面好引用全过（exit 0）'
  else
    echo 'fail: 指针面好引用被误报:'; sed 's/^/  /' "$T/o5"; fail=1
  fi
  rc=0; sh "$SELF" --root "$T/pbad" --skills-root "$T/pbad/skills" >"$T/o6" 2>&1 || rc=$?
  if [ "$rc" -eq 1 ] && grep -qF 'alpha §9' "$T/o6" && grep -qF '「缺失节」' "$T/o6"; then
    echo 'pass: 指针面坏引用被抓（§9 与「缺失节」）'
  else
    echo 'fail: 指针面坏引用漏检:'; sed 's/^/  /' "$T/o6"; fail=1
  fi
  # ---------- 夹具 4：project-local 技能根（<repo>/.agents/skills）互引可解析 ----------
  mkdir -p "$T/proj/.agents/skills/beta"
  cat > "$T/proj/.agents/skills/beta/SKILL.md" <<'EOF'
# beta

## 1. 项目级
参照 beta §1（project-local 互引应可解析）
EOF
  rc=0; sh "$SELF" --root "$T/proj" --skills-root "$T/emptyskills" >"$T/o7" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo 'pass: project-local skill 互引可解析（exit 0）'
  else
    echo 'fail: project-local skill 互引被误判失效:'; sed 's/^/  /' "$T/o7"; fail=1
  fi
  if [ "$fail" -eq 0 ]; then
    echo 'self-test: PASS'
    return 0
  fi
  echo 'self-test: FAIL'
  return 1
}

ACTION=''
while [ $# -gt 0 ]; do
  case "$1" in
    --json|--self-test|--help|-h) ACTION=$1; shift ;;
    --root) [ $# -ge 2 ] || { usage; exit 2; }; ROOT=$2; shift 2 ;;
    --skills-root) [ $# -ge 2 ] || { usage; exit 2; }; SKILLS_ROOT=$2; shift 2 ;;
    *) usage; exit 2 ;;
  esac
done

case "$ACTION" in
  --help|-h)
    usage
    ;;
  --self-test)
    self_test
    ;;
  --json)
    if run_all; then
      printf '{"status":"OK","severity":"info","message":"%s"}\n' "$MSG"
      exit 0
    fi
    sev=warn
    [ "$ERR" -eq 0 ] || sev=error
    printf '{"status":"FAIL","severity":"%s","message":"%s"}\n' "$sev" "$MSG"
    exit 1
    ;;
  '')
    if run_all; then
      [ -n "$NOTE" ] && printf '%s\n' "$NOTE"
      printf 'OK: %s\n' "$MSG"
      exit 0
    fi
    [ -n "$NOTE" ] && printf '%s\n' "$NOTE"
    printf '%b' "$FINDINGS"
    printf '结论: %s\n' "$MSG"
    exit 1
    ;;
  *)
    usage
    exit 2
    ;;
esac
