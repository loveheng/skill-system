#!/bin/sh
# cmds — 命令面收集器：从 COMMANDS.md 现场派生全量 ::指令清单与含义（零缓存；§1-§2 解析 + 白名单对账）
#
# toolbox-script
# format: v1
# name: cmds
# summary: 命令面收集器：解析 COMMANDS.md §1-§2 派生 ::指令+含义（分组/去重/白名单对账漂移即 ⚠）；::help 全量模式数据源
# trigger: manual
# cat: docs
# platform: unix
# self-test: --self-test

set -u
FILE=''
JSON=0
SELF_TEST=0

usage() {
  cat <<'EOF'
cmds —— 命令面收集器（只读；现场派生，零缓存，防枚举漂移）

用法: cmds.sh [--file <COMMANDS.md 路径>] [--json|--self-test|--help]

默认数据源: ~/.agents/COMMANDS.md（由脚本定位推导，可 --file 覆盖）

输出:
  按域分组（dev-loop / memo-collector）逐条 ::命令 + 一行含义；
  末尾「校验」行做白名单 ↔ 明细双向对账——漂移即 ⚠ 行（缺明细 / 不在白名单）。

口径:
  含义取 COMMANDS.md §1 标题（—— 之后）/ §2 表「行为」列首句，完整用法以原文为准；
  对账基准 = 解析契约白名单行。漂移修复 = 补 COMMANDS.md 明细或同步白名单（::audit 第 9 项口径）。

定位: ::help 全量模式（用户显式索要命令清单时）的数据源；工具脚本另查 toolbox list。

退出码: 0 正常（含漂移 ⚠）/ 2 自身故障（数据源缺失等）
EOF
}

self_test() {
  local td ok out f
  ok=1
  td=$(mktemp -d)
  f="$td/COMMANDS.md"
  cat > "$f" <<'EOF'
# 命令手册
**记法约定**：xx；仅命中白名单动词（alpha/beta/omega）方视为指令。
## 0. 命令总表
| `::alpha` | dev-loop | 测试 | 仅用户 |
## 1. dev-loop 指令（编码会话）
### `::alpha <x>` / `::alpha2` —— 测试甲（dev-loop §3）
### `::beta` —— 测试乙（dev-loop §6）
## 2. memo-collector 指令（备忘台账）
| 指令 | 行为 | 口径要点 |
|---|---|---|
| `::gamma <g>` | 追加伽马；细节说明 | 无 |
## 3. toolbox
EOF
  out=$(sh "$0" --file "$f" 2>&1)
  printf '%s' "$out" | grep -q '::alpha/alpha2  测试甲' || { echo "self-test: §1 多动词合并/含义错误: $out"; ok=0; }
  printf '%s' "$out" | grep -q '::beta  测试乙' || { echo "self-test: §1 单动词错误: $out"; ok=0; }
  printf '%s' "$out" | grep -q '::gamma  追加伽马' || { echo "self-test: §2 表解析/截断错误: $out"; ok=0; }
  printf '%s' "$out" | grep -q '缺明细: ::omega' || { echo "self-test: 白名单缺明细未检出: $out"; ok=0; }
  printf '%s' "$out" | grep -q '不在白名单: ::alpha2 ::gamma' || { echo "self-test: 明细超白名单未检出: $out"; ok=0; }
  sh "$0" --file "$td/无此文件.md" >/dev/null 2>&1 && { echo "self-test: 数据源缺失应 exit 2"; ok=0; }
  if [ "$ok" -eq 1 ]; then echo "self-test: OK"; rm -rf "$td"; return 0; fi
  rm -rf "$td"; return 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --file) FILE="$2"; shift 2;;
    --json) JSON=1; shift;;
    --self-test) SELF_TEST=1; shift;;
    --help|-h) usage; exit 0;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 2;;
  esac
done

if [ "$SELF_TEST" -eq 1 ]; then self_test; exit $?; fi

# 默认数据源: ~/.agents/COMMANDS.md（HOME 推导，与脚本安放位置无关）；无 HOME 时降级按脚本相对位置
if [ -z "$FILE" ]; then
  if [ -n "${HOME:-}" ] && [ -f "$HOME/.agents/COMMANDS.md" ]; then
    FILE="$HOME/.agents/COMMANDS.md"
  else
    HERE=$(cd "$(dirname "$0")" && pwd)
    FILE="$HERE/../../COMMANDS.md"
  fi
fi
if [ ! -f "$FILE" ]; then
  if [ "$JSON" -eq 1 ]; then
    printf '{"status":"FAIL","severity":"error","message":"数据源缺失: %s"}\n' "$FILE"
  else
    echo "FAIL: 数据源缺失: $FILE" >&2
    echo "[remedy] 检查 ~/.agents/COMMANDS.md 是否存在，或 --file 指定命令手册路径" >&2
  fi
  exit 2
