#!/bin/bash
# patch-dialog-parent.sh — Linux/Wayland: 去掉原生对话框的 parent window
#
# 用法: patch-dialog-parent.sh <asar解包目录>
# 目标: dist/electron/client-main.cjs，把所有 dialog.showOpenDialog(window2, ...) /
#       dialog.showSaveDialog(window2, ...) 改为不带 parent window。
#
# 为什么必须打（实测 Electron 41.0.1，KDE Wayland + Xvfb X11 都复现）：
#   * Electron 在 Linux 走 XDG portal FileChooser（file_dialog_linux_portal.cc）。
#   * 传 parent window 时，Electron 把窗口的 Wayland surface 句柄传给 portal 作为
#     parent_window；在 Wayland 下该句柄解析失败/为空（known issue），portal 后端
#     报 "Unhandled parent window type" / "Failed to associate portal window with
#     parent window"，对话框不显示，Promise 永不 resolve → 主界面被模态禁用，
#     表现为"打开目录选择后无法关闭/返回主界面"。
#   * 不传 parent window 时，portal 对话框正常走完整生命周期（实测锁屏下
#     "Request cancelled by user" → resolve {canceled:true}；未锁屏时用户可正常
#     点选返回路径）。
#   * A/B 对照（同一 Electron 41.0.1，真实 KDE Wayland）：
#       带 parent: OPENING_DIALOG... → 45s 超时，never resolved（挂死）
#       不带 parent: OPENING_DIALOG_NO_PARENT... → 4.8s 后 DIALOG_RESOLVED {canceled:true}
#   * showMessageBox（消息框）带不带 parent 都正常（~1s resolve），不改。
#   * 代价：对话框不再挂在主窗口上（非严格模态），但 KDE portal 对话框默认浮层置顶，
#     可见性不受影响；挂死比非模态严重得多。
#
# 只改 9 处（8 处 import_electron13 + 1 处 import_electron5 的 export-logs），
# 全部是文件选择/保存对话框。
set -euo pipefail

TREE="${1:?用法: patch-dialog-parent.sh <asar解包目录>}"
F="$TREE/dist/electron/client-main.cjs"
[ -f "$F" ] || { echo "错误: 找不到 $F" >&2; exit 1; }

python3 - "$F" <<'PY'
import io, sys

path = sys.argv[1]
src = io.open(path, encoding="utf-8").read()

before = src
# 去掉 dialog.showOpenDialog / showSaveDialog 的 parent window 参数（第一参数 window2）
src = src.replace(".showOpenDialog(window2,", ".showOpenDialog(")
src = src.replace(".showSaveDialog(window2,", ".showSaveDialog(")

# 断言：改动了正好 5 处 open + 4 处 save（含 import_electron5 的 export-logs）
n_open = before.count(".showOpenDialog(window2,")
n_save = before.count(".showSaveDialog(window2,")
if n_open != 5:
    print(f"错误: showOpenDialog(window2, 出现 {n_open} 次（应为 5），中止", file=sys.stderr)
    sys.exit(2)
if n_save != 4:
    print(f"错误: showSaveDialog(window2, 出现 {n_save} 次（应为 4），中止", file=sys.stderr)
    sys.exit(2)

if src == before:
    print("警告: 没有可替换的目标（可能已打过补丁）", file=sys.stderr)
    sys.exit(0)

io.open(path, "w", encoding="utf-8").write(src)
print(f"patch-dialog-parent: 已去掉 {n_open} 处 showOpenDialog + {n_save} 处 showSaveDialog 的 parent window -> {path}")
PY
