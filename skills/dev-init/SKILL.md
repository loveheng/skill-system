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

1. **项目形态判定**：编码项目 or 聊天/助理工作区？后者只需 copilot-context §0 的 `context/chat/` 骨架（CURRENT + threads/misc + profile/lessons/decisions），本清单其余步骤跳过。
2. **context/ 记忆骨架**：`context/CURRENT`（`epic: misc`）+ `epics/misc/`（memory.md + devlog.md）+ lessons.md；todos.md/done.md 可缺省（memo-collector §0：文件缺失时现写模板）——目录契约见 dev-loop §0。
3. **事实源 skill（workflow 类）**：从 README/构建脚本/CI **现场实测取证**提炼——模块结构、包名、构建/测试命令、环境硬约束（终端/写入限制）。结构与粒度参照 stock-calculator-workflow；内容严禁虚构，命令至少实测跑通一条。
4. **project-local 索引**：按 project-index `template.md` 建 `<repo>/.agents/skills/<repo-name>-index/SKILL.md`——只登记域级锚点，禁止一次性铺满（project-index「表格式规范」「维护协议」）。
5. **项目规范 skill（按需）**：从现有代码提炼写法模式（backend/frontend/docs 类，粒度对齐既有项目规范 skill）；小项目可跳过——workflow + 索引即最小可用集。新建守 README §4.4（description 预算 + 事实指针化）。
6. **toolbox 项目池**：`toolbox init --project` 建 `scripts/agent-tools/`；仓库内已有持久散放脚本按 agent-toolbox「散乱脚本治理」收编（check 门禁不豁免）。
7. **AGENTS.md（可选，跨 IDE 兜底）**：仓库根声明「按需读取 `.agents/skills/` 下对应 SKILL.md」——固定单 IDE 且自动路由正常时跳过（README §1.6）。
8. **冷启动验收（硬卡点）**：模拟新会话全流程——读 `context/CURRENT` → 只读 memory 恢复开工；随后 §2 自检全 ✓。

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
