# 命令手册
---
status: active
updated: 2026-10-07
---

> **定位**：全体系命令面（skill 指令 + toolbox CLI + 会话口令 + skill 加载操作）的统一速查，按命令归拢语法与口径，无教学论述。各 skill 正文 §节为唯一规范事实源，本文冲突以正文为准；设计意图与体系导航见 `README.md`。条目为浓缩速查（dev-loop §9 薄指针铁律的登记例外），语义漂移由 `::audit` 第 9 项抽查兜底。

## 0. 命令总表

| 命令 | 归属 | 职责 | 触发 |
|---|---|---|---|
| `::file` `::bind` | dev-loop | 绑定/切换 epic | 仅用户 |
| `::remember` `::adr` `::next` `::status` `::board` | dev-loop | 记忆 / 决策档案 / 断点规划 / 快照 / 任务看板（多任务并行选择入口） | 仅用户 |
| `::merge` | dev-loop | 手动归并（自动触发的人工覆盖口） | 仅用户 |
| `::confirm [事项]` | dev-loop | 决策点台账兜底：AI 漏走台账流程时补登记 `context/pending-confirm.md` + 分级确认（dev-loop §2 第 6 条） | 仅用户 |
| `::audit` `::verify` `::done` | dev-loop | 质检 / 对账 / 收尾 | 仅用户，Agent 严禁自主执行 |
| `::help` | dev-loop | 面板（panel 事实 + AI 判读）+ 指令总表（求助入口） | 仅用户 |
| `::todo` `::todos` `::tdone` `::todo-clean` `::todo-groom` | memo-collector | 待办增/查/结/清/洗 | 仅用户 |
| `toolbox <cmd>`（命令面 SSOT：`toolbox --help`） | agent-toolbox | 脚本工具池管理（生命周期 / 发现执行 / 钩子） | 人机同权 |
| `toolbox run uscan\|dscan\|hyg\|dtrig` | ai-sideeffect-guard | AI 副作用四工具扫描（不确定 / 静默降级 / 残留 / 运行时触发） | 人机同权 |
| 恢复口令「继续」等 | dev-loop | 会话恢复（收尾自动出会话绑定卡） | 仅用户 |

**记法约定**：用户指令一律以 `::` 前缀书写（如 `::bind`、`::todo`），与 `toolbox` CLI 子命令（无前缀，如 `toolbox check`）区分。**解析契约**：`::` 兼容全角 `：：`；指令动词后接空白/冒号/换行（**非 `(`**），以与代码作用域 `::ident()` 区分；仅命中白名单动词（bind/remember/adr/next/status/board/merge/audit/verify/done/help/confirm/file/todo/todos/tdone/todo-clean/todo-groom）方视为指令。

## 1. dev-loop 指令（编码会话，作用于当前项目 `context/`）

### `::file <名>` / `::bind` —— 绑定/切换 epic（dev-loop §3）
- 行为：改写 `context/CURRENT` 为 `epic: <名>`；**正式 epic 必须挂底子文档（文档锚定）**——`::bind` 先跑 `panel --mounts` 取候选列表与挂载对照（deprecated 墓碑不可挂；▶已挂 = 已有 epic，续绑或归档重开），**epic 名 = 文档 slug**，骨架 memory.md 首部 `- [挂载] <路径>`；候选空/不合适 → 亮牌先建文档再挂载（初稿提炼自讨论，严禁占位文案；冷 bind 走反向采访）。
- 机械件：选定后 `toolbox run mount-init --epic <名> --doc <文档>`（候选空加 `--create-doc`）一键落骨架与 CURRENT——slug/墓碑/重复挂载/切换前置由脚本拦截，AI 零拼装；仅切指针用 `--current-only`。
- 内容/状态分工：底子文档 = 内容 SSOT（即写即落，方案权衡走 ::adr），memory 只记状态，严禁双写（dev-loop §3「文档挂载纪律」）。
- 切换前置：旧 epic devlog 有未归并条目 → 先归并再切换，不留跨会话积压。
- 裸调用 `::file`（无参）：只读列出 `ls context/epics/` 候选与当前绑定，不写任何文件；带名直接调用仍可用（用户显式指令优先），AI 顺带校验/补挂载行。
- 示例：`::bind`（出候选选择）；散修/小改动不建 epic，直接说需求（自动挂 misc，无挂载）。

### `::remember <事实>` —— 人工记忆入口（dev-loop §6）
- 行为：结论直接写入绑定 epic 的 `memory.md` 正文（`- [YYYY-MM-DD] <事实>` 或归入相应小节）；用户发起即视为确认。影响下一步则同轮刷新断点；**不写 devlog**。

