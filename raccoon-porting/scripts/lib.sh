#!/bin/bash
# lib.sh — 商汤小浣熊 Windows→Linux 移植脚本公共函数
# 被 scripts/build-deb.sh 加载，不单独执行。
#
# 关键约束（见 PORTING.md）：
#   * Electron 必须与 Windows 包内置版本一致（41.0.1）
#   * 升级检测始终按 Windows 版本检测（patch-update-check.sh）
#   * Linux 原生依赖（box-agent/rg/canvas/esbuild/图标）来自官方 Linux deb

# 宿主注入的 LD_* 会搞坏 dpkg-deb/curl/7z/python3 等系统工具，入口统一源头清掉，
# 保证任何 shell 下直接跑（run_clean 仍保留作双保险）。
unset LD_LIBRARY_PATH LD_PRELOAD LD_AUDIT 2>/dev/null || true

# 始终在项目根目录运行
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

WIN_DIR="$ROOT/win"              # 放 商汤小浣熊-<版本>-x64.exe（NSIS 安装包）
ELEC_CACHE="$ROOT/.cache"         # 下载/解压缓存（Electron、官方 deb、pandoc）
ELECTRON_CACHE="$ELEC_CACHE/electron"  # Linux Electron 版本化缓存目录（见 prepare_electron）
MIGRATE="$ROOT/.migrate"          # 中间目录
WINAPP="$MIGRATE/winapp"          # 解包后的 Windows 应用目录（输入，长期保留）
STAGE="$MIGRATE/stage"            # deb 打包容器（构建后清除）
DIST="$ROOT/dist"                 # 产物目录

# 官方 Linux deb：同一应用的官方 Linux 构建，作为 Linux 原生依赖唯一来源。
# 版本号默认【与 Windows 版本动态匹配】（resolve_official_deb_version）：
#   精确同名 → linux feed latest-linux.yml → 兜底 1.0.38；OFFICIAL_DEB_VERSION 可强制指定。
OFFICIAL_DEB_VERSION="${OFFICIAL_DEB_VERSION:-}"   # 空 = 构建时动态匹配
OFFICIAL_DEB=""                                    # resolve_versions() 内按最终版本生成缓存路径
OFFICIAL_DEB_URL_BASE="https://sta-volc.xiaohuanxiong.com/office-agent/linux/x64"
OFFICIAL_TREE="$MIGRATE/official" # dpkg-deb -x 解出的官方 deb 内容
OFFICIAL_APP=""                   # extract_official() 内按 opt/ 下实际目录探测
                                   # （1.2.2 起官方目录名从 office-raccoon 变为 商汤小浣熊）

# Linux Electron 版本：默认【从 Windows 包动态识别】（win_electron_version），必须与内置一致；
# ELECTRON_VERSION 可显式覆盖。
ELECTRON_VERSION="${ELECTRON_VERSION:-}"           # 空 = 构建时从 Windows 包识别

PANDOC_VERSION="${PANDOC_VERSION:-3.7.0.2}"

INSTALL_DIR="/opt/office-raccoon"  # 与官方 deb 一致
BIN_NAME="raccoon-ai"             # 与官方 StartupWMClass 一致（决定 WM_CLASS/图标匹配）
PKG_NAME="raccoon-ai"             # dpkg 包名与官方一致 → 覆盖升级

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

# ───────────────────────── 源准备 ─────────────────────────

