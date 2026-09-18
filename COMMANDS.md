# 命令手册
---
status: active
updated: 2026-09-19
---

> **定位**：全体系命令面（skill 指令 + toolbox CLI + 会话口令 + skill 加载操作）的统一速查，按命令归拢语法与口径，无教学论述。各 skill 正文 §节为唯一规范事实源，本文冲突以正文为准；设计意图与体系导航见 `README.md`。条目为浓缩速查（dev-loop §9 薄指针铁律的登记例外），语义漂移由 `@audit` 第 9 项抽查兜底。

## 0. 命令总表

| 命令 | 归属 | 职责 | 触发 |
|---|---|---|---|
| `@file` `@bind` | dev-loop | 绑定/切换 epic | 仅用户 |
| `@remember` `@adr` `@next` `@status` | dev-loop | 记忆 / 决策档案 / 断点规划 / 快照 | 仅用户 |
| `@merge` | dev-loop | 手动归并（自动触发的人工覆盖口） | 仅用户 |
| `@audit` `@verify` `@done` | dev-loop | 质检 / 对账 / 收尾 | 仅用户，Agent 严禁自主执行 |
| `@help` | dev-loop | 指令总表 + 绑定状态（求助入口） | 仅用户 |
| `@todo` `@todos` `@tdone` `@todo-clean` `@todo-groom` | memo-collector | 待办增/查/结/清/洗 | 仅用户 |
| `@bind` `@remember` `@forget` `@adr` `@next` `@status` `@merge` `@audit` `@verify` `@done` `@help` | copilot-context | 聊天域独立指令集（`context/chat/`；与 dev-loop 同名不同约） | 仅用户 |
| `toolbox init/new/check/list/run-hooks/install-hooks/spec/remove/self-test` | agent-toolbox | 脚本工具池管理 | 人机同权 |
| 恢复口令「继续」等 | dev-loop / copilot-context | 会话恢复 | 仅用户 |

**记法约定**：用户指令一律以 `@` 前缀书写（如 `@bind`、`@todo`），与 `toolbox` CLI 子命令（无前缀，如 `toolbox check`）区分。

同名指令跨 dev-loop 与 copilot-context 是**两个独立协议**（接口对齐、实现分治）：仅共享指令词汇表与命名空间边界——前者操作 `<项目>/context/`（`epic:` 指针），后者操作 `context/chat/`（`thread:` 指针），共处同一工作区时互不读写对方目录；各域指令语义以本域 skill 正文为唯一事实源，一侧修订不产生另一侧的联动义务。

## 1. dev-loop 指令（编码会话，作用于当前项目 `context/`）

### `@file <名>` / `@bind <名>` —— 绑定/切换 epic（dev-loop §3）
- 行为：改写 `context/CURRENT` 为 `epic: <名>`（忽略路径后缀，只取名）；目标目录不存在时创建骨架（带头部 `memory.md` + `devlog.md` + 断点初始行）。
- 切换前置：旧 epic devlog 有未归并条目 → 先归并再切换，不留跨会话积压。
- 裸调用 `@file`（无参）：只读列出 `ls context/epics/` 候选与当前绑定，不写任何文件。
- 示例：`@file e2ee-auth`；散修/小改动不建 epic，直接说需求（自动挂 misc）。

### `@remember <事实>` —— 人工记忆入口（dev-loop §6）
- 行为：结论直接写入绑定 epic 的 `memory.md` 正文（`- [YYYY-MM-DD] <事实>` 或归入相应小节）；用户发起即视为确认。影响下一步则同轮刷新断点；**不写 devlog**。

### `@adr <标题>` —— 决策洞察档案（dev-loop §6）
- 行为：本窗口刚敲定的方案权衡落 `context/decisions.md`，按 epic 分节 + `## misc` 兜底，节内最新在上；条目固定四段：场景痛点 / 可选方案（含否决理由）/ 最终决定 / AI 洞察。
- 护栏：只写不读——不进裁决链、归并不回改、恢复不读；若约束后续工作，同轮经 `@remember` 单向写一行契约进 memory。