### `::adr <标题>` —— 决策洞察档案（dev-loop §6）
- 行为：本窗口刚敲定的方案权衡落 `context/decisions.md`，按 epic 分节 + `## misc` 兜底，节内最新在上；条目固定四段：场景痛点 / 可选方案（含否决理由）/ 最终决定 / AI 洞察。
- 护栏：只写不读——不进裁决链、归并不回改、恢复不读；若约束后续工作，同轮经 `::remember` 单向写一行契约进 memory。

### `::next [方向]` —— 断点规划（dev-loop §6）
- 断点明确未过期 → 报告内容确认开工；空/过期 → 读 memory 正文 + devlog 尾部推 **≤3 个候选**（各一行理由），选定后落盘为断点再开工。
- 候选取用优先级见 memo-collector §5（`(block)` 条目绝对优先）。规划结果必须落盘为断点。

### `::status` —— 运行态快照（dev-loop §6）
- 一条调用链只读返回：CURRENT、断点行、devlog（绑定 epic 与 misc）与 lessons 待归并计数、memory 行数。**输出 ≤5 行**。

### `::board` —— 任务看板（dev-loop §6）
- 数据源 `toolbox run panel --board`（未入池环境降级 ls+grep 现场推导）：逐任务一行（最后活动日期 + 断点），当前绑定标 ▶、misc 标常驻；零缓存，严禁维护存储式看板文件。
- AI 按面板判读协议渲染，末尾附跨 AI 恢复咒语：`读 context/epics/<任务名>/memory.md 按断点继续`；选定后走 `::bind <任务>` 正常绑定。

### `::confirm [事项]` —— 决策点台账兜底（dev-loop §2）
- AI 漏走台账流程（只出决策点清单未登记、或多个决策点混在一问）时手动触发：补登记 `context/pending-confirm.md` 全部决策点 → 按 §2 分级口径从 [1/N] 开始逐项确认。
- 带参数时仅登记该事项为单条台账并立即抛问。

### `::merge` —— 手动归并（dev-loop §4）
- 行为：双文件压缩——① 绑定 epic devlog 提炼进 `memory.md` 并清空追加区（`[SSOT 修正]` 条目最高优先级，严禁新旧并存）；② `lessons.md` 底部流水去重归纳进正文；两处头部 `total-merged`+1、`last-merge` 刷新。
- 与自动触发（任一日志 ≥5 条）同一套流程；misc 挂靠日志同样适用。

### `::audit` —— 十二项质检（dev-loop §7）
- **账账相符**（记忆与 skill 文档内部一致）逐项输出 `✓/⚠ + 动作建议`：断点新鲜度 / 新旧并存 / devlog 积压 SSOT 修正 / 记忆补记 / lessons 与规范去重 / 尺寸健康（memory >150 行 ⚠）/ 孤儿 epic / 头部校验 / 指针抽查 / skill 卫生（事实指针化 + description 预算）/ toolbox 巡检 / 验证缺口抽查（[变更] 行各有同日 [验证] 账本）。
- 建议时机：多机同步、分支切换、久别重开后。**Agent 严禁自主执行**；琐碎修复列清单经确认当场执行。

### `::verify <epic|lessons|all>` —— 账实对账（dev-loop §7）
- 验 memory 断言 vs 代码现实，仅限可机械定位的断言（类名/路径/属性/阈值）；三态输出 ≤15 行：`✅ 仍成立` / `❌ 已失效（附证据行）` / `❓ 无法机械验证（交人工）`。❌ 项经确认批量 `[SSOT 修正]`。**仅用户显式触发**。

### `::done` —— epic 收尾（dev-loop §8）
- 第一步强制 `::audit`，有 ⚠ 即中止先修复；通过后 memory 提炼 ≤10 行、目录移入 `context/archive/<名>/`（decisions 同步随迁）、CURRENT 改 `epic: none`。
- misc 常驻不适用；收尾联动 memo-collector（该 epic 待办节清零）。**Agent 严禁自主执行**。

### `::help` —— 面板入口（dev-loop §6）
- 数据源 `toolbox run panel` 事实块（绑定/断点/任务活动/计数）+ AI 判读渲染：建议动作结合语境自产（≤3 条），命令速查按意图分组；**全量命令清单（含含义）仅显式索要时经 `toolbox run cmds` 机械收集本文件派生**，零缓存防枚举漂移。
- 新会话 / 跨 IDE 时的第一句求助语；**忘命令时只记 ::help**。

## 2. memo-collector 指令（备忘台账，作用于 `<项目>/context/`）

