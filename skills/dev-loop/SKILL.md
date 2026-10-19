---
name: dev-loop
description: 编码会话交互 SOP 底座（回复格式/日志规约/全局护栏/:: 指令）：context/CURRENT 绑定 epic、断点恢复、memory/devlog ≥5 自动归并、决策点台账、资源拦截与两次熔断。日常编码/散修一律挂本 skill；仅大需求流程引导→dev-guide，长排查/重大故障协议→problem-triage，待办台账→memo-collector（各自显式触发才加载，勿与本项目重叠）。
---

# Skill: Dev-Loop (无状态极简交互 SOP - V3.8)

> **管辖边界**：仅约束回复格式、Token 管控、日志协议与全局护栏，全项目通用；代码规范优先 project-local skill / AGENTS.md。**冲突裁决链**：memory.md 显式最新决策 ＞ 项目级 Skill / AGENTS.md ＞ 本 Skill；推翻项目规范以 `[SSOT 修正]` 留痕。
> **分层铁律**：本文件 = 核心规则 + 薄指针；**细则唯一事实源 = REFERENCE.md（§2/§3/§4 细则 + §5-§8）**。修改细则只改 REFERENCE，严禁回填复述。

**全局护栏（全时段）**：

0. **总纲**：无法自行安全推进（资源缺位/重复失败/高危/不可排他歧义）→ 打断求助用户，严禁猜测硬试。**提问预算**：确认合并同类项、复述型一次抛、有默认建议的不单问——提问稀缺性即确认有效性，严禁为免责而问。
1. **输入校准**：错别字静默修正；破坏性歧义一句话阻断确认；零干预（不质疑未受邀方案）。
2. **资源拦截**：缺资源立刻索取，严禁伪造日志/配置/返回值；状态问题先工具取证再答，不足明说「未查证」。
3. **两次熔断**：同一卡点连续 2 次未解决即停，第 3 轮出 `[已尝试方案]/[核心卡点]/[建议方向]`；重大故障加「还原优先」选项——完整协议 = problem-triage §3。
4. **环境与高危**：环境未定先轻量探针或确认；破坏性动作前列影响范围等显式授权。
5. **静态强约束**：生成代码必经本地 compile/lint 校验才能交付；禁引不存在的 API；新依赖须经确认，优先复用已有工具类。
6. **契约保护**：禁隐式破坏公共接口与数据模型契约；大面积跨文件改动先列影响清单经确认。
7. **超时管控**：长时命令超时给足 300000~600000ms 或更长；未完成不自动中断，仅用户要求才终止。
8. **隐私拒存**：密钥/令牌严禁入 context/（随 git 入库）与代码/文档；误贴的秘密不复述不落盘，提示移 .env、按需轮换。

## 0. 目录结构 (Layout)

```
context/                      ← 提交 git（CURRENT 除外）
├── CURRENT                   ← 本窗口绑定指针（gitignore；日常默认 epic: misc；临时绑定态第二行 `base: <原绑定>`，--restore 恢复后清除）
├── epics/<名>/{memory.md, devlog.md, todos.md}
│                             ← memory=长期记忆 SSOT（决策+断点，恢复只读它）
│                             ← devlog=过程日志追加区（≥5 自动归并）；todos 归 memo-collector §0
├── epics/misc/               ← 常驻杂项 epic（散修挂靠）
├── archive/                  ← 真退役功能（人工确认后移入；维护态 epic 留在 epics/ 不搬）
├── todos.md / done.md        ← 全局备忘台账（格式归 memo-collector §0）
├── pending-confirm.md        ← 多决策点确认台账（§2；非空时大动作冻结）
├── lessons.md                ← 双区：正文=避坑规则 SSOT，底部=教训流水
└── decisions.md              ← 决策洞察档案（::adr 写入；AI 只写不读）
```

**头部 YAML**（memory 头部创建/::merge/devlog close-reopen 三通道写；devlog 头部创建/::merge/devlog clear 写；追加轮严禁触碰，不含 pending 计数）：
`dev-loop: memory|devlog|lessons|decisions` ｜ `format: v1` ｜ `epic: <名|global>` ｜ `total-merged: <n>` ｜ `last-merge: <日期|none>` ｜ `state: maintenance`（仅 memory 头部可选，close 写入/reopen 清除）

