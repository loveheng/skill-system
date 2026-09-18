---
name: dev-guide
description: 大需求开发、结构性重构或复杂 Bug 修复时的流程引导 Check List，含跨 skill 指针速查（交互指令与项目专属命令路由）。单文件微调、散修（挂 dev-loop misc）、纯咨询/问答/代码解释勿加载本 skill。
---

# dev-guide · 开发流程引导（薄路由）

> **管辖边界**：本 skill 只做「阶段引导 + 卡点检查 + 命令速查」，零裁决权、零规范正文——冲突裁决链归 dev-loop（memory 决策 ＞ 项目 skill ＞ 通用规约），被覆盖时无声让位。
> **前置条件**：假设 dev-loop 状态恢复已完成（CURRENT + memory.md 已读），本 skill 不重复定义恢复流程。
> **指针格式**：有节号用 §，纯命名节用「节名」——指针必须可 grep，写入前必须核对锚点真实存在。

## 0. 入口判定

- 大需求 / 结构性重构 → 走 §1 需求流
- Bug / 报错 / 异常 → 走 §2 修复流
- 散修 / 小改动 / 纯咨询 → 不走流程、不输出卡点标记，按 dev-loop §2 挂 misc
- 新项目/新仓库首次接入 skill 体系（或补缺项目 skill）→ dev-init（项目级一次性接入引导，不在本 skill 范围）

## 1. 需求开发流（每步一行，规范正文全在指针出处）

1. 绑定 epic → dev-loop `@bind`（切换且旧 epic 有积压时先归并）
2. 拆解落断点 → dev-loop `@next`（≤3 候选，选定后落盘为断点）
3. 定位落点 → project-index L1/L2（项目实例 = 各 repo 的 project-local index）
4. 写码 → 当前项目规范 skill（按描述自动加载，勿额外整读全文）
5. 验证 → 当前项目索引「命令速查」节
6. 文档联动 → 项目 docs 规范 skill（触达对外契约或域核心流程时）
7. 落盘 → dev-loop §2 日志协议（自动，勿重复落）

**硬卡点**（缺卡 = 流程未完成）：
- 定位完成：`[落点] <域> <代码路径> <文档路径>`
- 验证完成：`[验证] <命令> → 通过 / 跳过原因`
- 收尾：`[收尾] 日志已落 <epic>/devlog；文档联动: 是/否(理由)；断点已刷新`

## 2. Bug 修复流

1. Lessons 对照 → dev-loop §2 第 2 条（先读 lessons 正文再动手）→ 卡点 B1
2. 环境限制 → 当前项目 workflow 类 skill（终端/写入限制先行）
3. 定位 → project-index L1/L2
4. 根因修复 → 涉 native 构建走项目 native skill 的排查套路 → 卡点 B2（修复落地**前**输出）
5. 验证 → 当前项目索引「命令速查」节
6. Lesson 判定 → 具备通用价值才按 dev-loop §2 记 lessons → 卡点 B3

**硬卡点**：
- 开工前：`[Lessons 对照] 命中 N 条 / 未命中 / 未命中 → 降级散修`
- 修复前：`[根因] <一句话根因>`
- 收尾：`[Lesson 判定] 具备通用价值: 是→已落盘 / 否→理由`

**降级散修条款**：
- 判据：单文件 + 无行为契约/配置/schema 变化 + 预计一轮完成（typo/文案/注释级）
- 退场只设在步骤 1；进入定位后不退场（剩余卡点各一行，成本可忽略）
- **降级只退本 skill 卡点，不退 dev-loop §2 日志义务**——产生 Diff 照样挂 misc/devlog
- `降级散修` 出现频率 = 流程误触发率遥测；频繁出现应收紧本 skill 的 description

## 3. 命令速查（聚合视图——行内只有场景 + 指针，命令正文以出处为准，禁止复述）

### 通用区
| 场景 | 去处 |
|---|---|
| 交互指令（@file @bind @next @remember @adr @status @merge @audit @verify @done @help） | dev-loop §3-§9 |
| 备忘指令（@todo @todos @tdone @todo-clean @todo-groom） | memo-collector §3 |
| 代码/文档定位协议（L1/L2 两级展开） | project-index |
| 构建/验证/lint 等项目专属命令 | 当前项目仓库 project-local 索引的「命令速查」节（机制见 project-index；换项目零编辑） |


## 4. 卡点纪律

- 标记仅在**本 skill 加载的引导轮次**要求；散修/咨询轮零标记
- 标记是聊天输出物，**严禁写入 devlog**——落盘一律走 dev-loop §2 通道，防双写
- 每卡 ≤1 行；与 dev-loop 自动归并附注同轮出现时合并展示，回复尾部不堆叠

## 5. 维护协议

- 新指针写入前核对锚点；被引用 skill 改节号/节名的**当轮**，grep 引用方同步
- 检测网 = dev-loop @audit 第 9 项（指针抽查）+ 第 10 项（skill 卫生：事实指针化 + description 预算）；指针锚点存在性已由 audit 钩工具 context-lint 机械代跑（2026-09-19 起；中文数字节号与裸 § 自引用仍人工抽查）
- 本文件软上限 ~80 行；超限先砍描述密度，禁止往里加规范正文