### `@next [方向]` —— 断点规划（dev-loop §6）
- 断点明确未过期 → 报告内容确认开工；空/过期 → 读 memory 正文 + devlog 尾部推 **≤3 个候选**（各一行理由），选定后落盘为断点再开工。
- 候选取用优先级见 memo-collector §5（`(block)` 条目绝对优先）。规划结果必须落盘为断点。

### `@status` —— 运行态快照（dev-loop §6）
- 一条调用链只读返回：CURRENT、断点行、devlog（绑定 epic 与 misc）与 lessons 待归并计数、memory 行数。**输出 ≤5 行**。

### `@merge` —— 手动归并（dev-loop §4）
- 行为：双文件压缩——① 绑定 epic devlog 提炼进 `memory.md` 并清空追加区（`[SSOT 修正]` 条目最高优先级，严禁新旧并存）；② `lessons.md` 底部流水去重归纳进正文；两处头部 `total-merged`+1、`last-merge` 刷新。
- 与自动触发（任一日志 ≥5 条）同一套流程；misc 挂靠日志同样适用。

### `@audit` —— 十一项质检（dev-loop §7）
- **账账相符**（记忆与 skill 文档内部一致）逐项输出 `✓/⚠ + 动作建议`：断点新鲜度 / 新旧并存 / devlog 积压 SSOT 修正 / 记忆补记 / lessons 与规范去重 / 尺寸健康（memory >150 行 ⚠）/ 孤儿 epic / 头部校验 / 指针抽查 / skill 卫生（事实指针化 + description 预算）/ toolbox 巡检。
- 建议时机：多机同步、分支切换、久别重开后。**Agent 严禁自主执行**；琐碎修复列清单经确认当场执行。

### `@verify <epic|lessons|all>` —— 账实对账（dev-loop §7）
- 验 memory 断言 vs 代码现实，仅限可机械定位的断言（类名/路径/属性/阈值）；三态输出 ≤15 行：`✅ 仍成立` / `❌ 已失效（附证据行）` / `❓ 无法机械验证（交人工）`。❌ 项经确认批量 `[SSOT 修正]`。**仅用户显式触发**。

### `@done` —— epic 收尾（dev-loop §8）
- 第一步强制 `@audit`，有 ⚠ 即中止先修复；通过后 memory 提炼 ≤10 行、目录移入 `context/archive/<名>/`（decisions 同步随迁）、CURRENT 改 `epic: none`。
- misc 常驻不适用；收尾联动 memo-collector（该 epic 待办节清零）。**Agent 严禁自主执行**。

### `@help` —— 求助入口（dev-loop §9）
- 输出指令总表 + 当前绑定状态；新会话 / 跨 IDE 时的第一句求助语。

## 2. memo-collector 指令（备忘台账，作用于 `<项目>/context/`）

数据文件：`context/todos.md`（待办，按域分节，`## misc` 恒为末节）+ `context/done.md`（完成，append-only）。条目行格式：`- [ ] [YYYY-MM-DD] (<类型>) [(block)] <一句话事项> (src: ai | 用户)`；类型固定七种：功能/修复/优化/文档/环境/测试/风险（memo-collector §0）。

| 指令 | 行为 | 口径要点 |
|---|---|---|
| `@todo <事项>` | 追加待办 | 按域归属落节（域内挂 epic 节，散修/跨域挂 misc）；口述即确认，无二次询问 |
| `@todos [域]` | 只读展示 | 全量带临时编号 `#1 #2…`，可按域过滤；空则回「待办列表为空」 |
| `@tdone <编号\|关键词>` | 完成流转 | 从 todos.md 删除 + 追加 done.md（记来源域）；关键词歧义列候选让用户选 |
| `@todo-clean` | 清理待办 | 列全量 → 用户勾选 → 批量删除（**需确认**，破坏性） |
| `@todo-groom` | 语义洗盘 | 合并同类项直接执行（注明「并入自 X」）；疑似过期/已完成项列出让用户确认；任一节 >10 条时附注建议 |

