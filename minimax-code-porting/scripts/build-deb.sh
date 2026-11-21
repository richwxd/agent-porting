#!/usr/bin/env bash
# build-deb.sh — MiniMax Code Windows 安装包 → Linux deb 一键移植
#
# 用法：把 MiniMax Code Setup <版本>-x64.exe 放进 win/，执行 scripts/build-deb.sh
#       产物：dist/minimax-code_<版本>_amd64.deb，安装到 /opt/minimax-code
#
# 版本号从 app.asar/package.json 读取；Electron 版本从 exe 内嵌字符串读取
# （都可用环境变量覆盖：APP_VER=... ELECTRON_VERSION=...）。
set -euo pipefail
cd "$(dirname "$0")/.." && ROOT="$PWD"
. "$ROOT/scripts/lib.sh"

APP_NAME=minimax-code
APP_DISPLAY="MiniMax Code"
INSTALL_DIR="/opt/$APP_NAME"

WIN=""
VER=""
ELECTRON_VERSION="${ELECTRON_VERSION:-}"
STAGE="$ROOT/.migrate/stage"
APP_DIR="$STAGE/opt/$APP_NAME"
OUT_DIR="$ROOT/dist"

need 7z unzip dpkg-deb file curl python3 rsync strings tar sha256sum convert node npm

# --- 1) 解包 Windows 安装包 + 版本号 ---
log "1/9 解包 Windows 安装包"
ASAR_BIN="$(prepare_asar)"
log "   asar: $ASAR_BIN"
WIN="$(prepare_win)"
VER="${APP_VER:-$(win_version "$WIN")}"
[[ "$VER" =~ ^[0-9A-Za-z.+:~_-]+$ ]] || die "版本号异常：$VER"
[ -n "$ELECTRON_VERSION" ] || ELECTRON_VERSION="$(win_electron_version "$WIN")"
log "   $APP_DISPLAY $VER / Electron $ELECTRON_VERSION"

# --- 2) Linux Electron 运行时 ---
log "2/9 准备 Electron $ELECTRON_VERSION (linux-x64)"
rm -rf "$STAGE"
mkdir -p "$APP_DIR/bin" "$STAGE/usr/share/applications" "$OUT_DIR"
prepare_electron "$ELECTRON_VERSION" "$APP_DIR"
mv "$APP_DIR/electron" "$APP_DIR/$APP_NAME"   # 必须改名：app.isPackaged 按 execPath 文件名判定
chmod +x "$APP_DIR/$APP_NAME"

# --- 3) resources：跨平台资源迁移，剔除 Windows 专属件 ---
log "3/9 迁移 resources"
RES="$APP_DIR/resources"
mkdir -p "$RES"
rsync -a \
  --exclude 'app.asar' --exclude 'app.asar.unpacked' \
  --exclude 'elevate.exe' \
  --exclude 'computer-use/' \
  --exclude 'abe-broker/' \
  --exclude 'session-transfer/' \
  --exclude 'installer-*.nsh' \
  --exclude 'file-associations.generated.nsh' \
  --exclude 'dmg-background-*' \
  --exclude 'entitlements.mac.plist' \
  --exclude 'icon.icns' \
  "$WIN/resources/" "$RES/"

# --- 4) 解 app.asar（合并 unpacked）+ Linux 原生依赖 ---
log "4/9 解包 app.asar 并注入 Linux 原生模块"
WORK="$ROOT/.migrate/app-tree"
rm -rf "$WORK"
stub_missing_unpacked "$WIN/resources/app.asar" "$WIN/resources/app.asar.unpacked"
run_clean "$ASAR_BIN" extract "$WIN/resources/app.asar" "$WORK"
rsync -a "$WIN/resources/app.asar.unpacked/" "$WORK/"

prepare_node_pty
prepare_better_sqlite3

NM="$WORK/node_modules"
# 平台包：Electron 主进程/运行时按 process.platform-arch 解析 optionalDependencies
install_npm_pkg "@napi-rs/keyring-linux-x64-gnu@2.1.1"          keyring-linux-x64-gnu   "$NM"
install_npm_pkg "@mariozechner/clipboard-linux-x64-gnu@0.3.9"   clipboard-linux-x64-gnu "$NM"
install_npm_pkg "node-screenshots-linux-x64-gnu@0.2.8"          screenshots-linux-x64-gnu "$NM"
install_npm_pkg "@ubjs/node-linux-x64-gnu@0.31.0-3"             ubjs-linux-x64-gnu      "$NM"
install_npm_pkg "@trycua/cua-driver-linux-x64-gnu@0.34.1"        cua-linux-x64-gnu       "$NM"
install_npm_pkg "@vscode/ripgrep-linux-x64@1.18.0"              ripgrep-linux-x64       "$NM"

