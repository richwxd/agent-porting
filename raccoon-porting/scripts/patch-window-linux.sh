#!/bin/bash
# patch-window-linux.sh — 窗口/任务栏图标走 Linux 的 icon.png + 注入官方同款中文菜单（移植必打补丁）
#
# 用法: patch-window-linux.sh <asar解包目录>
# 目标: dist/electron/client-main.cjs，3 处定点替换，每处断言唯一出现。
#
# 为什么必须打：
#   * resolveTrayIconPath 原本只有 win32/darwin 分支，Linux 返回 null
#     → 主窗口没有 icon，任务栏/Alt-Tab 显示 Electron 默认图标。
#   * Windows 分支给的是 icon.ico，Wayland 下不吃 .ico，必须给 icon.png
#     （resources/assets/icon.png 由 build-deb.sh 从官方 Linux deb 迁入）。
#   * 菜单栏：本应用从不设置应用菜单，Linux 上会显示 Electron 自带的英文默认菜单
#     File/Edit/View/Window/Help（实测裸 Electron 41 即如此）；Windows 分支靠
#     setMenu(null) 隐藏。Linux 改为注入【官方同款中文菜单】（内容照抄官方 Linux 版
#     setupMenu() 模板，布局紧简化：去掉顶栏三空格边距与 (&X) 助记符，加速键由
#     role 自带）：文件(退出)/编辑/查看(全屏…)/窗口/帮助(关于)，setApplicationMenu
#     覆盖所有窗口。Xvfb 实测：先建窗、后 setApplicationMenu 对已存在窗口立即生效
#     （同一窗口 id，前=英文默认、后=中文），故无需再动 window2.setMenu。
#
# 标题栏不动：官方 Linux 构建 getWindowsTitleBarWindowOptions() 对非 win32
# 一律返回 {}，即保留系统原生标题栏（KDE 下按钮/拖动都正常）。
set -euo pipefail

TREE="${1:?用法: patch-window-linux.sh <asar解包目录>}"
F="$TREE/dist/electron/client-main.cjs"
[ -f "$F" ] || { echo "错误: 找不到 $F" >&2; exit 1; }

python3 - "$F" <<'PY'
import io, sys

path = sys.argv[1]
src = io.open(path, encoding="utf-8").read()

REPLACEMENTS = [
    (
        # resolveTrayIconPath：补 linux 分支
        '    return isPackaged ? import_node_path13.default.join(resourcesPath, "assets", "menu-bar-raccoon.png") : import_node_path13.default.join(assets, "menu-bar-raccoon.png");\n'
        '  }\n'
        '  return null;\n',
        '    return isPackaged ? import_node_path13.default.join(resourcesPath, "assets", "menu-bar-raccoon.png") : import_node_path13.default.join(assets, "menu-bar-raccoon.png");\n'
        '  }\n'
        '  if (platform === "linux") {\n'
        '    return isPackaged ? import_node_path13.default.join(resourcesPath, "assets", "icon.png") : import_node_path13.default.join(assets, "icon.png");\n'
        '  }\n'
        '  return null;\n',
    ),
    (
        # 主窗口 icon：只有 win32 才解析 → win32/linux 都解析
        'const windowsIconPath = process.platform === "win32" ? resolveTrayIconPath({',
        'const windowsIconPath = ["win32", "linux"].includes(process.platform) ? resolveTrayIconPath({',
    ),
    (
        # 菜单栏：Windows 靠 setMenu(null) 隐藏；Linux 注入官方同款中文菜单
        '  if (process.platform === "win32") window2.setMenu(null);\n',
        '  if (process.platform === "win32") window2.setMenu(null);\n'
        '''  if (process.platform === "linux") {
    // 紧凑布局：去掉官方模板的顶栏三空格边距与 (&X) 助记符；加速键仍由 role 自带
    const showAbout = () => import_electron13.dialog.showMessageBox({
      title: "关于 商汤小浣熊",
      message: `商汤小浣熊 v${import_electron13.app.getVersion()}`,
      detail: "A powerful AI-assisted editor",
      buttons: ["OK"]
    });
    import_electron13.Menu.setApplicationMenu(import_electron13.Menu.buildFromTemplate([
      { label: "文件", submenu: [
        { label: "退出", role: "quit" }
      ] },
      { label: "编辑", submenu: [
        { label: "撤销", role: "undo" },
        { label: "重做", role: "redo" },
        { type: "separator" },
        { label: "剪切", role: "cut" },
        { label: "复制", role: "copy" },
        { label: "粘贴", role: "paste" },
        { label: "删除", role: "delete" },
        { label: "全选", role: "selectAll" }
      ] },
      { label: "查看", submenu: [
        { label: "重新加载", role: "reload" },
        { label: "强制重新加载", role: "forceReload" },
        { label: "开发者工具", role: "toggleDevTools" },
        { type: "separator" },
        { label: "实际大小", role: "resetZoom" },
        { label: "放大", role: "zoomIn" },
        { label: "缩小", role: "zoomOut" },
        { type: "separator" },
        { label: "全屏", role: "togglefullscreen" }
      ] },
      { label: "窗口", submenu: [
        { label: "最小化", role: "minimize" },
        { label: "关闭", role: "close" }
      ] },
      { label: "帮助", id: "raccoon-help", submenu: [
        { label: "关于", click: showAbout }
      ] }
    ]));
  }
'''
    ),
]

for old, new in REPLACEMENTS:
    n = src.count(old)
    if n != 1:
        print(f"错误: 目标片段出现 {n} 次（应为 1 次），中止:\n{old[:160]!r}", file=sys.stderr)
        sys.exit(2)
    src = src.replace(old, new, 1)

io.open(path, "w", encoding="utf-8").write(src)
print(f"patch-window-linux: 已打 {len(REPLACEMENTS)} 处补丁 -> {path}")
PY
