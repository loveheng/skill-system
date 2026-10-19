---
dev-loop: devlog
format: v1
epic: misc
total-merged: 5
last-merge: 2026-10-11
---
- [2026-10-11] [变更]: n/a 归因改造：probe 拆分 未装/无本会话/会话数据不足/未配置/文件无效 五态，bare/brief/json 三形态逐源留因——消除 不支持 与 探测不到 的歧义
- [2026-10-11] [验证]: self-test 七用例过; /tmp 实测 n/a 归因输出; .agents --json 实测正常态(49%/17%); panel brief 归因实测过
- [2026-10-15] [变更]: 评估修订落地：lessons 增测试外生性断言；dev-loop 增测试写保护+Expand-Contract；solution-admission 合入 Spike/Solidify 双轴；agent-toolbox 成文薄 CLI 管道原则
- [2026-10-15] [验证]: 未执行: 纯规范/记忆文本修改，无编译或测试验证面
- [2026-10-15] [变更]: 新增 mutation-scan(mscan) 最小变异测试工具:条件/边界/布尔变异注入,基线绿门禁+还原校验+金丝雀双场景,登记全局池
- [2026-10-15] [验证]: mscan --self-test → 通过(真测试全杀灭/空心测试检出存活);toolbox check --scope global → 登记
- [2026-10-15] [变更]: mscan 增加 dart 支持:.dart 扩展名复用 Java 同构算子,测试文件约定 *_test.dart
- [2026-10-15] [验证]: dart 样本 dry-run → 变异点正确;mscan --self-test → 回归通过
- [2026-10-15] [变更]: 轻量级防御演进 1–3 项落地：① dscan/uscan/ascan 白名单反事实存活探针（逐行归因，失效行=当前未抑制任何发现，进 --md 失效白名单节+--json stale_whitelist，0/1/2 契约不变，⚠ 裁决收口 ::audit 第 11 项）② resident%（元系统常驻占用，仅展示不触发）进 ctx-ratio brief/bare/json + WINDOW_MAX 校准口径文档化（params.env 敏感文件被拒编辑，注记落工具头部口径）③ devlog bp 读改写包 flock（锁点 .bp.lock，-w 15s，进程退出自动释放，flock 缺失降级无锁）+ mount-init mkdir 原子认领（dry-run/--json 不认领）+ panel 并行行附样板 worktree 建议命令（仅建议不执行）+ .gitignore 收编 .bp.lock/.bp.tmp
- [2026-10-15] [验证]: 自测 7/7 绿：dscan/uscan/ascan/ctx-ratio/devlog/mount-init/panel（新断言：三工具存活探针/常驻 6%/断点锁点/T11 原子闸门/并行 worktree 行）
- [2026-10-15] [变更]: mount-init 自测加固：进沙箱前 SELF 绝对化——相对 $0 调用时 exec_self_test cd 进 $T 后脚本失路径，T1 静默失败（快检相对调用暴露的既有潜在缺陷，非本轮功能改动引入）
- [2026-10-15] [验证]: mount-init 自测三种调用形态绿（仓库根相对/scripts 目录相对/绝对路径）
- [2026-10-15] [变更]: 新增跨库只读评估-移交协议条款（dev-loop §2 + decisions.md ADR）
- [2026-10-15] [验证]: 未执行: 纯规约文档变更，无可执行验证
- [2026-10-15] [变更]: dev-loop 瘦身重构：SKILL.md 41.3KB→12.9KB（232→126 行，§0-§9 节号不变），§2/§3/§4 细则全文下沉 REFERENCE.md，正文收敛为一行 toolbox 调用规范
- [2026-10-15] [验证]: grep §0-§9 节号完整 → 通过；wc 前后体积核对 → 通过
- [2026-10-15] [变更]: skill 体系副作用治理三项落地：①提问预算（护栏0+台账>4收敛或分批+REFERENCE 五条细则）②dev-loop description 去独占式声明、改互指路由 ③快车道判据放宽（≤2→≤3 文件+连续小修默认沿用）
- [2026-10-15] [验证]: description 443/272/511/533 均 <550 上限 → 通过；grep 提问预算 SKILL+REFERENCE 各 1 处 → 通过；3 条待办流转 done.md → 通过
- [2026-10-17] [变更]: safe-patcher 写拦截 fail-open 加固：hook 基础设施故障(配置损坏/缺run/超时/执行异常)降级⚠放行不阻塞写路径，语法检查器超时同步降级；拦截面收敛 CODE_EXTS 仅代码文件做语法预检与 hook，md/骨架/文案直写不拦；OK 消息携带告警池；self-test 扩到 9/9
- [2026-10-17] [验证]: toolbox run safe-patcher --self-test → self-test: 9/9 通过
- [2026-10-17] [变更]: safe-patcher 门禁闭环：分流策略落地（hook 基础设施故障 fail-open 放行+落台账 DEGRADED_PASS，127 作为判定/故障分界；语法器超时/异常 fail-closed 阻断 SYNTAX_CHECK_TIMEOUT+落台账 BLOCKED）；台账函数 log_degradation_event 写全局 usage-ledger.jsonl（与既有记录同构，env 可覆盖供 self-test 隔离），自身故障不影响写路径；修复 YAML 解析错误掉进 fail-open 的洞（YAMLError 转语法错误）；self-test 扩到 11/11；audit 第 11 项接入 7 天降级台账消费规则（DEGRADED_PASS ⚠/BLOCKED 🛑）
- [2026-10-17] [验证]: toolbox run safe-patcher --self-test → self-test: 11/11 通过
- [2026-10-17] [变更]: safe-patcher 移除门禁降级台账机制（log_degradation_event/TOOLBOX_USAGE_LEDGER/audit 第11项消费规则全拆）：坏块拦截本就在写入口完成（语法坏=Rejected 零写入），语法对/逻辑错归编译器管辖，台账无可记事件且无消费场景；保留行为：hook 故障 fail-open 会话内⚠自纠、语法器超时 fail-closed SYNTAX_CHECK_TIMEOUT、self-test 11 用例不变
- [2026-10-17] [验证]: grep 残留=0 + safe-patcher --self-test 11/11 + 坏语法冒烟 exit 1 [remedy] 正确
- [2026-10-19] [变更]: 决策留档与生命周期机制改造：①新增 dlog 工具（devlog 决策条目→挂载文档「## 决策日志」/misc-decisions.md 双通道机械化归档+collect 只读聚合）②维护态生命周期（devlog close/reopen/clear+写护栏，epic 目录不搬，archive 仅真退役）③临时绑定（mount-init --temp/--restore，CURRENT base 行，防并行日志错位）④盘点修复（context-lint CURRENT 双态校验/维护态孤儿豁免/SELF 绝对化）+ 规约 §3/§4/§8 去重契约与口径同步
- [2026-10-19] [验证]: panel/mount-init/ctx-status/devlog/dlog/context-lint 六脚本 self-test 全绿 → 通过
