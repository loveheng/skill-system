---
dev-loop: devlog
format: v1
epic: misc
total-merged: 6
last-merge: 2026-10-20
---

- [2026-10-20] [变更]: 过程信息保留评估落地：① memo-collector §1 新增触发点 0（窗口内暂记 ≥3 条当轮批量落盘，堵重置蒸发口，原待办流转 done.md）② dev-loop REFERENCE §4 写死过程流水保留口径（非决策类 [变更]/[验证] 原文不进工作区，历史浏览一律 git log，显式取舍非缺口）
- [2026-10-20] [验证]: grep 触发点 0 / 过程流水保留口径锚点各 1 处 → 通过；todos done 暂记兜底流转 done.md → OK
- [2026-10-20] [变更]: goodhub 三件套底板化落地：① lessons 四段式+归并门禁升舱为全局 SSOT（dev-loop SKILL §2 + REFERENCE §2 细则 + 本仓 lessons.md 头部同步；源=goodhub-workflow 通用化）② goodhub-workflow lessons 节降级移交件出（快照 39ef9e2，跨库由用户执行，已登记待办）③ dev-init 模板库新建 templates/ 五件（README 提炼协议来源四项+停止判据 / workflow / index / docs / standards 骨架）④ dev-init §1 第 3/4/5/9 步内联接线（模板指针 + lessons SSOT 口径修正 + 验收加内容抽样）⑤ scaffold 增发三模板骨架登记待办（后置）
- [2026-10-20] [验证]: grep templates/ 锚点 dev-init 3 处 + 内容抽样 1 处 → 通过；templates/ 五文件 253 行在位 → 通过；todos 登记 scaffold 接线 → OK
- [2026-10-20] [验证]: toolbox run scaffold --self-test → OK（骨架齐备+幂等二次全跳过）；临时仓冒烟：三 SKILL.md name/描述按仓名替换、grep '<repo>' 三 skill 均 0 残留
- [2026-10-20] [变更]: scaffold 三模板接线：workflow/index/docs skill 骨架改由 dev-init templates/ 搬运（mk_tmpl 助手 + TMPLDIR 双路径探测 + sed 替换 <repo>，缺模板跳过并提示），删内联 heredoc 三块；standards 不自动发（须代码提炼，禁预写空泛条目）；workflow.template.md 补 name frontmatter；self-test 增定位边界/架构债断言
- [2026-10-20] [验证]: toolbox run scaffold --self-test → OK；临时仓冒烟三 skill 占位符零残留
- [2026-10-20] [变更]: ctx-ratio v2 排期落地：③ 宿主 compact 建议已实装——render_bare/render_json 四态补提示（命中附 compact、冷却提示压总量、RCR 高归并无益建议 compact、proxy 源总量超阈值提示），fail-open/冷却锁/exit 契约不变，self-test 用例2 加断言；① proxy 缓存感知侦查=无配置无样本→挂起等真实环境；② devlog 重叠度→暂缓（无实证痛点），均登记 todos
- [2026-10-20] [验证]: ctx-ratio --self-test → OK（含用例2 compact 断言）；stdin 命中样例 → 「⚠ 命中——建议 ::merge 归并后重置窗口（或宿主 compact）」exit 1
