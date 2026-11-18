#!/bin/bash
# verify-deb.sh — 校验构建产物：关键文件、Linux 原生件、更新补丁是否真的打进包
# 用法: verify-deb.sh [deb路径]   （默认 dist/workbuddy_*_amd64.deb）
set -euo pipefail
unset LD_LIBRARY_PATH LD_PRELOAD LD_AUDIT 2>/dev/null || true
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DEB="${1:-}"
if [ -z "$DEB" ]; then
  DEB="$(ls -t "$ROOT"/dist/workbuddy_*_amd64.deb 2>/dev/null | head -1)"
fi
[ -n "$DEB" ] && [ -f "$DEB" ] || { echo "错误: 找不到产物 dist/*.deb（先跑 build-deb.sh）" >&2; exit 1; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=1; }

echo "校验: $DEB ($(du -h "$DEB" | cut -f1))"

echo "== control =="
dpkg-deb -f "$DEB" Package Version Architecture Depends \
  | paste -sd' | ' - | sed 's/^/  /'

echo "== 关键文件 =="
dpkg-deb -x "$DEB" "$T"
APP="$T/opt/WorkBuddy"
for f in \
  "workbuddy:主程序(官方定制 Electron)" \
  "chrome-sandbox:沙箱" \
  "resources/app.asar:业务逻辑(asar 头)" \
  "resources/app.asar.unpacked/main/update-service.linux.js:更新服务(全量 unpacked)" \
  "resources/app.asar.unpacked/cli/vendor/ripgrep/x64-linux/rg:ripgrep Linux" \
  "resources/app.asar.unpacked/cli/vendor/ripgrep/x64-linux/ripgrep.node:ripgrep node 绑定" \
  "resources/app.asar.unpacked/cli/node_modules/@lydell/node-pty-linux-x64/prebuilds/linux-x64/pty.node:cli node-pty Linux" \
  "resources/app.asar.unpacked/node_modules/node-pty/build/Release/pty.node:node-pty Linux" \
  "resources/app.asar.unpacked/node_modules/koffi/build/koffi/linux_x64/koffi.node:koffi Linux" \
  "resources/app.asar.unpacked/cli/node_modules/koffi/build/koffi/linux_x64/koffi.node:cli koffi Linux" \
  "resources/app.asar.unpacked/node_modules/@tencent/qimei-node/build/Release/qimei.node:qimei Linux" \
  "resources/runtime/node/bin/node:runtime node" \
  "resources/runtime/python/bin/python3:runtime python" \
  "resources/tray-linux.png:托盘图标" \
  "resources/file-icons:文件图标" \
  "$T/usr/bin/workbuddy:启动包装器" \
  "$T/usr/share/applications/workbuddy.desktop:.desktop" \
  "$T/usr/share/icons/hicolor/256x256/apps/workbuddy.png:hicolor 图标"
