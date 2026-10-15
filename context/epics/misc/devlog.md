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