fi

OUT=$(awk -v S1='dev-loop（编码会话，<项目>/context/）' -v S2='memo-collector（备忘台账，<项目>/context/）' '
function flush() { if (plen > 0) printf "::%s  %s\n", pverbs, pmean; pverbs=""; pmean=""; plen=0 }
function add(vs, m,    n, i, v) {
  if (plen > 0 && m == pmean) pverbs = pverbs "/" vs
  else { flush(); pverbs=vs; pmean=m; plen=1 }
  n=split(vs, va, "/")
  for (i=1;i<=n;i++) { v=va[i]; if (!(v in seen)) { seen[v]=1; ucnt++; uv[ucnt]=v }
    if (sec==1) dc++; else if (sec==2) mc++ }
}
BEGIN { sec=0 }
/^## 1\./ { flush(); sec=1; print "== " S1 " =="; next }
/^## 2\./ { flush(); sec=2; print "== " S2 " =="; next }
/^## /    { flush(); sec=0; next }
/^### / && sec==1 {
  l=$0; vs=""
  while (match(l, /::[a-z0-9-]+/)) {
    t=substr(l, RSTART+2, RLENGTH-2)
    vs = vs (vs=="" ? "" : "/") t
    l=substr(l, RSTART+RLENGTH)
  }
  if (vs=="" || !match($0, /——/)) next
  m=substr($0, RSTART+RLENGTH)
  sub(/（dev-loop §[0-9]+）[ \t]*$/, "", m); sub(/^[ \t]+/, "", m)
  add(vs, m); next
}
/^\| `[ ]*::/ && sec==2 {
  line=$0
  # 转义竖线（如 <编号\|关键词>）先换哨兵符再分列，防列错位
  gsub(/\\\|/, sprintf("%c", 1), line)
  n=split(line, c, "|"); if (n < 3 || !match(c[2], /::[a-z0-9-]+/)) next
  v=substr(c[2], RSTART+2, RLENGTH-2)
  m=c[3]; gsub(/^[ \t`]+|[ \t`]+$/, "", m)
  # 首句截断：取三个分隔符的最靠前位置（逐字面 index，避开多字节字符类按字节误匹配）
  p=0
  i1=index(m, "；"); if (i1) p=i1
  i2=index(m, "（"); if (i2 && (!p || i2<p)) p=i2
  i3=index(m, "(");  if (i3 && (!p || i3<p)) p=i3
  if (p) m=substr(m, 1, p-1)
  gsub(/[*`]/, "", m); sub(/^[ \t]+|[ \t]+$/, "", m)
  if (m=="") next
  add(v, m); next
}
/仅命中白名单动词/ {
  w=$0
  if (match(w, /仅命中白名单动词（/)) {
    w=substr(w, RSTART+RLENGTH); sub(/）.*$/, "", w)
    n=split(w, wa, "/")
    for (i=1;i<=n;i++) { wl[++wln]=wa[i]; wlmap[wa[i]]=1 }
  }
  next
}
END {
  flush()
  miss=""; extra=""
  for (i=1;i<=wln;i++) if (!(wl[i] in seen)) miss = miss " ::" wl[i]
  for (i=1;i<=ucnt;i++) if (!(uv[i] in wlmap)) extra = extra " ::" uv[i]
  base=sprintf("校验: 白名单 %d 动词 ↔ 明细 %d 条（唯一动词 %d）", wln, dc+mc, ucnt)
  if (miss=="" && extra=="") print base " —— 一致"
  else {
    print base " —— 不一致"
    if (miss!="") print "⚠ 白名单缺明细:" miss "（补 COMMANDS.md 明细或移除白名单）"
    if (extra!="") print "⚠ 明细不在白名单:" extra "（补白名单或删明细）"
  }
  print "完整用法: COMMANDS.md 各域明细节 ｜ 工具脚本: toolbox list ｜ 项目专属命令: 项目索引「命令速查」节"
}' "$FILE")
if [ "$JSON" -ne 1 ]; then printf '%s\n' "$OUT"; fi

if [ "$JSON" -eq 1 ]; then
  m=$(printf '%s' "$OUT" | grep '^校验:' | head -n 1 | tr '\n' ' ' | tr -d '"')
  if printf '%s' "$OUT" | grep -q '^⚠'; then
    r=$(printf '%s' "$OUT" | grep '^⚠' | head -n 2 | tr '\n' ' ' | tr -d '"')
    printf '{"status":"OK","severity":"warn","message":"%s","remedy":"%s"}\n' "$m" "$r"
  else
    printf '{"status":"OK","severity":"info","message":"%s"}\n' "$m"
  fi
fi
exit 0