## 1. 动态输出策略

严禁主动打印未修改全量文件。优先级：① Tool Edit 原地修改 → ② 局部代码块（标文件路径+插入位置）→ ③ Unified Diff（仅显式要求）。

## 2. 日常交互与日志协议

**快车道**：影响面小且可逆——≤3 文件、不涉 schema/协议/公共契约/数据迁移、意图明确——的小改散修免评估/台账，仅留 [变更]/[验证]+断点刷新，文档攒批补写；连续同类小修默认沿用快车道，任一不满足回标准流程（细则=REFERENCE §2）。

本轮发生任一触发（Diff、解决通用价值 Bug、推翻决策）**必须追加日志，严禁只在聊天框回复**：

1. **devlog**：`- [YYYY-MM-DD] [变更]: <一句话>` → `epics/<名>/devlog.md` 底部。
2. **Lesson**（通用价值 Bug 必记）：`- [<模块>] <现象> ➔ <根因> ➔ <避坑规则> (Ref: <名>)` → lessons.md 底部流水；排错前先读正文对照历史规则；正文行禁用 `- [` 前缀。
3. **SSOT 修正**（推翻决策，不依赖 Diff）：① 当轮把 memory.md 旧结论改写为新结论（不等归并）；② devlog 追加 `- [日期] [SSOT 修正]: 旧 <X> ➔ 新 <Y>`。
4. **验证账本**（与 [变更] 成对）：`- [日期] [验证]: <命令与结果>`；未验证写 `未执行: <原因>`，严禁虚构。分级：compile/lint 恒跑；全量测试仅数据层/协议变更、跨文件重构、提交收尾跑；docs-lint 仅 docs 轮。门禁：`toolbox run devlog change` 缺 `--verify`/`--no-verify` 即拒。

**专项规则（一行口径，全文=REFERENCE §2）**：
- **副作用标记**：未实证/猜测性兜底按 ai-sideeffect-guard §1 留 `// UNCERTAIN:`/`// DEGRADE:`（不落 devlog）；只阻「逾期未处置标记」，严禁删标消报告。
- **测试写保护**：核心测试（tests/core/、tests/golden/、project-index 声明）为只读契约，diff 命中即判本轮失败，唯一出路回滚重写实现；变异探针仅 Solidify 模式 `toolbox run mscan`。
- **公共接口变更**：Expand-Contract 三步（并存→分批迁移→单 commit 移除），禁原地突变；不设行数熔断，断言=devlog 显式声明+单轮可运行验证。
- **跨库只读评估-移交**：AI 限只读评估+移交件；目标库写入一律用户执行（逐次显式授权可豁免）。
- **决策点台账**：一次产出 ≥2 个待裁决点 → **同轮**「登记 pending-confirm.md + 抛 [1/N] 第一问（附背景+默认建议）」；裁决型逐项串行、复述型合并抛；单轮裁决点 >4 个先按影响面收敛或分批，严禁整清单倾倒；未决期间大动作冻结、每回复列「未确认 N 项」；未清零禁 ::done。漏走时 `::confirm` 兜底。
- **收尾 git 建议**：Diff 轮末附「建议指令，未执行」块（git add+commit），严禁代跑 git 写操作。
- **日志豁免**：无结论纯咨询/排错、协议操作、纯 context 文档维护轮不追加；Lesson 与 SSOT 修正不受豁免。
- **实现口径**：优先 `toolbox run devlog <change|verify|note|lesson|bp> <epic> <文本>`；断点修复 `toolbox run breakpoint check|fix`；低频计数 `tail -n 20 | grep -c '^- \['`；量化探测 `toolbox run ctx-ratio`。降级细则与记账单一事实源=REFERENCE §2。

## 3. 状态自恢复与绑定协议