# node-pty：Linux 版 pty.node（N-API，与 Electron ABI 无关）
PTY="$NM/node-pty/prebuilds/linux-x64"
mkdir -p "$PTY"
cp "$ROOT/.cache/native/node-pty/pty.node" "$PTY/pty.node"
chmod 644 "$PTY/pty.node"

# better-sqlite3：Electron ABI 版 .node
BS3="$NM/better-sqlite3/build/Release"
mkdir -p "$BS3"
cp "$ROOT/.cache/native/better-sqlite3/better_sqlite3.node" "$BS3/better_sqlite3.node"
chmod 644 "$BS3/better_sqlite3.node"

# 剔除 Windows/macOS 平台件与 Windows 专属可执行体，控制体积
prune_platform() {
  local p
  for p in \
    "$NM/node-pty/prebuilds/win32-arm64" "$NM/node-pty/prebuilds/win32-x64" \
    "$NM/node-pty/prebuilds/darwin-arm64" "$NM/node-pty/prebuilds/darwin-x64" \
    "$NM/@trycua/cua-driver-win32-x64-msvc" "$NM/@trycua/cua-driver-darwin-arm64" "$NM/@trycua/cua-driver-darwin-x64" \
    "$NM/node-screenshots-win32-x64-msvc" "$NM/node-screenshots-win32-arm64-msvc" \
    "$NM/node-screenshots-darwin-arm64" "$NM/node-screenshots-darwin-x64" \
    "$NM/@mariozechner/clipboard-darwin-arm64" "$NM/@mariozechner/clipboard-darwin-universal" "$NM/@mariozechner/clipboard-darwin-x64" \
    "$NM/@napi-rs/keyring-darwin-arm64" "$NM/@napi-rs/keyring-darwin-x64" \
    "$NM/@ubjs/node-darwin-arm64" "$NM/@ubjs/node-darwin-x64" "$NM/@ubjs/node-win32-x64-msvc" \
    "$NM/@vscode/ripgrep-win32-x64" "$NM/@vscode/ripgrep-win32-arm64" "$NM/@vscode/ripgrep-win32-ia32" \
    "$NM/@vscode/ripgrep-darwin-x64" "$NM/@vscode/ripgrep-darwin-arm64" \
    "$NM/@earendil-works/pi-tui/native/win32" "$NM/@earendil-works/pi-tui/native/darwin" \
    "$NM/@minimax/mcode-sandbox-runtime/vendor/srt-win" \
    "$NM/@minimax/mcode-sandbox-runtime/vendor/java-proxy-agent" ; do
    [ -e "$p" ] && rm -rf "$p"
  done
  return 0
}
prune_platform

# 更新检测：Linux 走 Windows 版本流（检查 latest.yml、下载 Windows NSIS 安装包）
node "$ROOT/scripts/patch-update-check.cjs" "$WORK"

# 托盘：Linux 的 StatusNotifier/AppIndicator 只能通过 setContextMenu 弹菜单
node "$ROOT/scripts/patch-linux-tray.cjs" "$WORK"
node "$ROOT/scripts/patch-linux-window-icon.cjs" "$WORK"

# Computer Use：Linux 版 cua-driver（与 Windows 组件同协议）
CUA_DIR="$RES/resources/computer-use/0.34.1/linux-x64"
build_cua_component "$CUA_DIR"
CUA_MANIFEST_SHA="$(sha256sum "$CUA_DIR/component.json" | cut -d' ' -f1)"
node "$ROOT/scripts/patch-computer-use-linux.cjs" "$WORK" "$CUA_MANIFEST_SHA"

# Computer Use SDK：放到 asar 外，保证 Electron 能从真实路径加载 .node/.so
CUA_SDK="$RES/computer-use-sdk"
mkdir -p "$CUA_SDK/node_modules/@trycua" "$CUA_SDK/node_modules/@ubjs"
for pkg in "@trycua/cua-driver" "@trycua/cua-driver-linux-x64-gnu" \
           "@ubjs/core" "@ubjs/node" "@ubjs/node-linux-x64-gnu"; do
  cp -a "$NM/$pkg" "$CUA_SDK/node_modules/$pkg"
