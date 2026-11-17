#!/bin/bash
# patch-tray-linux.sh — Linux 补系统托盘（关窗隐藏到托盘，托盘可显示/退出）
#
# 用法: patch-tray-linux.sh <asar解包目录>
# 目标: dist/electron/client-main.cjs，4 处定点替换，每处断言唯一出现。
#
# 为什么必须打：
#   * 原版托盘代码（setupWindowsTray / updateWindowsTrayMenu / setupMenuBarShortcut）
#     只服务 win32 / darwin，Linux 分支从不调用 → Linux 上关窗即整个退出
#     （window-all-closed 直接 app.quit()），无托盘、无后台进程，无法从托盘控制进入/退出。
#   * 托盘图标：resolveTrayIconPath 的 linux 分支已在 patch-window-linux.sh 补齐
#     （resources/assets/icon.png），且 resources/assets/icon.png 由官方 Linux deb 迁入，
#     故 Linux 上 Tray 可直接用该路径。
#   * 本补丁只放宽 platform 门控（win32 → win32|linux），让现成的
#     setupWindowsTray/updateWindowsTrayMenu 在 Linux 生效；close 事件在 Linux 上
#     也隐藏到托盘而非 app.quit()；window-all-closed 仅在无托盘时 quit（托盘创建
#     失败时兜底退出，避免无头僵尸进程）。
#
# 行为（Linux）：
#   * 点窗口 X → 窗口隐藏，应用继续后台运行，托盘图标常驻
#   * 托盘单击 → 显示主界面（restoreMainWindow）
#   * 托盘右键 → 显示主界面 / 退出
#   * 托盘创建失败 → 保持原有"关窗即退出"兜底
set -euo pipefail

TREE="${1:?用法: patch-tray-linux.sh <asar解包目录>}"
F="$TREE/dist/electron/client-main.cjs"
[ -f "$F" ] || { echo "错误: 找不到 $F" >&2; exit 1; }

python3 - "$F" <<'PY'
import io, sys

path = sys.argv[1]
src = io.open(path, encoding="utf-8").read()

REPLACEMENTS = [
    (
        # updateWindowsTrayMenu 门控：win32 → win32|linux（darwin 走 setupMenuBarShortcut 专用菜单栏）
        '  if (process.platform !== "win32" || !tray || tray.isDestroyed()) return;',
        '  if (!["win32", "linux"].includes(process.platform) || !tray || tray.isDestroyed()) return;',
    ),
    (
        # setupWindowsTray 门控：win32 → win32|linux
        '  if (process.platform !== "win32" || tray && !tray.isDestroyed()) return;',
        '  if (!["win32", "linux"].includes(process.platform) || tray && !tray.isDestroyed()) return;',
    ),
    (
        # close 事件：win32/darwin 有托盘才隐藏；linux 也有托盘 → 同样隐藏而非退出
        '    if ((process.platform === "win32" || process.platform === "darwin") && tray && !tray.isDestroyed()) {',
        '    if (["win32", "darwin", "linux"].includes(process.platform) && tray && !tray.isDestroyed()) {',
    ),
    (
        # window-all-closed：有托盘则保持后台（托盘可唤回/退出）；无托盘（创建失败）仍退出兜底
        'import_electron13.app.on("window-all-closed", () => {\n  if (!updateInstalling) import_electron13.app.quit();\n});',
        'import_electron13.app.on("window-all-closed", () => {\n  if (updateInstalling) return;\n  // 有托盘：关窗后保持后台运行，由托盘显示主界面/退出；无托盘则退出（兜底）\n  if (typeof tray !== "undefined" && tray && !tray.isDestroyed()) return;\n  import_electron13.app.quit();\n});',
    ),
]

for old, new in REPLACEMENTS:
    n = src.count(old)
    if n != 1:
        print(f"错误: 目标片段出现 {n} 次（应为 1 次），中止:\n{old[:160]!r}", file=sys.stderr)
        sys.exit(2)
    src = src.replace(old, new, 1)

io.open(path, "w", encoding="utf-8").write(src)
print(f"patch-tray-linux: 已打 {len(REPLACEMENTS)} 处补丁 -> {path}")
PY