# 解包 win/*.exe（NSIS 两段式：外层 $PLUGINSDIR/app-64.7z → 应用目录），返回应用目录。
# 版本戳（名字+大小+mtime）匹配才复用；exe 换了就自动重新解包——版本升级后流水线跟着换。
# 解包后删掉 winapp 内的 exe 副本（win/ 里原样保留）。
prepare_win() {
  mkdir -p "$WIN_DIR"
  local exe newest=""
  for exe in "$WIN_DIR"/*.exe; do
    [ -e "$exe" ] || continue
    if [ -z "$newest" ] || [ "$exe" -nt "$newest" ]; then newest="$exe"; fi
  done
  [ -n "$newest" ] || die "win/ 下未找到 Windows 安装包（请放入 商汤小浣熊-<版本>-x64.exe）"

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

# 版本号：优先取 app.asar 内 package.json（与 exe ProductVersion 一致）
win_version() {
  local src="$1" ver="" tmp
  if [ -f "$src/resources/app.asar" ]; then
    tmp="$(mktemp -d)"
    if (cd "$tmp" && asar extract-file "$src/resources/app.asar" package.json >/dev/null 2>&1); then
      ver="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8"))["version"])' \
              "$tmp/package.json" 2>/dev/null || true)"
    fi
    rm -rf "$tmp"
  fi
  if [ -z "$ver" ]; then
    # 兜底：从安装包文件名识别（官方命名 商汤小浣熊-<版本>-x64.exe）
    local base exe
    for exe in "$WIN_DIR"/*.exe; do
      [ -e "$exe" ] || continue
      base="$(basename "$exe")"
      if [[ "$base" =~ ([0-9]+(\.[0-9]+)+) ]]; then ver="${BASH_REMATCH[1]}"; fi
    done
  fi
  [ -n "$ver" ] || die "无法识别版本号"
  echo "$ver"
}

# ───────────────────── 版本号动态匹配（随 Windows 包走） ─────────────────────

# 从 Windows 包的 app.asar 识别内置 Electron 版本（Linux 运行时必须与其严格一致）。
# 主证据：pnpm 依赖路径 electron-settings@x.y.z_electron@<解析版本>，按多数票取值；
# 兜底：源码注释 Electron vX.Y.Z。识别不到就失败（宁可报错也不静默用错运行时）。
win_electron_version() {
  local asar="$WINAPP/resources/app.asar" ver
  [ -f "$asar" ] || die "win_electron_version: 找不到 $asar"
  ver="$(grep -aoE '_electron@[0-9]+\.[0-9]+\.[0-9]+' "$asar" 2>/dev/null \
        | sed 's/^_electron@//' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')" || ver=""
  if [ -z "$ver" ]; then
    ver="$(grep -aoE 'Electron v[0-9]+\.[0-9]+\.[0-9]+' "$asar" 2>/dev/null \
          | head -1 | awk '{print $2}')" || ver=""
  fi
  [ -n "$ver" ] || die "无法从 Windows 包识别 Electron 版本（可显式指定 ELECTRON_VERSION=x.y.z）"
  echo "$ver"
}

# 官方 Linux deb 是否存在（Range 探测：存在返回 206/200，否则 404）
official_deb_exists() {
  local name enc code
  name="商汤小浣熊-$1-amd64.deb"
  enc="$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$name")"
  code="$(run_clean curl -s -o /dev/null -w '%{http_code}' --max-time 30 -r 0-0 \
          "$OFFICIAL_DEB_URL_BASE/$enc" 2>/dev/null)" || code=""
  [ "$code" = "206" ] || [ "$code" = "200" ]
}

# 官方 Linux deb 版本：与 Windows 版本动态匹配
#   ① 精确同名 商汤小浣熊-<winver>-amd64.deb
#   ② linux feed latest-linux.yml（官方 Linux 最新版）
#   ③ 兜底 1.0.38（历史已验证可用）
resolve_official_deb_version() {
  local winver="$1" latest=""
  if official_deb_exists "$winver"; then
    log "   官方 deb：精确匹配 Windows 版本 v$winver"
    echo "$winver"
    return 0
  fi
  latest="$(run_clean curl -fsSL --max-time 30 \
              "$OFFICIAL_DEB_URL_BASE/latest-linux.yml?noCache=$(date +%s%3N)" 2>/dev/null \
            | sed -n 's/^version:[[:space:]]*//p' | head -1)" || latest=""
  if [ -n "$latest" ] && official_deb_exists "$latest"; then
    log "   官方 deb：无同名版本，取 Linux feed 最新 v$latest"
    echo "$latest"
    return 0
  fi
  warn "官方 deb 版本探测失败，兜底 v1.0.38"
  echo "1.0.38"
}

