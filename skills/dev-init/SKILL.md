---
name: dev-init
description: 新项目/新仓库/存量项目初始化 AI 开发 skill 体系的一次性引导 checklist：按序编排 context/ 记忆骨架 → workflow 事实源 → project-local 索引 → 规范 skill → toolbox 项目池 → AGENTS.md 兜底 → 冷启动验收；存量项目含对账 §1.5。零项目数据，各步薄指针到既有机制。新项目接入、存量项目初始化（含大规模重写后重验）、补缺项目 skill 时加载；日常任务归 dev-guide。
---

# dev-init · 新项目接入引导（一次性 checklist）

> **定位**：编排层——把散在 dev-loop / memo-collector / copilot-context / project-index / agent-toolbox 的既有机制按接入顺序编排成一条 checklist。零规范事实、零项目数据，各步规范正文以指针出处为唯一事实源。
> **生命周期**：项目级一次性流程（每项目跑一遍）；与 dev-guide（每任务）分层——日常任务归 dev-guide §0，本 skill 只在接入/补缺时加载。
> **裁决链**：沿用 dev-loop 链，本 skill 零裁决权。

## 0. 入口判定

- 新项目/新仓库首次接入（空白板）→ 走 §1 全流程
- 存量项目上初始化（已有代码库：无 context/ 或无 project-local skill，或代码大规模重写后 skill 整体过期）→ 先跑 §1.5 存量对账，再按 §1 补缺
- 已接入项目补缺（**部分**缺件，如只有索引没有事实源）→ 直接跳对应步骤，已完成项 ✓ 跳过；缺的若是主体（context/ 与 project-local skill 俱无）→ 按上行走 §1.5
- 日常编码任务 → 不走本流程（dev-guide §0）；新机器/新环境准备（clone 两仓）→ README §1.5

## 1. 接入 Checklist（按序执行；跳过项必须留一句理由）

> **骨架捷径**：第 2/6/7 步的目录与空文件可由 `toolbox run scaffold` 一键生成（幂等、不覆盖已有文件；含 context/ 骨架 + 白名单骨架 + `.agents/skills/` + 项目池 + docs 数据 skill 仅存量 `docs/` 时创建，见 agent-toolbox）。人工取证项（事实源 / 索引内容 / 规范 skill / 无 `docs/` 时按项目类型生成初始域结构）脚本不代劳，仍需按步执行。

