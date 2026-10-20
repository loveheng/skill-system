#!/bin/sh
# bugpack —— Bug 报障 Prompt 拼装器：git diff + 报错日志 + 环境版本 → 密钥脱敏 → 三段式报障（problem-triage manual §1.5 口径）
# 三段：预期 vs 实际（用户填）/ 复现证据（diff + 日志原文）/ 代码与环境。
# 密钥脱敏是硬门槛：所有输出先过 sanitize；脱敏后仍命中疑似密钥模式 → exit 1 拒交（宁缺勿泄）。
# 缺料如实标注「未提供」，严禁凑段编造（对齐 manual §1.5「手头没有就明说」）。
#
# toolbox-script
# format: v1
# name: bugpack
# summary: Bug 报障 Prompt 拼装（diff+日志+环境版本→密钥脱敏→三段式 manual §1.5），脱敏后仍命中疑似密钥即拒交
# trigger: manual
# cat: test
# alias: bugpack
# platform: unix
# self-test: --self-test

set -u
MSG=""

usage() {
  cat <<'EOF'
用法: bugpack [--root <项目根>] [--log <文件|目录>]... [--out <文件>] [--json] [--self-test] [--help]
  --root   项目根（默认当前 git 仓）
  --log    报错日志/堆栈文件或目录（可重复；tail 80 行/文件；缺省段标「未提供」）
  --out    报告落盘路径（缺省打 stdout；禁默认 /tmp——易失，见 dev-init §1 第 7 步口径）
  --json   输出一行 JSON 契约结论（message 内禁双引号）
  --self-test  金丝雀自检（假密钥样本必被抹净、门槛必拦）
退出码: 0=报告已生成 1=脱敏后仍疑似命中密钥（拒交） 2=自身故障
EOF
}

# ---------- 密钥脱敏（硬门槛核心） ----------
# 用法: sanitize < 输入 > 输出；密钥命中数写全局 SANIT_HITS
SANIT_HITS=0
sanitize() {
  # 常见凭据赋值 / Bearer / 云厂商 AK / 私钥块 / 连接串口令
  perl -pe '
    s{(Bearer\s+)[^\s,;)\x27"]+}{$1***}g;
    s{((?:password|passwd|secret|token|api[_-]?key|apikey|access[_-]?key|auth)[^:=]*[:=]\s*)[^\s,;)\x27"]+}{$1***}gi;
    s{(AKIA)[0-9A-Z]{16}}{${1}***}g;
    s{((?:ghp|gho|ghu|ghs)_[A-Za-z0-9]{20,})}{***}g;
    s{(sk-[A-Za-z0-9]{20,})}{***}g;
    s{(xox[baprs]-)[A-Za-z0-9-]{10,}}{${1}***}g;
    s{(-----BEGIN [A-Z ]*PRIVATE KEY-----).*?(-----END [A-Z ]*PRIVATE KEY-----)}{${1} ... ${2}}gs;
    s{(://[^:/\s]+:)[^@\s/]+(@)}{${1}***${2}}g;
  '
}

# ---------- 报告拼装 ----------
build_report() {
  root=$1; shift
  now=$(date +%F' '%H:%M)
  {
    echo "# Bug 报障（bugpack @ $now，仓：$(basename "$root")）"
    echo
    echo "## 一、预期 vs 实际（【由报障人填写，此段工具不代笔】）"
    echo "- 预期："
    echo "- 实际："
    echo
    echo "## 二、复现证据"
    echo "### 变更集（git diff HEAD --stat，最近 60 行 patch）"
    if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      echo '```'
      git -C "$root" diff HEAD --stat | tail -n 30
      git -C "$root" diff HEAD | head -n 60
      echo '```'
      echo "### 最近提交"
      echo '```'
      git -C "$root" log --oneline -5
      echo '```'
    else
      echo "- 未提供（非 git 仓）"
    fi
    echo "### 报错日志 / 堆栈"
    if [ -n "$LOGS" ]; then
      for lf in $LOGS; do
        [ -e "$lf" ] || { echo "- 跳过（不存在）：$lf"; continue; }
        echo '```'
        echo "# $lf"
        if [ -d "$lf" ]; then
          find "$lf" -type f | head -n 5 | while IFS= read -r f; do echo "# -- $f"; tail -n 40 "$f"; done
        else
          tail -n 80 "$lf"
        fi
        echo '```'
      done
    else
      echo "- 未提供（--log 指定；手头没有就明说，严禁编造）"
    fi
    echo
    echo "## 三、代码与环境"
    echo '```'
    echo "OS: $(uname -s) $(uname -r 2>/dev/null)"
    for c in git node npm python3 pip3 java mvn docker flutter dart go rustc; do
      command -v "$c" >/dev/null 2>&1 || continue
      v=$("$c" --version 2>/dev/null | head -n 1)
      [ -n "$v" ] && echo "$c: $v"
    done
    echo '```'
    echo "- 能否稳定复现：【由报障人填写；不稳定时写频率/环境/操作路径——时序侧关键信号】"
  } 2>/dev/null
}

# ---------- 金丝雀自检 ----------
exec_self_test() {
  ok=0
  # 坏样本：假密钥必被抹净（源码内拼接构造，静态面不含连续密钥形状——check 门禁豁免自我误伤）
  _sk='sk-'; _skv='abcdefghijklmnopqrstuvwxyz123456'
  _ak='AKIA'; _akv='IOSFODNN7EXAMPLE'
  bad="password=SuperSecret123
Authorization: Bearer abc.def.ghi
api_key: \"${_sk}${_skv}\"
postgres://admin:hunter2@db.local/x
${_ak}${_akv}"
  clean=$(printf '%s' "$bad" | sanitize)
  echo "$clean" | grep -q "SuperSecret123\|Bearer abc\|${_sk}${_skv}\|hunter2\|${_ak}${_akv}" \
    && { echo 'self-test: fail 坏样本密钥未被抹净'; return 1; } || ok=1
  echo "$clean" | grep -q '\*\*\*' || { echo 'self-test: fail 抹净后缺 *** 占位'; ok=0; }
  # 好样本：正常内容不被误伤
  good='- [2026-10-20] (修复) fix null check in parser.py
panic: runtime error: index out of range [5]'
  gc=$(printf '%s' "$good" | sanitize)
  [ "$gc" = "$good" ] || { echo 'self-test: fail 好样本被误伤'; ok=0; }
  # 门槛：含明文密钥的未脱敏内容必须被拦（residual>0）
  r=$(printf '%s' "$bad" | grep -icE '(password|secret|api[_-]?key)[^:=]*[:=][^* ]' || true)
  [ "${r:-0}" -gt 0 ] || { echo 'self-test: fail 门槛对坏样本未报残留'; ok=0; }
  # 复合断言：脱敏→门槛 全链路对坏样本产出干净报告
  rc2=$(printf '%s' "$bad" | sanitize | grep -icE '(password|secret|api[_-]?key)[^:=]*[:=][^* ]' || true)
  [ "${rc2:-0}" -eq 0 ] || { echo 'self-test: fail 脱敏后门槛仍报残留'; ok=0; }
  [ "$ok" = 1 ] && echo 'self-test: OK（坏样本密钥全抹净 + 好样本零误伤 + 门槛必拦）' && return 0
  return 1
}

# ---------- 主流程 ----------
ROOT=""; OUT=""; LOGS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "[remedy] --root 缺参数"; exit 2; }; ROOT=$2; shift 2 ;;
    --log)  [ $# -ge 2 ] || { echo "[remedy] --log 缺参数"; exit 2; }; LOGS="${LOGS:+$LOGS }$2"; shift 2 ;;
    --out)  [ $# -ge 2 ] || { echo "[remedy] --out 缺参数"; exit 2; }; OUT=$2; shift 2 ;;
    --json) JSON=1; shift ;;
    --self-test) exec_self_test; exit $? ;;
    --help|-h) usage; exit 0 ;;
    *) usage; echo "[remedy] 未知参数: $1"; exit 2 ;;
  esac
