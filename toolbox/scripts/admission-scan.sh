#!/bin/sh
# admission-scan — 方案准入债扫描：收集 PATCH 标记注释 + 统计 git 补丁密度，识别该重构的补丁
#
# 约定：以权宜（补丁）方式引入的改动统一写 `// PATCH: <为何权宜 + 正解 + 何时必须重构>`。
# 本工具做两件事：① 扫出全部 PATCH 标记（债清单，让债可见）；② 对命中文件统计近期 git
# 提交次数（补丁密度）——密度达阈值说明该位置被反复打补丁，触发强制重构。
#
# 通用性：根目录默认取当前 git 仓库根（非 git 用 pwd），可 --root 覆盖；
# 白名单 = 仓库根 .admission-whitelist（每行一个正则，# 注释），可 --whitelist 覆盖。
#
# toolbox-script
# format: v1
# name: admission-scan
# summary: 扫描 PATCH 标记注释并统计 git 补丁密度，识别需强制重构的补丁堆积（通用，任意 git 仓库）
# trigger: audit
# cat: test
# alias: ascan
# platform: unix
# self-test: --self-test

set -eu
MSG=""
REMEDY=""
SEVERITY=info
JSON=0
SELF_TEST=0
MD_OUT=""
ROOT_DIR=""
WL_FILE=""
GIT_ROOT=""
GIT=1
THRESHOLD=3
WINDOW=90
MAX_FILES=40
PATTERN='PATCH[:：]'

usage() {
  cat <<'EOF'
用法: admission-scan.sh [选项]
  --json               输出一行 JSON 契约结论（message 内禁双引号）
  --md <文件>          把明细报告写入指定 Markdown 文件
  --root <目录>        扫描根目录（默认：当前 git 仓库根，非 git 环境用 pwd）
  --whitelist <文件>   自定义白名单文件（每行一个正则，# 为注释行）
  --pattern <正则>     覆盖标记词正则（默认 PATCH:）
  --threshold <N>      补丁密度阈值，达阈值即触发强制重构（默认 3）
  --window <天>        密度统计窗口（默认 90 天）
  --max-files <N>      最多统计多少个文件的 git 密度（默认 40，控时）
  --no-git             跳过补丁密度统计，只扫标记（快速）
  --self-test          金丝雀自检
说明: 扫描源码中的 PATCH 标记注释，并对命中文件统计窗口期内的 git 提交次数。
      退出码: 0=无债; 1=有债（密度达阈值为 error 级，仅标记命中为 warn 级）; 2=自身故障。
EOF
}

effective_whitelist() {
  # 仓库根 .admission-whitelist（缺省自动加载，缺失不报错）+ --whitelist 显式覆盖
  local f line
  f=${WL_FILE:-${ROOT_DIR:-.}/.admission-whitelist}
  if [ ! -f "$f" ]; then
    return 0
  fi
  line=$(grep -vE '^[[:space:]]*(#|$)' "$f" | paste -sd'|' - || true)
  if [ -n "$line" ]; then
    printf '%s' "$line"
  fi
  return 0
}

collect_hits() {
  # 在 $ROOT_DIR 下输出: relpath:line:content（已过滤排除目录与白名单）
  local wl
  wl=$(effective_whitelist || true)
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
    --exclude='admission-scan.sh' \
    "$PATTERN" . 2>/dev/null \
    | sed 's|^\./||' \
    | { if [ -n "$wl" ]; then grep -vE "$wl" || true; else cat; fi; } || true
}

git_density() {
  # $1 = 相对路径；输出该路径在窗口期内的提交次数（非 git 环境返回 0）
  if [ "$GIT" -ne 1 ] || [ -z "$GIT_ROOT" ]; then
    printf '0'
    return 0
  fi
  git -C "$ROOT_DIR" log --oneline --since="$WINDOW days ago" -- "$1" 2>/dev/null \
    | grep -c . || true
}