1. **项目形态判定**：编码项目 or 聊天/助理工作区？后者只需 copilot-context §0 的 `context/chat/` 骨架（CURRENT + threads/misc + profile/lessons/decisions），本清单其余步骤跳过。
2. **context/ 记忆骨架**：`context/CURRENT`（`epic: misc`）+ `epics/misc/`（memory.md + devlog.md）+ lessons.md；todos.md/done.md 可缺省（memo-collector §0：文件缺失时现写模板）——目录契约见 dev-loop §0。**骨架捷径**：`toolbox run scaffold` 可一键生成（幂等不覆盖）。**存量分支**：`context/` 已存在但文件不合当前契约（无 YAML 头 / 旧格式 / lessons 落错层 / CURRENT 被 commit）→ 走 §1.5 存量对账第 2 项迁移，勿直接「已存在 → 跳过」。
3. **事实源 skill（workflow 类）**：从 README/构建脚本/CI **现场实测取证**提炼——模块结构、包名、构建/测试命令、环境硬约束（终端/写入限制）。结构与粒度参照既有项目实例（样例：后端仓 project-local 的 stock-calculator-workflow，非全局）；内容严禁虚构，命令至少实测跑通一条。**存量分支**：workflow 已存在 → 按 §1.5 第 1 项逐条对当前代码重验，**全对才通过**（命令跑通 ≠ 事实源一致）。
4. **project-local 索引**：按 project-index `template.md` 建 `<repo>/.agents/skills/<repo-name>-index/SKILL.md`——只登记域级锚点，禁止一次性铺满（project-index「表格式规范」「维护协议」）。**存量分支**：索引已存在 → 按 §1.5 第 1 项核对锚点与代码一致。
5. **项目规范 skill（按需）**：从现有代码提炼写法模式（backend/frontend 类，粒度对齐既有项目规范 skill）；小项目可跳过——workflow + 索引即最小可用集。**落点与索引同级**：一律建在本仓 `<repo>/.agents/skills/`（project-local，随仓库版本化），**不进 global**（global 只放跨项目机制）；新建守 README §4.4（description 预算 + 事实指针化）。
   - **docs 单独判定（先取证存量，再按项目类型补充；不留空位）**：
     - **已有 `docs/`**：① 先取证存量结构——列目录树 + 抽查 2~3 篇的 frontmatter/命名/切片习惯，提炼现状口径（现有域、惯用命名、是否已有 lint 脚本）；② 建 `<repo>-docs/SKILL.md` 只填三项项目数据：域目录表（以存量域表为准，不臆造新域）/ 本仓 lint 脚本路径 / 本仓例外（存量与 `docs-spec` 的冲突记入此处，不静默改写存量文档；**分歧较大时**（根平铺/无 frontmatter/命名混乱）向用户出示分歧清单，由用户决定是否一次性存量迁移——迁移按 docs-spec §4/§5 墓碑与引用修复纪律执行，不属本步默认动作）；规范机制一律指针到 `docs-spec §1`–§7，**严禁复制规范正文**（防双源）。**文档头部区块（`status`/`updated` frontmatter、写后自检 lint、三层索引机制）是跨项目全局 SSOT**——项目 skill 不得把头部区块规范本身复制进去（否则全局升级时各项目副本漂移，踩 `docs-spec §7` 反模式）。
     - **无 `docs/`**：不建空骨架，**按项目类型推导初始域结构**（后端服务 → `architecture/` + `deploy/`，有对外接口加 `api/`；Web/前端 → `design/` + `api/`；CLI/库 → `reference/` + `cli/`；文档站 → `guide/` + `api/`；其余兜底 `architecture/` + `guide/`），生成 `docs/README.md` 纯结构索引（docs-spec §5）+ 至多 1~2 个种子文档（如指向主 README 的 `architecture/overview`，**内容必须提炼自主 README/代码现状，严禁占位文案**——否则即违反本步「不建空骨架」初衷），禁止一次性铺满五切片——后续按项目实际长域。
     - 两种情形收口均按 §2「三处同步」把 docs skill 域表同步进 `docs/README.md` 与项目索引的文档落点列。
6. **toolbox 项目池（脚本文件夹初始化）**：`toolbox init --project` 建 `scripts/agent-tools/` **并落 `README.md` 占位**——空目录不入 git，占位文件保证池随仓库 clone 即得；项目池随仓库版本化，同名工具覆盖全局池。**收编**：仓库内已有持久散放脚本（仓库根、`scripts/` 下的 .sh/.mjs/.py 等）按 agent-toolbox「散乱脚本治理」处理——评估复用价值 → 合规化（补头部块/`--help`/`--json`/`--self-test`）→ `toolbox check` 入池 → 原址删除或改一行薄指针（check 门禁不豁免）。**骨架捷径**：`toolbox run scaffold` 内部会调用 `toolbox init --project`。
7. **副作用收集白名单骨架（项目级，非全局）**：仓库根建 `.uncertainty-whitelist` 与 `.degrade-whitelist` 空文件（uscan/dscan 自动加载，缺失不报错）；文件仅含头注释（用途 + 格式：每行一个正则、`#` 注释 + 收录标准：逐处核读定性「有意降级/已知误报」才收录、修复后删行恢复监控），**禁预置条目**——首跑全量基线（首次 ::done；存量项目按 §1.5 第 5 项基线前移至接入时点）评估后才逐条登记（口径与格式见 ai-sideeffect-guard §3）。**骨架捷径**：`toolbox run scaffold` 已生成则 ✓ 跳过。
8. **AGENTS.md（可选，跨 IDE 兜底）**：仓库根声明「按需读取 `.agents/skills/` 下对应 SKILL.md」——固定单 IDE 且自动路由正常时跳过（README §1.6）。**存量分支**：仓库已有其他 AI 指令文件（AGENTS.md/CLAUDE.md 等）→ 先读、核对与 skill 体系无冲突后**追加一行指针**（指向 `.agents/skills/`），不另起新文件；有冲突则向用户出示分歧清单再收口（裁决链见 dev-loop 开头）。
9. **冷启动验收（硬卡点）**：模拟新会话全流程——读 `context/CURRENT` → 只读 memory 恢复开工 + project-local 三 skill（workflow/索引/规范）可加载且互洽（§1.5 第 1 项口径）；随后 §2 自检全 ✓。

