---
memo: done
format: v2
---

# 完成列表
- [2026-10-20] scaffold 三模板接线：workflow/index/docs skill 骨架改由 dev-init templates/ 搬运（mk_tmpl + TMPLDIR 探测 + sed 替换 <repo>，幂等不覆盖）；standards 不自动发（须代码提炼）——self-test OK + 冒烟占位符零残留 (src: ai, 用户确认) (域: misc)
- [2026-10-07] skill-verify 脚本：三 project-local skill 锚点批量校验（grep 提取路径/类名锚点→批量 test -e），dev-init §1.5 第 1 项机械半边自动化、语义核实留 AI——形态对齐 ctx-audit「机械项委托」 (src: ai, 体系审计) (域: misc)
- [2026-10-07] 冷启动接入验收档：ctx-audit 加 --init 档聚合 dev-init §2 机械项（check-ignore/YAML 头/机器件在场/description 预算/指针可 grep），验收从手工逐项变一条命令 (src: ai, 体系审计) (域: misc)
- [2026-10-15] skill 体系：给确认/提问设预算——同类确认合并、设轮次上限，防确认疲劳致「同意默认」失效确认机制 (src: ai) (域: misc)
- [2026-10-15] skill 体系：精修各 skill description 路由行（dev-loop/dev-guide/problem-triage/memo-collector 重叠区），降误触发省上下文 (src: ai) (域: misc)
- [2026-10-15] skill 体系：放宽 dev-loop 快车道判据，让更多小改轮免评估/台账仪式，降每轮过程税 (src: ai) (域: misc)
- [2026-10-20] 暂记备忘自计数兜底：memo-collector §1 触发点间仅对话内暂记、重置即弃——窗口内暂记 ≥3 条自动提前批量落盘（触发点 0） (src: ai, 体系审计) (域: misc)
- [2026-10-20] skill 体系评估 P5/P6：memo-collector v1-v3 迁移史压缩为版本注记；~/.agents/README.md 补 updated 字段并自审过程叙事；dev-init description 预算 250 字符口径指向 audit 550 上限出处 (src: ai) (src: ai) (域: misc)
- [2026-10-20] project-scaffold 模板欠账：todos 模板 v2→v3（对齐 memo-collector 现行）+ 横幅「dry-run，不落盘」误标纠正（实际创建 11 项） (src: ai, 冷启动演练) (域: misc)
- [2026-10-20] dev-init 演练整改包（2026-10-07 余 7 项）：实测命令 FAIL 卡点口径 / 实测前副作用面审查提示 / 基线与白名单登记顺序拼合 / ctx-audit --init ❓ 项标对应步骤号 / skill-verify 语义确认保留通道 / 硬卡点 [存量对账] docs 项适用新建 docs/ 情形 / §2 写明 todos v3 口径 (src: ai, 冷启动演练) (域: misc)
- [2026-10-20] skill-verify 代码符号锚点（如 todo.DB）被当文件路径误报，ctx-audit --init 只认 exit 0 无「语义确认保留」登记通道——补通道防机械件逼出反优化措辞 (src: ai, 冷启动演练) (域: misc)
- [2026-10-20] 跨项目层通道演练条目 (proj: goodAccount) (src: ai) (域: misc)
- [2026-10-20] dtrig 默认扫 /tmp/logs、四工具报告导 /tmp 易失：项目池登记时把持久日志路径约定进项目 skill（dev-init/README 提示） (src: ai, 体系审计) (域: misc)
- [2026-10-20] 待办缺 ::done 外的重评节拍：长跑 epic 数月不收尾则到期债无提醒——::audit 加时效项或 panel 待办计数旁标 [long]/[once] 过期条数 (src: ai, 体系审计) (域: misc)
- [2026-10-20] 跨项目待办/备忘无落点：memo-collector 路由仅域内/全局misc 两级，A 项目窗口聊出的 B 项目事项 B 侧恢复/::next 永远看不到——评估路由加跨项目行或以 ~/.agents/context 常驻仓为跨项目层 (src: ai, 体系审计) (域: misc)
- [2026-10-20] bugpack 脚本：抓 git diff + 最近报错日志/堆栈 + 环境与依赖版本 → 密钥脱敏后拼装结构化 Bug 报障 Prompt（三段式：预期vs实际/复现证据/代码与环境，problem-triage manual.md §1.5 口径）；日志脱敏是硬门槛，走 toolbox new→check 登记制 (src: ai, 用户确认) (域: misc)
- [2026-10-20] skill 体系评估 P3：建立遵循率遥测——为收集触发点/dev-guide 卡点等 2~3 个关键行为设计轻量抽样脚本 (src: ai) (src: ai) (域: misc)
- [2026-10-20] skill 体系评估 P1/P2：dev-loop 规则密度超可执行阈值、交叉引用网自指维护成本高——做一轮减法复盘，用 usage-ledger 找 30 天未触发的写死规则 (src: ai) (src: ai) (域: misc)
