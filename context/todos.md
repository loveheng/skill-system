---
memo: todos
format: v3
---

# 待办列表

## misc
- [ ] [2026-10-20] (功能) [挂起] ctx-ratio v2① proxy 缓存感知：侦查结论=CTX_PROXY_USAGE_FILE 未配置、无生产者、无样本，cache 字段存在性不可验证——等真实 proxy 环境出现后取样本再实施（zcode/cc 路径 L70-185 已读 cache 字段可复用同口径） (src: ai, v2 排期)
- [ ] [2026-10-20] (优化) [暂缓] ctx-ratio v2② devlog 文件重叠度：无实证痛点（归并已三通道触发），按「无实例不做」纪律挂起，观察到真实归并漏检再立项 (src: ai, v2 排期)
- [ ] [2026-10-20] (优化) goodhub-workflow lessons 节降级 Ref（移交件已出，快照 39ef9e2）：协议正文已升舱为 dev-loop REFERENCE §2 全局 SSOT，goodhub 侧删节内协议正文留薄指针——由用户在 goodhub 仓执行 (src: ai, 跨库移交) (src: ai)
- [ ] [2026-10-07] (优化) skill-verify 代码符号锚点（如 todo.DB）被当文件路径误报，ctx-audit --init 只认 exit 0 无「语义确认保留」登记通道——补通道防机械件逼出反优化措辞 (src: ai, 冷启动演练)
- [ ] [2026-10-07] (修复) project-scaffold 模板欠账：todos 模板 v2→v3（对齐 memo-collector 现行）+ 横幅「dry-run，不落盘」误标纠正（实际创建 11 项） (src: ai, 冷启动演练)
- [ ] [2026-10-07] (文档) dev-init 演练整改包（2026-10-07 余 7 项）：实测命令 FAIL 卡点口径 / 实测前副作用面审查提示 / 基线与白名单登记顺序拼合 / ctx-audit --init ❓ 项标对应步骤号 / skill-verify 语义确认保留通道 / 硬卡点 [存量对账] docs 项适用新建 docs/ 情形 / §2 写明 todos v3 口径 (src: ai, 冷启动演练)
- [ ] [2026-10-07] (功能) bugpack 脚本：抓 git diff + 最近报错日志/堆栈 + 环境与依赖版本 → 密钥脱敏后拼装结构化 Bug 报障 Prompt（三段式：预期vs实际/复现证据/代码与环境，problem-triage manual.md §1.5 口径）；日志脱敏是硬门槛，走 toolbox new→check 登记制 (src: ai, 用户确认)
- [ ] [2026-10-07] (优化) dtrig 默认扫 /tmp/logs、四工具报告导 /tmp 易失：项目池登记时把持久日志路径约定进项目 skill（dev-init/README 提示） (src: ai, 体系审计)
- [ ] [2026-10-07] (优化) [long] 待办缺 ::done 外的重评节拍：长跑 epic 数月不收尾则到期债无提醒——::audit 加时效项或 panel 待办计数旁标 [long]/[once] 过期条数 (src: ai, 体系审计)
- [ ] [2026-10-07] (优化) 跨项目待办/备忘无落点：memo-collector 路由仅域内/全局misc 两级，A 项目窗口聊出的 B 项目事项 B 侧恢复/::next 永远看不到——评估路由加跨项目行或以 ~/.agents/context 常驻仓为跨项目层 (src: ai, 体系审计)