run_checks() {
  local rc
  if [ -z "$ROOT_DIR" ]; then
    ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  fi
  if [ ! -d "$ROOT_DIR" ]; then
    MSG="扫描根目录不存在: $ROOT_DIR"
    REMEDY="检查 --root 参数路径"
    return 2
  fi
  GIT_ROOT=$(git -C "$ROOT_DIR" rev-parse --show-toplevel 2>/dev/null || true)

  HITS=$(cd "$ROOT_DIR" && collect_hits)
  COUNT=$(printf '%s\n' "$HITS" | grep -c . || true)

  DENSITY=""
  BREACH=""
  if [ "$COUNT" -gt 0 ]; then
    DENSITY=$(printf '%s\n' "$HITS" | cut -d: -f1 | sort -u | head -n "$MAX_FILES" | while IFS= read -r f; do
      if [ -n "$f" ]; then
        printf '%s|%s\n' "$f" "$(git_density "$f")"
      fi
    done)
    BREACH=$(printf '%s\n' "$DENSITY" | awk -F'|' -v t="$THRESHOLD" 'NF==2 && $2+0>=t {print}' || true)
  fi

  BREACH_N=$(printf '%s\n' "$BREACH" | grep -c . || true)

  if [ "$COUNT" -eq 0 ]; then
    MSG="未发现 PATCH 标记（根: $ROOT_DIR）"
    return 0
  fi

  if [ "$BREACH_N" -gt 0 ]; then
    MSG="补丁密度达阈值: ${BREACH_N} 个文件在 ${WINDOW} 天内被改 >= ${THRESHOLD} 次且带 PATCH 标记，触发强制重构（根: $ROOT_DIR）"
    REMEDY="按 solution-admission §1 重新评估该位置的结构性方案，重构后删除 PATCH 标记"
    SEVERITY=error
  else
    MSG="发现 ${COUNT} 处 PATCH 标记（债已登记，未达重构阈值 ${THRESHOLD}；根: $ROOT_DIR）"
    REMEDY="到期检查: 已达重构条件则重构并删标记，仍属有意权宜则保留标记"
    SEVERITY=warn
  fi

  if [ -n "$MD_OUT" ]; then
    {
      echo "# 方案准入债扫描报告"
      echo ""
      echo "- 日期: $(date +%F)"
      echo "- 扫描根: $ROOT_DIR"
      echo "- PATCH 标记: $COUNT 处；密度达阈值（>= $THRESHOLD 次 / ${WINDOW} 天）: $BREACH_N 个文件"
      echo ""
      echo "## 1. 达阈值（触发强制重构）"
      echo ""
      if [ "$BREACH_N" -gt 0 ]; then
        echo '| 文件 | 窗口内提交次数 |'
        echo '|---|---|'
        printf '%s\n' "$BREACH" | sort -t'|' -k2 -rn | while IFS= read -r line; do
          if [ -n "$line" ]; then
            echo "| $(printf '%s' "$line" | cut -d'|' -f1) | $(printf '%s' "$line" | cut -d'|' -f2) |"
          fi
        done
      else
        echo "无"
      fi
      echo ""
      echo "## 2. PATCH 标记清单"
      echo ""
      echo '| 位置 | 内容 |'
      echo '|---|---|'
      printf '%s\n' "$HITS" | while IFS= read -r line; do
        if [ -n "$line" ]; then
          echo "| $(printf '%s' "$line" | cut -d: -f1-2) | $(printf '%s' "$line" | cut -d: -f3-) |"
        fi
      done
      echo ""
      echo "> 处置口径见 solution-admission §5: 达阈值 → 强制重构；未达 → 保留标记，到期重评。"
    } > "$MD_OUT"
  fi
  return 1   # 有债（无论 warn/error 级）均为检查未通过
}

