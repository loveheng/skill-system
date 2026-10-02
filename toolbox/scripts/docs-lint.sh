#!/bin/sh
# docs-lint — docs/ 工程文档规范机械校验（docs-spec §6）：frontmatter 四字段 + 根目录平铺 + updated 软自查
#
# toolbox-script
# format: v1
# name: docs-lint
# summary: docs/ 规范机械校验：frontmatter 四字段 + 根目录平铺 + updated 软自查（docs-spec §6）
# trigger: manual
# cat: docs
# platform: unix
# self-test: --self-test

set -u
DOCS_DIR=''
JSON=0
MD_OUT=''
SELF_TEST=0
HARD=0
SOFT=0
SOFTLINE=''
DETAIL=''

usage() {
  cat <<'EOF'
docs-lint —— docs/ 工程文档规范机械校验（docs-spec §6）

用法: docs-lint.sh [--root <docs目录>] [--json|--md <文件>|--self-test|--help]

默认 docs 目录: 当前 git 仓库根的 docs/，非 git 用 ./docs

检查面:
  ① frontmatter 四字段校验（缺开头 / status 非法 / updated 非法 / 字段超量）
  ② 根目录平铺检查（除 README.md 外 docs/ 根不应有 .md）
  ③ updated 漏刷软自查（只提醒不拦截，列出 docs 的 git 改动文件）

退出码: 0 合规（含仅软自查提示）/ 1 有硬违规 / 2 自身故障
EOF
}

resolve_docs() {
  if [ -n "$DOCS_DIR" ]; then printf '%s' "$DOCS_DIR"; return; fi
  local r=''
  if command -v git >/dev/null 2>&1; then
    r=$(git rev-parse --show-toplevel 2>/dev/null || true)
  fi
  if [ -n "$r" ]; then printf '%s/docs' "$r"; else printf '%s/docs' "$(pwd)"; fi
}

scan() {
  local d="$1" f files bad flat n
  HARD=0; SOFT=0; SOFTLINE=''; DETAIL=''
  if [ ! -d "$d" ]; then
    DETAIL="docs 目录不存在，跳过: $d"
    return 0
  fi
  files=$(find "$d" -name '*.md' 2>/dev/null || true)
  if [ -n "$files" ]; then
    bad=$(printf '%s\n' "$files" | while IFS= read -r f; do
      [ -f "$f" ] || continue
      awk 'FNR==1&&!/^---/{print FILENAME " 缺frontmatter"} FNR==2&&!/^status: (draft|active|deprecated)$/{print FILENAME " status异常"} FNR==3&&!/^updated: [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/{print FILENAME " updated异常"} FNR==4&&!/^---/{print FILENAME " 字段超量"}' "$f" 2>/dev/null || true
    done) || true
    if [ -n "$bad" ]; then
      n=$(printf '%s\n' "$bad" | grep -c . || true)
      HARD=$((HARD + n))
      DETAIL="$DETAIL$bad\n"
    fi
  fi
  flat=$(find "$d" -maxdepth 1 -name '*.md' ! -name README.md 2>/dev/null || true)
  if [ -n "$flat" ]; then
    n=$(printf '%s\n' "$flat" | grep -c . || true)
    HARD=$((HARD + n))
    DETAIL="$DETAIL$(printf '%s\n' "$flat" | sed 's/$/ 根目录平铺(应移入子域)/')\n"
  fi
  SOFTLINE=$(git --no-pager diff --name-only HEAD -- "$d" 2>/dev/null || true)
  if [ -n "$SOFTLINE" ]; then
    SOFT=$(printf '%s\n' "$SOFTLINE" | grep -c . || true)
  fi
}

