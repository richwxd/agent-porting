#!/bin/bash
# build-deb.sh — WorkBuddy Windows 安装包 → Linux deb 一键移植
#
# 用法：把 WorkBuddy-win32-x64-user-<版本>-*.exe 放进 win/，执行 scripts/build-deb.sh
#       产物输出到 dist/workbuddy_<版本>_amd64.deb（覆盖安装到 /opt/WorkBuddy）
#
# 版本升级：直接换 win/ 里的 exe 重跑即可；升级检测始终按 Windows 版本通道
# （scripts/patch-update-check.sh 3 处补丁：检查 win32-x64-user + 点击触发下载）。
# Electron 版本读 winapp/version；官方 deb 版本/地址/sha 由 linux feed 动态解析。
set -euo pipefail
. "$(dirname "$0")/lib.sh"

for c in 7z unzip dpkg-deb file curl asar python3 tar sha256sum; do need "$c"; done

log "1/8 准备 Windows 源 + 动态匹配版本号"
SRC="$(prepare_win)"
VERSION="$(win_version "$SRC")"
resolve_versions
PKG="${PKG_NAME}_${VERSION}_amd64.deb"
log "   WorkBuddy 版本: $VERSION / Electron v$ELECTRON_VERSION / 官方 deb v$OFFICIAL_DEB_VERSION"

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

log "5/8 拷贝 Linux Electron → $BIN_NAME + 官方定制主程序"
cp -a "$ELEC_DIR"/. "$APP/"
mv "$APP/electron" "$APP/$BIN_NAME"
# 官方定制 Electron 才注入 electron.workbuddyStorage（凭据 bootstrap 依赖的
# native binding），原版 Electron 缺失 → 弹窗「关键组件加载失败」+ 全站 401。
# 主程序 + 同源的 resources.pak/libGLESv2 用官方 deb 件（与原版仅此 3 个公共文件不同）。
for f in "$BIN_NAME" resources.pak libGLESv2.so; do
  [ -f "$OFFICIAL_APP/$f" ] || die "官方 deb 缺 $f"
  cp -a "$OFFICIAL_APP/$f" "$APP/$f"
done

log "6/8 迁移资源 + app.asar 补丁（更新检查 3 处）+ Linux 原生件"
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