# 按 Windows 版本解析全部版本号并生成官方 deb 缓存路径；env 显式设置优先于自动识别
resolve_versions() {
  local winver="$1"
  if [ -z "$ELECTRON_VERSION" ]; then
    ELECTRON_VERSION="$(win_electron_version)"
    log "   Electron v$ELECTRON_VERSION（从 Windows 包 app.asar 识别）"
  else
    log "   Electron v$ELECTRON_VERSION（ELECTRON_VERSION 显式指定）"
  fi
  if [ -z "$OFFICIAL_DEB_VERSION" ]; then
    OFFICIAL_DEB_VERSION="$(resolve_official_deb_version "$winver")"
  else
    log "   官方 deb v$OFFICIAL_DEB_VERSION（OFFICIAL_DEB_VERSION 显式指定）"
  fi
  OFFICIAL_DEB="$ELEC_CACHE/raccoon-linux-${OFFICIAL_DEB_VERSION}.deb"
  log "   官方 deb 缓存: $(basename "$OFFICIAL_DEB")"
}

# ───────────────────── Linux Electron：版本化缓存 ─────────────────────
# 布局：.cache/electron/<版本>/（解压目录，含 electron 可执行）
#       .cache/electron/electron-v<版本>-linux-x64.zip
# 命中同名版本 → 直接复用（不联网）；版本不一致 → 删旧目录/旧压缩包后重新下载。

# SHASUMS256.txt：GitHub 常超时/被劫持，npmmirror、华为云镜像兜底；结果缓存到版本目录旁。
electron_expected_sha() {
  local base="electron-v${ELECTRON_VERSION}-linux-x64.zip"
  local sums="$ELECTRON_CACHE/SHASUMS256-v${ELECTRON_VERSION}.txt" sha url
  if [ -f "$sums" ]; then
    sha="$(grep -F "$base" "$sums" | awk '{print $1}' | head -1)"
    [ -n "$sha" ] && { echo "$sha"; return 0; }
    rm -f "$sums"
  fi
  mkdir -p "$ELECTRON_CACHE"
  for url in \
    "https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/SHASUMS256.txt" \
    "https://registry.npmmirror.com/-/binary/electron/${ELECTRON_VERSION}/SHASUMS256.txt" \
    "https://mirrors.huaweicloud.com/electron/${ELECTRON_VERSION}/SHASUMS256.txt"
  do
    if run_clean curl -fsSL --max-time 60 -o "$sums.tmp" "$url" 2>/dev/null; then
      sha="$(grep -F "$base" "$sums.tmp" | awk '{print $1}' | head -1)"
      if [ -n "$sha" ]; then
        mv -f "$sums.tmp" "$sums"
        echo "$sha"
        return 0
      fi
    fi
    rm -f "$sums.tmp"
  done
  return 1
}

# 旧布局 .cache/electron-v<版本>-linux-x64 自动搬进版本化目录（避免重复下载）
adopt_legacy_electron() {
  local base="$1" legacy="$ELEC_CACHE/$base" dest="$ELECTRON_CACHE/$ELECTRON_VERSION"
  [ -x "$legacy/electron" ] || return 0
  if [ -x "$dest/electron" ]; then
    rm -rf "$legacy"
  else
    log "   迁移旧缓存 .cache/$base → .cache/electron/$ELECTRON_VERSION"
    mkdir -p "$dest"
    cp -a "$legacy/." "$dest/" && rm -rf "$legacy"
  fi
  [ -f "$ELEC_CACHE/$base.zip" ] && mv -f "$ELEC_CACHE/$base.zip" "$ELECTRON_CACHE/" || true
}

