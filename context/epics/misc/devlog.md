---
dev-loop: devlog
format: v1
epic: misc
total-merged: 3
last-merge: 2026-10-07
---
- [2026-10-07] [变更]: 吸收外部 Debug 模板四增量进 problem-triage（评估后未采纳原样装入——避免与既有排错 SSOT 双源/输出模板与 dev-loop §1 冲突/无落盘接线）：①新增 §3.7 根因排查纪律（首次产生点锚定：报错抛出点只是症状/假设-验证句式与 [待验证假设] 同口径/最小侵入+影响面走 project-index/红线指针到 ai-sideeffect-guard §1·solution-admission §1·dev-loop 护栏 5/6）；②§3.5 解决验收升级：代码侧 MRE 先红后绿硬证据（非代码侧探针/监控证据替代，禁假测试）+ 同模式扫描（grep 兄弟代码点经确认处置）；③manual.md 新增 §1.5 三段式报障输入（预期vs实际/复现证据原样贴/代码与环境+密钥抹除+复现条件）；④bugpack 自动收集脚本入 misc 待办单开一轮（登记制+脱敏硬门槛）
- [2026-10-07] [验证]: 新锚点 grep 全命中（§3.7 四条/§3.5 两增量/manual §1.5）；被指节存在（ai-sideeffect-guard §1/solution-admission §1/dev-loop 护栏 5/6）；problem-triage 既有节号未动（§3.1-3.6 指针稳定，dev-loop §3 交叉引用不受影响）；context-lint 复跑
