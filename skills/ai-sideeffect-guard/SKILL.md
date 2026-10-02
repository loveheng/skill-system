---
name: ai-sideeffect-guard
description: AI 写码隐性副作用的标记与收集治理：未实证实现标 // UNCERTAIN:、猜测性兜底（空 catch/吞异常/返回默认值）标 // DEGRADE: 并打 [DEGRADE] 日志；四工具 uscan/dscan/hyg/dtrig 机械收集评估。写码留不确定实现或静默降级、清理写码残留、::done/::audit/发布前副作用体检时使用。
---

# AI-SideEffect-Guard · AI 写码副作用标记与收集

> **定位**：管三类极易随会话窗口蒸发的 AI 副作用——**实现不确定**（写了但没实证）、**错误被悄悄消化**（能跑但错，零报错）、**写码残留**（调试语句/注释掉的代码/依赖膨胀），外加运行期实际触发观测。标记落在**代码注释**里（随代码生存），结论落**既有容器**（todos/devlog），**零新增文件**。

**管辖边界（防越权）**：

| 事项 | 归属 |
|---|---|
| 会话流程、日志协议、验证账本 `[验证]` | dev-loop §2 |
| 待办类型、`[once]`/`[long]` 生命周期、done 流转 | memo-collector §0/§2/§4 |
| 工具脚本登记、退出码契约、钩子巡检 | agent-toolbox |
| **标记口径 / 四工具用法 / 白名单 / 评估处置** | **本 skill** |

**三层收集面**：意图类（AI 写码时附标记，人不可省）→ 形状类（机械扫描，无需标记）→ 运行期（grep 日志，看实际触发）。

## 1. 标记约定（UNCERTAIN / DEGRADE）

| 标记 | 什么时候写 | 写法 |
|---|---|---|
| `// UNCERTAIN:` | 整个实现**不确定 / 未实证**（未验证的接口行为、猜测的边界、绕坑的权宜实现） | `// UNCERTAIN: <哪里不确定 + 风险是什么>` |
| `// DEGRADE:` | 失败时**兜底而非上报**（返回默认值 / 只记日志 / 吞异常）且该兜底是**猜测未核实**的 | `// DEGRADE: <为何兜底 + 待谁核实>`，并在兜底**前**打一条 `log.warn("[DEGRADE] <场景key> …")` |

- 语言适配：注释符号随语言（`//`、`#`、`--`）；场景 key 用 kebab-case，与代码位置语义对齐（如 `persona-redis-unavailable`）。
- **区分三者**：`TODO` = 计划做；普通防腐注释 = 结论已确定（backend-dev §2.6 / frontend-dev §4）；`UNCERTAIN`/`DEGRADE` = 结论未定论。
- **与 PATCH 的边界**：本 skill 只管「认知类 / 容错类」隐患（不知道对不对 / 失败悄悄兜底）；「明知不是正解但先这样」的**引入方式取舍**属 solution-admission §4（`// PATCH:` 标记），两者语义正交，禁止混用。
- **有意降级不标记**：设计行为（如 LLM 渠道不可用返回降级文案）写普通注释说明理由，靠白名单/人审区分，不标 DEGRADE。
- **设计假设未落码**：默认实现/接口行为的假设仍停留在回答中、尚未写进代码时，标记无处安放——按 memo-collector §1 判定表以 `(风险)` 口径暂记 todos（未验证假设），落码后该处再按本 skill 留 UNCERTAIN/DEGRADE 标记，两段衔接不重复。
- 与 dev-loop 的关系：标记**不落日志、不进 devlog**，只随代码生存；dev-loop §2 的日志协议照常执行。

## 2. 四工具速查（uscan / dscan / hyg / dtrig）

全部为 agent-toolbox 全局池工具，任意 git 仓库内直接跑（自动探测仓库根）；**命中 = exit 1，无命中 = exit 0**；`--md <文件>` 导出报告，`--json` 单行契约结论（门禁/钩子消费），`--self-test` 自诊断（金丝雀：坏样本必抓、好样本必不误报）。权威参数口径以各脚本头部 `--help` 为 SSOT。

| 工具（别名） | 收集面 | 说明 |
|---|---|---|
| `uncertainty-scan`（uscan） | UNCERTAIN 标记 + TODO/FIXME/HACK + 中文隐患词（隐患/待确认/待验证/不确定） | 覆盖 14 种语言，自动排除构建目录；`--root/--whitelist/--pattern` 可覆盖默认 |
| `degrade-scan`（dscan） | DEGRADE 标记 + 静默失败形状（空 catch / 仅日志吞异常 / catch 后返回默认值 / except 仅 pass / JS 仅 console） | 有 rethrow 的 catch 自动跳过；白名单抑制已定性有意降级，报告输出抑制数 |
| `code-hygiene-scan`（hyg） | 调试残留 / 注释掉的代码 / 依赖膨胀 | println、printStackTrace、console.*、DEBUG 开关；注释代码按代码形态判定（说明性注释不误报）；`--deps` 追加 `mvn dependency:analyze`（较慢，默认不跑） |
| `degrade-trigger`（dtrig） | 运行时 `[DEGRADE] <场景>` 日志聚合（场景 × 次数 × 最近触发 × 文件 × 样例） | 纯 grep 非 watch、无常驻进程；默认扫 `/tmp/logs`，`--logs <目录\|文件>` 可指定多个 |