self_test() {
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  mkdir -p "$TMP/src"
  # 坏样本：同文件 3 次提交 + PATCH 标记 → 密度达阈值
  echo '// PATCH: 权宜实现，正解应下沉到 service 层' > "$TMP/src/Bad.java"
  # 好样本 1：有 PATCH 标记但仅 1 次提交 → 命中但不达阈值
  echo '// PATCH: 先这样' > "$TMP/src/Once.java"
  # 好样本 2：无标记 → 不应命中
  echo 'public class Clean {}' > "$TMP/src/Clean.java"
  git -C "$TMP" init -q
  git -C "$TMP" -c user.email=t@t -c user.name=t add -A
  git -C "$TMP" -c user.email=t@t -c user.name=t commit -q -m c1
  echo 'public class Bad { int x; }' >> "$TMP/src/Bad.java"
  git -C "$TMP" -c user.email=t@t -c user.name=t add -A
  git -C "$TMP" -c user.email=t@t -c user.name=t commit -q -m c2
  echo 'public class Bad2 { int y; }' >> "$TMP/src/Bad.java"
  git -C "$TMP" -c user.email=t@t -c user.name=t add -A
  git -C "$TMP" -c user.email=t@t -c user.name=t commit -q -m c3

  ROOT_DIR="$TMP"; WL_FILE=""; THRESHOLD=3; WINDOW=3650; MD_OUT=""; GIT=1
  rc=0
  run_checks || rc=$?
  if [ "$rc" -ne 1 ]; then echo "self-test: 有债场景未返回 exit 1（实际 $rc）"; return 2; fi
  if ! printf '%s\n' "$HITS" | grep -q 'Bad.java'; then echo "self-test: 未抓到坏样本标记"; return 2; fi
  if printf '%s\n' "$HITS" | grep -q 'Clean.java'; then echo "self-test: 无标记文件被误报"; return 2; fi
  if ! printf '%s\n' "$BREACH" | grep -q 'Bad.java'; then echo "self-test: 补丁密度未达阈值误判"; return 2; fi
  if printf '%s\n' "$BREACH" | grep -q 'Once.java'; then echo "self-test: 单次提交被误判达阈值"; return 2; fi

  # 白名单：Bad.java 入白名单后不应命中
  echo 'Bad\.java' > "$TMP/.admission-whitelist"
  WL_FILE="$TMP/.admission-whitelist"
  rc=0
  run_checks || rc=$?
  if printf '%s\n' "$HITS" | grep -q 'Bad.java'; then echo "self-test: 白名单未生效"; return 2; fi

  # 无债场景：清掉所有标记后应 exit 0
  rm -f "$TMP/.admission-whitelist"
  WL_FILE=""
  echo 'public class B {}' > "$TMP/src/Bad.java"
  echo 'public class O {}' > "$TMP/src/Once.java"
  rc=0
  run_checks || rc=$?
  if [ "$rc" -ne 0 ]; then echo "self-test: 无债场景未返回 exit 0（实际 $rc）"; return 2; fi

  echo "self-test: OK（密度达阈值可抓、单次提交不误判、无标记不误报、白名单生效、无债 exit 0）"
}

rc=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1 ;;
    --self-test) SELF_TEST=1 ;;
    --no-git) GIT=0 ;;
    --help|-h) usage; exit 0 ;;
    --md) [ $# -ge 2 ] || { echo "缺少参数: --md <文件>" >&2; exit 2; }; MD_OUT="$2"; shift ;;
    --root) [ $# -ge 2 ] || { echo "缺少参数: --root <目录>" >&2; exit 2; }; ROOT_DIR="$2"; shift ;;
    --whitelist) [ $# -ge 2 ] || { echo "缺少参数: --whitelist <文件>" >&2; exit 2; }; WL_FILE="$2"; shift ;;
    --pattern) [ $# -ge 2 ] || { echo "缺少参数: --pattern <正则>" >&2; exit 2; }; PATTERN="$2"; shift ;;
    --threshold) [ $# -ge 2 ] || { echo "缺少参数: --threshold <N>" >&2; exit 2; }; THRESHOLD="$2"; shift ;;
    --window) [ $# -ge 2 ] || { echo "缺少参数: --window <天>" >&2; exit 2; }; WINDOW="$2"; shift ;;
    --max-files) [ $# -ge 2 ] || { echo "缺少参数: --max-files <N>" >&2; exit 2; }; MAX_FILES="$2"; shift ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

if [ "$SELF_TEST" -eq 1 ]; then
  self_test
  exit $?
fi

rc=0
run_checks || rc=$?

if [ "$rc" -eq 0 ]; then
  if [ "$JSON" -eq 1 ]; then
    printf '{"status":"OK","severity":"info","message":"%s"}\n' "$MSG"
  else
    echo "OK: $MSG"
    if [ -n "$MD_OUT" ]; then echo "报告已写入 $MD_OUT"; fi
  fi
  exit 0
fi

if [ "$rc" -eq 2 ]; then
  if [ "$JSON" -eq 1 ]; then
    printf '{"status":"FAIL","severity":"error","message":"%s","remedy":"%s"}\n' "$MSG" "$REMEDY"
  else
    echo "ERROR: $MSG"
    echo "[remedy] $REMEDY"
  fi
  exit 2
fi

if [ "$JSON" -eq 1 ]; then
  printf '{"status":"FAIL","severity":"%s","message":"%s","remedy":"%s"}\n' "$SEVERITY" "$MSG" "$REMEDY"
else
  echo "FAIL[$SEVERITY]: $MSG"
  echo "[remedy] $REMEDY"
  if [ -n "$MD_OUT" ]; then echo "报告已写入 $MD_OUT"; fi
fi
exit 1
