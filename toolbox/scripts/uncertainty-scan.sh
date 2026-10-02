#!/bin/sh
# uncertainty-scan — 通用版：收集代码中 AI 留下的「不确定/隐患」标记注释，输出评估清单
#
# 约定：AI 写码遇不确定点统一写 `// UNCERTAIN: <说明>`（区别于 TODO=计划做）。
# 本工具扫描 UNCERTAIN/TODO/FIXME 及中文隐患词注释，白名单过滤降级文案类误报，
# 产出 file:line + 内容清单供人工评估（高危项建议转项目 todos 风险类）。
#
# 通用性：根目录默认取当前 git 仓库根（非 git 用 pwd），可 --root 覆盖；
# 白名单 = 内置（暂不可用等）+ 仓库根 .uncertainty-whitelist（每行一个正则，# 注释），
# 可 --whitelist <文件> 覆盖；标记词可 --pattern 覆盖。
#
# toolbox-script
# format: v1
# name: uncertainty-scan
# summary: 扫描 UNCERTAIN/TODO/FIXME 及中文隐患词注释，白名单过滤，产出评估报告（通用，任意 git 仓库）
# trigger: manual
# cat: test
# alias: uscan
# platform: unix
# self-test: --self-test

set -eu
MSG=""
JSON=0
SELF_TEST=0
MD_OUT=""
ROOT_DIR=""
WL_FILE=""
PATTERN='UNCERTAIN|TODO|FIXME|XXX|HACK|隐患|待确认|待验证|不确定|临时方案|权宜|注意[:：]'

usage() {
  cat <<'EOF'
用法: uncertainty-scan.sh [选项]
  --json             输出一行 JSON 契约结论（message 内禁双引号）
  --md <文件>        把明细报告写入指定 Markdown 文件
  --root <目录>      扫描根目录（默认：当前 git 仓库根，非 git 环境用 pwd）
  --whitelist <文件> 自定义白名单文件（每行一个正则，# 为注释行）
  --pattern <正则>   覆盖标记词正则
  --self-test        金丝雀自检
说明: 扫描源码中的不确定标记注释（UNCERTAIN 约定 + TODO/FIXME + 中文隐患词），
      白名单（内置 + 仓库根 .uncertainty-whitelist）过滤降级文案类误报。
      退出码: 0=无命中; 1=有命中（需评估）; 2=自身故障。
EOF
}

default_wl() {
  printf '暂不可用|宁可少提取|降级响应|请核对原文后修正'
}

effective_whitelist() {
  # 内置白名单 + 仓库根 .uncertainty-whitelist（缺省自动加载，缺失不报错）+ --whitelist 显式覆盖
  local parts line f
  parts=$(default_wl)
  f=${WL_FILE:-${ROOT_DIR:-.}/.uncertainty-whitelist}
  if [ -f "$f" ]; then
    line=$(grep -vE '^[[:space:]]*(#|$)' "$f" | paste -sd'|' - || true)
    [ -n "$line" ] && parts="$parts|$line"
  fi
  printf '%s' "$parts"
}

collect_hits() {
  # 在 $ROOT_DIR 下输出: relpath:line:content（已过滤排除目录与白名单）
  local wl
  grep -rnE \
    --include='*.java' --include='*.py' --include='*.sh' --include='*.ts' \
    --include='*.tsx' --include='*.js' --include='*.jsx' --include='*.go' \
    --include='*.rs' --include='*.c' --include='*.cpp' --include='*.h' \
    --include='*.cs' --include='*.rb' --include='*.php' --include='*.kt' \
    --include='*.scala' \
    --exclude-dir='.git' --exclude-dir='node_modules' --exclude-dir='target' \
    --exclude-dir='build' --exclude-dir='dist' --exclude-dir='out' \
    --exclude-dir='__pycache__' --exclude-dir='.venv' --exclude-dir='venv' \
    --exclude-dir='.idea' --exclude-dir='.trash' \
    "$PATTERN" . 2>/dev/null \
    | sed 's|^\./||' \
    | { wl=$(effective_whitelist); [ -n "$wl" ] && grep -vE "$wl" || cat; } || true
}

