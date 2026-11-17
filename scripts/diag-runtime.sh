#!/usr/bin/env bash
# Loomy（移植版）运行时体检 —— 只读诊断，不改任何东西。
# 排查两类已知问题：
#   1) 「OpenCode 二进制文件不存在」→ 检查 1
#   2) 「不报错但没反应」→ 检查 2/3/4/5（首启依赖安装把 API 请求全堵住，慢网络下数分钟）
# 用法：./scripts/diag-runtime.sh
# 覆盖安装位置：INSTALL_ROOT=/opt/xunfei/loomy ./scripts/diag-runtime.sh
set -u

INSTALL_ROOT="${INSTALL_ROOT:-/opt/xunfei/loomy}"
OC_BIN="$INSTALL_ROOT/resources/opencode/linux-x64/opencode"
OC_MIN_BYTES=$((20 * 1024 * 1024))   # opencode 侧 OPENCODE_BINARY_MIN_BYTES
CONF_DIRS=("$HOME/.config/loomy-opencode" "$HOME/.config/loomy-opencode/opencode")
LOCK_DIR="$HOME/.local/state/loomy/opencode/locks"
LOG_DIR="$HOME/.local/share/loomy/opencode/log"

fail=0
ok()   { printf '[ OK ] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
bad()  { printf '[FAIL] %s\n' "$*"; fail=1; }

echo "== 1. OpenCode 二进制 =="
if [ ! -e "$OC_BIN" ]; then
  bad "$OC_BIN 不存在（应用会报「OpenCode 二进制文件不存在」）"
else
  sz=$(stat -c%s "$OC_BIN" 2>/dev/null || echo 0)
  if [ "$sz" -ge "$OC_MIN_BYTES" ]; then ok "大小 $sz B（≥ $OC_MIN_BYTES）"; else bad "大小 $sz B 过小（疑似 git-lfs 指针或损坏）"; fi
  if head -c 200 "$OC_BIN" | grep -q 'git-lfs'; then bad "内容是 git-lfs 指针，不是真二进制"; else ok "非 git-lfs 指针"; fi
  if [ -x "$OC_BIN" ]; then ok "可执行"; else bad "缺 x 权限"; fi
  v=$("$OC_BIN" --version 2>/dev/null | head -1)
  if [ -n "$v" ]; then ok "--version → $v"; else bad "无法执行 --version"; fi
fi

echo "== 2. 配置目录依赖一致性（决定会不会触发 npm 重装 → 无反应）=="
for d in "${CONF_DIRS[@]}"; do
  if [ ! -d "$d" ]; then warn "$d 不存在（首次启动后才创建）"; continue; fi
  python3 - "$d" <<'PY'
import json, os, sys
d = sys.argv[1]
def load(p):
    try:
        with open(p) as f:
            return json.load(f)
    except Exception:
        return None
pkg = load(os.path.join(d, "package.json")) or {}
lock = load(os.path.join(d, "package-lock.json")) or {}
deps = pkg.get("dependencies", {})
lockdeps = ((lock.get("packages") or {}).get("") or {}).get("dependencies", {})
missing = [k for k in deps if lockdeps.get(k) != deps.get(k)]
if not os.path.isdir(os.path.join(d, "node_modules")):
    print("[FAIL] %s: node_modules 缺失 → 首启会 npm 重装，请求被堵数分钟" % d)
    sys.exit(1)
if missing:
    print("[FAIL] %s: lock 与 package.json 不一致 %s → 会重装" % (d, missing))
    sys.exit(1)
print("[ OK ] %s: 依赖一致，不会重装" % d)
PY
  [ $? -eq 0 ] || fail=1
done

echo "== 3. 残留文件锁（ReleaseError: token mismatch 来源）=="
if [ -d "$LOCK_DIR" ] && [ -n "$(ls -A "$LOCK_DIR" 2>/dev/null)" ]; then
  warn "有残留锁，可清空目录: $LOCK_DIR"
  ls -A "$LOCK_DIR"
else
  ok "无残留锁"
fi

echo "== 4. 最近日志 =="
latest=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
if [ -z "$latest" ]; then
  warn "无日志: $LOG_DIR"
else
  echo "最新: $latest"
  n=$(grep -c 'background dependency install failed' "$latest")
  if [ "$n" -gt 0 ]; then warn "依赖安装失败告警 ×$n（安装已落盘则无害）"; else ok "无依赖安装失败告警"; fi
  slow=$(grep -E 'duration=[0-9]{6,}' "$latest" | tail -3)
  if [ -n "$slow" ]; then warn "出现过 ≥100s 的请求（首启排队特征）:"; echo "$slow"; else ok "无超长请求"; fi
fi

echo "== 5. 服务响应 =="
port=$(pgrep -af 'opencode.*serve' | grep -oE 'port[= ][0-9]+' | grep -oE '[0-9]+' | head -1)
if [ -z "$port" ]; then
  warn "未发现 opencode serve 进程（应用没在跑）"
else
  echo "服务端口: $port"
  for p in doc config session; do
    printf 'GET /%s -> ' "$p"
    curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' --max-time 5 "http://127.0.0.1:$port/$p" || echo "连接失败"
  done
fi

echo
if [ "$fail" -eq 0 ]; then echo "结论: 健康"; else echo "结论: 有 FAIL 项，按上面提示处理"; fi
exit $fail