自动面（无需指令，memo-collector §1/§2）：回复含待办/风险/未验证假设/测试启发类信号时在触发点批量落盘（子任务收尾 / 显式搁置 / 显式指令，严禁逐轮碎写）；轮内完成条目自动流转 done.md；任何调阅前先回收人工打勾 `[x]` 条目（脏读校验）——`[x]` 是人类专用通道，AI 严禁写。

## 3. copilot-context 指令（聊天/助理会话，作用于 `context/chat/`）

CURRENT 字段为 `thread: <主线名>`（日常默认 `thread: misc`）；数据落 `context/chat/threads/<主线>/memory.md`、`devlog.md`，全局单文件 `profile.md`（用户画像）、`lessons.md`、`decisions.md`（copilot-context §0）。

| 指令 | 聊天域口径 |
|---|---|
| `@bind <主线名>` | 绑定主线（thread）；切换前先归并旧主线，骨架落 `context/chat/threads/`（§3） |
| `@remember <内容>` | **分流**：个人偏好/称呼/背景 → `profile.md`（跨主线）；主线内事实/结论 → memory.md（§6） |
| `@forget <内容或范围>` | **聊天域专属**：Edit 删除 memory/profile 对应条目；彻底遗忘时 devlog/lessons 对应行物理删除（唯一允许的非追加写），留 `[遗忘]` 审计行；隐私删除可穿透 decisions 与 archive（§4） |
| `@adr <标题>` | 按主线分节 + misc 兜底，条目四段（场景痛点/可选方案/最终决定/洞察），只写不读（§6） |
| `@next [方向]` | 断点有效则确认开工；空/过期则读 memory + devlog 尾部推 ≤3 候选，选定必须落盘为断点（§6） |
| `@status` | 只读快照 ≤5 行，必报**未兑现 `[承诺]`**（§6） |
| `@merge` | 双文件压缩：devlog 流水提炼进 memory、lessons 去重归纳，头部同步刷新（§4） |
| `@audit` | 9 项记忆体检，含 **profile 敏感信息扫描**（§7） |
| `@verify` | 对记忆中事实性断言检索核查，三态输出 ✅/❌/❓（§7） |
| `@done` | 主线收尾，归档至 `context/chat/archive/`，CURRENT 改 `thread: none`（§8） |
| `@help` | 输出本表 + 当前绑定（§9） |

聊天域护栏：**记忆禁虚构**——「我们之前说过什么」只允许引用记忆文件（memory ＞ devlog ＞ profile），三者皆无时明说没有；**隐私拒存**——密钥/证件/住址/支付信息拒绝写入任何记忆文件（§护栏）。

## 4. toolbox 元工具 CLI（跨项目，人与 AI 共用）

入口 shim：`~/.local/bin/toolbox`（无 AI 时 `toolbox --help` 即说明书；`toolbox <cmd> --help` 即该命令手册）。全局池 `~/.agents/toolbox/scripts/`，项目池 `<repo>/scripts/agent-tools/`（同名覆盖全局）。

