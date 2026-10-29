# toolbox/lib/render.sh —— 骨架模板渲染统一契约（/bin/sh，被 mount-init / project-scaffold / todos source）
#
# 契约（SSOT）：
#   render_tpl <输出路径> <模板路径> [KEY=value ...]  渲染并落盘
#   render_std <模板路径> [KEY=value ...]             渲染输出到 stdout（供管道给 mk 等读 stdin 的写盘器）
#   tpl_check <模板路径 ...>                          模板存在性预检
#
# 行为写死：
#   - 替换为全字面替换（占位符名 {{UPPER_SNAKE}}），值自动转义 sed 替换特殊符（& \ |）
#   - 残留校验：渲染产物仍有 {{...}} = 占位符漏替换，exit 2 fail-loud（占位符拼错/渲染参数缺 KEY 不许流入产物）
#   - 模板缺失 = 自身故障 exit 2（JSON 模式单行 JSON；JSON 变量由 source 方脚本持有）
#   - 模板路径按 toolbox 仓内路径约定（无空格无引号），eval 拼表达式为 sh 标准做法

render_esc() { printf '%s' "$1" | sed -e 's/[&/\|]/\\&/g'; }

tpl_fail() {
  if [ "${JSON:-0}" = 1 ]; then
    printf '{"status":"FAIL","severity":"error","message":"自身故障: 模板缺失 %s","remedy":"模板应随 ~/.agents 仓库同步；重新同步或补齐后重跑"}\n' "$1"
  else
    echo "ERROR: 模板缺失: $1"
    echo '[remedy] 模板应随 ~/.agents 仓库同步；重新同步或补齐后重跑'
  fi
  exit 2
}

tpl_check() {
  for _t in "$@"; do
    [ -f "$_t" ] || tpl_fail "$_t"
  done
  return 0
}

# 渲染到 stdout：$1=模板路径，$2...=KEY=value
render_body() {
  _rb_tpl="$1"; shift
  tpl_check "$_rb_tpl"
  if [ $# -eq 0 ]; then
    cat "$_rb_tpl"
    return 0
  fi
  _rb_exprs=''
  for _rb_kv in "$@"; do
    _rb_k=${_rb_kv%%=*}
    _rb_v=${_rb_kv#*=}
    case "$_rb_v" in
      *"'"*)
        echo "ERROR: 渲染值含单引号无法安全渲染: $_rb_k"
        echo '[remedy] 渲染值不得含单引号（模板渲染契约，见本头部注释）'
        exit 2 ;;
    esac
    # 单引号包整表达式：eval 重解析时 | 不再被当作管道符（裸 s|…| 会被拆成三条命令）
    _rb_exprs="$_rb_exprs -e 's|{{$_rb_k}}|$(render_esc "$_rb_v")|g'"
  done
  # shellcheck disable=SC2046
  eval "sed $_rb_exprs \"$_rb_tpl\""
}

render_std() {
  render_body "$@"
}

# 渲染落盘：$1=输出路径，$2=模板路径，$3...=KEY=value
render_tpl() {
  _rt_dst="$1"; shift
  _rt_tmp="${_rt_dst}.render.tmp"
  if ! render_body "$@" > "$_rt_tmp"; then
    rm -f "$_rt_tmp"
    if [ "${JSON:-0}" = 1 ]; then
      printf '{"status":"FAIL","severity":"error","message":"自身故障: 模板渲染失败","remedy":"检查模板与渲染参数（templates/README.md 占位符清单）"}\n'
    else
      echo "ERROR: 模板渲染失败"
      echo '[remedy] 检查模板与渲染参数（templates/README.md 占位符清单）'
    fi
    exit 2
  fi
  if grep -q '{{' "$_rt_tmp" 2>/dev/null; then
    rm -f "$_rt_tmp"
    if [ "${JSON:-0}" = 1 ]; then
      printf '{"status":"FAIL","severity":"error","message":"自身故障: 渲染产物残留占位符（渲染参数缺 KEY 或占位符拼错）","remedy":"核对模板占位符清单与渲染参数（templates/README.md）"}\n'
    else
      echo "ERROR: 渲染产物残留占位符: $_rt_dst（渲染参数缺 KEY 或占位符拼错）"
      echo '[remedy] 核对模板占位符清单与渲染参数（templates/README.md）'
    fi
    exit 2
  fi
  mv "$_rt_tmp" "$_rt_dst" || { rm -f "$_rt_tmp"; echo "ERROR: 写回失败: $_rt_dst"; echo '[remedy] 检查路径与权限'; exit 2; }
}
