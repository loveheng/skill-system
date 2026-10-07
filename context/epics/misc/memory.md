---
dev-loop: memory
format: v1
epic: misc
total-merged: 3
last-merge: 2026-10-07
---

# misc

体系仓自身的常驻散修挂靠：skill/脚本/协议级改动的状态与断点记此，内容 SSOT 仍是对应 SKILL.md/README。

## 状态
- [2026-10-04] 全局评审修复落定：单仓表述统一/开场钩子归位/挂载审计闭环/ctx-audit 接线/隐私拒存护栏/体系仓 context 骨架/月度复盘节拍/skill 退役口径（§4.4 第 5 条）。
- [2026-10-04] panel 债面层上线：默认事实块加债行（U/D/P 粗计数+体检时效）+ --debt 明细档；系统仓排除工具池自匹配。
- [2026-10-07] copilot-context skill 整体退役（chat 域 18 天仅 2 项目近骨架使用、与 dev epic 双轨冗余）：panel --chat/--chat-init 模式、开场判域、COMMANDS §3（§4-§6 重编号）、白名单 forget、dev-init 模板判域行、memo-collector 聊天节全清；goodshare/shiguang 已 git rm context/chat。
- [2026-10-07] mount-init 上线：::bind 机械件单一入口（slug/墓碑/重复挂载/切换前置机械拦截 + 骨架/CURRENT 一键；--create-doc/--current-only/--dry-run），AI 不再手拼骨架。
- [2026-10-07] todos 两级落点四件套落地：域文件按需创建 + 全局 misc 兜底、todos 工具（add/done/rm/move/list）、路由写死 memo-collector §0、panel/ctx-lint 联动、goodshare 43 + shiguang 2 条存量迁移。
- [2026-10-07] panel 并行信号：非 misc epic ≥2 且近 2 天活跃即事实块加「并行:」行（git 现场推导零缓存），绑定卡同步「恢复请点名任务」。
- [2026-10-07] 体系审计三项落地：①恢复协议加排查交接例外（tail 扫 [排查交接] 续读，problem-triage §3.6 口径收拢）②::adr 二选一显式留痕 + ::audit 第 9 项 decisions↔memory 契约对账 ③memo-collector 判定表新增事实行 + 咒语全局级 AGENTS.md 去向 + description 修至 532；4 条改进建议入 misc 待办（跨项目落点/暂记 ≥3 兜底/[long] 重评节拍/dtrig 持久日志路径）。
- [2026-10-07] fact-probe 上线（fprobe/env/全局池）：workflow 事实源取证底稿（构建系统/候选命令/测试框架/CI/结构/skill 现状），定位取证器非生成器（底稿严禁直接采信）；dev-init §1 第 3 步取证捷径 / §1.5 重验捷径接线。
- [2026-10-07] skill-verify 上线（sver/docs/全局池）：三 skill 路径/命令/FQN 锚点对仓库现实批量机械校验（精度优先，判不准不报）；dev-init §1.5 重验捷径 + ::audit 第 9 项代跑口径接线。
- [2026-10-07] ctx-audit --init 接入验收机械档：dev-init §2 机械项一条命令聚合（骨架/gitignore/数据面/skill 在场/docs 卡点/白名单/项目池/机器件 fail-open/锚点/description 预算）+ 4 项人判 ❓ 另计；§1 第 9 步改机械档先行。体系审计三条脚本化建议（fact-probe/skill-verify/验收档）至此全部落地。

## 断点
- [断点] 下一步：等待散修任务
