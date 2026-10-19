---
memo: done
format: v2
---

# 完成列表
- [2026-10-20] scaffold 三模板接线：workflow/index/docs skill 骨架改由 dev-init templates/ 搬运（mk_tmpl + TMPLDIR 探测 + sed 替换 <repo>，幂等不覆盖）；standards 不自动发（须代码提炼）——self-test OK + 冒烟占位符零残留 (src: ai, 用户确认) (域: misc)
- [2026-10-07] skill-verify 脚本：三 project-local skill 锚点批量校验（grep 提取路径/类名锚点→批量 test -e），dev-init §1.5 第 1 项机械半边自动化、语义核实留 AI——形态对齐 ctx-audit「机械项委托」 (src: ai, 体系审计) (域: misc)
- [2026-10-07] 冷启动接入验收档：ctx-audit 加 --init 档聚合 dev-init §2 机械项（check-ignore/YAML 头/机器件在场/description 预算/指针可 grep），验收从手工逐项变一条命令 (src: ai, 体系审计) (域: misc)
- [2026-10-15] skill 体系：给确认/提问设预算——同类确认合并、设轮次上限，防确认疲劳致「同意默认」失效确认机制 (src: ai) (域: misc)
- [2026-10-15] skill 体系：精修各 skill description 路由行（dev-loop/dev-guide/problem-triage/memo-collector 重叠区），降误触发省上下文 (src: ai) (域: misc)
- [2026-10-15] skill 体系：放宽 dev-loop 快车道判据，让更多小改轮免评估/台账仪式，降每轮过程税 (src: ai) (域: misc)
- [2026-10-20] 暂记备忘自计数兜底：memo-collector §1 触发点间仅对话内暂记、重置即弃——窗口内暂记 ≥3 条自动提前批量落盘（触发点 0） (src: ai, 体系审计) (域: misc)
