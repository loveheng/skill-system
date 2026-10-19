---
dev-loop: memory
format: v1
epic: misc
total-merged: 6
last-merge: 2026-10-20
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
- [2026-10-07] devlog.sh change 强制验证配对上线：`--verify "<命令 → 结果>"` / `--no-verify "<原因>"` 二选一合同（缺一 FAIL、JSON 预检同拦、--json 裸跑契约顺带修复），自测扩至 18 项；[变更] 从此不允许裸奔（§2.4 验证账本的机械面），独立补验/复验仍走 verify 子命令。
- [2026-10-07] dev-loop V3.7 减重：§5-§8 执行细则拆 REFERENCE.md 细则层（SKILL.md 251→217 行，摘要+指针、节号稳定外部引用不变；细则修改只改 REFERENCE）；外部评估采纳口径——配对机械化的源头条 + 热路径减法，「弱模型档位」「砍 description 预算」不做。
- [2026-10-07] 冷启动演练（体系外执行者首次验证闭环）：全新子代理仅凭 dev-init 接入 /tmp/coldstart-drill/todo-cli 全绿（硬卡点 4/4、ctx-audit --init exit 0、panel 绑定卡可出）；9 卡点 12 建议——4 项即修（dev-init §0 空白板定义 / §1-5 无 docs 分支补句 / §1-3 样例指针改 goodshare / §2 audit 口径），余 7 项整改包 + scaffold 欠账 + skill-verify 语义通道入 misc 待办；副作用披露：演练测试曾覆盖 ~/.todo-cli.json 损失 1 条存量（根因已修，教训入 lessons）。
- [2026-10-11] ctx-ratio 上线（docs/全局池）：总量%+RCR 双阈值+冷却锁+排错豁免+fail-open，触发接 §4 归并（触发方式扩为三）；数据源自适应 zcode/cc/proxy/stdin——zcode 定位走 cli db session.directory 精确匹配 + 尾部渐进窗兜底（开场目录与 system prompt 锚点均会说谎），usage 正则提取、峰值行取消息文本、total 取峰值防旁路小请求污染；panel 状态行 ctx: 字段；首跑即真实命中（86%｜RCR 8%）。v2 候选（proxy 缓存感知/devlog 文件重叠度/宿主 compact 建议）待排期。
- [2026-10-15] 决策（ADR 轻量级防御演进）：白名单=反事实存活探针（可 GC）·规则=禁零触发 GC（不对称）；拒 PID 锁/自动 worktree，采 flock+mkdir 原子原语；593%=长会话陈旧累积，暴露 resident% 以事实替代恐慌。1–3 项（白名单探针/resident%/锁原语）本轮实施。
- [2026-10-11] ctx-ratio n/a 归因五态改造：probe 拆分 未装/无会话/数据不足/未配置/文件无效，bare/brief/json 逐源留因。
- [2026-10-15] 评估修订四件套：lessons 测试外生性断言 / dev-loop 测试写保护+Expand-Contract+跨库只读评估-移交 / solution-admission Spike-Solidify 双轴 / agent-toolbox 薄 CLI 管道原则；mscan 最小变异工具上线（含 dart）；dev-loop 瘦身 232→126 行细则下沉 REFERENCE；提问预算 + description 互指路由 + 快车道 ≤3 文件。
- [2026-10-17] safe-patcher 写门禁两轮迭代：hook 基础设施故障 fail-open 放行、语法器超时 fail-closed、拦截面收敛 CODE_EXTS；降级台账试装后拆除（坏块拦截已在写入口完成，台账无消费场景），self-test 11/11。
- [2026-10-19] 决策留档与生命周期改造：dlog 工具（决策条目→挂载文档「决策日志」/misc-decisions.md 双通道）、维护态生命周期（devlog close/reopen/clear，目录不搬）、临时绑定（--temp/--restore base 行）、context-lint CURRENT 双态校验与规约同步。
- [2026-10-20] ::audit 补记（架构自洽评估）：两处张力待收敛——①dev-loop 薄指针与一行口径复述边界模糊（REFERENCE 仅 92 行，细则实居 SKILL）②toolbox 规范 SSOT 双声明（SKILL.md vs mgr 内嵌 spec，上位关系未写明）；归并阈值失灵已由本轮归并修复（20 条积压）。

## 断点
- [断点] 下一步：goodhub 仓执行移交件（用户侧）；ctx-ratio v2：③ 已落地，① 挂起待 proxy 样本，② 暂缓
