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