decide() {
  local d
  d=$(resolve_docs)
  if [ ! -d "$d" ]; then G_STATUS=OK; G_SEV=info; G_MSG="$DETAIL"; G_RC=0; return; fi
  if [ "$HARD" -gt 0 ]; then
    G_STATUS=FAIL; G_SEV=warn
    G_MSG="${HARD} 处硬违规(docs-spec §6)$( [ "$SOFT" -gt 0 ] && printf '; %s 文件 updated 待核' "$SOFT")"
    G_RC=1; return
  fi
  if [ "$SOFT" -gt 0 ]; then
    G_STATUS=OK; G_SEV=info; G_MSG="docs 规范校验通过; ${SOFT} 文件 updated 待核(软自查,不拦截)"; G_RC=0; return
  fi
  G_STATUS=OK; G_SEV=info; G_MSG="docs 规范校验通过"; G_RC=0
}

G_STATUS=''; G_SEV=''; G_MSG=''; G_RC=0

emit_json() {
  scan "$(resolve_docs)"; decide
  printf '{"status":"%s","severity":"%s","message":"%s"}\n' "$G_STATUS" "$G_SEV" "$G_MSG"
  exit "$G_RC"
}

run_bare() {
  local d
  d=$(resolve_docs); scan "$d"
  if [ ! -d "$d" ]; then echo "$DETAIL"; return 0; fi
  if [ -n "$DETAIL" ]; then printf '%s\n' "$DETAIL"; else echo "✓ docs 规范校验通过（docs: $d）"; fi
  if [ "$SOFT" -gt 0 ]; then echo "⚠ 软自查: ${SOFT} 个 docs 文件在 git 工作区改动，updated 可能漏刷（不拦截）"; fi
  if [ "$HARD" -gt 0 ]; then return 1; fi
  return 0
}

run_md() {
  local d
  d=$(resolve_docs); scan "$d"
  {
    echo "# docs-lint 报告（docs-spec §6）"
    echo
    if [ ! -d "$d" ]; then echo "$DETAIL"; else
      if [ -n "$DETAIL" ]; then printf '%s\n' "$DETAIL"; else echo "✓ 无硬违规"; fi
      if [ "$SOFT" -gt 0 ]; then
        echo
        echo "软自查(不拦截): 以下 docs 文件在 git 工作区改动，updated 可能漏刷:"
        printf '%s\n' "$SOFTLINE"
      fi
    fi
  } > "$MD_OUT"
  echo "✓ 报告已写入: $MD_OUT"
}

self_test() {
  local td ok cnt
  ok=1
  td=$(mktemp -d)
  mkdir -p "$td/sub"
  printf -- '---\nstatus: active\nupdated: 2026-09-15\n---\n\n# ok\n' > "$td/sub/good.md"
  printf -- '# no frontmatter\n\nsome text\n' > "$td/sub/bad1.md"
  printf -- '---\nstatus: weird\nupdated: 2026-09-15\n---\n' > "$td/sub/bad2.md"
  printf -- '---\nstatus: active\nupdated: 2026-13-99\n---\n' > "$td/flat-root.md"
  scan "$td"
  if [ "$HARD" -lt 3 ]; then echo "self-test: 未抓全坏样本 (HARD=$HARD, 期望>=3)"; ok=0; fi
  if printf '%s\n' "$DETAIL" | grep -q 'good.md'; then echo "self-test: 误报好样本 good.md"; ok=0; fi
  if [ "$ok" -eq 1 ]; then echo "self-test: OK"; rm -rf "$td"; return 0; fi
  rm -rf "$td"; return 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root) DOCS_DIR="$2"; shift 2;;
    --json) JSON=1; shift;;
    --md) MD_OUT="$2"; shift 2;;
    --self-test) SELF_TEST=1; shift;;
    --help|-h) usage; exit 0;;
    *) echo "未知参数: $1"; usage; exit 2;;
  esac
done

if [ "$SELF_TEST" -eq 1 ]; then self_test; exit $?; fi
if [ "$JSON" -eq 1 ]; then emit_json; fi
if [ -n "$MD_OUT" ]; then run_md; exit 0; fi
run_bare
