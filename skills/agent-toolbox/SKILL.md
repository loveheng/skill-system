---
name: agent-toolbox
description: 全局脚本工具箱机制：脚本池/元工具/头部规范/钩子巡检/脚本登记制。需要复杂校验、巡检、环境体检，新增/修改/退役/迁移定制脚本工具，或发现散落各处的持久脚本要收编登记（~/.agents/toolbox 与 <repo>/scripts/agent-tools）时加载；写脚本前先 toolbox spec，登记用 toolbox check，禁止散乱放置。
---

# agent-toolbox · 全局脚本工具箱

跨项目的脚本管理机制。本 skill 只承载法律（薄指针）；规范 SSOT 与全部执行逻辑在元工具内。**与具体项目无关**——换任何项目、任何机器，机制不变。

## 三层结构

- **法律**（本 skill + `toolbox spec`）：目录约定、编写规范、生命周期；
- **元工具**（规范 SSOT + 执行器）：`~/.agents/skills/agent-toolbox/toolbox-mgr.py`——唯一正身，**只搬运不重生**（新机器 clone/同步 `~/.agents` 后跑 `toolbox init` 即完成适配；严禁重新生成或手改副本）；
- **工具脚本**（自描述）：参数/帮助/检测项/金丝雀自测全部内聚在脚本头部与代码内，清单由 `toolbox list` 现场派生——**不存在需要维护的注册表**。

## 目录

- 全局池：`~/.agents/toolbox/scripts/`（跨项目通用）
- 项目池：`<repo>/scripts/agent-tools/`（项目专属，同名覆盖全局）
- **状态**：`~/.agents/toolbox/state/`（last-run-<hook>.json；使用台账 usage-ledger.jsonl——append-only 逐次流水，`list` 的 last_run 由此派生，直连调用不计入）；退役：`.trash/`
- shim：`~/.local/bin/toolbox`——人与 AI 共用同一命令入口，AI 无专属通道

## 命令面（`toolbox help` 或 `toolbox <cmd> --help` 看详情）

`init` / `new` / `check` / `list` / `run-hooks` / `install-hooks` / `spec` / `remove` / `self-test`

## 退出码契约（元工具与所有工具脚本一致）

`0`=通过；`1`=检查未通过；`2`=自身故障。
`run-hooks`：任一工具 FAIL → exit 1（pre-commit 门禁靠它拦截）；工具自身故障/不合规 → ERROR 可见但 **fail-open 不拦截**。

## AI 使用时机

1. 遇到复杂校验/巡检/环境体检需求：先 `toolbox list` 查现有工具，有则直接用；
2. 无合适工具且常规工具链低效：`toolbox new <name>` 生成脚手架 → 实现逻辑（守 `toolbox spec`）→ `toolbox check` 登记后使用；
3. 钩子 FAIL → 按 memo-collector 口径转 `风险` 类待办落 `todos.md`，message 即待办内容；
4. epic 收尾（/done）：看 `toolbox list` 盘点零使用工具，提议退役（人工确认后 `toolbox remove`）；
5. 发现散落各处的持久脚本（家目录/项目根等）或用户要求整理/收编/迁移脚本：按「散乱脚本治理」流程执行。

## 散乱脚本治理（登记制）

持久脚本（预期存活超过当前任务轮次）必须在工具池内，禁止散放于家目录、项目根等处：

1. **新脚本**：`toolbox new` 生成脚手架 → 实现 → `toolbox check` 入池；跨项目入全局池，项目专属入项目池；
2. **一次性豁免**：/tmp 下的临时分析脚本本轮用完即弃，不入池，也不得移入家目录/项目根长期留存；
3. **历史散放脚本收编**：发现散落脚本时评估——有复用价值 → 合规化（补头部块/`--help`/`--json`/`--self-test`，守 `toolbox spec`）→ `toolbox check` 入池 → 原址删除或改一行薄指针；无价值 → 提议删除（经确认）；
4. **迁移门禁不豁免**：收编走与新生脚本完全相同的 check 门禁（头部/help/json/自测/stdlib），不合规即拒收，补齐后再登记。

## 铁律

1. 语言双通道且 shell 优先：shell（POSIX sh/bash，platform: unix）为一等公民，优先实现；Python ≥ 3.9、仅标准库为兑底（仅当 shell 无法合理实现时使用）；
2. guard（trigger≠manual）必带 `--self-test` 金丝雀，内嵌已知坏样本证明"能抓到坏"；
3. 新工具首次 `check` 登记 = 引入新能力，经用户确认后执行；`remove`/`install-hooks` 属破坏性/侵入操作，执行前列影响并确认；
4. 平台差异只允许运行时探测实现（对齐元工具内 Adapter 模式），严禁 fork 文件；
5. 无 AI 时系统可完全人工操作：`toolbox --help` 即人类说明书，`~/.agents/toolbox/README.md` 为快速上手；
6. 版本控制（双仓库）：`~/.agents/skills/`（本体仓库：全部 skill + 元工具 `toolbox-mgr.py`）与 `~/.agents/toolbox/`（运行时仓库：工具脚本池）各自纳 git；改动后各自随手 commit（对齐「切换机器前 commit」纪律）；`toolbox/state/`、`toolbox/.trash/`、`__pycache__/` 为本机运行时已忽略；新机器 = 分别 clone 两仓库到对应路径 → `toolbox init` 完成适配（shim 在仓库外，由 init 生成）。

## 接线（对 dev-loop 的唯一侵入）

- dev-loop §3 开场：`toolbox run-hooks bootstrap --quiet`（exit 0 静默；FAIL/故障不阻塞恢复，仅附一行 ⚠）；
- dev-loop /audit 第 11 项：`toolbox run-hooks audit --quiet`，FAIL/ERROR 转 ⚠。
