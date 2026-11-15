#!/usr/bin/env bash
# scripts/lib.sh — 构建辅助函数（raccoon-porting / loomy-porting / scnet-porting 共享约定）。
# 仅供 source，不单独执行。

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

need() { # need <cmd...> — 缺任一命令即退出
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "缺少命令：$c（见 PORTING.md「构建依赖」）"
  done
}

run_clean() { # run_clean <cmd...> — 清掉打包器注入的环境变量再执行
  # LD_LIBRARY_PATH 里的 libstdc++ 缺 GPU 符号，且会污染 dpkg-deb（liblzma）
  env -u LD_LIBRARY_PATH -u LIBGL_DRIVERS_PATH -u TMPDIR "$@"
}

fetch() { # fetch <url> <out>
  curl -fSL --retry 3 -o "$2" "$1" || die "下载失败：$1"
}

# fetch_electron_zip <version> — 下载 electron-v<ver>-linux-x64.zip 到 .cache/
# 镜像：npmmirror → huaweicloud → github；无论 zip 来自哪个镜像，
# 一律用 github 官方 SHASUMS256.txt 做 sha256 校验后才可用。
fetch_electron_zip() {
  local ver="$1" name="electron-v${ver}-linux-x64"
  local zip="$ROOT/.cache/$name.zip"
  local sums="$ROOT/.cache/SHASUMS256-$ver.txt"
  local base
  mkdir -p "$ROOT/.cache"
  for base in \
    "https://npmmirror.com/mirrors/electron/$ver" \
    "https://mirrors.huaweicloud.com/electron/$ver" \
    "https://github.com/electron/electron/releases/download/v$ver"; do
    log "下载 $name.zip ← $base"
    if fetch "$base/$name.zip" "$zip" 2>/dev/null; then
      fetch "https://github.com/electron/electron/releases/download/v$ver/SHASUMS256.txt" "$sums"
      (cd "$ROOT/.cache" && grep " $name\\.zip\$" "$sums" | sha256sum -c -) \
        || die "SHASUMS256 校验失败：$name.zip"
      return 0
    fi
    warn "镜像不可用：$base"
  done
  die "无法下载 $name.zip；可手动放置到 $zip 后重试"
}

# prepare_electron <version> <dest> — Electron Linux 运行时就位到 <dest>（stock 布局，二进制名 electron）
# 顺序：已解包缓存 .cache/electron-v<ver>-linux-x64/ → 本地 zip → 镜像下载 + SHASUMS256 校验
prepare_electron() {
  local ver="$1" dest="$2"
  local name="electron-v${ver}-linux-x64"
  local cachedir="$ROOT/.cache/$name"
  local zip="$ROOT/.cache/$name.zip"
  mkdir -p "$dest"
  if [ -x "$cachedir/electron" ]; then
    log "Electron $ver：使用已解包缓存 $cachedir"
    cp -a "$cachedir/." "$dest/"
    return 0
  fi
  [ -f "$zip" ] || fetch_electron_zip "$ver"
  log "Electron $ver：解包 $zip"
  unzip -qo "$zip" -d "$dest"
  [ -x "$dest/electron" ] || die "解包后缺少 $dest/electron"
}