## 1.5 存量对账（存量项目初始化 / 大规模重写后重验；§0 命中后先跑本节，再按 §1 补缺）

> 空白板项目本节整体跳过。「现场提炼」对存量是**重验**不是**新建**——skill 能加载 ≠ skill 是最新的，过期 skill 比没有 skill 更危险（错误锚点误导每一轮定位）。

1. **skill 三互检 + 对代码 verify**：workflow / 索引 / 规范三 project-local skill 的技术栈与目录锚点**互相一致**，且逐条对当前代码核实（目录存在、命令可跑、接口签名在代码中）；任一过期 → 按 §1 对应步重建/修正（走 dev-loop §2「SSOT 修正」留痕口径，过期结论不许静默改写）。
2. **存量 context/ 迁移**：已有文件按当前契约逐一校验——YAML 头齐全（dev-loop §0 / memo-collector §0）；todos 旧格式走 memo-collector「v1 迁移」；lessons 落错层（如 `epics/<x>/lessons.md`）迁至 `context/lessons.md`；CURRENT 被 commit → 按 §2 第 1 项 gitignore 并从 index 移除（`git rm --cached`，经确认）。
3. **gitignore 机械校验**：`git check-ignore context/CURRENT` 必须命中，未命中 → 向 `.gitignore` 追加一行（追加不破坏存量规则）。
4. **docs 硬卡点**：`docs/` 已存在但无 `<repo>-docs` skill → 第 5 步的「已有 docs/」分支升级为**硬卡点**（§2），不得默认跳过。
5. **基线前移**：ai-sideeffect-guard 四工具 + toolbox bootstrap/audit 在接入时即跑一次全量基线（存量命中先定性：有意降级入白名单、高危转 `风险` 待办），不等首个 `::done`；未验证假设顺手登记 todos `(风险)[long]`。
6. **存量知识收割（可选）**：代码注释/旧文档/已修 bug 中有通用价值者，提炼进 lessons.md 与 decisions.md（口径归 memo-collector / dev-loop §6），不虚构、不搬运正文。

**对账硬卡点**（缺卡 = 存量接入未完成）：
- `[skill 一致]` 三 project-local skill 互检 + 对代码 verify 全过
- `[context 合规]` 迁移后 §2 第 1、2 项全 ✓

**硬卡点**（缺卡 = 接入未完成）：
- `[事实源]` workflow skill 已建，构建/测试命令已实测（≥1 条跑通）；**存量项目另加**「逐条对当前代码核实」（§1.5 第 1 项）
- `[索引]` 归属表 ≥1 行真实落点（非占位）；**存量项目另加**锚点对代码核实
- `[验收]` 冷启动演练通过 + §2 自检全 ✓
- `[存量对账]`（仅存量项目）§1.5 对账硬卡点全 ✓；`docs/` 存在时 `<repo>-docs` skill 已建

## 2. 自检清单

- `git check-ignore context/CURRENT` 命中（机械验证），context/ 其余纳入版本控制（dev-loop §0/§4）
- 记忆文件 schema 合规：todos.md 符合 memo-collector §0 模板（YAML 头 + `## misc` 兜底节 + 条目类型标签）；memory/lessons 有 dev-loop §0 YAML 头（存量项目 = §1.5 迁移后复核）
- 新建各 skill description ≤~250 字符、正文无易漂移事实（README §4.4）
- skill 间互引指针可 grep（§节号/节名锚点真实存在）
- 新登记脚本过 `toolbox check`，`toolbox list` 可现场派生
- 跑一遍 `::audit` 作为接入基线，此后交回 dev-loop 日常纪律

## 3. 维护协议与边界（防双源）

- 本 skill 只定顺序与卡点，严禁复制任何机制正文（归并/日志/索引格式等一律指针到出处）
- 各机制 skill 变更不回改本 skill（编排顺序稳定即无联动义务）；新增全局机制 skill 时检查 §1 是否需补一步
- 验收通过的标志是本 skill 不再被需要——日常恢复/审计/收尾全部走 dev-loop 既有纪律
- 软上限 ~80 行（§1.5 为存量对账子流程，占行计入）
