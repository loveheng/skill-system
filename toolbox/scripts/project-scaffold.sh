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
  .agent-patch.json                   safe-patcher 项目继承骨架：指纹探测 languages，
                                      hooks 留空待人工填（机制见全局 safe-patcher --help）
  .agents/skills/                     目录 + .gitkeep（空目录不入 git）
  三模板骨架（workflow/index/docs skill）源 = skills/dev-init/templates/*.template.md（SSOT，
  脚本只搬运 + 替换 <repo> 占位符；缺模板库则跳过并提示手工复制）
  .agents/skills/<repo>-workflow/SKILL.md  通用骨架：只出节位与指针，事实位「待补」（维护协议内聚）；
                                      读码纪律三段式已预填通用正文（项目只补实证锚点）
  .agents/skills/<repo>-index/SKILL.md     通用骨架：规约指针 + 索引数据文件位「待补」
  .agents/skills/<repo>-docs/SKILL.md 恒定创建（scaffold 恒产出 docs/ 最小集，见下）；
                                      文档评估方法论已预填通用正文（项目只补实证锚点）
  docs/ 最小集恒定创建：README.md 结构索引 + project/index.md（索引数据表头，frontmatter status: draft）+ project/coding-standards.md（写法规范骨架，条款随代码提炼增量长，禁预写空泛条目）；
  其余域（architecture/ 等）仍按项目类型人工生成（dev-init §1 第 5 步）
  scripts/agent-tools/                调用 toolbox init --project（toolbox 可用时）

不做（骨架已生成，内容必须人工取证后填入，脚本只列清单）:
  workflow 事实位：模块结构/包名/构建命令（需实测跑通）
  项目索引数据：归属表内容（需读代码提炼，禁止铺满）
  代码写法规范 skill（需从现有代码提炼；无则整份跳过）

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
  mkdir -p "$T/docs"   # 触发 docs 数据 skill 分支（含文档评估方法论预填）
  r=0
  sh "$SELF" --root "$T" >/dev/null 2>&1 || r=$?
  [ "$r" -eq 0 ] || { echo "fail: 骨架生成退出码 $r"; rm -rf "$T"; return 1; }
  for f in context/CURRENT context/epics/misc/memory.md context/epics/misc/devlog.md \
           context/lessons.md context/decisions.md context/todos.md context/done.md \
           .uncertainty-whitelist .degrade-whitelist .agent-patch.json \
           .agents/skills/.gitkeep ".agents/skills/$(basename "$T")-workflow/SKILL.md" \
           ".agents/skills/$(basename "$T")-index/SKILL.md" \
           ".agents/skills/$(basename "$T")-docs/SKILL.md"; do
    [ -f "$T/$f" ] || { echo "fail: 缺产出 $f"; rm -rf "$T"; return 1; }
  done
  grep -q '文档评估方法论' "$T/.agents/skills/$(basename "$T")-docs/SKILL.md" || { echo 'fail: docs skill 缺文档评估方法论节'; rm -rf "$T"; return 1; }
  grep -q '"hooks": *\[\]' "$T/.agent-patch.json" || { echo 'fail: .agent-patch.json 缺空 hooks'; rm -rf "$T"; return 1; }
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$T/.agent-patch.json" 2>/dev/null \
    || { echo 'fail: .agent-patch.json 非法 JSON'; rm -rf "$T"; return 1; }
  grep -q '^epic: misc$' "$T/context/CURRENT" || { echo 'fail: CURRENT 内容不符'; rm -rf "$T"; return 1; }
  grep -q '读码纪律' "$T/.agents/skills/$(basename "$T")-workflow/SKILL.md" || { echo 'fail: workflow skill 缺读码纪律节'; rm -rf "$T"; return 1; }
  grep -q '定位边界' "$T/.agents/skills/$(basename "$T")-workflow/SKILL.md" || { echo 'fail: workflow skill 缺定位边界节（模板搬运失效？）'; rm -rf "$T"; return 1; }
  grep -q '架构债' "$T/.agents/skills/$(basename "$T")-index/SKILL.md" || { echo 'fail: index skill 缺架构债表（模板搬运失效？）'; rm -rf "$T"; return 1; }
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

# ---- 骨架模板（context/ 记忆骨架=资产层：toolbox/templates/{scaffold,todos}，随 ~/.agents 仓库同步；脚本只留渲染落盘）----
# 渲染契约 = toolbox/lib/render.sh（render_tpl/render_std/tpl_check + 残留 {{ 校验 + 转义，占位符规格见 templates/README.md）
TPL_ROOT="$(cd "$(dirname "$SELF")/.." && pwd)/templates"
LIB_DIR="$(cd "$(dirname "$SELF")/.." && pwd)/lib"
[ -f "$LIB_DIR/render.sh" ] || { echo "ERROR: 渲染器缺失: $LIB_DIR/render.sh"; echo '[remedy] 渲染器应随 ~/.agents 仓库同步；重新同步或补齐后重跑'; exit 2; }
. "$LIB_DIR/render.sh"
_today=$(date +%F)
tpl_check "$TPL_ROOT/scaffold/current.md" "$TPL_ROOT/scaffold/memory-misc.md" \
  "$TPL_ROOT/scaffold/devlog-misc.md" "$TPL_ROOT/scaffold/lessons.md" \
  "$TPL_ROOT/scaffold/decisions.md" "$TPL_ROOT/scaffold/done.md" \
  "$TPL_ROOT/scaffold/uncertainty-whitelist.txt" "$TPL_ROOT/scaffold/degrade-whitelist.txt" \
  "$TPL_ROOT/scaffold/agent-patch.json" "$TPL_ROOT/scaffold/docs-readme.md" \
  "$TPL_ROOT/scaffold/docs-index.md" "$TPL_ROOT/scaffold/coding-standards.md" \
  "$TPL_ROOT/todos/global.md"

# 模板源 SSOT：skills/dev-init/templates/（脚本只搬运 + 替换 <repo> 占位符，不内联规范正文）
TMPLDIR=""
for cand in "$HOME/.agents/skills/dev-init/templates" "$(cd "$(dirname "$SELF")/../skills/dev-init/templates" 2>/dev/null && pwd)"; do
  [ -f "$cand/workflow.template.md" ] && { TMPLDIR=$cand; break; }
done
[ -n "$TMPLDIR" ] || echo "  warn   未找到 dev-init 模板库（~/.agents/skills/dev-init/templates），三模板骨架将跳过"

mk_tmpl() {
  rel=$1; tf=$2; dst="$ROOT/$rel"
  if [ -f "$dst" ]; then
    SKIPPED=$((SKIPPED + 1))
    echo "  skip  $rel（已存在，不覆盖）"
    return 0
  fi
  if [ ! -f "$TMPLDIR/$tf" ]; then
    SKIPPED=$((SKIPPED + 1))
    echo "  warn  $rel（缺模板 $TMPLDIR/$tf，请从 dev-init templates/ 手工复制）"
    return 0
  fi
  if [ "$DRY" -eq 1 ]; then
    echo "  [dry-run] 创建 $rel"
    CREATED=$((CREATED + 1))
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  sed "s|<repo>|$REPO|g" "$TMPLDIR/$tf" > "$dst"
  echo "  create $rel"
  CREATED=$((CREATED + 1))
}

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

if [ "$DRY" -eq 1 ]; then echo "==> 项目根: $ROOT（dry-run，不落盘）"; else echo "==> 项目根: $ROOT"; fi

render_std "$TPL_ROOT/scaffold/current.md" | mk 'context/CURRENT'

render_std "$TPL_ROOT/scaffold/memory-misc.md" | mk 'context/epics/misc/memory.md'

render_std "$TPL_ROOT/scaffold/devlog-misc.md" | mk 'context/epics/misc/devlog.md'

render_std "$TPL_ROOT/scaffold/lessons.md" | mk 'context/lessons.md'

render_std "$TPL_ROOT/scaffold/decisions.md" | mk 'context/decisions.md'

render_std "$TPL_ROOT/todos/global.md" | mk 'context/todos.md'

render_std "$TPL_ROOT/scaffold/done.md" | mk 'context/done.md'

render_std "$TPL_ROOT/scaffold/uncertainty-whitelist.txt" | mk '.uncertainty-whitelist'

render_std "$TPL_ROOT/scaffold/degrade-whitelist.txt" | mk '.degrade-whitelist'

# safe-patcher 项目 hook 骨架：按指纹文件探测技术栈写入 languages；hooks 留空待人工填
# （机制见全局 safe-patcher --help：写入前在内置语法预检之后执行 hooks 专属校验）
ap="$ROOT/.agent-patch.json"
if [ -f "$ap" ]; then
  SKIPPED=$((SKIPPED + 1)); echo '  skip  .agent-patch.json（已存在，不覆盖）'
elif [ "$DRY" -eq 1 ]; then
  echo '  [dry-run] 创建 .agent-patch.json'
  CREATED=$((CREATED + 1))
else
  langs=""
  for pair in 'python:pyproject.toml setup.py requirements.txt Pipfile' \
              'typescript:tsconfig.json' \
              'javascript:package.json' \
              'go:go.mod' \
              'rust:Cargo.toml' \
              'java:pom.xml build.gradle build.gradle.kts'; do
    lang=${pair%%:*}
    for marker in ${pair#*:}; do
      if [ -e "$ROOT/$marker" ]; then
        langs="$langs,\"$lang\""
        break
      fi
    done
  done
  [ -n "$langs" ] && langs=${langs#,} || langs='"generic"'
  mkdir -p "$ROOT"
  render_std "$TPL_ROOT/scaffold/agent-patch.json" "LANGS=$langs" > "$ap"
  echo '  create .agent-patch.json'
  CREATED=$((CREATED + 1))
fi

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

mk_tmpl ".agents/skills/$REPO-docs/SKILL.md" docs.template.md

render_std "$TPL_ROOT/scaffold/docs-readme.md" "REPO=$REPO" "DATE=$_today" | mk "docs/README.md"

render_std "$TPL_ROOT/scaffold/docs-index.md" "REPO=$REPO" "DATE=$_today" | mk "docs/project/index.md"

render_std "$TPL_ROOT/scaffold/coding-standards.md" "REPO=$REPO" "DATE=$_today" | mk "docs/project/coding-standards.md"

mk_tmpl ".agents/skills/$REPO-workflow/SKILL.md" workflow.template.md

mk_tmpl ".agents/skills/$REPO-index/SKILL.md" index.template.md

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
echo "==> 待人工取证（骨架已生成，填内容即可，见 dev-init §1）："
echo "    1) <repo>-workflow/SKILL.md 事实位：项目一句话 / 环境硬约束 / 构建测试命令（至少一条实测跑通）"
echo "    2) <repo>-index/SKILL.md：索引数据文件路径 + 归属表内容（按 project-index 只登记域级锚点，禁止铺满）"
echo "    3) 代码写法规范 skill：从现有代码提炼（无则跳过）"
echo "==> 收尾验证：toolbox run cl（骨架应判合规）"
exit 0
