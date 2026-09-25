---
name: dev-init
description: 新项目/新仓库首次接入 AI 开发 skill 体系的一次性初始化引导 checklist：按序编排 context/ 记忆骨架 → workflow 事实源 → project-local 索引 → 规范 skill → toolbox 项目池 → AGENTS.md 兜底 → 冷启动验收；零项目数据，各步薄指针到既有机制。新项目接入、初始化项目体系、补缺项目 skill 时加载；日常任务归 dev-guide。
---

# dev-init · 新项目接入引导（一次性 checklist）

> **定位**：编排层——把散在 dev-loop / memo-collector / copilot-context / project-index / agent-toolbox 的既有机制按接入顺序编排成一条 checklist。零规范事实、零项目数据，各步规范正文以指针出处为唯一事实源。
> **生命周期**：项目级一次性流程（每项目跑一遍）；与 dev-guide（每任务）分层——日常任务归 dev-guide §0，本 skill 只在接入/补缺时加载。
> **裁决链**：沿用 dev-loop 链，本 skill 零裁决权。

## 0. 入口判定

- 新项目/新仓库首次接入 → 走 §1 全流程
- 已接入项目补缺（如只有索引没有事实源）→ 直接跳对应步骤，已完成项 ✓ 跳过
- 日常编码任务 → 不走本流程（dev-guide §0）；新机器/新环境准备（clone 两仓）→ README §1.5

## 1. 接入 Checklist（按序执行；跳过项必须留一句理由）

> **骨架捷径**：第 2/6/7 步的目录与空文件可由 `toolbox run scaffold` 一键生成（幂等、不覆盖已有文件；含 context/ 骨架 + 白名单骨架 + `.agents/skills/` + 项目池 + docs 数据 skill 条件创建，见 agent-toolbox）。人工取证项（事实源 / 索引内容 / 规范 skill）脚本不代劳，仍需按步执行。

1. **项目形态判定**：编码项目 or 聊天/助理工作区？后者只需 copilot-context §0 的 `context/chat/` 骨架（CURRENT + threads/misc + profile/lessons/decisions），本清单其余步骤跳过。
2. **context/ 记忆骨架**：`context/CURRENT`（`epic: misc`）+ `epics/misc/`（memory.md + devlog.md）+ lessons.md；todos.md/done.md 可缺省（memo-collector §0：文件缺失时现写模板）——目录契约见 dev-loop §0。**骨架捷径**：`toolbox run scaffold` 可一键生成（幂等不覆盖）。
3. **事实源 skill（workflow 类）**：从 README/构建脚本/CI **现场实测取证**提炼——模块结构、包名、构建/测试命令、环境硬约束（终端/写入限制）。结构与粒度参照 stock-calculator-workflow；内容严禁虚构，命令至少实测跑通一条。
4. **project-local 索引**：按 project-index `template.md` 建 `<repo>/.agents/skills/<repo-name>-index/SKILL.md`——只登记域级锚点，禁止一次性铺满（project-index「表格式规范」「维护协议」）。
5. **项目规范 skill（按需）**：从现有代码提炼写法模式（backend/frontend 类，粒度对齐既有项目规范 skill）；小项目可跳过——workflow + 索引即最小可用集。**落点与索引同级**：一律建在本仓 `<repo>/.agents/skills/`（project-local，随仓库版本化），**不进 global**（global 只放跨项目机制）；新建守 README §4.4（description 预算 + 事实指针化）。
   - **docs 单独判定（条件化，不留空位）**：项目存在 `docs/`（或计划建）→ 建 `<repo>-docs/SKILL.md`，且**只填三项项目数据**：① 域目录表（域 → 定位）；② 本仓 lint/收集脚本路径；③ 本仓例外。规范机制一律指针到 `docs-spec §1`–§7，**严禁复制规范正文**（防双源）。尤其注意：**文档头部区块（`status`/`updated` frontmatter、写后自检 lint、三层索引机制）是跨项目全局 SSOT**——初始化生成默认文档规范 skill 时只填充项目本地数据（域目录表 / 本仓 lint 脚本 / 本仓例外），**不得把头部区块规范本身复制进项目 skill**（否则全局升级时各项目副本漂移，踩 `docs-spec §7` 反模式）。无 `docs/` 则整项跳过——**禁止为对齐清单而建空骨架**。
6. **toolbox 项目池（脚本文件夹初始化）**：`toolbox init --project` 建 `scripts/agent-tools/` **并落 `README.md` 占位**——空目录不入 git，占位文件保证池随仓库 clone 即得；项目池随仓库版本化，同名工具覆盖全局池。**收编**：仓库内已有持久散放脚本（仓库根、`scripts/` 下的 .sh/.mjs/.py 等）按 agent-toolbox「散乱脚本治理」处理——评估复用价值 → 合规化（补头部块/`--help`/`--json`/`--self-test`）→ `toolbox check` 入池 → 原址删除或改一行薄指针（check 门禁不豁免）。**骨架捷径**：`toolbox run scaffold` 内部会调用 `toolbox init --project`。
7. **副作用收集白名单骨架（项目级，非全局）**：仓库根建 `.uncertainty-whitelist` 与 `.degrade-whitelist` 空文件（uscan/dscan 自动加载，缺失不报错）；文件仅含头注释（用途 + 格式：每行一个正则、`#` 注释 + 收录标准：逐处核读定性「有意降级/已知误报」才收录、修复后删行恢复监控），**禁预置条目**——首跑全量基线（首次 @done）评估后才逐条登记（口径与格式见 ai-sideeffect-guard §3）。**骨架捷径**：`toolbox run scaffold` 已生成则 ✓ 跳过。
8. **AGENTS.md（可选，跨 IDE 兜底）**：仓库根声明「按需读取 `.agents/skills/` 下对应 SKILL.md」——固定单 IDE 且自动路由正常时跳过（README §1.6）。
9. **冷启动验收（硬卡点）**：模拟新会话全流程——读 `context/CURRENT` → 只读 memory 恢复开工；随后 §2 自检全 ✓。

**硬卡点**（缺卡 = 接入未完成）：
- `[事实源]` workflow skill 已建，构建/测试命令已实测（≥1 条跑通）
- `[索引]` 归属表 ≥1 行真实落点（非占位）
- `[验收]` 冷启动演练通过 + §2 自检全 ✓

## 2. 自检清单

- CURRENT 已 gitignore，context/ 其余纳入版本控制（dev-loop §0/§4）
- 新建各 skill description ≤~250 字符、正文无易漂移事实（README §4.4）
- skill 间互引指针可 grep（§节号/节名锚点真实存在）
- 新登记脚本过 `toolbox check`，`toolbox list` 可现场派生
- 跑一遍 `@audit` 作为接入基线，此后交回 dev-loop 日常纪律

## 3. 维护协议与边界（防双源）

- 本 skill 只定顺序与卡点，严禁复制任何机制正文（归并/日志/索引格式等一律指针到出处）
- 各机制 skill 变更不回改本 skill（编排顺序稳定即无联动义务）；新增全局机制 skill 时检查 §1 是否需补一步
- 验收通过的标志是本 skill 不再被需要——日常恢复/审计/收尾全部走 dev-loop 既有纪律
- 软上限 ~80 行
