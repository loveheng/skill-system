#!/bin/bash
# drift-guard — 契约面漂移机械护栏（多项目共用引擎，零项目知识）
#
# 治「回写不完整」这一框架级病害：契约面变更（工具改名 / 词表单轴化 / 新单源
# 常量 / 新超标件）后，代码、面向下游的文案、SSOT 文档三面漂移。本工具按各项目
# 自带的 registry 数据扫描三类**可机械判定**的漂移：
#
#   BANNED  退役词条（token 级）：面向下游的 copy 与 docs 出现已退役拼写
#   CONST   单源常量（字面量级）：代码字面量只许出现在声明处（+显式登记的镜像）
#   OVERSIZE 体量登记（行数级）：lib/ 超行数上限的件必须登记在项目超标清单
#
# 诚实边界（写死）：docs 与代码的「集合描述一致性」（如三档 vs 四档的散文表述）
# 机械不可靠，**不做扫描**，归 ::audit 人判；context/ 是历史账归属，不扫。
#
# registry 行格式（`|` 分字段，字段内多值用 `,`；`#` 起头为注释）：
#   BANNED|<token>|<scope,...>|<理由>
#   CONST|<常量名>|<字面量>|<声明文件>[,<镜像文件>...]
#   OVERSIZE|<行数上限>|<登记清单文件>
# scope = 目录（递归 .dart/.md）或文件路径；`.dart` 剥整行注释（// 与 * 起头），
# 任意文件行内 `drift:keep` 显式豁免（历史留档禁静默）。token/字面量按**固定串**
# 匹配（禁正则——token 常含 `?` 等正则元字符）；CONST 的 token 须带足上下文防误伤
# （如 `strategy=` 带等号，不误伤兼容别名代码 query['strategy']）。
#
# registry 缺失 = 项目未接入 → 放行（exit 0 + 提示），不fail-open成漏洞：
# 接入即建 `<repo>/scripts/agent-tools/drift-registry.txt`。
#
# 双入口（全局引擎 + 项目数据）：
#   本地/pre-commit: toolbox run drift-guard（经 pre-commit-gate 分派）
#   CI:             各项目 test/architecture/drift_rules_test.dart Dart 镜像
#                   （CI 无 toolbox；镜像与引擎同读同一 registry）
#
# toolbox-script
# format: v1
# name: drift-guard
# summary: 契约面漂移机械护栏（BANNED 退役词条 / CONST 单源常量 / OVERSIZE 超标登记），registry 数据留各项目、引擎全局共用
# trigger: pre-commit
# cat: test
# alias: dg
# platform: unix
# self-test: --self-test
#
# 规则口径（维护纪律）见各项目 docs/project/coding-standards.md §8 与设计稿；
# 引擎自身不含任何项目规则——新规则只加 registry 数据行，不改本脚本。

set -uo pipefail

ROOT=""
REGISTRY=""
JSON_ONLY=0
SELF_TEST=0
COUNT=0
HITS=""

usage() {
  cat <<'EOF'
用法: drift-guard.sh [选项]        （toolbox run drift-guard [选项] 等价）
  按项目 registry 扫描契约面漂移，逐条打印命中，0=通过 1=有漂移
选项:
  --root <目录>     指定仓库根（默认 git 顶层 / 当前目录）
  --registry <路径> 指定 registry 文件（默认 <root>/scripts/agent-tools/drift-registry.txt）
  --json            只输出一行 JSON 结论（供 AI/钩子判定，不打印明细）
  --self-test       金丝雀自测：内嵌真实历史坏样本，证明"能抓到坏"
  -h, --help        本帮助
说明: registry 缺失 = 项目未接入 → 放行并提示（接入即建文件）。
EOF
}

die() { echo "ERROR: $*" >&2; exit 2; }

resolve_root() {
  if [ -n "$ROOT" ]; then printf '%s\n' "$ROOT"; return; fi
  local here d
  here=$(cd "$(dirname "$0")" && pwd)
  d=$(git -C "$here" rev-parse --show-toplevel 2>/dev/null)
  printf '%s\n' "${d:-$PWD}"
}

hit() { # $1=规则id $2=描述 $3=命中行（file:lineno: code 或纯文本）
  HITS="${HITS}FAIL $3 [$1] $2\n"
  COUNT=$((COUNT + 1))
}