- **状态恢复**：读 `context/CURRENT` → **只读** `epics/<名>/memory.md` 恢复共识（先 `head -n 7` 校验一致）；排查交接例外与台账联动=REFERENCE §3。CURRENT 缺失/none 或 epic 失配 → 列候选提示 `::file`，严禁自选开工。
- **会话绑定卡**（≤4 行，数据源 `toolbox run panel`，缺失降级手推；字段口径=REFERENCE §3）：
  ```
  会话绑定 ｜ dev ｜ 类型: epic 大需求（建议挂 dev-guide）
  挂载: ▶ e2ee-auth（CURRENT 一致）→ memory.md / devlog.md
  任务: e2ee-auth(10-02)▶ payment-refactor(09-25) ｜ 多任务切换 ::board
  状态: 断点 下一步：完成重连握手 ｜ 待决 2（大动作冻结）｜ 待归并 3 ｜ 债 U0 D1 P0 ｜ ctx: 62% ⚠
  ```
  绑定卡是恢复收尾输出，严禁为出卡单独询问用户。
- **绑定纪律**：日志/断点/SSOT 只落绑定挂载点；换绑 `::bind`（切走先归并）；类型只定挂载与流程入口，仪式密度按 §2 逐轮分级。
- **断点**：memory.md 末尾 `## 断点` 恒一行 `- [断点] 下一步：<具体子任务>`（无待办写「等待新子任务」，严禁留空/过期）；使「下一步」改变的轮次收尾刷新，机械件 `toolbox run devlog bp <epic> <文本>`。
- **绑定与切换**：`::file`/`::bind <名>` 机械件统一 `toolbox run mount-init`（骨架/CURRENT/切换前置由脚本拦截，**严禁手拼骨架**）；文档挂载纪律=REFERENCE §3；裸 `::file` 只列候选。
- **misc 挂靠**：散修统一挂 `epics/misc/`，不切 CURRENT，流程同 §2；长成大功能 `::bind` 转正。
- **并行窗口纪律**：一窗口一 epic，同 epic 禁双窗同写；插做成规模工作先切绑；恢复「继续」前核对 CURRENT；越界失败自动暂停（全文=REFERENCE §3）。
- **自动重构**：绑定 epic devlog 或 lessons 任一 ≥5 条，或 `ctx-ratio` 命中且 devlog 非空 → 本轮末尾自动执行 §4 归并 + `ctx-ratio --mark-merged`；排错中豁免只提示。附注：⚙️ [自动重构完成]…建议 Cmd+R 重置窗口。
- **开场环境检查**：toolbox 在场先 `toolbox run-hooks bootstrap --quiet`；非 0 仅附一行 ⚠，严禁阻塞恢复。
- **写入纪律**：进度事实只追加 devlog；memory 正文仅 §4 归并 / `::remember` / SSOT 修正 三通道；同一文件同一轮只用一种编辑工具。
- **代理写入**：结构性修改（函数/类/接口级增删改）、配置与数据文件（.json/.yaml/.toml/.sh 等）一律经 `toolbox run safe-patcher patch/write` 落盘（唯一性匹配+语法预检+项目 hook+原子写入，失败零写入并按报错自纠错后重试）；直接 edit_file 仅限单行微调/纯文案/注释/骨架文件（context/、白名单等）与 safe-patcher 报错后的定向修正。

## 4. 重构与归纳

触发三（§3 自动阈值 / `::merge` / ctx-ratio 命中），同一套双文件压缩：① **先归档决策过程**——将 devlog 中有留档价值的决策/权衡条目提炼进挂载底子文档的「决策日志」专节（epic 挂载时；格式=REFERENCE §4）；② devlog 提炼进 memory.md 正文并清空追加区（对已入文档决策日志的条目只留一行 `Ref:` 指针，严禁整条重抄——去重契约=REFERENCE §4），两文件头部同步（total-merged+1、last-merge），`## 断点` 原样保留，**[SSOT 修正] 最高归纳优先级、严禁新旧并存**；③ lessons.md 底部流水去重归纳进正文并清空；④ 极简回复一行（格式、git 冲突面、软上限、事故回滚纪律=REFERENCE §4）。

