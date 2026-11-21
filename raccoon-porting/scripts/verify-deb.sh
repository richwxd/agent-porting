#!/bin/bash
# verify-deb.sh — 校验构建产物：关键文件、平台专属替换、两处补丁是否真的打进 asar
# 用法: verify-deb.sh [deb路径]   （默认 dist/raccoon-ai_*_amd64.deb）
set -euo pipefail
unset LD_LIBRARY_PATH LD_PRELOAD LD_AUDIT 2>/dev/null || true
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DEB="${1:-}"
if [ -z "$DEB" ]; then
  DEB="$(ls -t "$ROOT"/dist/raccoon-ai_*_amd64.deb 2>/dev/null | head -1)"
fi
[ -n "$DEB" ] && [ -f "$DEB" ] || { echo "错误: 找不到产物 dist/*.deb（先跑 build-deb.sh）" >&2; exit 1; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=1; }

echo "校验: $DEB ($(du -h "$DEB" | cut -f1))"

echo "== control =="
env -u LD_LIBRARY_PATH -u LD_PRELOAD dpkg-deb -f "$DEB" Package Version Architecture Depends \
  | paste -sd' | ' - | sed 's/^/  /'

echo "== 关键文件 =="
env -u LD_LIBRARY_PATH -u LD_PRELOAD dpkg-deb -x "$DEB" "$T"
APP="$T/opt/office-raccoon"
for f in \
  "raccoon-ai:主程序(=electron 重命名)" \
  "resources/app.asar:业务逻辑" \
  "resources/app.asar.unpacked/node_modules/@esbuild/linux-x64/bin/esbuild:esbuild Linux 二进制" \
  "resources/app-update.yml:更新 feed" \
  "resources/box-agent-runtime/manifest.json:agent 运行时" \
  "resources/rg/rg:ripgrep" \
  "resources/pandoc/pandoc:pandoc" \
  "resources/assets/icon.png:窗口图标" \
  "resources/render-node-deps/node_modules/@napi-rs/canvas-linux-x64-gnu/skia.linux-x64-gnu.node:canvas Linux" \
  "$T/usr/bin/raccoon-ai:启动包装器" \
  "$T/usr/share/applications/raccoon-ai.desktop:.desktop" \
  "$T/usr/share/icons/hicolor/256x256/apps/raccoon-ai.png:hicolor 图标"
