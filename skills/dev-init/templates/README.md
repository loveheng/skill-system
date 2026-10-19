# dev-init 模板库（项目接入底板）

> 来源：goodhub project-local 三件套通用化提纯（2026-10-20）。模板只含**通用骨架与规约**，全部项目数据（命令/路径/域清单/模块名）以 `<占位>` 标注，接入时按提炼协议现场实证填充。规范机制正文一律薄指针到全局 skill（dev-loop / project-index / docs-spec / memo-collector），模板内严禁复制机制正文。

## 提炼协议（第 3/4/5 步共用，写死）

**来源清单（四项，按序取证）**：
1. **构建与元数据**：README、构建脚本（Makefile/mvnw/pubspec/package.json…）、CI 配置、锁文件——出命令与工具链候选；
2. **代码结构**：一级目录清单 + 抽读 1~2 个代表模块的分层与依赖方向——出模块结构与写法模式候选；
3. **质量设施**：lint/analyze 配置、测试目录结构、pre-commit/CI 检查项——出门禁与红线候选；
4. **环境硬约束**：SDK/工具链安装位、本地依赖、终端与写入限制（实测跑通至少一条命令）。

**停止判据（最小可用，写死）**：workflow ≥1 条命令实测跑通；索引 ≥1 行真实落点（非占位）；standards ≥1 个真实模块的写法约束成文。达到即停，**禁止一次性铺满**——表与条款随实现增量长。

**顺序**：第 3 步（workflow，`workflow.template.md`）→ 第 4 步（索引，`index.template.md`）→ 第 5 步（standards 骨架 `standards.template.md` + 按需 docs `docs.template.md`）。每步产出落 `<repo>/.agents/skills/<repo>-<类>/SKILL.md`，数据文件落 `docs/project/`（随 docs 结构）。

**硬约束**：内容严禁虚构，命令至少实测一条；description ≤~250 字符；skill 间互引指针须可 grep（README §4.4）。

## 模板清单

| 模板 | 服务步骤 | 产出 |
|---|---|---|
| `workflow.template.md` | §1 第 3 步 | `<repo>-workflow` 事实源 skill |
| `index.template.md` | §1 第 4 步 | `<repo>-index` 索引规约 skill（数据住 docs/project/index.md） |
| `standards.template.md` | §1 第 5 步 | `docs/project/coding-standards.md` 骨架 |
| `docs.template.md` | §1 第 5 步 docs 分支 | `<repo>-docs` 域路由 skill |
