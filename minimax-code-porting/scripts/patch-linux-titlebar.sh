#!/bin/bash
# patch-linux-titlebar.sh — Linux 自绘 titlebar（Loomy 移植）
#
# 背景：Windows 版主窗口 frame:false + titleBarOverlay（原生三按钮浮在右上角），
#   渲染层另有 46px 自绘 drag 条 #loomy-titlebar-system-strip（win32 专属
#   --titlebar-overlay-height:32px 决定其高度）。Linux 走 Wayland ozone 且未开
#   WaylandWindowDecorations → Chromium 不画任何窗口装饰，overlay 高度又是 0px
#   → 既没有标题栏也没有窗口按钮。
#
# 改法（三处，均幂等）：
#   1. main-window-controller.js：Linux 也 frame:false（防 X11 双标题栏，客户端全权）
#   2. main.js：注册 ipcMain 通道 loomy:window-control（minimize/maximize/close）
#   3. preload.js 末尾：注入 CSS 打开 --titlebar-overlay-height:36px（复用 app 自绘
#      strip 作为自绘 titlebar）+ 右上角三个窗口按钮，点击走上面的 IPC
#
# 用法：patch-linux-titlebar.sh <asar解包根目录>
set -euo pipefail

ROOT="${1:?用法：patch-linux-titlebar.sh <asar解包根目录>}"

WCTRL="$ROOT/electron/windows/main-window-controller.js"
MAIN="$ROOT/electron/main.js"
PRELOAD="$ROOT/electron/preload.js"

for f in "$WCTRL" "$MAIN" "$PRELOAD"; do
  [ -f "$f" ] || { echo "未找到 $f（先 asar extract）" >&2; exit 1; }
done

python3 - "$WCTRL" "$MAIN" "$PRELOAD" <<'PY'
import sys, io

MARK = "LOOMY_LINUX_TITLEBAR_PATCH"
wctrl, main, preload = sys.argv[1], sys.argv[2], sys.argv[3]

def load(p):
    return io.open(p, encoding="utf-8").read()

def save(p, s):
    io.open(p, "w", encoding="utf-8").write(s)

# ---- 1) 主窗口：Linux 也无边框 ----
src = load(wctrl)
if MARK in src:
    print("已补丁(跳过)：", wctrl)
else:
    old = "      frame: isWindows ? false : undefined,"
    new = (
        "      // " + MARK + ": Linux 也无边框，由渲染层自绘 titlebar 并注入窗口按钮\n"
        "      frame: isWindows || platform === 'linux' ? false : undefined,"
    )
    assert old in src, "frame 行与预期不符"
    save(wctrl, src.replace(old, new, 1))
    print("已补丁：", wctrl)

# ---- 2) main.js：窗口控制 IPC（仅 Linux 注册）----
src = load(main)
if MARK in src:
    print("已补丁(跳过)：", main)
else:
    old = """function requestMainWindowFocus() {
  mainWindowController?.requestFocusWhenReady?.()
}"""
    new = old + """

// LOOMY_LINUX_TITLEBAR_PATCH: Linux 自绘 titlebar 的窗口控制通道（渲染层注入按钮调用）
if (process.platform === "linux") {
  ipcMain.handle("loomy:window-control", (_event, action) => {
    const win = getMainWindow()
    if (!win || win.isDestroyed()) return false
    try {
      if (action === "minimize") {
        win.minimize()
      } else if (action === "maximize") {
        win.isMaximized() ? win.unmaximize() : win.maximize()
      } else if (action === "close") {
        win.close()
      } else {
        return false
      }
      return true
    } catch {
      return false
    }
  })
}"""
    assert old in src, "requestMainWindowFocus 锚点与预期不符"
    save(main, src.replace(old, new, 1))
    print("已补丁：", main)

# ---- 3) preload.js：注入 CSS + 三按钮 ----
src = load(preload)
if MARK in src:
    print("已补丁(跳过)：", preload)
