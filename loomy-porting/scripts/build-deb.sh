#!/bin/bash
# build-deb.sh — Loomy Windows 绿色版 → Linux deb 一键移植
#
# 用法：把新版 Loomy-*-win.zip 放入 win/，electron-v*-linux-x64.zip 放项目根，
#       然后 scripts/build-deb.sh。产物输出到 dist/loomy_<版本>_amd64.deb。
#
# 流程：解压 win/electron → 迁移相关文件 → 打包 deb → 清除中间目录
set -euo pipefail
. "$(dirname "$0")/lib.sh"

for c in unzip dpkg-deb file curl; do need "$c"; done

# 可覆盖的固定参数
NODE_VER="${NODE_VER:-26.13.0}"          # 独立 node-runtime（MCP 用）
OPENCODE_VER="${OPENCODE_VER:-1.14.22}"  # OpenCode CLI（AI 运行时，对应 @opencode-ai/sdk 1.14.x）
FFMPEG_URL="${FFMPEG_URL:-https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz}"
FFMPEG_DIRNAME="${FFMPEG_DIRNAME:-ffmpeg-7.0.2-amd64-static}"
KEYRING_PKG="@napi-rs/keyring-linux-x64-gnu"
KEYRING_VER="1.3.0"

log "1/9 准备源目录"
SRC="$(prepare_win)"
VERSION="$(win_version "$SRC")"
PKG="loomy_${VERSION}_amd64.deb"
log "   Loomy 版本: $VERSION"

ELEC_DIR="$(prepare_electron)"
log "   Electron: $(basename "$ELEC_DIR")"

log "2/9 建立中间迁移目录"
rm -rf "$MIGRATE"
APP="$MIGRATE/opt/xunfei/loomy"
RES="$APP/resources"
mkdir -p "$APP" "$RES" "$MIGRATE/usr/bin" "$MIGRATE/usr/share/applications" \
         "$MIGRATE/usr/share/icons" "$MIGRATE/usr/share/pixmaps" "$MIGRATE/DEBIAN"

log "3/9 拷贝 Linux Electron 并重命名为 loomy"
cp -a "$ELEC_DIR/." "$APP/"
mv "$APP/electron" "$APP/loomy"   # 重命名 → app.isPackaged=true

log "4/9 迁移 Windows 包业务资源（app.asar 等，跨平台）"
# asar extract 会跟随旁边的 app.asar.unpacked 读取 unpacked 文件，必须一起拷；
# repack 完成后会用 asar 生成的新 unpacked 替换它（见 repack_asar）。
for f in app.asar app.asar.unpacked app-update.yml .env.prod app.ico; do
  [ -e "$SRC/resources/$f" ] && cp -a "$SRC/resources/$f" "$RES/$f"
done

log "5/9 迁移纯 JS 运行时目录（win/darwin 专属二进制跳过，OpenCode 换 Linux 版）"
# 这些目录含 win32-x64/darwin 二进制。opencode 不能靠降级——缺了直接报
# “OpenCode 二进制文件不存在”（binary-runtime-coordinator 校验），故单独补 Linux CLI；
# 其余目录无 Linux 版，运行时自动降级，不搬。
SKIP_DIRS="node-runtime|ffmpeg-static|local-model-runtime|uv|opencode|python-archive|wecom|dingtalk-workspace-cli|lark-cli|larksuite-cli|app.asar.unpacked"
for d in "$SRC"/resources/*/; do
  name="$(basename "$d")"
  [[ "$name" =~ ^($SKIP_DIRS)$ ]] && continue
  # 只搬真正跨平台的纯 JS 目录
  cp -a "$d" "$RES/$name"
done

# OpenCode CLI（AI 运行时）：npm opencode-linux-x64（unscoped 平台包）。
# 应用按 resources/opencode/<平台>-<架构>/opencode 查找（linux → binName "opencode"）。
mkdir -p "$RES/opencode/linux-x64"
if [ ! -x "$RES/opencode/linux-x64/opencode" ]; then
  fetch "https://registry.npmjs.org/opencode-linux-x64/-/opencode-linux-x64-${OPENCODE_VER}.tgz" "$ELEC_CACHE/opencode.tgz"
  mkdir -p "$ELEC_CACHE/oc"
  run_clean tar -xzf "$ELEC_CACHE/opencode.tgz" -C "$ELEC_CACHE/oc" --strip-components=2 package/bin/opencode
  cp "$ELEC_CACHE/oc/opencode" "$RES/opencode/linux-x64/opencode"
  rm -rf "$ELEC_CACHE/oc" "$ELEC_CACHE/opencode.tgz"
fi
chmod 755 "$RES/opencode/linux-x64/opencode"
log "   opencode: $("$RES/opencode/linux-x64/opencode" --version 2>/dev/null || echo "未知（请检查二进制）")"

log "6/9 独立 node-runtime = Node v$NODE_VER linux-x64"
mkdir -p "$RES/node-runtime/bin"
"$RES/node-runtime/bin/node" --version 2>/dev/null || {
  fetch "https://nodejs.org/dist/v${NODE_VER}/node-v${NODE_VER}-linux-x64.tar.xz" "$ELEC_CACHE/node.tar.xz"
  mkdir -p "$ELEC_CACHE/nd"
  run_clean tar -xJf "$ELEC_CACHE/node.tar.xz" -C "$ELEC_CACHE/nd" --strip-components=1 node-v${NODE_VER}-linux-x64/bin/node
  cp "$ELEC_CACHE/nd/bin/node" "$RES/node-runtime/bin/node"
  rm -rf "$ELEC_CACHE/nd" "$ELEC_CACHE/node.tar.xz"
}
chmod +x "$RES/node-runtime/bin/node"
log "   node: $("$RES/node-runtime/bin/node" --version)"

log "7/9 静态 ffmpeg（linux-x64）"
mkdir -p "$RES/ffmpeg-static"
if [ ! -x "$RES/ffmpeg-static/ffmpeg" ]; then
  fetch "$FFMPEG_URL" "$ELEC_CACHE/ffmpeg.tar.xz"
  mkdir -p "$ELEC_CACHE/ff"
  run_clean tar -xJf "$ELEC_CACHE/ffmpeg.tar.xz" -C "$ELEC_CACHE/ff"
  cp "$ELEC_CACHE/ff/$FFMPEG_DIRNAME/ffmpeg" "$RES/ffmpeg-static/ffmpeg"
  rm -rf "$ELEC_CACHE/ff" "$ELEC_CACHE/ffmpeg.tar.xz"
fi
chmod +x "$RES/ffmpeg-static/ffmpeg"
log "   $(file -b "$RES/ffmpeg-static/ffmpeg" | cut -d, -f1)"

log "8/9 重打包 app.asar（注入 Linux 原生模块 keyring）"
repack_asar

log "9/9 图标 + 启动脚本 + DEBIAN + 打包"
gen_icons "$SRC"
write_launcher
write_desktop
write_debian "$VERSION"
build_deb
