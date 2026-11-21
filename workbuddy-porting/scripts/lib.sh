#!/bin/bash
# lib.sh — WorkBuddy Windows→Linux 移植脚本公共函数
# 被 scripts/build-deb.sh 加载，不单独执行。
#
# 关键约束（见 PORTING.md）：
#   * Electron 必须与 Windows 包内置版本一致（读 winapp/version，37.10.3-43 → 37.10.3）
#   * 升级检测始终按 Windows 版本通道检测（patch-update-check.sh 3 处补丁）
#   * Linux 原生依赖（runtime/node、runtime/python、koffi/node-pty/ripgrep/qimei 的
#     linux 件、tray 图标）来自官方 Linux deb（linux feed 动态解析，sha256 校验）

# 宿主注入的 LD_* 会搞坏 dpkg-deb/curl/7z/python3 等系统工具，入口统一源头清掉，
# 保证任何 shell 下直接跑（run_clean 仍保留作双保险）。
unset LD_LIBRARY_PATH LD_PRELOAD LD_AUDIT 2>/dev/null || true

# 始终在项目根目录运行
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

WIN_DIR="$ROOT/win"              # 放 WorkBuddy-win32-x64-user-<版本>-*.exe（NSIS 安装包）
ELEC_CACHE="$ROOT/.cache"         # 下载/解压缓存（Electron、官方 deb）
MIGRATE="$ROOT/.migrate"          # 中间目录
WINAPP="$MIGRATE/winapp"          # 解包后的 Windows 应用目录（输入，长期保留）
STAGE="$MIGRATE/stage"            # deb 打包容器（构建后清除）
DIST="$ROOT/dist"                 # 产物目录

# 官方 Linux deb：同一应用的官方 Linux 构建，作为 Linux 原生依赖唯一来源。
# 版本/下载地址/sha256 由 linux feed 动态解析（fetch_official_feed）：
#   GET /v2/update?platform=workbuddy-linux-x64-deb&version=0.0.1
OFFICIAL_DEB_VERSION=""
OFFICIAL_DEB_URL=""
OFFICIAL_DEB_SHA256=""
OFFICIAL_DEB=""
OFFICIAL_FEED_PLATFORM="workbuddy-linux-x64-deb"
OFFICIAL_TREE="$MIGRATE/official" # dpkg-deb -x 解出的官方 deb 内容
OFFICIAL_APP="$OFFICIAL_TREE/opt/WorkBuddy"

# Linux Electron 版本：从 Windows 包 version 文件动态识别（37.10.3-43 → 37.10.3）
ELECTRON_VERSION="${ELECTRON_VERSION:-}"

INSTALL_DIR="/opt/WorkBuddy"     # 与官方 deb 一致
BIN_NAME="workbuddy"             # 与官方 StartupWMClass/主程序名一致
PKG_NAME="workbuddy"             # dpkg 包名与官方一致 → 覆盖升级

# Hermes/Distro 注入的库会干扰系统工具（xz/tar/dpkg-deb/curl/7z）以及 Electron GPU。
CLEAN_ENV_KEYS=(LD_LIBRARY_PATH LD_PRELOAD)

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

# 下载（干净环境 + 3 次重试）
fetch() {
  local url="$1" out="$2" attempt
  for attempt in 1 2 3; do
    if run_clean curl -fsSL --retry 2 --max-time 900 -o "$out" "$url" 2>/dev/null; then
      return 0
    fi
    warn "下载失败(第 $attempt 次): $url，重试..."
    rm -f "$out"
    sleep 2
  done
  die "下载失败: $url"
}

sha256_of() { sha256sum "$1" | cut -d' ' -f1; }

# ───────────────────────── 源准备 ─────────────────────────