done

# 打包前用 Electron 的 Node 运行时验证 ABI（失败立刻停，避免产出“装得上但起不来”的 deb）
verify_native_with_electron "$ROOT/.cache/electron-v${ELECTRON_VERSION}-linux-x64/electron" "$WORK"

# --- 5) 重打包 app.asar ---
log "5/9 重打包 app.asar"
run_clean "$ASAR_BIN" pack "$WORK" "$RES/app.asar" --unpack '{rg,*.node,*.so,*.dll,*.exe}' >/dev/null
[ -d "$RES/app.asar.unpacked" ] || die "重打包后缺少 app.asar.unpacked"
for f in node-pty/prebuilds/linux-x64/pty.node better-sqlite3/build/Release/better_sqlite3.node @vscode/ripgrep-linux-x64/bin/rg; do
  [ -f "$RES/app.asar.unpacked/node_modules/$f" ] || die "原生模块未进入 app.asar.unpacked：$f"
done
file "$RES/app.asar.unpacked/node_modules/@vscode/ripgrep-linux-x64/bin/rg" | grep -q ELF \
  || die "ripgrep Linux 二进制未进入 unpacked（asar 内无法执行）"
log "   app.asar.unpacked: $(du -sh "$RES/app.asar.unpacked" | cut -f1)"

# --- 6) 启动包装器 / 图标 / desktop ---
log "6/9 启动包装器 + 图标 + desktop"
install -m755 "$ROOT/scripts/minimax-code-launcher" "$APP_DIR/bin/$APP_NAME"
convert "$RES/resources/icon.ico"[0] -resize 512x512 "$APP_DIR/$APP_NAME.png" 2>/dev/null \
  || convert "$RES/resources/icon.ico" -resize 512x512 "$APP_DIR/$APP_NAME.png"
# 除 desktop entry 外，所有文件都留在 /opt/minimax-code，便于整体备份/替换。
# 不再写 /usr/bin/* 与 /usr/share/icons/*；desktop 用绝对路径引用图标。
install -m644 "$ROOT/scripts/minimax-code.desktop" "$STAGE/usr/share/applications/$APP_NAME.desktop"

# --- 7) DEBIAN/ ---
log "7/9 生成 DEBIAN"
DEB="$STAGE/DEBIAN"
mkdir -p "$DEB"
install -m755 "$ROOT/scripts/minimax-code-postinst" "$DEB/postinst"
install -m755 "$ROOT/scripts/minimax-code-postrm" "$DEB/postrm"
INSTALLED_SIZE="$(du -sk "$APP_DIR" "$STAGE/usr" | awk '{s+=$1} END {print s}')"
cat > "$DEB/control" <<EOF
Package: $APP_NAME
Version: $VER
Section: utils
Priority: optional
Architecture: amd64
Installed-Size: $INSTALLED_SIZE
Depends: libc6 (>= 2.34), libstdc++6, libgcc-s1, libgtk-3-0, libnss3, libasound2, libx11-6, libxcomposite1, libxdamage1, libxfixes3, libxrandr2, libgbm1, libpango-1.0-0, libcairo2, libatk1.0-0, libatk-bridge2.0-0, libcups2, libdrm2, libxkbcommon0, libxshmfence1, libglib2.0-0, libdbus-1-3, libatspi2.0-0, libsecret-1-0
Maintainer: MiniMax (Linux port) <noreply@minimax.io>
Homepage: https://www.minimax.io
Description: MiniMax Code 桌面客户端（Linux x64）
 MiniMax Code 桌面应用（Windows 版移植），基于 Electron $ELECTRON_VERSION 构建。
 包含本地 Agent 运行时、内置 mcode-tools 与 Office 文档能力。
EOF

# --- 8) 打包 ---
log "8/9 打包 deb"
OUT="$OUT_DIR/${APP_NAME}_${VER}_amd64.deb"
run_clean dpkg-deb --root-owner-group -b "$STAGE" "$OUT"

log "9/9 校验产物"
run_clean dpkg-deb -I "$OUT" >/dev/null || die "deb 元数据校验失败"
[ "$(stat -c %s "$OUT")" -gt 100000000 ] || warn "deb 体积异常偏小：$(du -h "$OUT" | cut -f1)"
log "完成：$OUT（$(du -h "$OUT" | cut -f1)）"
log "安装：sudo apt install $OUT"
