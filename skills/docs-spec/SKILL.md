---
name: docs-spec
description: 工程文档（docs/）规范机制层：域目录落点与生命周期切片命名、Frontmatter（status/updated）时效标注、Mermaid 唯一图表标准、废弃 Tombstone 与域墓碑、引用移动与 README 纯结构索引、写后自检 lint。零项目数据——域表与 lint 脚本由项目 docs skill 填。新增/修改/移动/废弃工程文档时加载。
---

# docs-spec · 工程文档规范（机制层）

> **定位**：与 `project-index` 同构的**机制 + 零项目数据** skill——只定"工程文档长什么样、怎么标、怎么废、怎么自检"，**不定义任何项目的域结构与脚本路径**。项目侧数据（域目录表、lint/收集脚本、本仓例外）一律落在项目仓的 `<repo>-docs/SKILL.md`，规范指针回本 skill。

**管辖边界**：

| 事项 | 归属 |
|---|---|
| 工程文档（docs/）规范机制 | **本 skill** |
| 项目的域落点表 / lint 脚本 / 例外 | 项目仓 `<repo>-docs/SKILL.md`（dev-init §1 第 5 步条件化创建） |
| 功能 → 代码落点索引 | project-index |
| 过程记忆（memory/devlog/lessons/todos） | dev-loop / memo-collector（**严禁写入 docs/**） |
| 代码内非显然逻辑 | 代码注释（backend-dev / frontend-dev）；跨契约的宏观规则才落 docs |

**铁律**：项目 docs skill **严禁复制本 skill 正文**，只写指针 + 项目数据（防双源）。

## 1. Frontmatter 时效（强制）

docs/ 下所有 `.md`（含 README 索引）头部必须有且**仅有两个字段**：

```yaml
---
status: active
updated: 2026-09-15
---
```

- `status`：`draft | active | deprecated`；`updated`：最后一次**实质修改**日期（YYYY-MM-DD）。
- 不扩展其他字段（禁 author/version/created/date）。
- **实质修改正文必须同轮刷新 `updated`**：纠正错误表述/数字/结论属实质修改；typo、排版、纯引用路径修复等基础设施性改动**豁免**。
- 读到 `status: deprecated`：严禁当作现行事实引用，必须按正文墓碑行指向的继任文档。

## 2. 落点与生命周期切片命名

- **按功能域切分子目录**，新文档严禁在 `docs/` 根目录平铺（README.md 除外）。
- 新文档落点：先查项目索引 skill 定位功能域 → 落 `docs/<域>/`；跨域架构决策 → `architecture/`（或项目自定的等价域）；部署运维 → `deploy/`。**具体域表由项目 docs skill 声明**。
- **域内生命周期切片固定名**：`spec → design → implementation → api → support`；独立主题用主题名；迁移/部署实录保留日期后缀；文件名一律 kebab-case。
- 新增或整域变迁时**三处同步**（防双源漂移）：项目 docs skill 的域表、`docs/README.md` 域头、项目索引 skill 的文档落点列。
- docs/ = 跨会话工程交付物（设计/接口/部署手册）；context/ = 过程记忆。两者互不侵入。

## 3. Mermaid 唯一图表标准

流程、状态机、架构、时序的描述一律 Mermaid 代码块，**严禁 ASCII 画图**；存量 ASCII 图随文档实质修改时顺手改造。

前提假设：文档消费环境原生渲染 Mermaid（现代 IDE / Git 平台），故不设图表类型白名单。若出现终端纯文本、PDF/离线导出、老旧 Git 端等消费场景，再评估白名单（优先 `flowchart TD` / `sequenceDiagram` / `stateDiagram-v2`）并直接修订本节。

## 4. 废弃：Tombstone（不删、不改正文）

**单文件废弃**：① frontmatter 改 `status: deprecated`（`updated` 同轮刷新）；② 标题下加墓碑行 `> [Deprecated YYYY-MM-DD] 已被 <X> 取代 → <继任文档相对路径>`；③ 检索入口 `grep -rn 'status: deprecated' docs`。
单文件废弃**不动 README 索引条目**——零操作即零漂移面；可见性由「条目仍在索引 + 打开首行即墓碑 + 检索入口」三层兑底。

**域级变迁（拆分/合并/整体迁移）**不做单文件墓碑，改域墓碑：① 域内 active 文档按 §5 迁移至新域（索引同步 + 全仓引用修复）；② 原域目录只留一个域墓碑 README（frontmatter 标 deprecated + 墓碑行指向新域）；③ 按 §2 三处同步收尾。

## 5. 引用、移动与索引维护

- 文档间引用一律**仓库相对路径**。
- **移动/重命名**必须：① 同步 `docs/README.md` 索引；② 全仓 grep 修复引用——用精确文件名逐项验证，勿用宽 glob（易假阴性漏检）。
- **`docs/README.md` 是纯结构索引**（域 → 文档 → 一句话定位），**不加状态列**：状态以各文档 frontmatter 为唯一事实源，索引不重复（防双源）。
- **双向覆盖原则**：README 链接的文档必须存在；每个非 README 文档必须在 README 有条目（域墓碑 README 天然豁免）。
- **文档被索引的三层机制**（语义定位 ≠ 头部字段）：① **目录分类**——`docs/<域>/` 即天然分类索引；② **结构索引**——`docs/README.md`（域→文档→一句话）与 `project-index` 的文档落点列（功能→文档）；③ **时效过滤**——各文档 frontmatter 的 `status/updated` 决定该不该引用（active 才引用，deprecated 不引用）。语义锚点一律放目录 + README + 索引 skill，**不进 frontmatter**（否则与 README/目录双源漂移，见 §7）。

## 6. 写后自检 lint

改完 docs 后执行（glob 按本仓 docs 层级调整），输出为空即合规：

```sh
# ① frontmatter 四项校验（缺开头 / status 非法 / updated 非法 / 字段超量）
awk 'FNR==1&&!/^---/{print FILENAME " 缺frontmatter"} FNR==2&&!/^status: (draft|active|deprecated)$/{print FILENAME " status异常"} FNR==3&&!/^updated: [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/{print FILENAME " updated异常"} FNR==4&&!/^---/{print FILENAME " 字段超量"}' $(find docs -name '*.md')

# ② 根目录平铺检查（除 README.md 外 docs/ 根不应有 .md）
find docs -maxdepth 1 -name '*.md' ! -name README.md

# ③ updated 漏刷软自查（只提醒不拦截）
git --no-pager diff --name-only HEAD -- docs
```

- ①② 为机械硬校验；项目若有专属 lint/收集脚本（收集视图 + README↔docs 双向覆盖校验），路径由项目 docs skill 声明。
- ③ 机器无法区分实质/基础设施改动，硬校验（强制 `updated` = 当天）会与 §1 例外冲突，故只做软自查。

## 7. 反模式

- ❌ docs/ 根目录平铺新文档
- ❌ 跳过或省略 frontmatter、改正文不刷新 `updated`
- ❌ ASCII 画图
- ❌ README 索引抄写 status/updated（与 frontmatter 双源）
- ❌ 过程记忆写入 docs/；废弃文档当现行事实引用
- ❌ 项目 docs skill 复制本 skill 规范正文（应只写指针 + 项目数据）
