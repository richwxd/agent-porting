#!/bin/bash
# lib.sh — Loomy 移植脚本公共函数（解压源、版本识别、环境处理）
# 被 scripts/build-deb.sh 加载，不单独执行。

# 始终在项目根目录运行
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

WIN_DIR="$ROOT/win"          # 放 Loomy-***-win.zip
ELEC_CACHE="$ROOT/.cache"    # 解压后的 Electron 缓存
MIGRATE="$ROOT/.migrate"     # 中间迁移目录（出 deb 后清除）
DIST="$ROOT/dist"            # 产物目录
SRC="$ROOT/src"              # 解压后的 Windows 绿色版目录
SCRATCH="$ELEC_CACHE/tmp"    # 解压临时目录

# Hermes/Distro 注入的库会干扰系统工具（xz/tar/dpkg-deb/curl），
# 以及干扰 Electron GPU。系统工具统一用 run_clean 包裹。
CLEAN_ENV_KEYS=(
  LD_LIBRARY_PATH LD_PRELOAD
)

# 用干净环境跑系统命令
run_clean() {
  local -a unset_args=()
  for k in "${CLEAN_ENV_KEYS[@]}"; do unset_args+=(-u "$k"); done
  env "${unset_args[@]}" "$@"
}

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m警告:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m错误:\033[0m %s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "缺少依赖: $1（请先安装）"
}