# 版本不一致时清掉旧版本缓存（当前版本目录/SHASUMS/zip 保留）
purge_stale_electron() {
  local keep="$ELECTRON_VERSION" e n removed=0
  for e in "$ELECTRON_CACHE"/*; do
    [ -e "$e" ] || continue
    n="$(basename "$e")"
    [ "$n" = "$keep" ] && continue
    case "$n" in
      SHASUMS256-v${keep}.txt) continue ;;
      electron-v${keep}-linux-x64.zip*) continue ;;
      [0-9]*|electron-v*.zip|SHASUMS256-v*.txt) rm -rf "$e"; removed=1 ;;
    esac
  done
  [ "$removed" = 1 ] && log "   清理旧版本 Electron 缓存（当前 v$keep）"
  return 0
}

# 解压 electron-v<版本>-linux-x64.zip（版本化缓存，缺失则自动下载+sha 校验）
# 返回解压目录（内含可执行 electron）
prepare_electron() {
  mkdir -p "$ELECTRON_CACHE"
  local base="electron-v${ELECTRON_VERSION}-linux-x64"
  local dest="$ELECTRON_CACHE/$ELECTRON_VERSION"

  adopt_legacy_electron "$base"
  purge_stale_electron

  if [ -x "$dest/electron" ]; then
    log "   复用缓存: .cache/electron/$ELECTRON_VERSION"
    echo "$dest"
    return 0
  fi

  local zip="" c
  for c in "$ELECTRON_CACHE/$base.zip" "$ROOT/$base.zip" "$ELEC_CACHE/$base.zip"; do
    [ -f "$c" ] && { zip="$c"; break; }
  done
  if [ -n "$zip" ]; then
    local want got
    want="$(electron_expected_sha)" || want=""
    if [ -n "$want" ]; then
      got="$(sha256sum "$zip" | cut -d' ' -f1)"
      if [ "$got" = "$want" ]; then
        log "   已有 Electron 压缩包，sha256 校验通过: $(basename "$zip")"
      else
        warn "缓存压缩包 sha256 不匹配，删除后重新下载: $(basename "$zip")"
        rm -f "$zip"; zip=""
      fi
    else
      warn "无法获取 Electron v${ELECTRON_VERSION} SHASUMS256.txt，跳过校验直接使用 $(basename "$zip")"
    fi
  fi
  if [ -z "$zip" ]; then
    fetch_electron_zip
    zip="$ELECTRON_CACHE/$base.zip"
  fi
  if [ "$zip" != "$ELECTRON_CACHE/$base.zip" ]; then
    mv -f "$zip" "$ELECTRON_CACHE/$base.zip"
    zip="$ELECTRON_CACHE/$base.zip"
  fi

  log "解压 Linux Electron: $(basename "$zip")"
  rm -rf "$dest" && mkdir -p "$dest"
  run_clean unzip -oq "$zip" -d "$dest/" || die "解压 electron zip 失败"
  # zip 保留不删：作为持久输入，版本目录被清理后仍可离线重解压
  [ -x "$dest/electron" ] || die "electron zip 内未找到可执行 electron"
  echo "$dest"
}

# 下载指定版本 Electron（npmmirror 优先，华为云/GitHub 兜底；SHASUMS256 校验）
fetch_electron_zip() {
  local base="electron-v${ELECTRON_VERSION}-linux-x64"
  local out="$ELECTRON_CACHE/$base.zip" want m got
  mkdir -p "$ELECTRON_CACHE"
  want="$(electron_expected_sha)" || want=""
  [ -n "$want" ] || warn "Electron v${ELECTRON_VERSION} SHASUMS256.txt 所有镜像均不可用：仅记录 sha256，不做校验"
  for m in \
    "https://registry.npmmirror.com/-/binary/electron/${ELECTRON_VERSION}/$base.zip" \
    "https://mirrors.huaweicloud.com/electron/${ELECTRON_VERSION}/$base.zip" \
    "https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/$base.zip"
  do
    log "下载 Linux Electron v${ELECTRON_VERSION}: $m"
    if run_clean curl -fL --retry 2 --max-time 1800 -o "$out" "$m" 2>/dev/null && [ -s "$out" ]; then
      got="$(sha256sum "$out" | cut -d' ' -f1)"
      if [ -z "$want" ] || [ "$got" = "$want" ]; then
        [ -n "$want" ] && log "   sha256 校验通过"
        printf '%s  %s\n' "$got" "$base.zip" > "$out.sha256"
        return 0
      fi
      warn "sha256 不匹配，换下一个镜像"
    fi
    rm -f "$out"
  done
  rm -f "$out"
  die "Electron 下载失败（所有镜像）"
}

# 官方 Linux deb（Linux 原生依赖来源）
prepare_official_deb() {
  if [ ! -f "$OFFICIAL_DEB" ]; then
    local name="商汤小浣熊-${OFFICIAL_DEB_VERSION}-amd64.deb" enc
    enc="$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$name")"
    log "下载官方 Linux deb v${OFFICIAL_DEB_VERSION}（原生依赖来源）"
    fetch "$OFFICIAL_DEB_URL_BASE/$enc" "$OFFICIAL_DEB"
  fi
}

# 官方 deb 的 opt/ 目录名随版本变化（office-raccoon → 商汤小浣熊），按内容探测
detect_official_app() {
  local d
  for d in "$OFFICIAL_TREE"/opt/*; do
    [ -d "$d" ] || continue
    if [ -f "$d/resources/box-agent-runtime/manifest.json" ]; then
      OFFICIAL_APP="$d"
      return 0
    fi
  done
  return 1
}

extract_official() {
  if ! detect_official_app; then
    log "解包官方 Linux deb → $OFFICIAL_TREE"
    rm -rf "$OFFICIAL_TREE" && mkdir -p "$OFFICIAL_TREE"
    run_clean dpkg-deb -x "$OFFICIAL_DEB" "$OFFICIAL_TREE" || die "解包官方 deb 失败"
    detect_official_app || die "官方 deb 里找不到 resources/box-agent-runtime（opt 下: $(ls "$OFFICIAL_TREE/opt" 2>/dev/null | tr "\n" " ")）"
  fi
}

# ───────────────────────── 构建步骤函数 ─────────────────────────

# 迁移 Windows 包 resources（跨平台目录原样拷，平台专属换 Linux 版）
migrate_resources() {
  # 跨平台原样拷贝；平台专属的在 SKIP 里排除后单独处理
  local SKIP="app.asar|app.asar.unpacked|7za|elevate.exe|box-agent-runtime|rg|pandoc"
  local f name
  for f in "$WINAPP"/resources/*; do
    [ -e "$f" ] || continue
    name="$(basename "$f")"
    if [[ "$name" =~ ^($SKIP)$ ]]; then continue; fi
    cp -a "$f" "$RES/$name"
  done

  # box-agent-runtime：Windows 冻结 Python（.exe/.pyd/.dll）→ 官方 Linux 版（0.9.8 linux）
  rm -rf "$RES/box-agent-runtime"
  cp -a "$OFFICIAL_APP/resources/box-agent-runtime" "$RES/box-agent-runtime"

  # rg：rg.exe → 官方 Linux rg
  rm -rf "$RES/rg"
  cp -a "$OFFICIAL_APP/resources/rg" "$RES/rg"

  # pandoc：pandoc.exe → 静态 Linux pandoc（保持 resources/pandoc/pandoc 布局）
  local ptar="$ELEC_CACHE/pandoc-${PANDOC_VERSION}-linux-amd64.tar.gz"
  # 复用早期手工下载的缓存
  if [ ! -f "$ptar" ] && [ -f "$MIGRATE/linuxdeps/pandoc.tar.gz" ]; then
    mv "$MIGRATE/linuxdeps/pandoc.tar.gz" "$ptar"
  fi
  if [ ! -f "$RES/pandoc/pandoc" ]; then
    if [ ! -f "$ptar" ]; then
      # GitHub 直连本机超时，走镜像链（ghfast → gh-proxy → 官方源）
      local rel="/jgm/pandoc/releases/download/${PANDOC_VERSION}/pandoc-${PANDOC_VERSION}-linux-amd64.tar.gz" got=0 m
      for m in "https://ghfast.top/https://github.com$rel" \
               "https://gh-proxy.com/https://github.com$rel" \
               "https://github.com$rel"; do
        log "下载 pandoc v${PANDOC_VERSION}: $m"
        if run_clean curl -fsSL --retry 2 --max-time 900 -o "$ptar" "$m"; then got=1; break; fi
        rm -f "$ptar"
      done
      [ "$got" = 1 ] || die "pandoc 下载失败（所有镜像）"
    fi
    mkdir -p "$MIGRATE/ptmp"
    run_clean tar -xzf "$ptar" -C "$MIGRATE/ptmp"
    mkdir -p "$RES/pandoc"
    cp "$MIGRATE/ptmp/pandoc-${PANDOC_VERSION}/bin/pandoc" "$RES/pandoc/pandoc"
    chmod +x "$RES/pandoc/pandoc"
    rm -rf "$MIGRATE/ptmp"
  fi

  # assets：Windows 有 icon.ico/menu-bar-raccoon.png，补 icon.png（窗口图标，Wayland 不吃 .ico）
  # 来源：官方 assets/icon.png → 兜底官方 hicolor 主图标（1.2.2 起官方不再放 assets/icon.png，两者字节一致）
  local icon_src="$OFFICIAL_APP/resources/assets/icon.png"
  [ -f "$icon_src" ] || icon_src="$OFFICIAL_TREE/usr/share/icons/hicolor/1024x1024/apps/$BIN_NAME.png"
  [ -f "$icon_src" ] || die "找不到窗口图标 icon.png 来源"
  cp -a "$icon_src" "$RES/assets/icon.png"

  # render-node-deps：Linux 专用渲染依赖（app 只在 platform=linux 时读取），官方 deb 是唯一来源；
  # win1.2.2 起不再随 Windows 包附带，整体取官方 Linux 版替换（win32 版对 Linux 无用）
  local rd="$OFFICIAL_APP/resources/render-node-deps"
  [ -d "$rd/node_modules" ] || die "官方 deb 缺 resources/render-node-deps"
  rm -rf "$RES/render-node-deps"
  cp -a "$rd" "$RES/render-node-deps"

  # 兜底检查：resources 下不应再有 Windows 专属二进制
  local leftover
  leftover="$(find "$RES" -not -path "*app.asar*" \
      \( -iname "*.exe" -o -iname "*.pyd" -o -iname "*win32-x64*" \) 2>/dev/null | head -5)"
  [ -z "$leftover" ] || warn "resources 仍有 Windows 专属文件:\n$leftover"
}

# 解包 app.asar → 打补丁（升级检测/无边框窗口/图标）→ 注入 @esbuild/linux-x64 → 重打包
repack_asar() {
  need asar
  local tree="$MIGRATE/asar"
  rm -rf "$tree" && mkdir -p "$tree"
  # 从 winapp 解（旁边有 Windows 的 app.asar.unpacked，extract 需要它读 unpacked 文件）
  asar extract "$WINAPP/resources/app.asar" "$tree"

  bash "$ROOT/scripts/patch-update-check.sh" "$tree"
  # 更新包改为点「下载」→ 询问保存路径 → 存到所选路径（不自动下载/不自动安装）
  bash "$ROOT/scripts/patch-update-saveas.sh" "$tree"
  bash "$ROOT/scripts/patch-window-linux.sh" "$tree"
  # Linux：系统托盘（关窗隐藏到托盘，托盘可显示主界面/退出；patch-window-linux 已补图标路径）
  bash "$ROOT/scripts/patch-tray-linux.sh" "$tree"
  # Linux/Wayland：去掉原生文件对话框的 parent window（Electron portal parent 传递失败→挂死）
  bash "$ROOT/scripts/patch-dialog-parent.sh" "$tree"
  # Linux/Wayland：修复"打开当前目录"卡死（shell.openPath 挂起→IPC 不返回→前端锁定）
  bash "$ROOT/scripts/patch-workspace-open-linux.sh" "$tree"
  # Linux：修复托盘/窗口"退出"挂起（agent-host 清理永不 resolve→close() 无超时→永不退出）
  bash "$ROOT/scripts/patch-quit-timeout-linux.sh" "$tree"
  # 产品：首页"完善资料"入口在 cloud 构建会打开本地问卷（保存必失败）
  # → 改走引导向导的记忆步骤，由向导按 memory-v2 status 分流 local/cloud
  bash "$ROOT/scripts/patch-memory-questionnaire.sh" "$tree"

  # esbuild：Windows 包只有 win32-x64，补 Linux 二进制（tsx 跑 TS 脚本用）
  local esb="$OFFICIAL_APP/resources/node_modules/@esbuild/linux-x64"
  if [ -d "$esb" ]; then
    mkdir -p "$tree/node_modules/@esbuild"
    rm -rf "$tree/node_modules/@esbuild/linux-x64" "$tree/node_modules/@esbuild/win32-x64"
    cp -a "$esb" "$tree/node_modules/@esbuild/linux-x64"
  else
    warn "官方 deb 里没有 @esbuild/linux-x64，跳过"
  fi

  # 清掉 Windows 专属原生模块（Linux 永远不会加载）
  rm -rf "$tree/node_modules/@koromix/koffi-win32-x64"
  rm -f "$tree/node_modules/@electron-internal/extract-zip/"index.win32-*.node

  rm -f "$RES/app.asar"
  rm -rf "$RES/app.asar.unpacked"
  # .node 与 esbuild 二进制不能留在 asar 里（无法 dlopen/exec），解到 app.asar.unpacked
  asar pack "$tree" "$RES/app.asar" \
    --unpack-dir "node_modules/@esbuild" \
    --unpack "**/*.node" || die "asar pack 失败"
  rm -rf "$tree"
  log "   app.asar 已重打包（Linux 补丁 + @esbuild/linux-x64）"
}

