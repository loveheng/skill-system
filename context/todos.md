---
memo: todos
format: v3
---

# 待办列表

## misc
- [ ] [2026-10-07] (功能) bugpack 脚本：抓 git diff + 最近报错日志/堆栈 + 环境与依赖版本 → 密钥脱敏后拼装结构化 Bug 报障 Prompt（三段式：预期vs实际/复现证据/代码与环境，problem-triage manual.md §1.5 口径）；日志脱敏是硬门槛，走 toolbox new→check 登记制 (src: ai, 用户确认)
- [ ] [2026-10-07] (优化) dtrig 默认扫 /tmp/logs、四工具报告导 /tmp 易失：项目池登记时把持久日志路径约定进项目 skill（dev-init/README 提示） (src: ai, 体系审计)
- [ ] [2026-10-07] (优化) [long] 待办缺 ::done 外的重评节拍：长跑 epic 数月不收尾则到期债无提醒——::audit 加时效项或 panel 待办计数旁标 [long]/[once] 过期条数 (src: ai, 体系审计)
- [ ] [2026-10-07] (优化) 暂记备忘自计数兜底：memo-collector §1 触发点间仅对话内暂记、重置即弃——窗口内暂记 ≥3 条自动提前批量落盘（触发点 0） (src: ai, 体系审计)
- [ ] [2026-10-07] (优化) 跨项目待办/备忘无落点：memo-collector 路由仅域内/全局misc 两级，A 项目窗口聊出的 B 项目事项 B 侧恢复/::next 永远看不到——评估路由加跨项目行或以 ~/.agents/context 常驻仓为跨项目层 (src: ai, 体系审计)
