---
memo: todos
format: v3
---

# 待办列表

## misc
- [ ] [2026-10-20] (优化) [long] dev-loop SKILL/REFERENCE 分层重组（复盘张力①排期）：SKILL 217 行细则实居与「分层铁律」声明相悖（REFERENCE 仅 92 行），重组牵动全部外部 § 引用网——需逐节核对引用方后排期实施（::audit 2026-10-20 补记口径） (src: ai) (src: ai)
- [ ] [2026-10-20] (功能) [挂起] ctx-ratio v2① proxy 缓存感知：侦查结论=CTX_PROXY_USAGE_FILE 未配置、无生产者、无样本，cache 字段存在性不可验证——等真实 proxy 环境出现后取样本再实施（zcode/cc 路径 L70-185 已读 cache 字段可复用同口径） (src: ai, v2 排期)
- [ ] [2026-10-20] (优化) [暂缓] ctx-ratio v2② devlog 文件重叠度：无实证痛点（归并已三通道触发），按「无实例不做」纪律挂起，观察到真实归并漏检再立项 (src: ai, v2 排期)
- [ ] [2026-10-20] (优化) goodhub-workflow lessons 节降级 Ref（移交件已出，快照 39ef9e2）：协议正文已升舱为 dev-loop REFERENCE §2 全局 SSOT，goodhub 侧删节内协议正文留薄指针——由用户在 goodhub 仓执行 (src: ai, 跨库移交) (src: ai)
- [x] [2026-11-08] (风险)(proj: goodhub)(层:L0)(重:中) W6-a 宿主缺陷 A（**taskPool 接线缺失**，2026-11-08 已修复；原「装载窗口空窗」系误判已更正——primitive `completeStream` 本有「未就绪→立即抛」，装载窗口不存在）：`reverse_wiring.dart` 装配点 executor 未传 `taskPool` → `allow_deferred` 请求永不入池，冷态只能同步报错（非 queued 回执）。已修：补 `taskPool: SupplyTaskPool.instance`（驻留单例，仅 allow_deferred=true 生效，存量 failFast 零变化）；真机「90s 无响应」实为环境事实 B（freezer 冻结）所致。复验 = goodshare W6-a 验收 2–6 (src: goodshare W6-a 联调 2026-11-07/08，证据链在 goodshare ai-app-split devlog)
- [ ] [2026-11-07] (风险)(proj: goodhub)(层:L0)(重:轻) W6-a 宿主侧环境事实 B（**系统 freezer 冻结后台进程**，非 app 代码缺陷；原「UI isolate 挂死」系误判已更正）：实证——goodhub 退后台约 2min 后 `dumpsys` 显示 `isFrozen=true`，期间整进程无响应（debug 桥 HTTP / logcat 全停、进程存活 pid 不变），前台化后 `isFrozen=false` 即刻恢复（45807 桥秒回）。模型实际从未装载（Native Heap 21MB，21:19 日志为 warmup=bind 非装载）。影响：宿主后台冻结期间反向请求无响应 → 消费端 90s 超时/快速失败 → 解冻后恢复（消费端「宿主不可用跳过下轮重试」语义天然覆盖，No Active Polling 纪律不变）。可选加固（不阻塞验收）：bind 期间 UI 进程 FGS 保护（进程模型级改动，另立排期） (src: goodshare W6-a 联调 2026-11-07/08，dumpsys isFrozen 实证)
- [x] [2026-11-08] (风险)(proj: goodhub)(层:L1)(重:中) W6-a 宿主缺陷 D（**聊天 Run 收口连带断驻留 bind**，2026-11-08 已修复）：根因 = `transportId` 确定性生成（`local:<pkg>_<serverId>`）+ native `transports.computeIfAbsent(id)` 共享单条连接 + `close → remove(id).close()` 销毁共享连接——聊天 Run 收口 close 自己的 Dart 实例即 unbind 驻留连接（「模型装载唯一入口 = 聊天 Run × Run 收口必拆 bind」死循环）。已修：`binder_transport.dart` 增 `_liveByTid` 引用计数（构造 +1/close -1，最后一个持有者才 native close，否则路由槽转让），单连接语义保持、native 零改动。复验：Run 收口后 `McpBinderService` 无 onDestroy、验收 2 温热直出 ✓（[AI-CAP] ms=206 同步 Immediate）、验收 3/4 复测 ✓。**第二面已修（同日）**：goodshare 进程被杀后 goodhub 不自动重 bind——根因 = 自愈仅挂在 send（DEAD→rebind）而 idle 无人 send（task-consume 无常驻轮询、心跳仅推理期）+ force-stop 置 stopped state（BIND_AUTO_CREATE 不拉起）。已修：native `HostTransport` 断连退避自愈重连（`scheduleReconnect`：1s→60s 封顶指数退避，四条断连路径统一挂调度，connected 归零，宿主 close 置 closedByOwner 永久停止）。复验：force-stop 杀进程 → am start 重启 → `reconnect attempt #2` 自动重 bind（onCreate+attach）→ 回前台 35s Pull 零 not_ready，全程无 send/聊天/重启 (src: goodshare W6-a 复验 2026-11-08)
- [ ] [2026-11-08] (暂缓)(proj: goodshare)(层:L1)(重:轻) W6-a 验收 5/6 真机补验（待 debug 设施，不依赖缺陷 D/D 已修）：⑤ not_found 失败收敛——需假 task_id 注入设施；⑥ stale 收敛——需正文修改通道（HTTP MCP server 未运行 `mcpRunning:false`，`update_item` 走不通；或 debug action 注入）——两者收敛逻辑均由 `on_device_service_test` 16 例单测覆盖，待补的是真机 UI 收敛表现 (src: goodshare W6-a 复验 2026-11-08)