# 解压 Loomy-***-win.zip 到 win/，返回解压目录名
# 同时删除 zip
prepare_win() {
  mkdir -p "$WIN_DIR"
  local zip
  for zip in "$WIN_DIR"/Loomy-*-win.zip; do
    [ -e "$zip" ] || continue
    log "解压 Windows 绿色版: $(basename "$zip")"
    run_clean unzip -oq "$zip" -d "$WIN_DIR/" || die "解压 $zip 失败"
    rm -f "$zip"
    log "已删除 $(basename "$zip")"
  done

  # 找出解压后的目录（含 Loomy.exe 的那个）
  local d
  for d in "$WIN_DIR"/Loomy-*-win "$WIN_DIR"/*/; do
    [ -d "$d" ] || continue
    if [ -f "$d/Loomy.exe" ]; then
      echo "$(cd "$d" && pwd)"
      return 0
    fi
  done
  # 兼容已解压但平铺在 win/ 根的情况
  if [ -f "$WIN_DIR/Loomy.exe" ]; then
    echo "$(cd "$WIN_DIR" && pwd)"; return 0
  fi
  die "win/ 下未找到 Windows 绿色版（请把 Loomy-*-win.zip 放入 $WIN_DIR）"
}

# 从 win 目录读版本号（Loomy-0.9.39-win → 0.9.39）
win_version() {
  local dir="$1" base ver
  base="$(basename "$dir")"
  [[ "$base" =~ Loomy-([0-9][0-9a-zA-Z.\-]*)-win ]] && { echo "${BASH_REMATCH[1]}"; return 0; }
  # 官方 zip 可能平铺解压（无 Loomy-<版本>-win 顶层目录）→ 从应用 package.json 兜底
  if [ -f "$dir/resources/app.asar.unpacked/package.json" ]; then
    ver="$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$dir/resources/app.asar.unpacked/package.json" | head -1)"
    [[ "$ver" =~ ^[0-9] ]] && { echo "$ver"; return 0; }
  fi
  die "无法识别 Loomy 版本号（目录名 $base 不匹配 Loomy-<版本>-win，且未找到 resources/app.asar.unpacked/package.json）"
}

# 解压 electron-v***-linux-x64.zip（放项目根目录）到 .cache/，删除 zip
# 官方 zip 内部是平铺的（electron 可执行直接在根），也兼容带 electron-v*/ 子目录的情况
# 返回解压目录路径（内含可执行 electron）
prepare_electron() {
  mkdir -p "$ELEC_CACHE"
  local zip
  for zip in "$ROOT"/electron-v*-linux-x64.zip; do
    [ -e "$zip" ] || continue
    log "解压 Linux Electron: $(basename "$zip")"
    local base dest
    base="$(basename "$zip" .zip)"
    dest="$ELEC_CACHE/$base"
    rm -rf "$dest" "$SCRATCH" && mkdir -p "$dest"
    run_clean unzip -oq "$zip" -d "$dest/" || die "解压 $zip 失败"
    rm -f "$zip"
    log "已删除 $(basename "$zip")"

    # 平铺结构：electron 就在 dest 根；带子目录则下钻一层
    if [ -x "$dest/electron" ]; then
      echo "$dest"; return 0
    fi
    local d
    d="$(find "$dest" -maxdepth 2 -type f -name electron | head -1 | xargs -r dirname)"
    [ -n "$d" ] && [ -x "$d/electron" ] && { echo "$d"; return 0; }
    rm -rf "$dest"
    die "electron zip 内未找到可执行 electron"
  done

  # 无新 zip → 复用缓存里已有的
  local cached
  cached="$(find "$ELEC_CACHE" -maxdepth 1 -mindepth 1 -type d | while read -r d; do [ -x "$d/electron" ] && echo "$d"; done | sort -V | tail -1)"
  [ -n "$cached" ] && { echo "$cached"; return 0; }
  die "项目根目录未找到 electron-v*-linux-x64.zip（且 .cache 无缓存）"
}

# 下载（走干净环境，避免 Hermes 注入库干扰 curl）
fetch() {
  local url="$1" out="$2" attempt
  for attempt in 1 2 3; do
    if run_clean curl -fsSL --retry 2 --max-time 300 -o "$out" "$url" 2>/dev/null; then
      return 0
    fi
    warn "下载失败(第 $attempt 次): $url，重试..."
    rm -f "$out"
    sleep 2
  done
  die "下载失败: $url"
}

# ───────────────────────── 构建步骤函数 ─────────────────────────

# 解包官方 app.asar，注入 Linux 原生模块（keyring），重打包。
# app.asar 内 require('@napi-rs/keyring') 解析的是顶层 node_modules。
repack_asar() {
  need asar
  local tree="$MIGRATE/asar"
  rm -rf "$tree" && mkdir -p "$tree"
  asar extract "$RES/app.asar" "$tree"

  # 修正 Linux“检查更新”报“请求参数错误”：平台归一 + 绿色版下载地址
  bash "$ROOT/scripts/patch-update-check.sh" "$tree"

  # Linux 自绘 titlebar：frame:false + 窗口控制 IPC + 渲染层注入三按钮
  bash "$ROOT/scripts/patch-linux-titlebar.sh" "$tree"

  # 讯飞 spark-x2.6：历史 tool 参数双重编码/非法 JSON → 400 invalid request（发送前清洗）
  bash "$ROOT/scripts/patch-spark-toolargs.sh" "$tree"

  local kr="node_modules/$KEYRING_PKG"
  mkdir -p "$tree/$kr"
  fetch "https://registry.npmjs.org/$KEYRING_PKG/-/${KEYRING_PKG#@napi-rs/}-${KEYRING_VER}.tgz" \
        "$ELEC_CACHE/kr.tgz"
  run_clean tar -xzf "$ELEC_CACHE/kr.tgz" -C "$tree/$kr" --strip-components=1
  rm -f "$ELEC_CACHE/kr.tgz"

  rm -f "$RES/app.asar"
  asar pack "$tree" "$RES/app.asar"
  rm -rf "$tree"

  # .node 会自动解到 app.asar.unpacked；把 unpacked 里的 ffmpeg 换成 Linux ELF，
  # 并清掉 win/darwin 专属二进制（audio-transcoder.js 实际加载 unpacked 这份）。
  local unp="$RES/app.asar.unpacked/node_modules/ffmpeg-static"
  if [ -d "$unp" ]; then
    cp -f "$RES/ffmpeg-static/ffmpeg" "$unp/ffmpeg"
    chmod +x "$unp/ffmpeg"
    rm -f "$unp"/ffmpeg.exe* 2>/dev/null || true
  fi
  log "   app.asar 已重打包（含 $KEYRING_PKG@$KEYRING_VER）"
}

# app.ico → hicolor 各尺寸 png（ICO 自带 16~256 帧）
gen_icons() {
  local src="$1" s
  local ico="$src/resources/app.ico"
  need magick
  local -A FRAME=( [16]=0 [24]=1 [32]=2 [48]=3 [64]=4 [128]=5 [256]=6 )
  for s in 16 24 32 48 64 128 256; do
    local d="$MIGRATE/usr/share/icons/hicolor/${s}x${s}/apps"
    mkdir -p "$d"
    magick "ICO:$ico[${FRAME[$s]}]" -background none "PNG32:$d/loomy.png"
  done
  local d="$MIGRATE/usr/share/icons/hicolor/512x512/apps"
  mkdir -p "$d"
  magick "ICO:$ico[6]" -background none -thumbnail 512x512 "PNG32:$d/loomy.png"
  cp "$MIGRATE/usr/share/icons/hicolor/256x256/apps/loomy.png" \
     "$MIGRATE/usr/share/pixmaps/loomy.png"
  cp "$MIGRATE/usr/share/icons/hicolor/256x256/apps/loomy.png" "$RES/loomy.png"
}

# 启动包装器：排除会破坏 Electron GPU/沙箱的环境变量（需求 6）
write_launcher() {
  cat > "$MIGRATE/usr/bin/loomy" <<'EOF'
#!/bin/bash
# Loomy Linux 启动包装器
# 排除宿主环境里会导致启动失败的变量：
#   LD_LIBRARY_PATH / LD_PRELOAD — Hermes 等注入的错误 libstdc++ → GPU LAUNCH_FAILED
#   ELECTRON_RUN_AS_NODE         — 让 Electron 当 node 跑，起不来窗口
#   TMPDIR 太长                  — SingletonSocket FATAL，强制短 /tmp
#   CHROME_* / XDG 沙箱覆盖        — 避免污染 Chromium 沙箱
unset LD_LIBRARY_PATH LD_PRELOAD LD_AUDIT ELECTRON_RUN_AS_NODE
unset ELECTRON_ENABLE_LOGGING ELECTRON_DEBUG_NOTIFICATIONS
unset CHROME_DEVEL_SANDBOX CHROMIUM_FLAGS SANDBOX_LD_AUDIT
export TMPDIR=/tmp

APP_DIR="/opt/xunfei/loomy"
exec "$APP_DIR/loomy" "$@"
EOF
  chmod +x "$MIGRATE/usr/bin/loomy"
}

write_desktop() {
  cat > "$MIGRATE/usr/share/applications/loomy.desktop" <<'EOF'
[Desktop Entry]
Name=Loomy
Name[zh_CN]=Loomy
Comment=Loomy — your AI work buddy
Comment[zh_CN]=Loomy — 你的 AI 工作搭子
Exec=/usr/bin/loomy %U
Icon=loomy
Terminal=false
Type=Application
Categories=Development;Utility;
Keywords=Loomy;iFlytek;Xunfei;AI;Agent;
StartupWMClass=Loomy
EOF
}

write_debian() {
  local version="$1" size
  size="$(du -sk "$MIGRATE/opt" | cut -f1)"
  cat > "$MIGRATE/DEBIAN/control" <<EOF
Package: loomy
Version: $version
Architecture: amd64
Maintainer: wxd <wxd@local>
Installed-Size: $size
Depends: libgtk-3-0, libnotify4, libnss3, libxss1, libxtst6, libxdamage1, libgbm1, libasound2, libatk-bridge2.0-0, libcups2, libdrm2, libxkbcommon0, libatspi2.0-0, libxcomposite1, libxfixes3, libxrandr2
Section: devel
Priority: optional
Homepage: https://loomy.xunfei.cn
Description: Loomy — iFlytek AI work assistant (Linux port)
 Loomy 桌面客户端，从 Windows 绿色版移植到 Linux。
 复用官方 app.asar 业务逻辑，搭配 Linux Electron 运行时。
 自包含安装到 /opt/xunfei/loomy，可用 dpkg/apt 升级。
EOF
  cat > "$MIGRATE/DEBIAN/postinst" <<'EOF'
#!/bin/bash
set -e
APP_DIR="/opt/xunfei/loomy"
chown root:root "$APP_DIR/chrome-sandbox" 2>/dev/null || true
chmod 4755 "$APP_DIR/chrome-sandbox" 2>/dev/null || true
chmod +x "$APP_DIR/loomy" "$APP_DIR/resources/node-runtime/bin/node" \
        "$APP_DIR/resources/ffmpeg-static/ffmpeg" 2>/dev/null || true
update-desktop-database -q /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -q -f /usr/share/icons/hicolor 2>/dev/null || true
echo "Loomy 已安装到 $APP_DIR，启动: loomy"
EOF
  cat > "$MIGRATE/DEBIAN/prerm" <<'EOF'
#!/bin/bash
pkill -x loomy 2>/dev/null || true
exit 0
EOF
  chmod 755 "$MIGRATE/DEBIAN/postinst" "$MIGRATE/DEBIAN/prerm"
}

build_deb() {
  mkdir -p "$DIST"
  local out="$DIST/$(basename "${PKG}")"
  rm -f "$out"
  run_clean dpkg-deb --build --root-owner-group "$MIGRATE" "$out"
  log "清除中间迁移目录"
  rm -rf "$MIGRATE"
  log "✅ 产物: $out ($(du -h "$out" | cut -f1))"
}