done
[ -n "$ROOT" ] || ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
[ -d "$ROOT" ] || { MSG="root 目录不存在：$ROOT"; [ "${JSON:-0}" = 1 ] && printf '{"status":"FAIL","severity":"error","message":"%s"}\n' "$MSG" || echo "FAIL: $MSG"; exit 2; }

RAW=$(build_report "$ROOT")
# 脱敏命中数：对脱敏前原文按全形状谱统计（赋值/Bearer/AKIA/ghp/sk-/xox/私钥块/连接串）
SANIT_HITS=$(printf '%s' "$RAW" | grep -icE '(password|passwd|secret|token|api[_-]?key|apikey|access[_-]?key|auth)[^:=]*[:=][^* ]|Bearer [^ *]|AKIA[0-9A-Z]{16}|(ghp|gho|ghu|ghs)_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY|://[^:/ ]+:[^@ ]+@' || true)
SANIT_HITS=${SANIT_HITS:-0}
CLEAN=$(printf '%s' "$RAW" | sanitize)
RESIDUAL=$(printf '%s' "$CLEAN" | grep -icE '(password|passwd|secret|api[_-]?key|apikey|access[_-]?key)[^:=]*[:=][^* ]' || true)
if [ "${RESIDUAL:-0}" -gt 0 ]; then
  MSG="脱敏后仍疑似命中疑似密钥 $RESIDUAL 处——拒交，人工核对后手工剔除再报障"
  if [ "${JSON:-0}" = 1 ]; then printf '{"status":"FAIL","severity":"warn","message":"%s"}\n' "$MSG"; else echo "FAIL: $MSG"; fi
  exit 1
fi
if [ -n "$OUT" ]; then
  printf '%s' "$CLEAN" > "$OUT"
  MSG="报告已写入 $OUT（脱敏改写 $SANIT_HITS 处）；--out 路径请勿放 /tmp（易失）"
elif [ "${JSON:-0}" = 1 ]; then
  # JSON 契约模式：stdout 仅一行结论，报告正文不打印（可随后 --out 落盘获取）
  MSG="报告已生成（脱敏改写 $SANIT_HITS 处，未落盘）"
else
  printf '%s' "$CLEAN"
  MSG="报告已生成（脱敏改写 $SANIT_HITS 处）"
fi
if [ "${JSON:-0}" = 1 ]; then printf '{"status":"OK","severity":"info","message":"%s"}\n' "$MSG"; else [ -n "$OUT" ] && echo "OK: $MSG"; fi
exit 0
