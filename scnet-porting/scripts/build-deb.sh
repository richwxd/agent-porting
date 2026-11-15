#!/usr/bin/env bash
# scnet-porting 一键构建：win/（Windows 绿色版）→ dist/scnet-client_<ver>_amd64.deb
# 用法：用新版 Windows 绿色版整体替换 win/，然后 ./scripts/build-deb.sh
set -euo pipefail
cd "$(dirname "$0")/.." && ROOT="$PWD"
. "$ROOT/scripts/lib.sh"

ELECTRON_VERSION=45.2.3   # win 包内置的 Electron 版本；升级客户端后在此对齐（PORTING.md「调整 Electron 版本」）
APP_NAME=scnet-client
WIN="$ROOT/win"
STAGE="$ROOT/.migrate/stage"
INJECT="$ROOT/.cache/inject"
LINUX_BIN="$ROOT/.cache/linux-bin"
OUT_DIR="$ROOT/dist"

need python3 asar dpkg-deb curl unzip rsync

# --- 0) 输入 / 注入集校验 ---
[ -f "$WIN/resources/app.asar" ] || die "未找到 win/resources/app.asar：把 Windows 绿色版整体放进 win/"
[ -d "$INJECT/node_modules" ] || die "缺少 .cache/inject（app.asar 注入集，见 PORTING.md「app.asar 注入集」）"
[ -x "$LINUX_BIN/bin/uv" ] || die "缺少 .cache/linux-bin/bin/uv（linux 版 uv）"
[ -x "$LINUX_BIN/agent-browser/agent-browser" ] || die "缺少 .cache/linux-bin/agent-browser/agent-browser（linux 版 agent-browser）"

# --- 1) 版本号：从 win/resources/app.asar 的 package.json 自动读取 ---
VER_DIR="$ROOT/.migrate/ver"
rm -rf "$VER_DIR" && mkdir -p "$VER_DIR"
VER="$(
  cd "$VER_DIR"
  run_clean asar extract-file "$WIN/resources/app.asar" package.json >/dev/null
  python3 -c 'import json; print(json.load(open("package.json"))["version"])'
)" || die "无法从 app.asar/package.json 读取版本"
[[ "$VER" =~ ^[0-9A-Za-z.+:~_-]+$ ]] || die "版本号异常：$VER"
log "构建 $APP_NAME $VER（Electron $ELECTRON_VERSION）"

# --- 2) Electron Linux 运行时 → .migrate/stage/opt/scnet-client/ ---
# 二进制改名 electron → scnet-client：app.isPackaged 按 execPath 文件名判定，勿改回 electron
rm -rf "$STAGE"
APP_DIR="$STAGE/opt/$APP_NAME"
mkdir -p "$APP_DIR/bin" "$STAGE/usr/share/applications" "$OUT_DIR"
prepare_electron "$ELECTRON_VERSION" "$APP_DIR"
mv "$APP_DIR/electron" "$APP_DIR/$APP_NAME"
chmod +x "$APP_DIR/$APP_NAME"

# --- 3) resources/：win 迁移，剔除 Windows 平台件，换入 linux 版 ---
RES="$APP_DIR/resources"
rsync -a \
  --exclude 'app.asar' --exclude 'app.asar.unpacked' \
  --exclude 'elevate.exe' --exclude 'bin/uv.exe' --exclude 'agent-browser/agent-browser.exe' \
  "$WIN/resources/" "$RES/"
install -m755 "$LINUX_BIN/bin/uv" "$RES/bin/uv"
install -m755 "$LINUX_BIN/agent-browser/agent-browser" "$RES/agent-browser/agent-browser"

# --- 4) app.asar 重打包：解 win 树（合并 app.asar.unpacked）+ 注入集叠加 + 打包 ---
# 原生模块必须进 app.asar.unpacked（Electron 不能从 asar 内 dlopen）
WORK="$ROOT/.migrate/app-tree"
rm -rf "$WORK" && mkdir -p "$WORK"
run_clean asar extract "$WIN/resources/app.asar" "$WORK"
cp -a "$INJECT/." "$WORK/"
run_clean asar pack "$WORK" "$RES/app.asar" \
  --unpack '*.{node,so,dll,exe}' --unpack-dir '**/node-pty/prebuilds'
log "app.asar 重打包完成（叠加注入集 $(cd "$INJECT" && find . -type f | wc -l) 个文件）"

# --- 5) 启动包装器 / desktop / 图标 ---
install -m755 "$ROOT/scripts/scnet-client-launcher" "$APP_DIR/bin/$APP_NAME"
install -m644 "$ROOT/scripts/scnet-client.desktop" "$STAGE/usr/share/applications/$APP_NAME.desktop"
install -m644 "$ROOT/scripts/icons/$APP_NAME-512.png" "$APP_DIR/$APP_NAME.png"

# --- 6) DEBIAN/ ---
DEB="$STAGE/DEBIAN"
mkdir -p "$DEB"
install -m755 "$ROOT/scripts/scnet-client-postinst" "$DEB/postinst"
install -m755 "$ROOT/scripts/scnet-client-postrm" "$DEB/postrm"
INSTALLED_SIZE="$(du -sk "$APP_DIR" "$STAGE/usr" | awk '{s+=$1} END {print s}')"
cat > "$DEB/control" <<EOF
Package: $APP_NAME
Version: $VER
Section: utils
Priority: optional
Architecture: amd64
Installed-Size: $INSTALLED_SIZE
Depends: libc6 (>= 2.34), libstdc++6, libgcc-s1, libgtk-3-0, libnss3, libasound2, libx11-6, libxcomposite1, libxdamage1, libxfixes3, libxrandr2, libgbm1, libpango-1.0-0, libcairo2, libatk1.0-0, libatk-bridge2.0-0, libcups2, libdrm2, libxkbcommon0, libxshmfence1, libglib2.0-0, libdbus-1-3, libatspi2.0-0
Maintainer: 曙光智算信息技术有限公司 <scnet-client@scnet.cn>
Homepage: https://www.scnet.cn
Description: SCNet 客户端（Linux x64）
 SCNet 计算服务桌面客户端，基于 Electron v$ELECTRON_VERSION 构建。
 提供高性能计算资源管理、agent 工作流、浏览器自动化等能力。
EOF

# --- 7) 打包 → dist/ ---
OUT="$OUT_DIR/${APP_NAME}_${VER}_amd64.deb"
run_clean dpkg-deb --root-owner-group -b "$STAGE" "$OUT"
log "完成：$OUT"
