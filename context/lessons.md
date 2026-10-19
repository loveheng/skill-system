---
dev-loop: lessons
format: v1
epic: global
total-merged: 1
last-merge: 2026-10-07
---

# lessons

体系运维教训（四段式：现象 | 根因 | 处置 | 回归——2026-10-20 升舱，口径=dev-loop REFERENCE §2），按主题归类的正文行不以 `- [` 开头（该前缀专属底部追加区，保 grep 计数纯净）；归并门禁：缺回归段不进正文。

## 测试隔离

模块级外部状态（DB 路径、连接句柄等）一律惰性解析（函数内读 env/配置），严禁 import 时绑定——import 时绑定会让测试的 `mock.patch.dict(os.environ)` 失效，测试静默读写真实数据文件（2026-10-07 冷启动演练实测：覆盖丢 1 条存量 `~/.todo-cli.json`）。跑陌生项目的测试前先审副作用面（会写哪些真实路径）。

## toolbox

校验池内既有脚本直接跑 `--self-test` 或显式 `--scope global`——`toolbox check` 传池内脚本路径会把脚本移动进 scope 对应池（scope 默认随 cwd 解析为 project，全局池副本消失）；登记新脚本一律显式传 `--scope`（2026-10-07 实测）。

## 测试外生性

测试判定权外生于执行者：黄金基准与核心测试只读、禁改宽断言/删用例/加 Mock 凑绿（Goodhart 效应，2026-10-15 定调）→ 规范已收编，执行口径以 dev-loop §2「测试写保护」为唯一事实源 (Ref: dev-loop)。