# 解包 win/*.exe（NSIS 两段式：外层 $PLUGINSDIR/app-64.7z → 应用目录），返回应用目录。
# 版本戳（名字+大小+mtime）匹配才复用；exe 换了就自动重新解包。
prepare_win() {
  mkdir -p "$WIN_DIR"
  local exe newest=""
  for exe in "$WIN_DIR"/*.exe; do
    [ -e "$exe" ] || continue
    if [ -z "$newest" ] || [ "$exe" -nt "$newest" ]; then newest="$exe"; fi
  done
  [ -n "$newest" ] || die "win/ 下未找到 Windows 安装包（请放入 WorkBuddy-win32-x64-user-<版本>-*.exe）"

  local sig stamp="$MIGRATE/winapp.stamp"
  sig="$(basename "$newest"):$(stat -c '%s:%Y' "$newest")"
  if [ -f "$WINAPP/resources/app.asar" ] && [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$sig" ]; then
    echo "$WINAPP"
    return 0
  fi

  log "解包 NSIS 安装包: $(basename "$newest")"
  rm -rf "$MIGRATE/nsis" "$WINAPP"
  mkdir -p "$MIGRATE/nsis" "$WINAPP"
  run_clean 7z x -y "-o$MIGRATE/nsis" "$newest" >/dev/null || die "7z 解包外层失败"

  local app7z="$MIGRATE/nsis/\$PLUGINSDIR/app-64.7z"
  [ -f "$app7z" ] || die "未找到 \$PLUGINSDIR/app-64.7z（安装包结构可能已变化）"
  run_clean 7z x -y "-o$WINAPP" "$app7z" >/dev/null || die "解包 app-64.7z 失败"
  rm -rf "$MIGRATE/nsis"

  rm -f "$WINAPP"/*.exe          # 安装包自带的 exe 副本，Linux 不需要
  [ -f "$WINAPP/resources/app.asar" ] || die "解包结果缺少 resources/app.asar"
  printf '%s\n' "$sig" > "$stamp"
  log "   应用目录: $WINAPP"
  echo "$WINAPP"
}

# 版本号：优先安装包文件名的「全版本-哈希」（与 Windows 对齐，如 5.11.3.43806934-ecace0f7）；
# 兜底 app.asar 内 package.json（3 段），再兜底文件名前 3 段。
# Debian 版本语义：最后一个 - 之后是 revision，比较时 5.11.3.43806934-ecace0f7 > 5.11.3 成立。
win_version() {
  local src="$1" ver="" tmp base exe
  for exe in "$WIN_DIR"/*.exe; do
    [ -e "$exe" ] || continue
    base="$(basename "$exe")"
    if [[ "$base" =~ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9a-zA-Z]+) ]]; then
      ver="${BASH_REMATCH[1]}"
      break
    fi
  done
  if [ -z "$ver" ] && [ -f "$src/resources/app.asar" ]; then
    tmp="$(mktemp -d)"
    if (cd "$tmp" && asar extract-file "$src/resources/app.asar" package.json >/dev/null 2>&1); then
      ver="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8"))["version"])' \
              "$tmp/package.json" 2>/dev/null || true)"
    fi
    rm -rf "$tmp"
  fi
  if [ -z "$ver" ]; then
    for exe in "$WIN_DIR"/*.exe; do
      [ -e "$exe" ] || continue
      base="$(basename "$exe")"
      if [[ "$base" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then ver="${BASH_REMATCH[1]}"; fi
    done
  fi
  [ -n "$ver" ] || die "无法识别版本号"
  echo "$ver"
}

# Electron 版本：winapp/version 文件形如 37.10.3-43（Electron 构建标识），取首段。
win_electron_version() {
  local f="$WINAPP/version" ver
  [ -f "$f" ] || die "找不到 $WINAPP/version（Electron 版本标识）"
  ver="$(head -1 "$f" | sed 's/-.*//')"
  [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version 文件内容异常: $(cat "$f")"
  echo "$ver"
}

# 官方 deb feed：解析版本/下载地址/sha256（设置全局变量，不能放子 shell）
fetch_official_feed() {
  local json
  json="$(run_clean curl -fsSL --max-time 30 \
    "https://copilot.tencent.com/v2/update?platform=${OFFICIAL_FEED_PLATFORM}&version=0.0.1" 2>/dev/null)" \
    || die "官方 deb feed 探测失败（需联网）"
  OFFICIAL_DEB_VERSION="$(printf '%s' "$json" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("productVersion") or d.get("version") or "")')"
  OFFICIAL_DEB_URL="$(printf '%s' "$json" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("url") or "")')"
  OFFICIAL_DEB_SHA256="$(printf '%s' "$json" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("sha256hash") or "")')"
  [ -n "$OFFICIAL_DEB_VERSION" ] && [ -n "$OFFICIAL_DEB_URL" ] && [ -n "$OFFICIAL_DEB_SHA256" ] \
    || die "官方 deb feed 缺字段: $json"
  OFFICIAL_DEB="$ELEC_CACHE/workbuddy-linux-${OFFICIAL_DEB_VERSION}.deb"
  log "   官方 deb v${OFFICIAL_DEB_VERSION}（linux feed，sha256 已记录）"
}

# 按 Windows 包解析全部版本号；env 显式设置优先于自动识别
resolve_versions() {
  if [ -z "$ELECTRON_VERSION" ]; then
    ELECTRON_VERSION="$(win_electron_version)"
    log "   Electron v$ELECTRON_VERSION（从 winapp/version 识别）"
  else
    log "   Electron v$ELECTRON_VERSION（ELECTRON_VERSION 显式指定）"
  fi
  fetch_official_feed
  log "   官方 deb 缓存: $(basename "$OFFICIAL_DEB")"
}

# 解压 electron-v<版本>-linux-x64.zip（项目根或 .cache，缺失则自动下载+sha 校验）
prepare_electron() {
  mkdir -p "$ELEC_CACHE"
  local base="electron-v${ELECTRON_VERSION}-linux-x64"
  local dest="$ELEC_CACHE/$base"

  if [ ! -x "$dest/electron" ]; then
    local zip=""
    [ -f "$ROOT/$base.zip" ] && zip="$ROOT/$base.zip"
    [ -z "$zip" ] && [ -f "$ELEC_CACHE/$base.zip" ] && zip="$ELEC_CACHE/$base.zip"
    if [ -z "$zip" ]; then
      fetch_electron_zip
      zip="$ELEC_CACHE/$base.zip"
    fi
    log "解压 Linux Electron: $(basename "$zip")"
    rm -rf "$dest" && mkdir -p "$dest"
    run_clean unzip -oq "$zip" -d "$dest/" || die "解压 electron zip 失败"
  fi

  [ -x "$dest/electron" ] || die "electron zip 内未找到可执行 electron"
  echo "$dest"
}

# 下载指定版本 Electron（npmmirror 优先，GitHub 兜底；对照官方 SHASUMS256.txt 校验）
fetch_electron_zip() {
  local base="electron-v${ELECTRON_VERSION}-linux-x64"
  local out="$ELEC_CACHE/$base.zip" want m
  for m in \
    "https://registry.npmmirror.com/-/binary/electron/${ELECTRON_VERSION}/SHASUMS256.txt" \
    "https://mirrors.huaweicloud.com/electron/${ELECTRON_VERSION}/SHASUMS256.txt" \
    "https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/SHASUMS256.txt"
  do
    want="$(run_clean curl -fsSL --max-time 60 "$m" 2>/dev/null | grep -F "$base.zip" | awk '{print $1}')" || true
    [ -n "$want" ] && break
  done
  [ -n "$want" ] || die "无法获取 Electron v${ELECTRON_VERSION} SHASUMS256.txt（三镜像均失败）"
  for m in \
    "https://registry.npmmirror.com/-/binary/electron/${ELECTRON_VERSION}/$base.zip" \
    "https://mirrors.huaweicloud.com/electron/${ELECTRON_VERSION}/$base.zip" \
    "https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/$base.zip"
  do
    log "下载 Linux Electron v${ELECTRON_VERSION}: $m"
    if run_clean curl -fL --retry 2 --max-time 1800 -o "$out" "$m" 2>/dev/null; then
      if [ "$(sha256_of "$out")" = "$want" ]; then
        log "   sha256 校验通过"
        return 0
      fi
      warn "sha256 不匹配，换下一个镜像"
    fi
    rm -f "$out"
  done
  die "Electron 下载失败（所有镜像）"
}

# 官方 Linux deb（Linux 原生依赖来源）：缓存按 sha256 校验
prepare_official_deb() {
  if [ -f "$OFFICIAL_DEB" ]; then
    if [ "$(sha256_of "$OFFICIAL_DEB")" = "$OFFICIAL_DEB_SHA256" ]; then
      log "   官方 deb 缓存命中: $(basename "$OFFICIAL_DEB")"
      return 0
    fi
    warn "官方 deb 缓存 sha 不匹配，重新下载"
    rm -f "$OFFICIAL_DEB"
  fi
  log "下载官方 Linux deb v${OFFICIAL_DEB_VERSION}（Linux 原生依赖来源）"
  fetch "$OFFICIAL_DEB_URL" "$OFFICIAL_DEB"
  [ "$(sha256_of "$OFFICIAL_DEB")" = "$OFFICIAL_DEB_SHA256" ] \
    || { rm -f "$OFFICIAL_DEB"; die "官方 deb sha256 与 feed 不符"; }
}

extract_official() {
  [ -d "$OFFICIAL_APP/resources/runtime" ] && return 0
  log "解包官方 Linux deb → $OFFICIAL_TREE"
  rm -rf "$OFFICIAL_TREE" && mkdir -p "$OFFICIAL_TREE"
  run_clean dpkg-deb -x "$OFFICIAL_DEB" "$OFFICIAL_TREE" || die "解包官方 deb 失败"
  [ -d "$OFFICIAL_APP/resources/runtime" ] || die "官方 deb 缺 resources/runtime"
}

# ───────────────────────── 构建步骤函数 ─────────────────────────

# 迁移 Windows 包 resources（跨平台目录原样拷；win 专属剔除；官方 deb 补 Linux 件）
migrate_resources() {
  # win 专属：elevate/qm-helper/supervisor 只被 win32 更新流引用；vendor 全是 win
  # 运行时（linux 走 resources/runtime 软链）；scripts 是 ps1/vbs 更新进度条
  local SKIP="app.asar|app.asar.unpacked|elevate.exe|qimei.dll|workbuddy-editor-sdk-supervisor.exe|vendor|qm|scripts"
  local f name
  for f in "$WINAPP"/resources/*; do
    [ -e "$f" ] || continue
    name="$(basename "$f")"
    if [[ "$name" =~ ^($SKIP)$ ]]; then continue; fi
    cp -a "$f" "$RES/$name"
  done

  # 官方 deb 独有的 Linux 资源：runtime（node/python，VendorAssetEnsure 软链目标）、
  # 托盘图标（main-bootstrap 引用 tray-linux*.png）、AppArmor profile
  for name in runtime tray-linux.png "tray-linux@2x.png" apparmor-profile; do
    [ -e "$OFFICIAL_APP/resources/$name" ] || die "官方 deb 缺 resources/$name"
    rm -rf "$RES/$name"
    cp -a "$OFFICIAL_APP/resources/$name" "$RES/$name"
  done

  # 兜底检查：resources 顶层不应再有 Windows 专属二进制
  local leftover
  leftover="$(find "$RES" -not -path "*app.asar*" -not -path "*resources/runtime/*" \
      \( -iname "*.exe" -o -iname "*.pyd" -o -iname "*.dll" -o -iname "*win32-x64*" \) 2>/dev/null | head -5)"
  [ -z "$leftover" ] || warn "resources 仍有 Windows 专属文件:
$leftover"
}

# 解包 app.asar → 补缺失占位 → 叠加 winapp unpacked → 注入官方 Linux 原生件
# → 打更新补丁 → 重打包（全量 unpacked）
repack_asar() {
  need asar
  local tree="$MIGRATE/asar"
  local unpacked="$WINAPP/resources/app.asar.unpacked"
  local stublist="$MIGRATE/stub-list.txt"
  rm -rf "$tree" && mkdir -p "$tree"

  # 1) asar 头枚举 unpacked 且 winapp 磁盘缺失的文件 → 0 字节占位，否则 extract 中断
  #    （占位清单两侧同删，空文件不会进新包）
  python3 - "$WINAPP/resources/app.asar" "$unpacked" "$stublist" <<'PY'
import os, struct, json, sys
asar, unpacked, listpath = sys.argv[1:4]
with open(asar, "rb") as f:
    head = f.read(16)
    json_len = struct.unpack("<I", head[12:16])[0]
    header = json.loads(f.read(json_len).decode("utf-8"))
missing = []
def walk(node, prefix):
    for name, entry in node.get("files", {}).items():
        p = f"{prefix}/{name}" if prefix else name
        if "files" in entry:
            walk(entry, p)
        elif entry.get("unpacked"):
            if not os.path.exists(os.path.join(unpacked, p)):
                missing.append(p)
walk(header, "")
with open(listpath, "w") as out:
    for p in missing:
        dst = os.path.join(unpacked, p)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        open(dst, "wb").close()
        out.write(p + "\n")
print(f"stub: {len(missing)} 个 unpacked 文件在 winapp 缺失，已占位")
PY

  # 2) 解包（旁边需 winapp 的 app.asar.unpacked 供 unpacked 文件读取）
  asar extract "$WINAPP/resources/app.asar" "$tree" || die "asar extract 失败"

  # 3) 删占位（winapp 侧：下次构建重新枚举；tree 侧：空文件不进新包）
  if [ -s "$stublist" ]; then
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      rm -f "$unpacked/$p" "$tree/$p"
    done < "$stublist"
  fi

  # 4) winapp unpacked 里 asar header 没有的真文件（main/preload 等 325 个）叠加进 tree
  cp -an "$unpacked/." "$tree/"

  # 5) 官方 deb 的 Linux 原生件（winapp 只有 win32 版或被 win 构建剔除）
  local src="$OFFICIAL_APP/resources/app.asar.unpacked" n
  # cli 侧 koffi：官方 5.6.2 没有 cli/koffi，用官方根 koffi 同版本(2.16.2)的 linux 件
  mkdir -p "$tree/cli/node_modules/koffi/build/koffi/linux_x64"
  cp -a "$src/node_modules/koffi/build/koffi/linux_x64/koffi.node" \
        "$tree/cli/node_modules/koffi/build/koffi/linux_x64/koffi.node"
  local natives=(
    "cli/node_modules/@lydell/node-pty-linux-x64"
    "cli/vendor/ripgrep/x64-linux/rg"
    "cli/vendor/ripgrep/x64-linux/ripgrep.node"
    "node_modules/node-pty/build/Release/pty.node"
    "node_modules/koffi/build/koffi/linux_x64/koffi.node"
    "node_modules/@tencent/qimei-node/build/Release/qimei.node"
  )
  for n in "${natives[@]}"; do
    [ -e "$src/$n" ] || die "官方 deb 缺 Linux 原生件: $n"
    rm -rf "$tree/$n"
    mkdir -p "$tree/$(dirname "$n")"
    cp -a "$src/$n" "$tree/$n"
  done

  # 6) 更新检查补丁（Windows 通道 + 点击触发下载）
  bash "$ROOT/scripts/patch-update-check.sh" "$tree"
  # 6b) 设置界面对齐 Windows（detectPlatform Linux→win32 + 安全中心 isHostWindows）
  bash "$ROOT/scripts/patch-settings-win32.sh" "$tree"

  # 7) 重打包：全部 unpacked（原包 4000+ 非二进制文件也 unpacked，超集安全）
  rm -f "$RES/app.asar"
  rm -rf "$RES/app.asar.unpacked"
  asar pack "$tree" "$RES/app.asar" --unpack-dir '**' || die "asar pack 失败"
  rm -rf "$tree"
  log "   app.asar 已重打包（更新补丁 + Linux 原生件 + 全量 unpacked）"
}

# 官方 deb 自带 hicolor 全尺寸图标（workbuddy.png 16~512）
gen_icons() {
  local h="$OFFICIAL_TREE/usr/share/icons/hicolor"
  if [ -d "$h" ]; then
    mkdir -p "$STAGE/usr/share/icons"
    rm -rf "$STAGE/usr/share/icons/hicolor"
    cp -a "$h" "$STAGE/usr/share/icons/"
  else
    warn "官方 deb 无 hicolor 图标，跳过"
  fi
}

# 启动包装器：排除会破坏 Electron GPU/沙箱的环境变量
write_launcher() {
  cat > "$STAGE/usr/bin/$BIN_NAME" <<EOF
#!/bin/bash
# WorkBuddy Linux 启动包装器
# 排除宿主环境里会导致启动失败的变量：
#   LD_LIBRARY_PATH / LD_PRELOAD — 注入的错误 libstdc++ → GPU LAUNCH_FAILED
#   ELECTRON_RUN_AS_NODE         — 让 Electron 当 node 跑，起不来窗口
#   TMPDIR 太长                  — SingletonSocket FATAL，强制短 /tmp
unset LD_LIBRARY_PATH LD_PRELOAD LD_AUDIT ELECTRON_RUN_AS_NODE
unset ELECTRON_ENABLE_LOGGING ELECTRON_DEBUG_NOTIFICATIONS
unset CHROME_DEVEL_SANDBOX CHROMIUM_FLAGS SANDBOX_LD_AUDIT
export TMPDIR=/tmp

exec "$INSTALL_DIR/$BIN_NAME" "\$@"
EOF
  chmod +x "$STAGE/usr/bin/$BIN_NAME"
}

# .desktop：以官方 .desktop 为底，仅把 Exec 换成启动包装器（走 env 清理）
write_desktop() {
  local out="$STAGE/usr/share/applications/$BIN_NAME.desktop"
  local src="$OFFICIAL_TREE/usr/share/applications/$BIN_NAME.desktop"
  if [ -f "$src" ]; then
    sed -E "s|^Exec=.*|Exec=/usr/bin/$BIN_NAME %U|" "$src" > "$out"
  else
    cat > "$out" <<EOF
[Desktop Entry]
Name=WorkBuddy
Exec=/usr/bin/$BIN_NAME %U
Terminal=false
Type=Application
Icon=$BIN_NAME
StartupWMClass=$BIN_NAME
MimeType=x-scheme-handler/workbuddy;
Categories=Development;
EOF
  fi
}

write_debian() {
  local version="$1" size
  size="$(du -sk "$STAGE/opt" | cut -f1)"
  mkdir -p "$STAGE/DEBIAN"
  cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PKG_NAME
Version: $version
License: commercial
Vendor: Tencent WorkBuddy <workbuddy@tencent.com>
Architecture: amd64
Maintainer: wxd <wxd@local>
Installed-Size: $size
Depends: libgtk-3-0, libnotify4, libnss3, libxss1, libxtst6, xdg-utils, libatspi2.0-0, libuuid1, libsecret-1-0
Recommends: libappindicator3-1, imagemagick
Section: utils
Priority: optional
Homepage: https://www.workbuddy.cn
Description: WorkBuddy — Linux port of the Windows build
 WorkBuddy 桌面客户端，从 Windows 安装包移植到 Linux。
 复用 Windows 包 app.asar 业务逻辑 + Linux Electron 运行时，自包含安装到
 /opt/WorkBuddy，可用 dpkg/apt 升级。升级检测始终按 Windows 版本通道。
EOF
  cat > "$STAGE/DEBIAN/postinst" <<EOF
#!/bin/bash
set -e
APP_DIR="$INSTALL_DIR"
# 沙箱：内核不支持用户命名空间时退回 SUID chrome-sandbox（与官方 postinst 一致）
if ! { [ -L /proc/self/ns/user ] && unshare --user true; }; then
    chown root:root "\$APP_DIR/chrome-sandbox" 2>/dev/null || true
    chmod 4755 "\$APP_DIR/chrome-sandbox" 2>/dev/null || true
else
    chmod 0755 "\$APP_DIR/chrome-sandbox" 2>/dev/null || true
fi
chmod +x "\$APP_DIR/$BIN_NAME" 2>/dev/null || true
# 覆盖安装过官方包时，清掉它建的 update-alternatives 链接（本包自带 /usr/bin/$BIN_NAME）
update-alternatives --remove $BIN_NAME "\$APP_DIR/$BIN_NAME" 2>/dev/null || true
update-desktop-database -q /usr/share/applications 2>/dev/null || true
update-mime-database /usr/share/mime 2>/dev/null || true
gtk-update-icon-cache -q -f /usr/share/icons/hicolor 2>/dev/null || true
echo "$BIN_NAME 已安装到 \$APP_DIR，启动: $BIN_NAME"
EOF
  cat > "$STAGE/DEBIAN/prerm" <<EOF
#!/bin/bash
pkill -x $BIN_NAME 2>/dev/null || true
exit 0
EOF
  chmod 755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/prerm"
}

build_deb() {
  mkdir -p "$DIST"
  local out="$DIST/${PKG_NAME}_${VERSION}_amd64.deb"
  rm -f "$out"
  run_clean dpkg-deb --build --root-owner-group "$STAGE" "$out" || die "dpkg-deb 打包失败"
  log "清除中间目录（保留 .migrate/winapp 源目录）"
  rm -rf "$STAGE" "$MIGRATE/asar" "$MIGRATE/ptmp"
  log "✅ 产物: $out ($(du -h "$out" | cut -f1))"
}
