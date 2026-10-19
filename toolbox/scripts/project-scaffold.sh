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
  .agents/skills/<repo>-workflow/SKILL.md  通用骨架：只出节位与指针，事实位「待补」（维护协议内聚）；
                                      读码纪律三段式已预填通用正文（项目只补实证锚点）
  .agents/skills/<repo>-index/SKILL.md     通用骨架：规约指针 + 索引数据文件位「待补」
  .agents/skills/<repo>-docs/SKILL.md 仅当存在 docs/ 时创建（数据位待补，规范指针回 docs-spec）；
                                      文档评估方法论已预填通用正文（项目只补实证锚点）
  docs/project/index.md               仅当存在 docs/ 时创建（索引数据文件表头骨架，frontmatter status: draft）；
  无 docs/ 不生成空骨架——初始域结构按项目类型人工生成（dev-init §1 第 5 步）
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
  cat > "$ap" <<EOF
{
  "_comment": "safe-patcher 项目继承配置（全局脚本写盘前执行 hooks 校验）。languages 由脚手架按指纹探测，仅供 AI 参考技术栈；hooks 每项 {match: 正则(匹配仓库相对路径,空=全部), run: 命令({file} 占位), timeout: 秒(默认60)}，任一失败即拒绝写入。禁预置校验命令——先确认本仓工具链可用再填。",
  "languages": [$langs],
  "hooks": []
}
EOF
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

## 文档评估方法论（通用骨架，随项目收敛）
评估目的不是判断文档好坏，而是决定**依赖深度**。六维判据：

| 维度 | 判据 |
|---|---|
| D1 时效性 | frontmatter updated/last-merge 是否落后于代码实际变更；devlog 后续 [变更] 是否未回填 |
| D2 账实一致性 | 可机械定位断言（类名/路径/行号/阈值/开关）对代码实证，三态 ✅/❌/❓ |
| D3 单源状态 | 同主题有无矛盾表述（新旧并存）；指针能否 grep 定位 |
| D4 决策状态 | 结论「已拍板/待裁决/已废弃」是否显式；评估与实施是否分开陈述 |
| D5 验证账本 | 变更是否有成对 [验证]；「未执行」是否带原因+自证条件 |
| D6 信息密度 | 每条陈述是否携带可行动信息；有无遥测式重复 |

依赖分级（评估输出）：L3 可直接依赖（六维全过，作设计前提）｜L2 抽查依赖（关键断言动手前实证）｜L1 仅线索（过期/缺验证/状态不明任一命中，一切以代码为准）。

使用时机：① 依赖前——文档建图时顺带分级（读码纪律配套）；② 变更后——触及断言同轮 SSOT 回填；③ 收尾时——::audit 机械项覆盖 D2/D3，本方法论补 D1/D4/D5/D6 人判口径。

收敛：踩过「文档失真」实例时把实证锚点补进判据列（样例：goodhub-docs）。
EOF
else
  echo '  skip  docs 数据 skill（项目无 docs/，按 dev-init §1 第 5 步不留空位）'
fi

if [ -d "$ROOT/docs" ]; then
  mk "docs/project/index.md" <<EOF
---
status: draft
updated: $(date +%F)
---

# $REPO · 功能落点索引（数据）

> 索引数据文件（唯一数据源）；登记规约 = \`<repo>-index\` skill，机制正文 = 全局 \`project-index\`。增量登记，禁止一次性铺满。

## 代码落点

| 功能 | 代码落点 | 备注 |
|---|---|---|
| _待补_ | | |

## 文档落点

| 主题 | 文档路径 | 状态 |
|---|---|---|
| _待补_ | | |
EOF
fi

mk ".agents/skills/$REPO-workflow/SKILL.md" <<EOF
---
name: $REPO-workflow
description: $REPO 工作流事实源：构建/测试/运行命令唯一出处、环境硬约束。构建报错、跑测试、换机器前先读，命令勿凭记忆写。（待补一句话项目定位）
---

# $REPO · 工作流事实源

> 本文件是项目工作流**唯一出处**：事实位填实测取证结果，严禁虚构；工具链踩坑数据归 \`context/lessons.md\`（本文件只写维护协议，不复制坑正文）。三件套分工：写码规则归规范 skill（未建规范 skill 则删本句）、改前定位归索引 skill、命令与环境归本文件。

## 项目一句话（待补）
- 待补（一句定位：这是什么、技术栈、与外部系统的接缝）

## 环境硬约束（待补：实测取证）
- 待补（工具链位置、平台限制、无 X 环境时的唯一替代验证途径）

## 研发闭环命令（唯一出处，待补：至少一条实测跑通）
- 待补（提交前质检 / 本地运行 / 打包发布，按耗时从小到大排序）

## lessons 维护协议（通用骨架，随项目收敛）
- 数据住 \`context/lessons.md\`，协议住本文件：写前检索（动高风险模块前）→ 排障检索（报错关键字全字匹配）→ 升维销项（解法挂回归钉子）。
- 录入门槛：排查 >15min 的确定性故障同轮沉淀；临时抖动、情绪流水账、泛泛建议不记。

## 读码纪律（通用骨架，随项目收敛）
- 三段式：① 文档建图——先读项目索引/记忆/devlog 拿「为什么/边界/落点」；② 定向读码——LSP/semantic search 只读相关符号与区域（readSymbol/行号范围），禁整文件通读；③ 关键断言实证——文档每个「已实现」结论动手前抽查一处代码确认，行号引用须实测（会漂移）。
- 判据：「文档+定向读码」比「通读代码」省 token；「只读文档」省的是阅读成本、付的是正确性风险（文档有损且可能失真，返工远超省下的 token）。
- 收敛：踩过「文档失真/行号漂移」实例时把实证锚点补进本节（样例：goodhub-workflow 读码纪律节）。
EOF

mk ".agents/skills/$REPO-index/SKILL.md" <<EOF
---
name: $REPO-index
description: $REPO 的「功能 → 代码落点 + 文档落点」索引规约——本文件只登记表结构与登记纪律；索引数据一律住索引数据文件，本文件不复制数据（防双源）。改功能落点、新增文档前先读规约与数据。
---

# $REPO · 功能落点索引（规约）

> 机制（表格式规范、增量登记纪律）见全局 \`project-index\` skill，本文件不复制其正文。

## 1. 索引数据文件
- \`docs/project/index.md\`（存在 \`docs/\` 时已由 scaffold 生成表头骨架；无 \`docs/\` 则待补路径并手工建）

## 2. 登记纪律（通用骨架）
- 增量登记，禁止一次性铺满：表随实现长出来。
- 一行一功能：落点精确到文件（仓库相对路径，禁绝对路径）；备注只放定位后必读的指针。
- 禁写施工过程（日期/切片号/PR 记录）与易腐数字；失效落点同轮即修，不留「待对账」。

## 3. 维护协议（通用骨架）
- 改前先查索引；跨域改动先登记再动手。
- 索引体检：epic 收尾对账一次——落点路径存在性抽查、活跃/归档比例。
EOF

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