do
  p="${f%%:*}"; d="${f##*:}"
  case "$p" in /*) abs="$p";; *) abs="$APP/$p";; esac
  if [ -e "$abs" ]; then ok "$d ($p)"; else bad "缺失: $d ($p)"; fi
done

echo "== 主程序/原生件必须是 Linux ELF =="
for b in "$APP/workbuddy" \
         "$APP/resources/app.asar.unpacked/cli/vendor/ripgrep/x64-linux/rg" \
         "$APP/resources/app.asar.unpacked/node_modules/koffi/build/koffi/linux_x64/koffi.node" \
         "$APP/resources/app.asar.unpacked/node_modules/node-pty/build/Release/pty.node" \
         "$APP/resources/runtime/node/bin/node"; do
  t="$(file -b "$b" 2>/dev/null || true)"
  case "$t" in *ELF*executable*|*ELF*pie*|*ELF*shared*) ok "$(basename "$b"): ${t%%,*}";; *) bad "$(basename "$b") 不是 ELF: $t";; esac
done

echo "== 官方定制 Electron（workbuddyStorage 凭据绑定）=="
if grep -aq "electron_browser_workbuddy_storage" "$APP/workbuddy"; then
  ok "主程序含 electron_browser_workbuddy_storage（凭据 bootstrap 可用）"
else
  bad "主程序缺 electron_browser_workbuddy_storage（原版 Electron → 弹窗+401 回归）"
fi
for p in resources.pak libGLESv2.so; do
  [ -f "$APP/$p" ] || { bad "缺失 $p"; continue; }
done
OFF="$(dirname "$0")/../.migrate/official/opt/WorkBuddy"
if [ -d "$OFF" ]; then
  for p in resources.pak libGLESv2.so; do
    a="$(md5sum "$APP/$p" 2>/dev/null | cut -d' ' -f1)"
    b="$(md5sum "$OFF/$p" 2>/dev/null | cut -d' ' -f1)"
    if [ -n "$b" ] && [ "$a" = "$b" ]; then ok "$p = 官方件 ($a)"; else bad "$p 与官方 deb 不一致 ($a vs $b)"; fi
  done
else
  echo "  - 跳过 pak/libGLESv2 官方件比对（.migrate/official 不存在）"
fi

echo "== 不应残留 win 专属顶层资源 =="
left="$(find "$APP/resources" -not -path "*app.asar*" -not -path "*resources/runtime/*" \
        \( -iname "*.exe" -o -iname "*.pyd" -o -iname "*.dll" -o -iname "*win32-x64*" \) 2>/dev/null | head -5 || true)"
if [ -z "$left" ]; then ok "resources 顶层无 .exe/.pyd/.dll/win32-x64"; else bad "残留: $left"; fi
for gone in elevate.exe qm vendor scripts workbuddy-editor-sdk-supervisor.exe; do
  if [ -e "$APP/resources/$gone" ]; then bad "应剔除仍存在: resources/$gone"; else ok "已剔除 resources/$gone"; fi
done

echo "== 更新补丁（app.asar.unpacked 内字节断言）=="
python3 - "$APP/resources/app.asar.unpacked" <<'PY' || fail=1
import sys
from pathlib import Path
u = Path(sys.argv[1])
def rd(p):
    f = u / p
    if not f.exists():
        print("  \033[31m✗\033[0m 缺文件 %s" % p); sys.exit(1)
    return f.read_bytes()
linux = rd("main/update-service.linux.js")
base = rd("main/update-service.js")
checks = [
    (linux, b'getPlatformAssetId(){return`win32-x64-user`}', 1, "A 检查走 Windows 通道 win32-x64-user"),
    (linux, b'getPlatformAssetId(){return this.target.platformAssetId}', 0, "A 旧 linux channel 已移除"),
    (linux, b'releaseNotes:l.releaseNotes,url:l.url,action:', 1, "B available 带 url"),
    (linux, b'async openUpdateDestination(){if(this.updateInfo&&this.updateInfo.url){this.externalOpener.options.officialDownloadUrl=this.updateInfo.url}', 1, "C 点击用 feed url 下载"),
    (base, b'this.version=r.app.getVersion()', 1, "诚实版本检查(app.getVersion 保留)"),
    (base, b'this.version=`5.11.2`', 0, "D 强制5.11.2已移除(不误弹更新)"),
    (base, b'/v2/update?platform=', 1, "feed URL 构造 intact"),
]
bad_n = 0
for data, pat, want, name in checks:
    n = data.count(pat)
    if n == want:
        print("  \033[32m✓\033[0m %s" % name)
    else:
        print("  \033[31m✗\033[0m %s (命中 %d，应为 %d)" % (name, n, want))
        bad_n += 1
sys.exit(1 if bad_n else 0)
PY

echo
if [ "$fail" -eq 0 ]; then
  echo "✅ 校验通过: $DEB"
else
  echo "❌ 校验有失败项" >&2
fi
exit "$fail"