```sh
# 会话中按需：只跑与本轮改动相关的 1 个（动 catch/兜底 → dscan；动标记注释 → uscan；残留清理 → hyg；部署/发布观测 → dtrig）
toolbox run uscan --md /tmp/uncertainty-report.md
toolbox run dscan --md /tmp/degrade-report.md
toolbox run hyg   --md /tmp/hygiene-report.md
toolbox run hyg   --deps
toolbox run dtrig --md /tmp/degrade-trigger-report.md   # 默认 /tmp/logs，--logs 可指定

# 覆盖默认与自诊断
toolbox run uscan --root <目录> --whitelist <文件> --pattern <正则>
toolbox run <uscan|dscan|hyg|dtrig> --self-test
```

- **分级节奏（防四报告噪音坟场）**：会话中按需只跑 1 个；`::done` / `::audit` / 发布前全跑四个；新仓库首次跑一次建立基线（存量命中先评估，有意降级登记白名单，后续只关注增量）。
- **dtrig 存量零命中是预期**：只对本约定启用后新写的 `[DEGRADE]` 日志行有数据，早期零命中 ≠ 没有降级发生。

## 3. 白名单与防误报

- 两个仓库根文件（项目级，非全局）：`.uncertainty-whitelist`（uscan 误报）、`.degrade-whitelist`（dscan 有意降级），缺失不报错。
- 格式：每行一个正则，`#` 为注释行；骨架仅含头注释（用途 + 格式 + 收录标准），**禁预置条目**——首跑全量基线评估后才逐条登记（dev-init §1 第 7 步）。
- 内置过滤：降级文案类误报（「暂不可用」「降级响应」等撞上中文隐患词的行）。
- 收录标准：逐处核读定性为「有意降级 / 已知误报」才登记；**对应路径修复后必须删除该行恢复监控**（白名单 = 已知有意，≠ 已修复）。

## 4. 评估节奏与处置口径

| 命中类别 | 定性 | 处置 |
|---|---|---|
| 静默降级 | 有意降级（设计合理） | 补注释说明理由 + 登记 `.degrade-whitelist` 抑制（防重复 triage） |
| 静默降级 | 未核实猜测 / 高危（正确性、数据一致性、安全边界） | 升级为 UNCERTAIN/DEGRADE 标记，并转 `context/todos.md` `(风险)` 类待办（memo-collector §0；常带 `[long]`，事件绑定的盯守动作带 `[once]`） |
| 静态命中但 dtrig 长期零触发 | 路径可能已死 | 降观察 / 清理，不落待办 |
| dtrig 高频场景 | 该路径真实承载流量 | 先定性（有意降级则确认降级文案合理；未核实则补告警 / 转风险待办） |
| 不确定标记 | 低危（已知降级且有版本规划） | 保留注释即可，不落待办 |
| 代码残留 | — | 调试语句删除或降为受控日志；**注释掉的代码整段删**（git 有历史）；依赖 undeclared 补声明、unused 移除（先确认非反射/AOT 需要） |

评估时机：会话中按需 → 只跑相关 1 个工具；epic 收尾（::done）/ `::audit` 第 11 项 / 发布前 → 全跑四工具并导出报告。

## 5. 完整生命周期示例（标记 → 扫描 → 白名单 → 触发 → todos）

**写码（唯一的手动动作）**：

```java
public String getPersona(String key) {
    try {
        return redisCache.get(key);
    } catch (Exception e) {
        // DEGRADE: Redis 不可用回落代码 persona，是否等价需产品确认
        log.warn("[DEGRADE] persona-redis-unavailable fallback to code persona");
        return CODE_PERSONA;
    }
}

// UNCERTAIN: 该接口未实证——tz 参数缺失时是否按 UTC 处理
private OffsetDateTime parseAt(String raw, String tz) { /* ... */ }
```

**扫描与定性**：`toolbox run dscan --md /tmp/degrade-report.md` → 有意降级则 `.degrade-whitelist` 追加一行 `persona-redis-unavailable`；高危则不登记白名单，转 todos：

```
- [ ] [2026-09-25] (风险) [long] PersonaStore.getPersona: Redis 不可用静默回落代码 persona，persona 语义等价未核实 (src: ai, degrade-scan)
```

**运行期**：`toolbox run dtrig --md /tmp/degrade-trigger-report.md` → 高频（如 1042 次）说明路径真实承载流量，按 §4 定性；零触发说明路径可能已死。

**收口**：`::done` / `::audit` 全跑四工具；Diff 轮次照 dev-loop §2 追加 `[验证]` 行（::audit 第 12 项核缺口）。

## 6. 护栏与反模式

- ❌ 不确定点只留普通「注意」注释 → 必须 `// UNCERTAIN:`（否则扫描找不到，隐患长期潜伏）
- ❌ catch 吞异常 / 返回默认值却无 DEGRADE 标记 → 零报错隐患，补标记 + 兜底前日志
- ❌ 把白名单当修复清单 → 白名单是「已知有意」，修复后删行恢复监控
- ❌ 每轮全跑四工具 → 报告噪音坟场，会话中只跑相关 1 个
- ❌ dtrig 零命中解读为「没有降级」→ 存量代码无 `[DEGRADE]` 日志行，属预期
- ❌ 注释掉的代码留着「以后可能用到」→ 整段删，git 有历史