数据文件：两级待办——`context/epics/<名>/todos.md`（域内，按需创建）+ `context/todos.md`（全局 `## misc` 兜底：散修/跨域/项目级）+ `context/done.md`（完成，append-only 全局）；机械件 `toolbox run todos`（add/done/rm/move/list，list=聚合视图）。条目行格式：`- [ ] [YYYY-MM-DD] (<类型>) [(block)] <一句话事项> (src: ai | 用户)`；类型固定七种：功能/修复/优化/文档/环境/测试/风险（memo-collector §0）；生命周期标注 `[once]`/`[long]`（memo-collector §0）——once 事件确认后自动转 done、过期附注建议清除；long 每个 ::done 强制重评。

| 指令 | 行为 | 口径要点 |
|---|---|---|
| `::todo <事项>` | 追加待办 | 按 memo-collector §0 路由规则判域 → `todos add --to <epic名\|misc>` 落盘（域内=epic 可独立解决项；全局=misc/跨域/项目级）；口述即确认，无二次询问 |
| `::todos [域]` | 只读展示 | `todos list` 机械聚合（全局+域文件并列，带临时编号 `#1 #2…`）；空则回「待办列表为空」 |
| `::tdone <编号\|关键词>` | 完成流转 | `todos done` 移入 done.md（记来源域）；关键词歧义列候选让用户选 |
| `::todo-clean` | 清理待办 | 列全量 → 用户勾选 → 逐条 `todos rm`（**需确认**，破坏性） |
| `::todo-groom` | 语义洗盘 | 合并同类项直接执行（注明「并入自 X」）；疑似过期/已完成项列出让用户确认；任一文件 >10 条时附注建议 |

自动面（无需指令，memo-collector §1/§2）：回复含待办/风险/未验证假设/测试启发类信号时在触发点批量落盘（子任务收尾 / 显式搁置 / 显式指令，严禁逐轮碎写）；轮内完成条目自动流转 done.md；任何调阅前先回收人工打勾 `[x]` 条目（脏读校验）——`[x]` 是人类专用通道，AI 严禁写。

## 3. toolbox 元工具 CLI（跨项目，人与 AI 共用）

入口 shim：`~/.local/bin/toolbox`（无 AI 时 `toolbox --help` 即说明书；`toolbox <cmd> --help` 即该命令手册）。全局池 `~/.agents/toolbox/scripts/`，项目池 `<repo>/scripts/agent-tools/`（同名覆盖全局）。

**命令面（薄指针，防双源）**：子命令清单、语法与参数一律以 `toolbox --help` / `toolbox <cmd> --help` 为唯一事实源——**命令增删只改元工具与 `agent-toolbox` SKILL.md「命令面」节，本文不再逐条枚举**（历史教训：枚举版曾停在 9 个子命令，实际已 14 个）。当前分组仅供导航：

| 组 | 子命令 | 用途 |
|---|---|---|
| 生命周期 | `init` / `new` / `check` / `remove` | 初始化池与 shim、生成脚手架、门禁登记入池、退役入 `.trash`（登记新能力与退役均需确认） |
| 发现与执行 | `list` / `suggest` / `run` / `recent` / `propose` / `approve` | 现场派生清单（无注册表）、按类别推荐、运行工具（支持别名与 `KEY=value` 内联参数）、近期使用摘要、提案入队与批量审批 |
| 钩子与规范 | `run-hooks` / `install-hooks` / `spec` / `self-test` | 钩子批量执行（任一 FAIL → exit 1）、接线 profile/cron/pre-commit、规范 SSOT、元工具自检 |

**退出码契约**（元工具与所有池内工具一致）：`0` 通过 / `1` 检查未通过 / `2` 自身故障。`run-hooks` 中工具 FAIL → exit 1（供门禁拦截）；工具自身故障 → ERROR 可见但 fail-open 不阻塞。

**既有接线**（dev-loop，唯一侵入点）：会话开场 `toolbox run-hooks bootstrap --quiet`（用户级开场协议 AGENTS.md 已内嵌本钩，同窗口不重复跑；exit 0 静默继续；非 0 不阻塞恢复，仅附一行 ⚠）；`::audit` 第 11 项 `toolbox run-hooks audit --quiet`。钩子 FAIL 按 memo-collector 口径转 `风险` 待办；`--quiet` 静默一切输出，只以退出码判定（需明细去掉 `--quiet` 重跑）。

