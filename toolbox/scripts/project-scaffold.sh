#!/bin/sh
# toolbox-script
# format: v1
# name: project-scaffold
# summary: 新项目 skill 体系骨架一键初始化（context/ 记忆骨架 + 白名单骨架 + .agents/skills + docs 数据 skill + toolbox 项目池），幂等不覆盖
# trigger: manual
# cat: ops
# alias: scaffold,pscaf
# platform: unix
# self-test: --self-test
#
# 骨架格式 SSOT：dev-loop §0（context/ 目录与文件头部）、memo-collector §0（todos/done 头部与节）、
# ai-sideeffect-guard §3（白名单格式）、dev-init §1（接入顺序与人工取证项）。本脚本只搬运，不定义规范。
set -u
SELF=$0

usage() {
  cat <<'EOF'
project-scaffold —— 项目 skill 体系骨架初始化（幂等）

用法: project-scaffold [--root <目录>] [--dry-run] [--json] [--self-test] [--help]

做什么（全部幂等：已存在即跳过，绝不覆盖已有文件）:
  context/CURRENT                     epic: misc
  context/epics/misc/memory.md        含 YAML 头部 + ## 断点 初始行
  context/epics/misc/devlog.md        含 YAML 头部
  context/lessons.md / decisions.md   含 YAML 头部 + misc 兜底节
  context/todos.md / done.md          memo 头部 + ## misc 末节
  .gitignore                          追加 context/CURRENT（个人指针，不入库）
  .uncertainty-whitelist              仅头注释，禁预置条目
  .degrade-whitelist                  仅头注释，禁预置条目
  .agents/skills/                     目录 + .gitkeep（空目录不入 git）
  .agents/skills/<repo>-docs/SKILL.md 仅当存在 docs/ 时创建（只填数据位，规范指针回 docs-spec）；
  无 docs/ 不生成空骨架——初始域结构按项目类型人工生成（dev-init §1 第 5 步）
  scripts/agent-tools/                调用 toolbox init --project（toolbox 可用时）

不做（必须人工取证，脚本只列清单）:
  workflow 事实源 skill（模块结构/构建命令需实测跑通）
  项目索引 skill 的归属表内容（需读代码提炼）
  代码写法规范 skill（需从现有代码提炼）

模式:
  --dry-run  只打印将创建的路径，不落盘
  --json     预检结论（不落盘）：仓库根/已有骨架状态
EOF
}

json_out() {
  printf '{"status":"%s","severity":"%s","message":"%s"%s}\n' "$1" "$2" "$3" "${4:+,\"remedy\":\"$4\"}"
}

exec_self_test() {
  T=$(mktemp -d)
  (cd "$T" && git init -q . 2>/dev/null) || { echo 'fail: 无法初始化临时 git 仓库'; rm -rf "$T"; return 1; }
  printf 'x\n' > "$T/README.md"
  r=0
  sh "$SELF" --root "$T" >/dev/null 2>&1 || r=$?
  [ "$r" -eq 0 ] || { echo "fail: 骨架生成退出码 $r"; rm -rf "$T"; return 1; }
  for f in context/CURRENT context/epics/misc/memory.md context/epics/misc/devlog.md \
           context/lessons.md context/decisions.md context/todos.md context/done.md \
           .uncertainty-whitelist .degrade-whitelist .agents/skills/.gitkeep; do
    [ -f "$T/$f" ] || { echo "fail: 缺产出 $f"; rm -rf "$T"; return 1; }
  done
  grep -q '^epic: misc$' "$T/context/CURRENT" || { echo 'fail: CURRENT 内容不符'; rm -rf "$T"; return 1; }
  grep -qxF 'context/CURRENT' "$T/.gitignore" || { echo 'fail: .gitignore 未追加 CURRENT'; rm -rf "$T"; return 1; }
  r2=0
  out=$(sh "$SELF" --root "$T" 2>&1) || r2=$?
  [ "$r2" -eq 0 ] || { echo "fail: 二次执行退出码 $r2（幂等失败）"; rm -rf "$T"; return 1; }
  printf '%s' "$out" | grep -q '创建 0 项' || { echo 'fail: 二次执行未全跳过（非幂等）'; rm -rf "$T"; return 1; }
  rm -rf "$T"
  echo 'self-test: OK（骨架齐备 + 幂等二次全跳过 + .gitignore 追加）'
  return 0
}

ROOT=''; DRY=0; JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "[remedy] --root 缺参数"; exit 2; }; ROOT=$2; shift 2 ;;
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
    json_out FAIL error "未定位到项目根（当前不在 git 仓库内）" "进入目标仓库后重跑，或显式 --root <目录>"
    exit 1
  fi
  echo "[remedy] 未定位到项目根：请在目标 git 仓库内运行，或用 --root <目录>"
  exit 2
fi

if [ "$JSON" -eq 1 ]; then
  have=0
  [ -f "$ROOT/context/CURRENT" ] && have=$((have + 1))
  [ -d "$ROOT/context/epics/misc" ] && have=$((have + 1))
  [ -f "$ROOT/context/todos.md" ] && have=$((have + 1))
  [ -d "$ROOT/.agents/skills" ] && have=$((have + 1))
  json_out OK info "项目根 $ROOT 可初始化（已有骨架项 $have/4，--json 仅预检不落盘）" "执行 toolbox run scaffold 生成骨架（幂等，已存在项跳过）"
  exit 0
fi

REPO=$(basename "$ROOT")
CREATED=0; SKIPPED=0