## 5. 实测闭环验证 (1 分钟，dev-init 接入时跑一次)

绑定 → 重置 → 无状态恢复的开环冒烟——步骤与成功标准 = REFERENCE.md §5。

## 6. 附属指令流程 (Manual Ops)

六指令——::remember 直写 memory 正文｜::adr 四段式落 decisions.md（AI 只写不读）｜::next ≤3 候选落盘为断点｜::board 逐任务看板+跨 AI 恢复咒语｜::status ≤5 行只读快照｜::help panel 四区渲染+求助入口——及「面板判读协议」。**全部执行细则 = REFERENCE.md §6（唯一事实源），按需加载。**

## 7. 审计与质检 (Audit)

**触发**：① `::audit` 手动；② `::done` 第一步强制；③ 多机同步/久别重置后建议。**机械预填**：`toolbox run ctx-audit --root <项目根>`（脚本仅执行器，清单语义唯一事实源=REFERENCE §7）。**十二项**（逐项一行 ✓/⚠，口径=REFERENCE §7）：①断点新鲜度 ②新旧并存 ③devlog 积压 SSOT 修正 ④记忆补记 ⑤lessons 去重 ⑥尺寸健康 ⑦孤儿 epic ⑧头部校验 ⑨指针抽查 ⑩skill 卫生 ⑪toolbox 巡检 ⑫验证缺口抽查。修复经确认，审计轮不追加日志。**`::verify`**（账实对账，仅用户显式触发）：只验可机械定位断言，三态 ✅/❌/❓（≤15 行），❌ 提议批量 [SSOT 修正]——细则=REFERENCE §7。

## 8. epic 收尾 (Closure)

**`::done`**（misc 不适用）：§7 审计强制前置（⚠ 中止先修）→ **决策过程归档**（devlog 决策/权衡条目写进挂载底子文档「决策日志」专节，同 §4 ①）→ 收敛复盘（升舱 L2→L3，附一行收敛度量）→ **标记强制结算**（本 epic 的 UNCERTAIN/DEGRADE 逐条清零三选一：补实证删标/升级 ADR/转 `(风险)` 待办——**逾期未处置标记是唯一阻断项**）→ 待办清零（memo-collector §4）→ memory 提炼 ≤10 行 → **维护态收尾**：`toolbox run devlog close <名> <完结说明>`（memory 头部 `state: maintenance` + 断点完结 + CURRENT → none，**目录不搬**，archive 仅真退役人工移入；重开 `devlog reopen`）。**流程全文 = REFERENCE.md §8（唯一事实源）**。**收尾汇总卡必出**（标记/白名单/Hypothesis 实数，全零也出卡，以扫描实数为准）：

```
📋 结算：<epic名> ｜ 标记 清零 ✓（实证删 N / ADR M / 转办 K）｜ 白名单 W 处 ｜ [Hypothesis] H 条
```

## 9. 指令总表 (Command Surface)

**指令体一律薄指针（「执行 §X」），流程正文全 skill 只此一份。**

| 指令 | 职责 | 指向 |
|---|---|---|
| `::file` `::bind` | 绑定/切换（文档锚定，名=slug；切走先归并） | §3 |
| `::remember` `::next` `::status` `::board` | 记忆入口 / 断点规划 / 快照 / 任务看板 | §6 |
| `::adr` | 决策洞察档案（AI 只写不读） | §6 |
| `::confirm [事项]` | 决策点拆分登记+分级确认（漏走台账的兜底） | §2 |
| `::merge` | 手动归并 | §4 |
| `::audit` `::verify` | 十二项质检（账账）/ 记忆对现实（账实） | §7 |
| `::done` | epic 收尾（内含审计） | §8 |
| `::help` | 面板+求助入口；排错协作附「人类侧说明：problem-triage/manual.md」 | §6 |

**触发纪律**：全部指令仅用户显式触发，严禁自主执行 ::audit / ::verify / ::done；一切修复经确认后落盘。**跨 skill 速查**：项目专属命令见 project-local 索引（机制见 project-index）。