# 命中行过滤：.dart 整行注释（// 与 * 起头）不判；任意行内 drift:keep 显式豁免。
# 注意：只剥**整行**注释（对齐 arch-guard R9 口径）；行尾注释误伤走 drift:keep
# 豁免（可见、可审计，禁静默）。
# 所有 grep 带 -H：单文件操作数默认不输出文件名（多文件/目录才输出），解析依赖
# `path:lineno:content` 形态——缺 -H 会把行号当路径（2026-10-23 首跑实证）。
filter_hits() { # $1=文件扩展名（dart|md|other）
  local ext="$1"
  grep -v 'drift:keep' | {
    if [ "$ext" = "dart" ]; then
      grep -vE "^[^:]+:[0-9]+: *(//|\*)"
    else
      cat
    fi
  }
}

# 展开 scope 为文件列表（目录递归 .dart/.md；文件原样）。未知 scope 记 WARN 不计 FAIL。
expand_scope() { # $1=scope（相对 ROOT）
  local s="$1"
  if [ -d "$ROOT/$s" ]; then
    find "$ROOT/$s" -type f \( -name '*.dart' -o -name '*.md' \) 2>/dev/null
  elif [ -f "$ROOT/$s" ]; then
    printf '%s\n' "$ROOT/$s"
  else
    echo "WARN: scope 不存在: $s" >&2
  fi
}

file_ext() {
  case "$1" in
    *.dart) printf 'dart' ;;
    *.md) printf 'md' ;;
    *) printf 'other' ;;
  esac
}

# ---- BANNED：token 级退役词条 ----
scan_banned() { # $1=token $2=scopes(逗号分隔) $3=理由 $4=序号
  local token="$1" scopes="$2" reason="$3" idx="$4"
  local s f out ext line rel rest lineno code
  local IFS=','
  for s in $scopes; do
    [ -z "$s" ] && continue
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      ext=$(file_ext "$f")
      out=$(grep -rnHF -- "$token" "$f" 2>/dev/null | filter_hits "$ext" || true)
      [ -z "$out" ] && continue
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        rel=${line%%:*}; rest=${line#*:}; lineno=${rest%%:*}; code=${rest#*:}
        rel=${rel#"$ROOT/"}
        code=$(printf '%s' "$code" | cut -c1-72 | tr -d '"')
        hit "D1-banned#$idx" "退役词条「$token」不得出现在契约面（$reason）" \
            "${rel}:${lineno}"$'\n'"        ${code}"
      done <<EOF
$out
EOF
    done < <(expand_scope "$s")
  done
}

# ---- CONST：字面量级单源常量 ----
scan_const() { # $1=name $2=literal $3=files(逗号分隔：声明+镜像) $4=序号
  local name="$1" literal="$2" files="$3" idx="$4"
  local out line rel rest lineno code allowed
  # 搜索面 = **lib/ 生产代码**（注释剥除）。test/ 不扫：测试字面量是有意的
  # 独立钉子（协议版本等常量变更会让相关测试直接失败，自曝式守护），扫了只会
  # 逼出几十个假镜像登记。docs 散文提及不判（版本号在文档里是正常叙述）。
  out=$(grep -rnHF -- "$literal" "$ROOT/lib" \
        --include='*.dart' 2>/dev/null | filter_hits dart || true)
  [ -z "$out" ] && return 0
  allowed=" $files "
  local IFS=','
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    rel=${line%%:*}; rel=${rel#"$ROOT/"}
    case "$allowed" in *" $rel "*) continue ;; esac
    rest=${line#*:}; lineno=${rest%%:*}; code=${rest#*:}
    code=$(printf '%s' "$code" | cut -c1-72 | tr -d '"')
    hit "D2-const#$idx" "单源常量 $name 的字面量「$literal」只许出现在: $files" \
        "${rel}:${lineno}"$'\n'"        ${code}"
  done <<EOF
$out
EOF
}

# ---- OVERSIZE：行数级超标登记核对 ----
scan_oversize() { # $1=limit $2=登记清单文件 $3=序号
  local limit="$1" listfile="$2" idx="$3"
  local list="$ROOT/$listfile"
  if [ ! -f "$list" ]; then
    hit "D3-oversize#$idx" "登记清单文件不存在: $listfile（OVERSIZE 登记失据）" "registry"
    return 0
  fi
  local f rel lines
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    lines=$(wc -l < "$f")
    [ "$lines" -gt "$limit" ] || continue
    # 超标清单按 lib/ 前缀剥离形态登记（ui/chat_page.dart）——同形态核对。
    rel=${f#"$ROOT/"}; rel=${rel#lib/}
    grep -qF "$rel" "$list" || \
      hit "D3-oversize#$idx" "lib/ 文件超 ${limit} 行未登记超标清单（$lines 行；只减不增纪律：先登记再长大）" \
          "${f#"$ROOT/"}"
  done < <(find "$ROOT/lib" -type f -name '*.dart' 2>/dev/null)
}

scan_all() {
  COUNT=0
  HITS=""
  [ -f "$REGISTRY" ] || {
    echo "NOTE: registry 不存在（$REGISTRY）——项目未接入 drift-guard，放行。接入即建该文件（格式见脚本头注释）。" >&2
    return 0
  }
  local n=0 line kind
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    kind=${line%%|*}
    n=$((n + 1))
    case "$kind" in
      BANNED)
        local token scopes reason
        IFS='|' read -r _ token scopes reason <<< "$line"
        if [ -z "${token:-}" ] || [ -z "${scopes:-}" ]; then
          hit "D0-format#$n" "BANNED 行缺字段（须 BANNED|token|scopes|reason）" "registry:$n"
          continue
        fi
        scan_banned "$token" "$scopes" "${reason:-（未注明理由）}" "$n"
        ;;
      CONST)
        local cname literal files
        IFS='|' read -r _ cname literal files <<< "$line"
        if [ -z "${cname:-}" ] || [ -z "${literal:-}" ] || [ -z "${files:-}" ]; then
          hit "D0-format#$n" "CONST 行缺字段（须 CONST|name|literal|files）" "registry:$n"
          continue
        fi
        scan_const "$cname" "$literal" "$files" "$n"
        ;;
      OVERSIZE)
        local limit listfile
        IFS='|' read -r _ limit listfile <<< "$line"
        if [ -z "${limit:-}" ] || [ -z "${listfile:-}" ]; then
          hit "D0-format#$n" "OVERSIZE 行缺字段（须 OVERSIZE|limit|listfile）" "registry:$n"
          continue
        fi
        scan_oversize "$limit" "$listfile" "$n"
        ;;
      *)
        hit "D0-format#$n" "未知规则类型「$kind」（合法: BANNED/CONST/OVERSIZE）" "registry:$n"
        ;;
    esac
  done < "$REGISTRY"
  return 0
}