| 命令 | 语法 | 作用 |
|---|---|---|
| `init` | `toolbox init [--project]` | 初始化全局池与 shim（幂等）；`--project` 同时初始化当前仓库项目池 |
| `new` | `toolbox new <name> [--lang {sh,python}] [--scope {global,project}] [--trigger {bootstrap,audit,cron,pre-commit,manual}] [--summary <一句话>]` | 生成合规脚手架（默认 sh——shell 一等公民，python 兜底） |
| `check` | `toolbox check <path> [--scope {global,project}] [--force]` | 门禁校验并登记入池（头部块/--help/--json/--self-test/语言门禁/密钥扫描）；**引入新能力需用户确认** |
| `list` | `toolbox list [--json]` | 现场派生工具清单（名称/摘要/trigger/平台/last_run），无注册表 |
| `run-hooks` | `toolbox run-hooks <hook> [--quiet] [--json] [--notify]` | 按钩子批量执行 trigger 匹配的工具；任一 FAIL → exit 1 |
| `install-hooks` | `toolbox install-hooks [--remove]` | 接线 profile/cron/pre-commit（`--remove` 卸载）；**侵入操作，需确认** |
| `spec` | `toolbox spec` | 打印脚本编写规范 SSOT（写脚本前先看） |
| `remove` | `toolbox remove <name> [--yes]` | 退役工具移入 `.trash`；**破坏性，需确认** |
| `self-test` | `toolbox self-test` | 元工具自检 |

**退出码契约**（元工具与所有池内工具一致）：`0` 通过 / `1` 检查未通过 / `2` 自身故障。`run-hooks` 中工具 FAIL → exit 1（供门禁拦截）；工具自身故障 → ERROR 可见但 fail-open 不阻塞。

**既有接线**（dev-loop，唯一侵入点）：会话开场 `toolbox run-hooks bootstrap --quiet`（exit 0 静默继续；非 0 不阻塞恢复，仅附一行 ⚠）；`@audit` 第 11 项 `toolbox run-hooks audit --quiet`。钩子 FAIL 按 memo-collector 口径转 `风险` 待办。

**池内工具现状**：全局池现有 `env-doctor`（trigger: bootstrap——会话开场体检）与 `context-lint`（trigger: audit——context 数据面 + skill 指针面机械校验；裸跑=逐条明细，--json=单行结论）；项目池工具随各仓库版本化，以该仓库内 `toolbox list` 现场派生为准（agent-toolbox §命令面）。

## 5. 会话口令与 skill 加载

**会话恢复口令**（无状态恢复，配合 context/CURRENT）：

| 场景 | 口令 |
|---|---|
| 编码会话恢复 | `继续` 或 `读 context/CURRENT，开始下一个子任务：<xxx>` |
| 聊天会话恢复 | `继续` 或 `读 context/chat/CURRENT，继续` |
| 跨 IDE / 新会话求助 | `@help` |

**skill 加载三方式**（README §1.4/§1.6）：

1. **自动路由**：请求与 skill description 匹配时自动加载（基准行为，无需操作）；
2. **显式调用**：对话中点名加载，如「加载 dev-guide 按 §一 流程推进」；
3. **跨 IDE 兑底**（自动路由失效时，功能不降级）：prompt 中 @文件或给路径——「先读 `~/.agents/skills/<name>/SKILL.md` 再开工」（global）；项目内为 `<repo>/.agents/skills/<name>/SKILL.md`。

**skill 清单速览**：本仓库 global skill 见 `skills/` 目录（每目录一个 SKILL.md）；各 skill 职责与触发时机速查见 `README.md` §二，场景 → 入口速查见 §3.3。

## 6. 触发权限矩阵（通用纪律）

| 级别 | 内容 |
|---|---|
| Agent 自动执行 | 日志追加落盘、≥5 条自动归并（⚙️ 附注）、断点刷新、备忘自动收集与完成流转、人工打勾回收、开场 `bootstrap` 钩子、文档联动**提示**、咒语→skill 进化**建议** |
| 仅用户显式触发 | 全部 §1–§3 指令；其中 `@audit` `@verify` `@done` 为 Agent **严禁自主执行**红线 |
| 需用户确认后执行 | 一切修复落盘、批量删除（@todo-clean）、批量 `[SSOT 修正]`、`toolbox check` 新能力 / `remove` / `install-hooks`、破坏性操作（删表/清队列/强推分支） |
| 人类专用通道 | `todos.md` 中的 `[x]` 打勾（AI 只回收不书写）；`archive/` 翻档 |