run_checks() {
  [ -z "$ROOT_DIR" ] && ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  [ -d "$ROOT_DIR" ] || { MSG="扫描根目录不存在: $ROOT_DIR"; return 2; }
  HITS=$(cd "$ROOT_DIR" && collect_hits)
  COUNT=$(printf '%s\n' "$HITS" | grep -c . || true)

  if [ "$COUNT" -eq 0 ]; then
    MSG="未发现不确定标记注释（根: $ROOT_DIR）"
    return 0
  fi

  MSG="发现 $COUNT 处不确定标记注释，建议人工评估（--md 可导出明细）"

  if [ -n "$MD_OUT" ]; then
    {
      echo "# 不确定标记扫描报告"
      echo ""
      echo "- 日期: $(date +%F)"
      echo "- 扫描根: $ROOT_DIR"
      echo "- 命中: $COUNT 处（白名单已过滤降级文案类误报）"
      echo ""
      echo '| 位置 | 内容 |'
      echo '|---|---|'
      printf '%s\n' "$HITS" | while IFS= read -r line; do
        [ -z "$line" ] && continue
        loc=$(printf '%s' "$line" | cut -d: -f1-2)
        c=$(printf '%s' "$line" | cut -d: -f3-)
        echo "| $loc | $c |"
      done
      echo ""
      echo "> 评估建议: 高危项（影响正确性/数据一致性）转项目 todos 风险类；"
      echo "低危项（已知降级、有版本规划）保留注释即可。"
    } > "$MD_OUT"
  fi
  return 1   # 有命中视为 WARN（退出码 1），提示需要评估
}

self_test() {
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  mkdir -p "$TMP/src/main/java"
  echo '// UNCERTAIN: 这里未实证' > "$TMP/src/main/java/Bad.java"
  echo '// 行情服务暂不可用' > "$TMP/src/main/java/Ok.java"
  ROOT_DIR="$TMP"
  HITS=$(cd "$TMP" && collect_hits)
  printf '%s' "$HITS" | grep -q 'UNCERTAIN' || { echo "self-test: 未能抓到已知坏样本"; return 2; }
  printf '%s' "$HITS" | grep -q 'Ok.java' && { echo "self-test: 内置白名单误报"; return 2; }
  # 自定义白名单：行含标记词「注意：」但含词「内部约定」，加入白名单后应被过滤
  echo '// 注意：这里有个内部约定' > "$TMP/src/main/java/C.java"
  HITS2=$(cd "$TMP" && collect_hits)
  printf '%s' "$HITS2" | grep -q 'C.java' || { echo "self-test: 未标记样本未被扫描"; return 2; }
  echo '内部约定' > "$TMP/.uncertainty-whitelist"
  WL_FILE="$TMP/.uncertainty-whitelist"
  HITS3=$(cd "$TMP" && collect_hits)
  printf '%s' "$HITS3" | grep -q 'C.java' && { echo "self-test: 自定义白名单未生效"; return 2; }
  echo "self-test: OK（坏样本可抓，内置/自定义白名单均不误报）"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1 ;;
    --self-test) SELF_TEST=1 ;;
    --help|-h) usage; exit 0 ;;
    --md) [ $# -ge 2 ] || { echo "缺少参数: --md <文件>" >&2; exit 2; }; MD_OUT="$2"; shift ;;
    --root) [ $# -ge 2 ] || { echo "缺少参数: --root <目录>" >&2; exit 2; }; ROOT_DIR="$2"; shift ;;
    --whitelist) [ $# -ge 2 ] || { echo "缺少参数: --whitelist <文件>" >&2; exit 2; }; WL_FILE="$2"; shift ;;
    --pattern) [ $# -ge 2 ] || { echo "缺少参数: --pattern <正则>" >&2; exit 2; }; PATTERN="$2"; shift ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

if [ "$SELF_TEST" -eq 1 ]; then
  self_test
  exit $?
fi

if run_checks; then
  [ "$JSON" -eq 1 ] && printf '{"status":"OK","severity":"info","message":"%s"}\n' "$MSG"
  [ "$JSON" -eq 0 ] && echo "OK: $MSG"
  [ -n "$MD_OUT" ] && [ "$JSON" -eq 0 ] && echo "报告已写入 $MD_OUT"
  exit 0
fi
if [ "$JSON" -eq 1 ]; then
  printf '{"status":"FAIL","severity":"warn","message":"%s"}\n' "$MSG"
else
  echo "FAIL: $MSG"
  [ -n "$MD_OUT" ] && echo "报告已写入 $MD_OUT"
fi
exit 1
