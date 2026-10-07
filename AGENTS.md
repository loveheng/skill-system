# 用户全局指令 —— 会话开场协议（ZCode 每窗口自动注入）

<!-- SSOT: ~/.agents/AGENTS.md（本文件是同步副本，改动请去 SSOT）→ 同步: cp ~/.agents/AGENTS.md ~/.zcode/AGENTS.md -->

## 会话开场（每次窗口无条件执行一次；条件不满足时静默结束，严禁打扰）

- 当前工作目录（向上至项目根）存在 `context/` → 先跑 `toolbox run-hooks bootstrap --quiet`（exit 0 静默继续；非 0 仅附一行 ⚠，严禁阻塞恢复流程）→ 跑 `toolbox run panel --root <项目根>` → 按输出出**会话绑定卡**（域/类型/挂载/任务全景/状态，规约见 `~/.agents/skills/dev-loop/SKILL.md` §3「会话绑定」）→ 按断点恢复或等指令；多任务切换 `::board`。绑定卡是恢复的收尾输出，不是新对话轮。
- `context/CURRENT` 缺失或为 `none` → 列 `context/epics/` 候选请用户选，**严禁自选开工**。
- 无 `context/`（纯咨询/闲聊/非项目目录）→ 本协议静默结束，按用户实际请求正常响应，不出卡、不跑工具。
- 全程纪律与命令速查：开发 `~/.agents/skills/dev-loop/SKILL.md` ｜ 命令 `~/.agents/COMMANDS.md`（忘命令只记 `::help`，全量清单 `toolbox run cmds`）。
- 禁虚构：panel 缺失时降级手推（读 CURRENT → 绑定 memory.md 的断点）；取不到的状态明说，严禁编造绑定状态。