# 官方 deb 自带 hicolor 全尺寸图标（raccoon-ai.png 16~1024）
gen_icons() {
  local h="$OFFICIAL_TREE/usr/share/icons/hicolor"
  if [ -d "$h" ]; then
    mkdir -p "$STAGE/usr/share/icons"
    rm -rf "$STAGE/usr/share/icons/hicolor"
    cp -a "$h" "$STAGE/usr/share/icons/"
    # 1.2.2 起官方只带 1024x1024；补齐常用尺寸（桌面缩放 + verify 断言 256x256）
    local src="$h/1024x1024/apps/$BIN_NAME.png" size dst
    if [ -f "$src" ]; then
      for size in 16 24 32 48 64 128 256 512; do
        dst="$STAGE/usr/share/icons/hicolor/${size}x${size}/apps"
        [ -f "$dst/$BIN_NAME.png" ] && continue
        mkdir -p "$dst"
        run_clean convert "$src" -resize "${size}x${size}" "$dst/$BIN_NAME.png"
      done
    fi
  else
    warn "官方 deb 无 hicolor 图标，跳过"
  fi
}

# 启动包装器：排除会破坏 Electron GPU/沙箱的环境变量
write_launcher() {
  cat > "$STAGE/usr/bin/$BIN_NAME" <<EOF
#!/bin/bash
# 商汤小浣熊 Linux 启动包装器
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
Name=Raccoon Work
Name[zh_CN]=商汤小浣熊
Exec=/usr/bin/$BIN_NAME %U
Terminal=false
Type=Application
Icon=$BIN_NAME
StartupWMClass=$BIN_NAME
MimeType=x-scheme-handler/office-raccoon;x-scheme-handler/raccoon-work;
Categories=Utility;
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
License: unknown
Vendor: Raccoon Team <xiaohuanxiong@sensetime.com>
Architecture: amd64
Maintainer: wxd <wxd@local>
Installed-Size: $size
Depends: libgtk-3-0, libnotify4, libnss3, libxss1, libxtst6, xdg-utils, libatspi2.0-0, libuuid1, libsecret-1-0
Recommends: libayatana-appindicator3-1 | libappindicator3-1
Section: utils
Priority: optional
Homepage: https://xiaohuanxiong.com
Description: Raccoon Work (商汤小浣熊) — Linux port of the Windows build
 商汤小浣熊桌面客户端，从 Windows 安装包移植到 Linux。
 复用官方 app.asar 业务逻辑 + Linux Electron 运行时，自包含安装到
 /opt/office-raccoon，可用 dpkg/apt 升级。升级检测始终按 Windows 版本。
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