else:
    injection = '''
// LOOMY_LINUX_TITLEBAR_PATCH: Linux 自绘 titlebar —— 打开 win32 专属的 overlay 布局并注入窗口控制按钮
;(function () {
  try {
    if (typeof process === "undefined" || process.platform !== "linux") return
    var loc = typeof location !== "undefined" ? location : null
    var path = (loc && loc.pathname) || ""
    var hash = (loc && loc.hash) || ""
    if (!/index\\.html?$/i.test(path)) return // 仅主窗口（跳过 markdown viewer 等独立窗）
    if (hash.indexOf("#/global-search") === 0) return // 全局搜索窗有自己的窗口形态
    var STYLE = [
      // 打开 app 自绘 strip（#loomy-titlebar-system-strip）的 win32 同款高度与分隔线
      "html.loomy-linux-wc-on{--titlebar-overlay-height:36px}",
      "html.loomy-linux-wc-on[data-fullscreen=true]{--titlebar-overlay-height:0px}",
      "html.loomy-linux-wc-on[data-fullscreen=true] #loomy-linux-wc{display:none}",
      "html.loomy-linux-wc-on #loomy-titlebar-system-strip{border-bottom:.5px solid var(--border, rgba(0,0,0,.08))}",
      // 窗口三按钮：fixed 贴右上，登录页（strip 未渲染）也像 Windows overlay 一样悬浮
      "#loomy-linux-wc{position:fixed;top:0;right:0;height:36px;display:flex;align-items:stretch;z-index:101;-webkit-app-region:no-drag}",
      "#loomy-linux-wc button{width:46px;height:100%;display:flex;align-items:center;justify-content:center;padding:0;background:transparent;border:0;color:var(--foreground,#5f6368);cursor:pointer}",
      "#loomy-linux-wc button:hover{background:var(--accent,rgba(127,127,127,.18))}",
      "#loomy-linux-wc button.loomy-wc-close:hover{background:var(--destructive,#e81123);color:#fff}",
      "#loomy-linux-wc svg{width:16px;height:16px;display:block}"
    ].join("\\n")
    var ICONS = {
      minimize: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"><path d="M3.5 8h9"/></svg>',
      maximize: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4"><rect x="3.6" y="3.6" width="8.8" height="8.8" rx="1.2"/></svg>',
      close: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"><path d="M4.2 4.2l7.6 7.6M11.8 4.2l-7.6 7.6"/></svg>'
    }
    var mounted = false
    function mount() {
      if (mounted) return
      var rootEl = document.documentElement
      if (!rootEl) return
      mounted = true
      rootEl.classList.add("loomy-linux-wc-on")
      var style = document.createElement("style")
      style.textContent = STYLE
      rootEl.appendChild(style)
      var box = document.createElement("div")
      box.id = "loomy-linux-wc"
      ;["minimize", "maximize", "close"].forEach(function (act) {
        var btn = document.createElement("button")
        btn.type = "button"
        btn.setAttribute("aria-label", act)
        if (act === "close") btn.className = "loomy-wc-close"
        btn.innerHTML = ICONS[act]
        btn.addEventListener("click", function (ev) {
          ev.preventDefault()
          ev.stopPropagation()
          ipcRenderer.invoke("loomy:window-control", act).catch(function () {})
        })
        box.appendChild(btn)
      })
      rootEl.appendChild(box)
    }
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", mount)
    }
    mount()
  } catch (err) {
    console.warn("[loomy-linux-titlebar]", err)
  }
})()
'''
    save(preload, src.rstrip("\n") + "\n" + injection)
    print("已补丁：", preload)
PY

echo "--- 关键改动预览 ---"
grep -nE "LOOMY_LINUX_TITLEBAR_PATCH|loomy:window-control" \
  "$WCTRL" "$MAIN" "$PRELOAD" | head -20 || true
node --check "$WCTRL" && echo "语法 OK: $WCTRL"
node --check "$MAIN" && echo "语法 OK: $MAIN"
node --check "$PRELOAD" && echo "语法 OK: $PRELOAD"
