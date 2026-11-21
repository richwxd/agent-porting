#!/bin/bash
# smoke-test.sh — 安装 deb → 启动 → 等待升级检测 → 汇报（一次性验证，可重复跑）
set -uo pipefail
unset LD_LIBRARY_PATH LD_PRELOAD LD_AUDIT 2>/dev/null || true
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEB="$(ls -t "$ROOT"/dist/raccoon-ai_*_amd64.deb 2>/dev/null | head -1)"
[ -n "$DEB" ] || { echo "找不到产物"; exit 1; }

echo "== 1/5 安装 =="
sudo dpkg -i "$DEB" || { echo "dpkg 安装失败"; exit 1; }

echo "== 2/5 安装清单抽查 =="
dpkg -L raccoon-ai | grep -E "^/usr/bin/|desktop$|256x256" | sed 's/^/  /'
ls -la /opt/office-raccoon/raccoon-ai /usr/bin/raccoon-ai | sed 's/^/  /'

echo "== 3/5 启动（启动器已排除有害 env）=="
pkill -x raccoon-ai 2>/dev/null
sleep 1
setsid /usr/bin/raccoon-ai >/tmp/raccoon-smoke.log 2>&1 </dev/null &
sleep 12
if pgrep -x raccoon-ai >/dev/null; then
  echo "  ✓ 进程存活: pids=$(pgrep -x raccoon-ai | tr '\n' ' ')"
else
  echo "  ✗ 进程未存活，启动日志:"
  tail -40 /tmp/raccoon-smoke.log | sed 's/^/    /'
  exit 1
fi

echo "== 4/5 等待升级检测（首查在启动后约 8s）=="
sleep 35
echo "  --- stdout/stderr 中的 app-update ---"
grep -hE "\[app-update\]|version policy|update" /tmp/raccoon-smoke.log 2>/dev/null | tail -15 | sed 's/^/    /' || true
echo "  --- electron 日志文件 ---"
LOGS="$(find "$HOME/.config" "$HOME/.local/share" -name '*.log' -mmin -5 2>/dev/null | head -8)"
for l in $LOGS; do
  echo "    [$l]"
  grep -hE "\[app-update\]|Version policy|check failed|Checking for update|is not available|latest-linux|Cannot find channel|NsisUpdater" "$l" 2>/dev/null | tail -12 | sed 's/^/      /'
done

echo "== 5/5 进程状态 =="
ps -o pid,etime,rss,args -p "$(pgrep -x raccoon-ai | head -1)" 2>/dev/null | sed 's/^/  /'
echo
echo "完成。窗口应已弹出（可用肉眼/截图确认图标与原生标题栏）。"
