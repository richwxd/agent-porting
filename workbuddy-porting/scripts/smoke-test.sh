#!/bin/bash
# smoke-test.sh — 安装 deb → 启动 → 等待升级检测 → 汇报（一次性验证，可重复跑）
# 升级检测：启动后约 30s 首查（main-bootstrap setTimeout 3e4），feed=win32-x64-user；
# 已移除 D 补丁走诚实检查：5.11.3→feed 204 → 应出现 No update available (HTTP 204)（不再误弹更新）。
set -uo pipefail
unset LD_LIBRARY_PATH LD_PRELOAD LD_AUDIT 2>/dev/null || true
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEB="$(ls -t "$ROOT"/dist/workbuddy_*_amd64.deb 2>/dev/null | head -1)"
[ -n "$DEB" ] || { echo "找不到产物"; exit 1; }

echo "== 1/5 安装 =="
sudo dpkg -i "$DEB" || { echo "dpkg 安装失败"; exit 1; }

echo "== 2/5 安装清单抽查 =="
dpkg -L workbuddy | grep -E "^/usr/bin/|desktop$|256x256" | sed 's/^/  /'
ls -la /opt/WorkBuddy/workbuddy /usr/bin/workbuddy | sed 's/^/  /'

echo "== 3/5 启动（启动器已排除有害 env）=="
pkill -x workbuddy 2>/dev/null
sleep 1
setsid /usr/bin/workbuddy >/tmp/workbuddy-smoke.log 2>&1 </dev/null &
sleep 12
if pgrep -x workbuddy >/dev/null; then
  echo "  ✓ 进程存活: pids=$(pgrep -x workbuddy | tr '\n' ' ')"
else
  echo "  ✗ 进程未存活，启动日志:"
  tail -40 /tmp/workbuddy-smoke.log | sed 's/^/    /'
  exit 1
fi

echo "== 4/5 等待升级检测（首查在启动后约 30s）=="
sleep 40
echo "  --- stdout/stderr 中的更新日志 ---"
grep -hE "win32-x64-user|Checking for updates|Update response|External update available|No new version|No update" /tmp/workbuddy-smoke.log 2>/dev/null | tail -15 | sed 's/^/    /' || true
grep -q "platform=workbuddy-win32-x64-user" /tmp/workbuddy-smoke.log && echo "  ✓ 走 win32-x64-user 通道" || echo "  ✗ 未见 win32-x64-user 通道"
grep -q "No update available (HTTP 204)" /tmp/workbuddy-smoke.log && echo "  ✓ 204 已是最新（不误弹更新）" || { grep -q "External update available" /tmp/workbuddy-smoke.log && echo "  ✗ 仍报 available（D 未删净？）" || echo "  ✗ 未见 204 也未见 available"; }
echo "  --- electron 日志文件 ---"
LOGS="$(find "$HOME/.config" "$HOME/.local/share" -name '*.log' -mmin -5 2>/dev/null | head -8)"
for l in $LOGS; do
  echo "    [$l]"
  grep -hE "win32-x64-user|Checking for updates|Update response|External update available|No new version|No update" "$l" 2>/dev/null | tail -12 | sed 's/^/      /'
done

echo "== 5/5 进程状态 =="
ps -o pid,etime,rss,args -p "$(pgrep -x workbuddy | head -1)" 2>/dev/null | sed 's/^/  /'
echo
echo "完成。升级检测命中 win32-x64-user 通道且报 No update available (HTTP 204)（已是最新）即通过；官方发 5.11.4 后应报 available 并可点击下载。"