do
  p="${f%%:*}"; d="${f##*:}"
  case "$p" in /*) abs="$p";; *) abs="$APP/$p";; esac
  if [ -e "$abs" ]; then ok "$d ($p)"; else bad "缺失: $d ($p)"; fi
done

echo "== 主程序/工具必须是 Linux ELF =="
for b in "$APP/raccoon-ai" "$APP/resources/rg/rg" "$APP/resources/pandoc/pandoc" \
         "$APP/resources/app.asar.unpacked/node_modules/@esbuild/linux-x64/bin/esbuild"; do
  t="$(file -b "$b" 2>/dev/null || true)"
  case "$t" in *ELF*executable*|*ELF*pie*) ok "$(basename "$b"): ${t%%,*}";; *) bad "$(basename "$b") 不是 ELF: $t";; esac
done

echo "== 不应残留 Windows 专属文件 =="
left="$(find "$APP/resources" -not -path "*app.asar*" \
        \( -iname "*.exe" -o -iname "*.pyd" -o -iname "*win32-x64*" -o -iname "*.dll" \) 2>/dev/null | head -5 || true)"
if [ -z "$left" ]; then ok "resources 下无 .exe/.pyd/.dll/win32-x64"; else bad "残留: $left"; fi
if [ -f "$APP/resources/box-agent-runtime/bin/box-agent-acp.exe" ]; then bad "box-agent-runtime 仍是 Windows 版"; else ok "box-agent-runtime 已是 Linux 版"; fi

echo "== app.asar 内补丁 =="
env -u LD_LIBRARY_PATH -u LD_PRELOAD python3 - "$APP/resources/app.asar" <<'PY' || fail=1
import sys, io
data = open(sys.argv[1], "rb").read()
checks = [
    (b'platform: "win32",',                       "补丁① policy platform=win32"),
    (b'process.platform === "win32" || process.platform === "linux"', "补丁② NsisUpdater(Linux)"),
    (b'let autoDownloadEnabled = false;',         "补丁③ autoDownload 关闭"),
    (b'platform: this._testOnlyOptions == null ? "win32" : this._testOnlyOptions.platform', "补丁④ provider platform=win32(通道 latest.yml)"),
    (b'if (platform === "linux") {',              "补丁A resolveTrayIconPath linux 分支"),
    (b'["win32", "linux"].includes(process.platform) ? resolveTrayIconPath', "补丁B 主窗口 icon 解析"),
    (b'import_electron13.Menu.setApplicationMenu(import_electron13.Menu.buildFromTemplate([', "补丁C Linux 中文菜单栏"),
    ('label: "帮助", id: "raccoon-help"'.encode(), "补丁C 帮助项带 raccoon-help id(更新菜单安装器合并入口)"),
    (b'!["win32", "linux"].includes(process.platform) || !tray || tray.isDestroyed()', "补丁E updateWindowsTrayMenu 门控(win32|linux)"),
    (b'!["win32", "linux"].includes(process.platform) || tray && !tray.isDestroyed()', "补丁E setupWindowsTray 门控(win32|linux)"),
    (b'["win32", "darwin", "linux"].includes(process.platform) && tray && !tray.isDestroyed()', "补丁E close 事件隐藏到托盘(含 linux)"),
    (b'typeof tray !== "undefined" && tray && !tray.isDestroyed()', "补丁E window-all-closed 有托盘不退出"),
    (b'shell.openPath(requestedPath).catch(() => {})', "补丁F① system 分支 fire-and-forget(不 await shell.openPath)"),
    (b'electron_1.shell.openPath(directory).catch(() => {})', "补丁F② open-task-workspace fire-and-forget(不 await)"),
    (b'electron_1.shell.openPath(dir).catch(() => {})', "补丁F③ open-runtime-directory fire-and-forget(不 await)"),
    (b'electron_1.shell.openPath(entry.path).catch(() => {})', "补丁F④ 浏览器 external fire-and-forget(不 await)"),
    (b'const quitForceTimer = setTimeout(() => {', "补丁G 退出超时兜底: quitForceTimer 定义"),
    ('title: "保存更新包",'.encode(), "补丁H 更新包另存为: showSaveDialog"),
    (b'[app-update] update package saved', "补丁H 保存完成提示"),
    (b'platform === "win32" ? {',                 "原样: 标题栏仍按 win32 判定(不改)"),
]
bad_n = 0
# 补丁D 关键否定断言：不能再有带 parent 的对话框调用
if data.count(b'showOpenDialog(window2,') != 0 or data.count(b'showSaveDialog(window2,') != 0:
    print("  \033[31m✗\033[0m 补丁D 仍有带 parent 的对话框调用 (open=%d, save=%d)" % (
        data.count(b'showOpenDialog(window2,'), data.count(b'showSaveDialog(window2,')))
    bad_n += 1
else:
    print("  \033[32m✓\033[0m 补丁D 无带 parent 的对话框调用")
# 补丁D 精确计数断言：patch-dialog-parent.sh 恰改 5 处 open + 4 处 save（带空格形式）
if data.count(b'showOpenDialog( {') == 5 and data.count(b'showSaveDialog( {') == 4:
    print("  \033[32m✓\033[0m 补丁D 去 parent 计数 (open=5, save=4)")
else:
    print("  \033[31m✗\033[0m 补丁D 去 parent 计数异常 (open=%d, save=%d)" % (
        data.count(b'showOpenDialog( {'), data.count(b'showSaveDialog( {')))
    bad_n += 1
# 补丁F 否定断言：4 个 IPC handler 内不得再残留 await shell.openPath（会锁前端）
for pat, name in [
    (b'const error = await electron_1.shell.openPath(directory);', "补丁F② 无残留 await openPath(open-task-workspace)"),
    (b'const error = await electron_1.shell.openPath(dir);', "补丁F③ 无残留 await openPath(open-runtime-directory)"),
    (b'const error = await electron_1.shell.openPath(entry.path);', "补丁F④ 无残留 await openPath(浏览器 external)"),
]:
    if data.count(pat) == 0:
        print(f"  \033[32m✓\033[0m {name}")
    else:
        print(f"  \033[31m✗\033[0m {name} (命中 {data.count(pat)} 次，应为 0)")
        bad_n += 1
# 补丁G 精确计数：quitForceTimer 的 clearTimeout 恰 2 处（then + catch）
if data.count(b'clearTimeout(quitForceTimer)') == 2:
    print("  \033[32m✓\033[0m 补丁G clearTimeout 计数 (2 处: then+catch)")
else:
    print("  \033[31m✗\033[0m 补丁G clearTimeout 计数异常 (命中 %d，应为 2)" % data.count(b'clearTimeout(quitForceTimer)'))
    bad_n += 1
for pat, name in checks:
    n = data.count(pat)
    if n == 1:
        print(f"  \033[32m✓\033[0m {name}")
    else:
        print(f"  \033[31m✗\033[0m {name} (命中 {n} 次，应为 1)")
        bad_n += 1
# 必须仍能解析为 JS（补丁不能改坏语法）
if b'function doLoadAutoUpdater()' in data and b'const policyClient = createVersionPolicyClient({' in data:
    print("  \033[32m✓\033[0m 关键函数结构完整")
else:
    print("  \033[31m✗\033[0m 关键函数结构异常")
    bad_n += 1
sys.exit(1 if bad_n else 0)
PY

echo "== 更新 feed 必须是 Windows =="
feed="$(grep -E "^url:" "$APP/resources/app-update.yml" | head -1 || true)"
case "$feed" in
  *"/office-agent/win"*) ok "$feed";;
  *) bad "feed 不是 Windows: $feed";;
esac

echo
if [ "$fail" -eq 0 ]; then
  echo "✅ 校验通过: $DEB"
else
  echo "❌ 校验有失败项" >&2
fi
exit "$fail"
