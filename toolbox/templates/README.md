# templates/ —— 骨架模板规格 SSOT

骨架格式 = 资产层：本目录下的模板是格式的**唯一定义**。脚本只负责渲染落盘（`toolbox/lib/render.sh`），skill 散文口径（dev-loop §0 / memo-collector §0）不复述格式正文。

**格式演进规则（写死）**：改格式 = 改模板 + 同步下方「占位符清单」；**除非占位符集合变化，否则不碰脚本**。新增模板 = 模板文件 + 清单一行 + 对应脚本 `tpl_check` 调用点加一路径（三处缺一不可，漏脚本侧 = 模板不会被预检）。

## 渲染契约（机械件与手工件共用）

- **占位符命名**：`{{UPPER_SNAKE_CASE}}`，渲染器做全字面全局替换（非变量展开，模板里其他 `{{` 字面量会被残留校验拒收）。
- **渲染器**：`toolbox/lib/render.sh`（被 mount-init / project-scaffold / todos source），行为写死：
  - `render_tpl <输出> <模板> [KEY=VALUE ...]` 渲染落盘；`render_std <模板> [KEY=VALUE ...]` 输出 stdout 供管道；`tpl_check <模板...>` 存在性预检。
  - 值自动转义 sed 替换特殊符（`&` `\` `|`）；**渲染值不得含单引号**（命中即 exit 2）。
  - **残留校验**：渲染产物仍含 `{{...}}` = 占位符漏替换，exit 2 fail-loud（占位符拼错 / 渲染参数缺 KEY 不许流入产物）。
  - 模板缺失 = 自身故障 exit 2（fail-loud 禁静默兜底）。
- **降级手工建骨架**（脚本不可用的兜底路径）：`cp` 模板 + 按下方清单替换 + 自检 `grep -n '{{' <产物>` 必须无命中——与机械件同一份契约，无第二套口径。

## 占位符清单

| 模板 | 占位符 | 来源 | 示例 |
|---|---|---|---|
| `epic/memory-formal.md` | `{{EPIC}}` `{{MOUNT}}` | epic 名（= 文档 slug）；挂载文档路径 | `demo`；`docs/design/demo.md` |
| `epic/memory-temp.md` | `{{EPIC}}` | 临时 epic 名 | `hotfix-login` |
| `epic/devlog.md` | `{{EPIC}}` | epic 名（正式/临时共用） | `demo` |
| `scaffold/current.md` | — | — | — |
| `scaffold/memory-misc.md` `scaffold/devlog-misc.md` `scaffold/lessons.md` `scaffold/decisions.md` `scaffold/done.md` | — | — | — |
| `scaffold/uncertainty-whitelist.txt` `scaffold/degrade-whitelist.txt` | — | —（仅头注释，禁预置条目） | — |
| `scaffold/agent-patch.json` | `{{LANGS}}` | 指纹探测的技术栈（JSON 数组元素，含引号） | `"rust","typescript"` |
| `scaffold/docs-readme.md` `scaffold/docs-index.md` `scaffold/coding-standards.md` | `{{REPO}}` `{{DATE}}` | 仓库根 basename；生成日（`date +%F`） | `myrepo`；`2026-10-28` |
| `todos/global.md` | — | —（scaffold 与 todos.sh 共用） | — |
| `todos/domain.md` | `{{EPIC}}` | 落点 epic 名（字母/数字/-/_） | `demo` |