mk() {
  rel=$1; dst="$ROOT/$rel"
  if [ -f "$dst" ]; then
    SKIPPED=$((SKIPPED + 1))
    echo "  skip  $rel（已存在，不覆盖）"
    return 0
  fi
  if [ "$DRY" -eq 1 ]; then
    echo "  [dry-run] 创建 $rel"
    CREATED=$((CREATED + 1))
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  cat > "$dst"
  echo "  create $rel"
  CREATED=$((CREATED + 1))
}

echo "==> 项目根: $ROOT${DRY:+（dry-run，不落盘）}"

mk 'context/CURRENT' <<'EOF'
epic: misc
EOF

mk 'context/epics/misc/memory.md' <<'EOF'
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

mk 'context/epics/misc/devlog.md' <<'EOF'
---
dev-loop: devlog
format: v1
epic: misc
total-merged: 0
last-merge: none
---

（散修/小改动按行追加；≥5 条自动归并进 memory.md）
EOF

mk 'context/lessons.md' <<'EOF'
---
dev-loop: lessons
format: v1
epic: global
total-merged: 0
last-merge: none
---

# lessons

按模块归类的避坑规则正文（正文行禁用 `- [` 开头——该前缀专属底部追加区）
EOF

mk 'context/decisions.md' <<'EOF'
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

mk 'context/todos.md' <<'EOF'
---
memo: todos
format: v2
---

# 待办列表

## misc
EOF

mk 'context/done.md' <<'EOF'
---
memo: done
format: v2
---

# 完成列表
EOF

mk '.uncertainty-whitelist' <<'EOF'
# uncertainty-scan 本仓白名单（每行一个正则，# 为注释行）
# 机制见 ai-sideeffect-guard §3：只收录逐处核读定性为「已知误报」的模式；
# 对应路径修复后须删行恢复监控。禁预置条目——首跑基线评估后再逐条登记。
EOF

mk '.degrade-whitelist' <<'EOF'
# degrade-scan 本仓白名单（每行一个正则，# 为注释行）
# 机制见 ai-sideeffect-guard §3：只登记定性为「有意降级」的路径；
# 对应路径修复后须删行恢复监控。禁预置条目——首跑基线评估后再逐条登记。
EOF

gi="$ROOT/.gitignore"
if [ -f "$gi" ] && grep -qxF 'context/CURRENT' "$gi"; then
  SKIPPED=$((SKIPPED + 1)); echo '  skip  .gitignore（已含 context/CURRENT）'
elif [ "$DRY" -eq 1 ]; then
  echo '  [dry-run] .gitignore 追加 context/CURRENT'; CREATED=$((CREATED + 1))
else
  printf 'context/CURRENT\n' >> "$gi"
  echo '  append .gitignore ← context/CURRENT'
  CREATED=$((CREATED + 1))
fi

sd="$ROOT/.agents/skills"
if [ -d "$sd" ]; then
  SKIPPED=$((SKIPPED + 1)); echo '  skip  .agents/skills/（已存在）'
elif [ "$DRY" -eq 1 ]; then
  echo '  [dry-run] 创建 .agents/skills/ + .gitkeep'; CREATED=$((CREATED + 1))
else
  mkdir -p "$sd"; touch "$sd/.gitkeep"
  echo '  create .agents/skills/.gitkeep'
  CREATED=$((CREATED + 1))
fi

if [ -d "$ROOT/docs" ]; then
  mk ".agents/skills/$REPO-docs/SKILL.md" <<EOF
---
name: $REPO-docs
description: $REPO 的 docs/ 项目数据：域目录表、lint/收集脚本路径、本仓例外；通用规范机制见全局 docs-spec §1–§7，本文件严禁复制规范正文。
---

# $REPO · docs/ 项目数据

> 规范机制（frontmatter 时效 / 落点与切片命名 / Mermaid / Tombstone / 引用移动与索引 / 写后自检）见全局 \`docs-spec\` §1–§7——**本文件只写项目数据**。

## 域目录表（待补：从 docs/ 现状提炼）
| 域 | 定位 |
|---|---|
| _待补_ | 新文档落点先查项目索引 skill |

## lint / 收集脚本（待补：无则删本节）
- 待补

## 本仓例外（待补：无则删本节）
- 待补
EOF
else
  echo '  skip  docs 数据 skill（项目无 docs/，按 dev-init §1 第 5 步不留空位）'
fi

if [ "$DRY" -eq 1 ]; then
  echo '  [dry-run] 调用 toolbox init --project'
elif command -v toolbox >/dev/null 2>&1; then
  if (cd "$ROOT" && toolbox init --project >/dev/null 2>&1); then
    echo '  ok     toolbox 项目池 scripts/agent-tools/'
  else
    echo '  warn   toolbox init --project 未成功（可稍后手动执行）'
  fi
else
  echo '  skip   toolbox 不可用，跳过项目池（安装后手动 toolbox init --project）'
fi

echo
echo "==> 完成：创建 $CREATED 项，跳过 $SKIPPED 项（幂等，未覆盖任何已有文件）"
echo "==> 待人工取证（脚本不代劳，见 dev-init §1）："
echo "    1) workflow 事实源 skill：模块结构 / 包名 / 构建测试命令 / 环境硬约束（命令至少实测跑通一条）"
echo "    2) 项目索引 skill 归属表内容：按 project-index 只登记域级锚点，禁止一次性铺满"
echo "    3) 代码写法规范 skill：从现有代码提炼（无则跳过）"
echo "==> 收尾验证：toolbox run cl（骨架应判合规）"
exit 0
