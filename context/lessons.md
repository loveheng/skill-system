---
dev-loop: lessons
format: v1
epic: global
total-merged: 1
last-merge: 2026-10-07
---

# lessons

体系运维教训（现象 ➔ 根因 ➔ 避坑规则），按主题归类的正文行不以 `- [` 开头（该前缀专属底部追加区，保 grep 计数纯净）。

## 测试隔离

模块级外部状态（DB 路径、连接句柄等）一律惰性解析（函数内读 env/配置），严禁 import 时绑定——import 时绑定会让测试的 `mock.patch.dict(os.environ)` 失效，测试静默读写真实数据文件（2026-10-07 冷启动演练实测：覆盖丢 1 条存量 `~/.todo-cli.json`）。跑陌生项目的测试前先审副作用面（会写哪些真实路径）。

## toolbox

校验池内既有脚本直接跑 `--self-test` 或显式 `--scope global`——`toolbox check` 传池内脚本路径会把脚本移动进 scope 对应池（scope 默认随 cwd 解析为 project，全局池副本消失）；登记新脚本一律显式传 `--scope`（2026-10-07 实测）。

## 测试外生性

[WHEN] 核心业务重构或让 AI 驱动测试修复时 → [DO] 锁定黄金基准与核心测试文件（如 `tests/core/`、`tests/golden/`）为只读契约，严禁执行者通过修改、放宽断言或删除用例使测试通过——验证判定权必须外生于执行者 → [VERIFY] `git diff --stat tests/core/` 变更为 0，且核心套件 Exit Code 为 0（2026-10-15 评估定调：Goodhart 效应，AI 擅长改宽断言、加 Mock、删用例让红灯变绿；自产自销的测试易成同义反复，100% 覆盖率测了个寂寞）。