**池内工具**：全量清单 `toolbox list` 现场派生（零注册表，防枚举漂移），用法 `toolbox run <工具> --help`；**流程接线**（哪个钩子/流程挂哪些工具）唯一事实源 = agent-toolbox SKILL.md「接线」节，本文件不复制清单。常用入口导航：开场/恢复卡与 `::help`/`::board`/`::bind` 候选 → `panel`（`--root`/`--board`/`--deep`/`--debt`/`--mounts`；默认块含债行 U/D/P 粗计数+体检时效；事实脚本出、判断 AI 出，判读协议见 dev-loop §6）；记账与断点刷新 → `devlog`（dev-loop §2 单一入口）；`::help` 全量命令 → `cmds`（现场解析本文件 §1-§2，白名单↔明细双向对账、漂移即 ⚠）；audit 钩机械项 → `context-lint`（context 数据面 + skill 指针面 + 挂载行，裸跑=逐条明细）+ `admission-scan`（`ascan`，PATCH 债与补丁密度，solution-admission §5）；`::audit` 一键预检（机械项代跑 + 人判项标 ❓）→ `ctx-audit`（dev-loop §7）；副作用扫描 → `uscan`/`dscan`/`hyg`/`dtrig`（ai-sideeffect-guard §2）；docs 写后自检 → `docs-lint`（docs-spec §6）。项目池工具随各仓库版本化，以该仓库内 `toolbox list` 现场派生为准。

**副作用四工具速查**：`toolbox run uscan --md /tmp/uncertainty-report.md`（同族：`dscan` / `hyg` / `dtrig`；命中 exit 1，`--self-test` 自诊断）——会话中按需只跑与本轮改动相关的 1 个，`::done`/`::audit`/发布前全跑四个；标记约定与处置口径见 ai-sideeffect-guard §1/§2/§4。

## 4. 会话口令与 skill 加载

**会话恢复口令**（无状态恢复，配合 context/CURRENT；恢复流收尾自动出**会话绑定卡**——域/类型/挂载/状态四行，协议见 dev-loop §3「会话绑定」）：

| 场景 | 口令 |
|---|---|
| 编码会话恢复 | `继续` 或 `读 context/CURRENT，开始下一个子任务：<xxx>` |
| 多任务选任务 / 跨 AI 恢复 | `::board`（无本体系的 AI：「列出 context/epics/ 各任务断点」）→ 选定后 `读 context/epics/<任务>/memory.md 按断点继续` |
| 跨 IDE / 新会话求助 | `::help` |
| 非 ZCode 工具开场 | 项目 AGENTS.md「会话初始化」节自动生效（dev-init §1 第 8 步模板）；无该节时开场说「先读 ~/.agents/skills/dev-loop/SKILL.md 再开工」 |

**空白窗口零记忆起步**：ZCode 用户级 `~/.zcode/AGENTS.md`（SSOT `~/.agents/AGENTS.md`，改动后 `cp` 同步）每窗口自动注入开场协议——有 `context/` 即自动出**会话绑定卡**，无则静默；任何口令都不需要记。该文件为跨工具同文，可直接装入其他 AI 工具的全局指令（如 `~/.claude/CLAUDE.md`）。

**skill 加载三方式**（README §1.4/§1.6）：

1. **自动路由**：请求与 skill description 匹配时自动加载（基准行为，无需操作）；
2. **显式调用**：对话中点名加载，如「加载 dev-guide 按 §一 流程推进」；
3. **跨 IDE 兑底**（自动路由失效时，功能不降级）：prompt 中 `@文件`（IDE 原生引用语法，非本体系 `::` 指令）或给路径——「先读 `~/.agents/skills/<name>/SKILL.md` 再开工」（global）；项目内为 `<repo>/.agents/skills/<name>/SKILL.md`。

**skill 清单速览**：global skill（10 个，跨项目机制）见 `~/.agents/skills/`（每目录一个 SKILL.md）；项目专属规范 skill 与功能归属索引（project-local）在各仓库 `<repo>/.agents/skills/`。各 skill 职责与触发时机速查见 `README.md` §二，场景 → 入口速查见 §3.3。

## 5. 触发权限矩阵（通用纪律）

| 级别 | 内容 |
|---|---|
| Agent 自动执行 | 日志追加落盘、≥5 条自动归并（⚙️ 附注）、断点刷新、备忘自动收集与完成流转、人工打勾回收、开场 `bootstrap` 钩子、文档联动**提示**、咒语→skill 进化**建议**、收尾生成 git 指令建议（**生成不执行**）、越界失败自动暂停（并行窗口纪律 ⑥——只停不改，等用户授权） |
| 仅用户显式触发 | 全部 §1–§2 指令；其中 `::audit` `::verify` `::done` 为 Agent **严禁自主执行**红线 |
| 需用户确认后执行 | 一切修复落盘、批量删除（::todo-clean）、批量 `[SSOT 修正]`、`toolbox check` 新能力 / `remove` / `install-hooks`、破坏性操作（删表/清队列/强推分支） |
| 人类专用通道 | `todos.md` 中的 `[x]` 打勾（AI 只回收不书写）；`archive/` 翻档 |
