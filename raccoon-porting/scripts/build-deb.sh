#!/bin/bash
# build-deb.sh — 商汤小浣熊 Windows 安装包 → Linux deb 一键移植
#
# 用法：把 商汤小浣熊-<版本>-x64.exe 放进 win/，执行 scripts/build-deb.sh
#       产物输出到 dist/raccoon-ai_<版本>_amd64.deb（覆盖安装到 /opt/office-raccoon）
#
# 版本升级：直接换 win/ 里的 exe 重跑即可；升级检测始终按 Windows 版本
# （scripts/patch-update-check.sh），Linux 侧永远走 Windows 的 win32 版本流。
# 版本号（应用/Electron/官方 deb）默认全部按 Windows 包动态匹配，见 lib.sh: resolve_versions。
set -euo pipefail
. "$(dirname "$0")/lib.sh"

for c in 7z unzip dpkg-deb file curl asar python3 tar sha256sum; do need "$c"; done

log "1/8 准备 Windows 源 + 动态匹配版本号"
SRC="$(prepare_win)"
VERSION="$(win_version "$SRC")"
resolve_versions "$VERSION"
PKG="${PKG_NAME}_${VERSION}_amd64.deb"
log "   商汤小浣熊 版本: $VERSION / Electron v$ELECTRON_VERSION / 官方 deb v$OFFICIAL_DEB_VERSION"

log "2/8 准备 Linux Electron v$ELECTRON_VERSION（与 Windows 包内置一致）"
ELEC_DIR="$(prepare_electron)"
log "   Electron: $(basename "$ELEC_DIR")"

log "3/8 准备官方 Linux deb v$OFFICIAL_DEB_VERSION（Linux 原生依赖来源）"
prepare_official_deb
extract_official
log "   $(basename "$OFFICIAL_DEB")"

log "4/8 建立 deb 中间目录"
rm -rf "$STAGE"
APP="$STAGE$INSTALL_DIR"
RES="$APP/resources"
mkdir -p "$APP" "$STAGE/usr/bin" "$STAGE/usr/share/applications" \
         "$STAGE/usr/share/icons" "$STAGE/DEBIAN"

log "5/8 拷贝 Linux Electron 并重命名 → $BIN_NAME"
cp -a "$ELEC_DIR"/. "$APP/"
mv "$APP/electron" "$APP/$BIN_NAME"

log "6/8 迁移资源 + app.asar 打补丁 + 注入 Linux 原生依赖"
migrate_resources
repack_asar

log "7/8 图标 + 启动包装器 + .desktop + DEBIAN"
gen_icons
write_launcher
write_desktop
write_debian "$VERSION"

log "8/8 打包 deb"
build_deb

log "安装：sudo dpkg -i dist/$PKG"