report_text() {
  if [ "$COUNT" -eq 0 ]; then
    echo "OK: 契约面漂移扫描通过（$REGISTRY）"
    return 0
  fi
  printf '%b' "$HITS"
  echo "----"
  echo "FAIL: $COUNT 处契约面漂移"
  echo "[remedy] ① 改文案/代码消除漂移；② 确属历史留档的行加 drift:keep 行内豁免（显式、可审计）；"
  echo "[remedy] ③ 合法镜像（如跨域本地声明的同步常量）登记进 registry 对应行；禁为过检而删词条"
  return 1
}

report_json() {
  if [ "$COUNT" -eq 0 ]; then
    printf '{"status":"OK","severity":"info","message":"drift-guard: 契约面漂移扫描通过"}\n'
    return 0
  fi
  printf '{"status":"FAIL","severity":"error","message":"drift-guard: %d 处契约面漂移（BANNED 退役词条 / CONST 单源常量 / OVERSIZE 超标登记）","remedy":"裸跑 toolbox run drift-guard 看逐条明细；历史留档加 drift:keep 行内豁免，合法镜像登记 registry"}\n' "$COUNT"
  return 1
}

self_test() {
  local bad clean rc
  bad=$(mktemp -d); clean=$(mktemp -d)
  trap 'rm -rf "$bad" "$clean"' RETURN

  # —— 坏样本：全部取自 2026-10-23 真实发生过的漂移现场 ——
  mkdir -p "$bad/lib/gateway" "$bad/docs/design" "$bad/scripts/agent-tools" "$bad/lib/ui"
  cat >"$bad/lib/gateway/bad_handler.dart" <<'EOF'
// single 拒绝话术（历史坏样本原文）
return const GatewayToolResult(
  content: 'gateway__* 是网关连接级系统工具；如需切换请改连 ?strategy=full',
);
EOF
  cat >"$bad/docs/design/bad_doc.md" <<'EOF'
# 设计稿
旧名 gateway__list_private_servers 已清理。
EOF
  cat >"$bad/lib/mcp_cap_dup.dart" <<'EOF'
const kMcpProtocolVersion = '2025-06-18';
EOF
  mkdir -p "$bad/lib/mcp"
  cat >"$bad/lib/mcp/dup.dart" <<'EOF'
const kMcpProtocolVersion = '2025-06-18';
EOF
  # 未登记超标件（limit=5 的小样本仓库里造一个 8 行文件）
  printf 'a\nb\nc\nd\ne\nf\ng\nh\n' > "$bad/lib/ui/giant.dart"
  cat >"$bad/scripts/agent-tools/drift-registry.txt" <<'EOF'
# 坏样本 registry
BANNED|?strategy=|lib/gateway|D1 单轴化后旧 URL 键
BANNED|gateway__list_private_servers|lib,docs|旧工具名
CONST|kMcpProtocolVersion|2025-06-18|lib/mcp/server_capabilities.dart
OVERSIZE|5|docs/project/index.md
EOF
  printf '# idx\n' > "$bad/docs/project_index_placeholder.md" 2>/dev/null
  mkdir -p "$bad/docs/project" && printf '# idx\n' > "$bad/docs/project/index.md"

  ROOT="$bad"; REGISTRY="$bad/scripts/agent-tools/drift-registry.txt"; scan_all
  if [ "$COUNT" -lt 4 ]; then
    echo "SELF-TEST FAIL: 坏样本只抓到 $COUNT 处（期望 >=4：BANNED×2 + CONST×1 + OVERSIZE×1）" >&2
    printf '%b' "$HITS" >&2
    return 2
  fi

  # —— 干净样本：合规 copy + drift:keep 历史留档 + 单源常量 + 无超标件 ——
  mkdir -p "$clean/lib/gateway" "$clean/lib/mcp" "$clean/docs/design" "$clean/scripts/agent-tools" "$clean/docs/project"
  cat >"$clean/lib/gateway/ok_handler.dart" <<'EOF'
// 现行口径：回联邦面请调 gateway__select_private(server_id="all", policy=full)
return const GatewayToolResult(content: 'ok');
// 历史留档：旧写法 ?strategy=full 已退役（drift:keep）
EOF
  cat >"$clean/docs/design/ok_doc.md" <<'EOF'
# 设计稿
旧名 gateway__list_private_servers 在术语纠错后改名（drift:keep：历史账留档）。
EOF
  cat >"$clean/lib/mcp/server_capabilities.dart" <<'EOF'
const kMcpProtocolVersion = '2025-06-18';
EOF
  printf '# idx\n' > "$clean/docs/project/index.md"
  cat >"$clean/scripts/agent-tools/drift-registry.txt" <<'EOF'
BANNED|?strategy=|lib/gateway|旧 URL 键
BANNED|gateway__list_private_servers|lib,docs|旧工具名
CONST|kMcpProtocolVersion|2025-06-18|lib/mcp/server_capabilities.dart
OVERSIZE|5|docs/project/index.md
EOF

  ROOT="$clean"; REGISTRY="$clean/scripts/agent-tools/drift-registry.txt"; scan_all
  if [ "$COUNT" -ne 0 ]; then
    echo "SELF-TEST FAIL: 干净样本误报 $COUNT 处" >&2
    printf '%b' "$HITS" >&2
    return 2
  fi

  # —— registry 缺失 = 未接入放行 ——
  ROOT="$clean"; REGISTRY="$clean/not-exist.txt"; scan_all
  if [ "$COUNT" -ne 0 ]; then
    echo "SELF-TEST FAIL: registry 缺失应放行" >&2
    return 2
  fi

  echo "SELF-TEST PASS: 坏样本抓到 >=4 处（BANNED×2/CONST×1/OVERSIZE×1，均为真实历史现场）、干净样本零误报、缺 registry 放行"
  return 0
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --root) ROOT="${2:-}"; [ -n "$ROOT" ] || die "--root 缺参数"; shift 2 ;;
      --registry) REGISTRY="${2:-}"; [ -n "$REGISTRY" ] || die "--registry 缺参数"; shift 2 ;;
      --json) JSON_ONLY=1; shift ;;
      --self-test) SELF_TEST=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) usage; exit 2 ;;
    esac
  done

  if [ "$SELF_TEST" -eq 1 ]; then
    self_test; exit $?
  fi

  ROOT=$(resolve_root)
  [ -d "$ROOT" ] || die "根目录不存在: $ROOT"
  REGISTRY="${REGISTRY:-$ROOT/scripts/agent-tools/drift-registry.txt}"

  scan_all
  if [ "$JSON_ONLY" -eq 1 ]; then report_json; else report_text; fi
}

main "$@"
