---
dev-loop: devlog
format: v1
epic: misc
total-merged: 7
last-merge: 2026-10-20
---
- [2026-10-20] [变更]: #2 体系减法复盘完成（用户三项裁决）：① doc-domain-map 留观察（30 天 0 次/总历史 0，检查面等索引长大，下轮复盘再议）② 张力②本轮写明——agent-toolbox SKILL 法律节补上位关系（规范 SSOT=元工具内嵌 spec，SKILL 是指针摘要层，冲突以 spec 为准）③ 张力① dev-loop 分层重组挂 todos 排期（新 [long] 待办）。数据面结论：核心面全活跃（devlog 843/todos 285/panel 163），无大面积可砍规则——账本面证据不支持大砍
- [2026-10-20] [验证]: usage-ledger 3942 条 30 天窗统计（python 聚合）；grep doc-domain-map 引用面仅 1 处举例；agent-toolbox SKILL 上位关系行 grep 命中「写死」
- [2026-11-11] [变更]: dev-loop 新增有界自动推进 ::auto：SKILL §2/§6/§9 + REFERENCE §2/§3 + COMMANDS.md 表+详情节 + ADR 落 decisions.md；会话级显式授权，硬停清单+逐节点资格判定写死
- [2026-11-11] [验证]: grep 校验：dev-loop SKILL/REFERENCE/COMMANDS.md/decisions.md 四文件新增锚点行均在场（::auto / 有界自动推进 / 2026-11-11 ADR）
- [2026-11-11] [变更]: dev-loop ::auto 补夜间无人值守档 ::auto night：裁决点挂账跳过不停链+默认建议预授权+失败一次即停，高危仍跳过不碰；SKILL §2/REFERENCE §2/COMMANDS.md 同步
- [2026-11-11] [验证]: grep 校验：三文件 '::auto night' 锚点在场
- [2026-11-11] [变更]: ::auto night 设计评审两缺口补死：①验证失败语义改整链收摊（该节点+后续全部挂账，禁跳过失败节点续跑）②默认建议预授权加负面清单（schema/契约/删除/不可逆永远裁决型禁包装）；SKILL/REFERENCE/COMMANDS 三文件同步
- [2026-11-11] [验证]: grep 校验：'整链收摊' 与 '负面清单' 锚点在三文件在场
- [2026-11-11] [变更]: ::auto 缺省目标改大节点粒度：缺省=完成当前整个大节点（底子文档章节级），文档无大节点拆分则整份实施流程走完，显式 N/until 仍可覆盖（原 N 缺省=3 废弃）；SKILL/REFERENCE/COMMANDS 三文件同步
- [2026-11-11] [验证]: grep 校验：'缺省目标' 大节点口径在三文件在场且无 'N 缺省=3' 残留
- [2026-11-16] [变更]: ::auto 推进面改造（11-16 推进偏差根治）：推进面=域内 todos.md 结构化节点（大节点→子步骤→验收三层），文档正文只读；缺省目标改机械判定=当前大节点子步骤全 [x]；新增启动报目标+断点恒指子步骤编号+无验收不连走+无结构化拆解面拒绝开工（补拆或显式 until）四条写死；night 缺省同步；SKILL/REFERENCE §2/§3/COMMANDS 四处同步
- [2026-11-16] [验证]: grep 校验：推进面与内容面分离/启动报目标/机械判定 锚点在场，旧缺省口径零残留（本轮已实测）
- [2026-11-16] [变更]: ::auto 跨节点口径统一（白天夜间一致不分叉）：显式 N 允许跨大节点边界，跨边界步一行报位不停；范围预期由启动报目标预览覆盖（含 N 预计落点）；N 卡节点中间照常停步数用尽即回手动；REFERENCE §2 + COMMANDS.md 同步
- [2026-11-16] [验证]: grep 校验：'跨节点（写死' 锚点在 REFERENCE §2 与 COMMANDS.md 在场
- [2026-11-16] [变更]: 裁决台账域内化（过程数据随 epic 生命周期+锚点关联推进面）：唯一落点=epics/<名>/pending-confirm.md（misc 同域内），全局文件退役禁双落点；条目锚点=todos 拆解序号（T3.2）写死，补走机械匹配，锚点失联停问；严禁混入域内 todos.md 污染推进面。机械面：panel.sh 聚合（默认+--deep 本域改本域计数+夹具 T3.2/T4.1 锚点用例）、ctx-status.sh 聚合同步；协议面 SKILL §0/§2、REFERENCE §2 登记/§2 night①、§3 台账联动、COMMANDS 表+详情同步；panel/ctx-status 金丝雀自测双绿
- [2026-11-16] [验证]: panel/ctx-status --self-test 双绿（本轮实测）+ grep 校验全局路径引用协议面零残留
- [2026-11-16] [变更]: 新增全局池工具 confirm（薄 CLI，替代台账登记口约）：add 登记即机械校验（锚点在域内 todos 真实存在/同锚点未清拒收/拒收零写入）+list/resolve/list-all --json；自检 7/7 含幽灵锚点坏样本，自检抓出并修复 resolve 锚点分发 bug；登记经 check --scope global 入全局池（无注册表，list 现场派生）；接线 REFERENCE §2 登记 机械件行+COMMANDS ::confirm 详情机械件行
- [2026-11-16] [验证]: toolbox list confirm=global ✓ + toolbox run confirm --self-test 7/7 ✓ + list-all --json 契约 ✓（本轮实测）+ grep 机械件锚点在 REFERENCE/COMMANDS 在场
- [2026-11-16] [变更]: ::auto 新增 --yes 参数（夜间②预授权白天化同源）：附默认建议项按默认推进不停链，每批报位「已按默认通过 N 项」留痕；负面清单同源（schema/契约/删除/不可逆永远停），真裁决项（互斥无默认倾向）仍停；night 措辞对齐同一负面清单；SKILL/REFERENCE §2/COMMANDS 表+详情同步
- [2026-11-16] [验证]: grep 校验：--yes 锚点三文件在场、night② 同源措辞在场（本轮已实测）
- [2026-11-16] [变更]: ::auto night 新增前置沙盘（开工三段式：启动报目标→只读逐节点预跑→答完开工）：机械校验锚点/验收在场，中段取舍前置挖出批量裁决（能默认清单一键同意默认+真互斥当场抛），登记走 confirm 锚点门禁（挂不上推进面=拆解面有洞先补拆解）；沙盘只读不真跑验收命令；沙盘≠放开授权（途中新现裁决项仍按既有语义）；白天档不加沙盘；SKILL/REFERENCE §2 night/COMMANDS 同步
- [2026-11-16] [验证]: grep 校验：'前置沙盘' 锚点在 REFERENCE/SKILL/COMMANDS 三文件在场（同轮已编辑落盘）
- [2026-11-16] [变更]: 补上评估两缺口：①context-lint 新增 lint_pc 台账域内面检查——epics/<名>/pending-confirm.md 锚点失锚（锚点须在域内 todos.md 真实存在，缺失 todos 面单独报）+ 全局 pending-confirm.md 退役残留；自测夹具补好样本（T1.1 锚）/坏样本（T9.9 幽灵锚+全局残留）与 [PCANCHOR] 断言，PASS；真仓裸跑无误报（FAIL 标签=存量积压 MERGE/RECLAIM/TODOS）②::status 输出口径补域内台账聚合行（未确认 N 项，ctx-status 挂起行同源，取数失败标 ❓ 不假报）
- [2026-11-16] [验证]: context-lint --self-test PASS（含 [PCANCHOR] 坏样本断言）+ 真仓 --json 无 PCANCHOR/MIGRATE 标签（本轮实测）
- [2026-11-16] [变更]: demo 首战验收场就绪（/home/zzh/app/demo）：待办 CLI（python3 零依赖，add/list/done）+底子文档+拆解面（T1×2/T2×1 带验收命令）+mount-init 绑定+断点 T1.1；机械件 e2e 全过——confirm 门禁真仓生效（合法锚点过/T9.9 幽灵拒收/list/resolve/panel 事实）；抓出两发现：①断点双重前缀=调用方误带前缀（bp 恒加，已修正）②拆解行与 memo-collector v3 行格式口径打架（lint 报 TODOS 违规行 10/11/14）——真实体系裁决项抛出待拍板
- [2026-11-16] [验证]: demo 仓实测：mount-init 骨架+CURRENT ✓、confirm 四命令 ✓、lint exit 1 报 TODOS ✓、panel 事实块 ✓（本轮实测）
- [2026-11-16] [变更]: 裁决项定案（方案 A，用户拍板）：::auto 拆解行在 memo-collector v3 行格式内承载——锚点居事项段首位、验收段居 (src:) 前；格式 SSOT=algo-collector 同源 §0 写死拆解行适配句，dev-loop REFERENCE §2 推进面示例同步；demo 拆解行改 A 格式后 context-lint exit 0（首战验收场就绪态）
- [2026-11-16] [验证]: context-lint --root /home/zzh/app/demo exit 0 + grep T1.1 锚点在场（本轮实测）
- [2026-11-16] [更正]: 上条 [变更] 行错别字：格式 SSOT=algo-collector ➔ memo-collector（§0 拆解行适配句落盘无误，仅账本行笔误）
- [2026-11-16] [变更]: RECLAIM 冲突定案（方案 A'，用户拍板）：::auto 拆解行 [x]=机械判定要素非人工打勾——context-lint RECLAIM 检查豁免带 T<节点>.<步> 锚点行（普通待办 [x] 照报，扫描面收紧不放宽）；自测双证：合规夹具加拆解 [x] 样例仍 exit 0 + 坏样本 [RECLAIM] 断言照过；demo 仓复跑 0 告警 exit 0（首战误报消除）
- [2026-11-16] [验证]: context-lint --self-test PASS + demo 仓 --root 复跑 exit 0（本轮实测）
- [2026-11-16] [变更]: ::auto 参数测试矩阵完成（demo 仓 T2/T3 推进）：缺省边界停 ✓（首战 T1）| ::auto 1 步数卡大节点中间停 ✓（T2.1 后断点 T2.2，1/1 用尽即停未越界）| ::auto until T2 显式目标达成停 ✓（T2 全 [x]，清单余 T3 未越界）| ::auto night until T3 夜档+前置沙盘 ✓（沙盘挖出 2 项默认建议预授权消+0 真裁决，推完 T3=整份清单走完=整流程完成停）| --yes 报位 5 项全程留痕（demo devlog 变更行内注明）；demo CLI 全功能就绪（add/list/done/--help/四容错）lint exit 0
- [2026-11-16] [验证]: demo 仓 lint --root 复跑 exit 0 + confirm list-all total=0 + T1-T3 全 [x]（本轮实测）
- [2026-11-16] [更正]: 上条参数矩阵 [验证] 行笔误：demo lint 实测 exit 1（MERGE ⚠ devlog 12 条 ≥5 触发归并；TODOS 面 0 违规干净）非 exit 0——随即按 §4 执行 demo 仓归并闭环
- [2026-11-16] [验证]: demo 归并闭环复验：devlog clear total-merged=1/last-merge=2026-11-16 + memory 提炼 16 行（软上限 150 内）+ context-lint --root /home/zzh/app/demo exit 0 ✓（实测）
- [2026-11-16] [变更]: 新增全局池工具 autocheck（::auto 启动门禁薄 CLI，实战 5 次重复收编）：推进面健康（未清子步行验收段门禁）+缺省目标推导（首个含未清子步大节点+全子步锚点判定清单）+断点锚一致性（断点 T 锚须在推进面真实存在防漂移）+台账聚合，message 即启动报目标推导结果；自检 7/7 抓三真 bug（双重 T 模板 TT1 永不匹配/set -eu 赋值式内层预期失败静默中止/自检夹具时序污染）全修后 PASS；真仓实测推导与实况一致；bp 防呆小修：run_bp 入口剥调用方误带「下一步：」前缀（demo e2e 双重前缀实战），devlog 自测 48/48；接线 REFERENCE §2 启动报目标机械件+COMMANDS ::auto 详情节（flags-first --root 须前置）
- [2026-11-16] [验证]: autocheck --self-test 7/7 ✓ + demo --root 实测「整流程完结 拆解面全[x] 台账=0」✓ + devlog --self-test 48/48 ✓（本轮实测）
- [2026-11-16] [变更]: 方案定稿门落盘（dev-guide §1 步骤 0.5 + 硬卡点 [定稿]，最薄形态 +2 行）：结构性方案产出后同轮四段定稿（细化/反思含≥1 反例/备选与否决理由/评估与验收——复用 ::adr 四段式与 admission 六信号三次成本）+方案轮严禁开工（显式采纳才进步骤 1，显式跳过打磨可豁免）；落点三轮辩论定案：dev-guide 触发才加载零常驻（dev-loop 零膨胀/项目级 docs 可缺席已证伪），换项目成立判据=回合协议非项目内容
- [2026-11-16] [验证]: grep 方案定稿门 锚点在 dev-guide SKILL 在场 + 行数 82（软上限 80 触，已挂尾注）
- [2026-11-16] [更正]: 上条方案定稿门 [验证] 行两处不符：①行数实测 80（dev-guide 原基线 78 非 80，+2 恰触软上限未超限）非 82 ②「已挂尾注」未发生——软上限由 dev-guide §5 维护协议既有条款覆盖（超限先砍描述密度），不加尾注；下次往 dev-guide 加内容前须先砍
