# toolbox — 全局脚本工具箱

人类与 AI 共用的脚本管理运行时。管理器（规范 SSOT）:
~/.agents/skills/agent-toolbox/toolbox-mgr.py（只搬运，严禁重生/手改副本）

## 快速上手
  toolbox spec                 查看脚本编写规范（v1.5，唯一事实源）
  toolbox new <name>           生成脚手架（默认 shell 语言、项目池；--lang python / --scope global 可选）
  toolbox check <path>         校验并登记（文件移入工具池）
  toolbox propose <path>       脚本入提案队列（过静态门禁，等人审批）
  toolbox approve [--all]      审批提案队列（默认列队；--all 全收 / --name 指定收）
  toolbox list                 派生清单（⚠ = 不合规；[类别] 与 [服务型 verbs: ...] 一眼可辨）
  toolbox suggest              上下文感知推荐（读 git 变更推断类别，开局跑一次）
  toolbox recent [-n N]        近期使用工具摘要（断点恢复/新会话开局注入）
  toolbox run <工具|别名> [args...]   运行工具（KEY=value 内联覆盖参数，其余原样透传，无需 -- 分隔）
  toolbox run <工具> --chain   成功后依次执行头部 after: 声明的后续工具
  toolbox run-hooks <hook>     执行钩子（bootstrap/audit/cron/pre-commit）
  toolbox install-hooks        接线登录检查/cron/pre-commit（--remove 卸载）
  toolbox remove <name>        退役 → .trash/

## 按类别查（防清单膨胀）
  toolbox list --cat <类别>    只拉该类目的小片清单；查空时回显现有类别与语义映射

需求 → 类目映射（惯例，不强制枚举）：
  构建/编译 → build    测试/验证/冒烟/回归 → test    部署/发布 → deploy
  环境体检/依赖探测 → env    服务起停/进程运维 → ops    文档/索引校验 → docs

## 服务型工具（持续运行类）
头部声明 `verbs: run,stop,status,restart`（可子集）即可用前置动词，等价于 run 透传：
  toolbox <stop|status|restart> <工具> [args...]
约定：run 支持 `--daemon`/`-d` 后台模式（nohup 脱终端、日志定向文件、存活确认）；
stop 幂等（未运行 exit 0）；status 可安全重复；restart 单目标。一次性工具不得声明 verbs，
对其用前置动词会被拒绝（exit 2）。

## 常用全局工具（按类别，`toolbox list --cat <类别>` 看全量）
  toolbox run scaffold         # 新项目 skill 体系骨架一键初始化（context/ + 白名单 + .agents/skills + 项目池）[ops]
  toolbox run envdoc           # 环境体检（Java/GraalVM/docker/git 损坏 + 开场协议部署一致性）[env]
  toolbox run fact-probe       # workflow 事实源取证底稿（构建系统/候选命令/CI/结构线索；dev-init §1 第 3 步 / §1.5 重验配套，alias: fprobe）[env]
  toolbox run skill-verify     # project-local skill 锚点批量校验（路径/命令/类名 FQN 对仓库现实；dev-init §1.5 / ::audit 第 9 项配套，alias: sver）[docs]
  toolbox run cl               # context 记忆体系机械校验（含挂载行）[docs]
  toolbox run ctx-audit        # @audit 12 项清单呈现（--init = dev-init §2 接入验收机械档，人判 4 项另计）[docs]
  toolbox run panel            # 开场绑定卡/::help/::board/::bind 候选的事实块（--root/--board/--deep/--debt/--mounts）→ dev-loop §3/§6；默认块含债行（U/D/P 粗计数+体检时效）
  toolbox run mount-init --epic <名> --doc <docs/...md> [--create-doc]
                               # ::bind 机械件：挂载骨架+CURRENT 一键初始化（--current-only 仅切指针；alias: mi）[ops]
  toolbox run devlog <change|verify|note|lesson|bp> <epic> <文本>
                               # dev-loop §2 记账单一入口（追加/验证/断点刷新，--json 预检）
  toolbox run cmds             # ::help 全量命令清单数据源（COMMANDS.md §1-§2 派生 + 白名单对账）
  toolbox run uscan            # AI 不确定标记扫描（UNCERTAIN/TODO/隐患词）[test] → ai-sideeffect-guard §1
  toolbox run dscan            # 静默降级/吞异常扫描（DEGRADE + 形状）[test] → ai-sideeffect-guard §1
  toolbox run hyg              # 代码残留扫描（调试语句/注释代码；--deps 依赖膨胀）[test] → ai-sideeffect-guard §2
  toolbox run dtrig            # 运行时 [DEGRADE] 实际触发聚合（grep 非 watch，默认 /tmp/logs）[test] → ai-sideeffect-guard §2
  扫描类工具: 任意 git 仓库内跑即扫该仓库根；--md <文件> 导出报告，--self-test 自诊断，
  命中 exit 1；节奏：会话中按需只跑与改动相关的 1 个，::done / ::audit 全跑（防四报告噪音坟场）；
  约定、用法速查与评估口径见 ~/.agents/skills/ai-sideeffect-guard/SKILL.md §1/§2/§4

## 示例（本项目 Java 模块运维）
  toolbox run jm main             # 前台启动 main（加载根目录 .env）
  toolbox run jm -- mcp --daemon  # 后台启动 mcp（日志 /tmp/logs/mcp.log）
  toolbox status jm               # 五模块状态表（状态/PID/日志）
  toolbox stop jm all             # 停止全部本机 JVM 进程
  toolbox restart jm mcp          # 重启单个模块

## 目录
  scripts/   全局工具池（跨项目）
  state/     钩子运行状态 last-run-<hook>.json；使用台账 usage-ledger.jsonl（append-only）
  .trash/    退役脚本
项目池: <repo>/scripts/agent-tools/（同名覆盖全局）

## 生命周期约定（摘录，全文见 toolbox spec）
  - 写脚本前先 `toolbox list --cat <类别>` 查池，有则直接用，不重复造轮子
  - 高频裸命令（同会话 ≥3 次或跨会话再手写）→ 提炼入池（登记经确认，可批量）
  - 登记门禁：头部块/help/json/自测/stdlib/密钥扫描，不合规即拒收
  - 退出码契约：0=通过 1=检查未通过 2=自身故障
