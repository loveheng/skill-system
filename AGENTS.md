# 用户全局指令 —— 会话开场协议（ZCode 每窗口自动注入）

<!-- SSOT: ~/.agents/AGENTS.md（本文件是同步副本，改动请去 SSOT）→ 同步: cp ~/.agents/AGENTS.md ~/.zcode/AGENTS.md -->

## 会话开场（每次窗口无条件执行一次；条件不满足时静默结束，严禁打扰）

- 跑 `toolbox run bootstrap --root <项目根>`（省略 --root 时自工作目录向上自动定位项目根），**按输出首行标记分支**：
  - `NO-CONTEXT` → 本协议静默结束，按用户实际请求正常响应，不出卡、不跑工具（纯咨询/闲聊/非项目目录）。
  - `UNBOUND` → 把工具列出的候选给用户选 `::bind`，**严禁自选开工**。
  - `BOUND` → 按工具输出组装**会话绑定卡**（≤4 行，格式与字段口径 = `~/.agents/skills/dev-loop/SKILL.md` §3，数据源 = 工具输出，类型字段由 AI 判断）→ 按断点恢复或等指令；多任务切换 `::board`。绑定卡是恢复的收尾输出，不是新对话轮。
- 工具已内联 `run-hooks bootstrap --quiet`（⚠ 仅一行，严禁阻塞恢复流程）与 panel 数据源，无需再单独跑这两步。
- 降级：bootstrap 缺失/失败时转手工流程——探测 context/（无 → 静默结束）→ 读 CURRENT（缺失/none → 列 epics/ 候选请用户选）→ **只读** memory.md 恢复 → 手推出卡；取不到的状态明说，**严禁编造绑定状态**。
- 全程纪律与命令速查：开发 `~/.agents/skills/dev-loop/SKILL.md` ｜ 命令 `~/.agents/COMMANDS.md`（忘命令只记 `::help`，全量清单 `toolbox run cmds`）。
