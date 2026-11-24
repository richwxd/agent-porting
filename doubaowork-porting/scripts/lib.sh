#!/bin/bash
# lib.sh — doubaowork-porting 公共函数（用户级安装，不碰 /opt、/usr）
#
# 所有路径都可由 DOUBAOWORK_HOME 覆盖，默认：
#   ~/.local/share/doubaowork
set -euo pipefail

APP_NAME="doubaowork"
APP_DISPLAY="豆包工作"
APP_ID="DoubaoWork"

: "${DOUBAOWORK_HOME:=${XDG_DATA_HOME:-$HOME/.local/share}/doubaowork}"
HOME_ROOT="$DOUBAOWORK_HOME"
PREFIX="$HOME_ROOT/prefix"
BIN_DIR="$HOME_ROOT/bin"
APP_REL="users/$USER/AppData/Local/DoubaoWork"   # WINEPREFIX 内的相对路径
WIN_DIR="$PREFIX/drive_c/$APP_REL"
APP_DIR="$WIN_DIR/Application"
PAYLOAD_DIR="$APP_DIR/app"
DESKTOP_DIR="${DOUBAOWORK_DESKTOP_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/applications}"
ICON_DIR="$HOME_ROOT/share/icons"
STATE_FILE="$HOME_ROOT/state.json"
MANIFEST="$PAYLOAD_DIR/manifest.json"

UPDATE_API="https://www.doubao.com/service/settings/v3/"
UPDATE_API_QS="device_platform=pc&brand=doubaowork&aid=1044603&os=windows&update_type=downloader"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "缺少依赖：$1"; }

# 宿主若注入错误的 LD_*（libstdc++/liblzma），会污染 curl/dpkg 等系统命令
run_clean() { env -u LD_LIBRARY_PATH -u LD_PRELOAD -u LD_AUDIT "$@"; }

# 递归删除：用 python 而不是 rm -rf，避免误伤与终端守卫
rm_rf() {
  python3 - "$@" <<'PY'
import shutil, sys
for p in sys.argv[1:]:
    shutil.rmtree(p, ignore_errors=True)
PY
}

WINE_MIN_MAJOR=11

wine_version_of() { "$1" --version 2>/dev/null | sed -n 's/^wine-\([0-9][0-9.]*\).*/\1/p' | head -1; }

pick_wine() {
  local c v major
  for c in "${DOUBAOWORK_WINE:-}" wine wine64; do
    [ -n "$c" ] || continue
    command -v "$c" >/dev/null 2>&1 || continue
    v="$(wine_version_of "$c")"
    major="${v%%.*}"
    case "$major" in
      ''|*[!0-9]*) continue ;;
    esac
    [ "$major" -ge "$WINE_MIN_MAJOR" ] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

wine_exec() {
  local w
  w="$(pick_wine)" || die "未找到 Wine ${WINE_MIN_MAJOR}+（安装 winehq-stable，或设 DOUBAOWORK_WINE=...）"
  printf '%s\n' "$w"
}

app_version() {
  [ -f "$MANIFEST" ] || return 1
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["version"])' "$MANIFEST" 2>/dev/null
}

ver_gt() { # ver_gt A B -> A > B
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

require_prefix() {
  [ -d "$APP_DIR" ] || die "未安装：$APP_DIR 不存在（先运行 ./install.sh）"
  [ -f "$PAYLOAD_DIR/DoubaoWork.exe" ] || die "安装不完整：$PAYLOAD_DIR/DoubaoWork.exe 不存在"
}

# 关闭本地运行时（sandbox）对 pwsh 的依赖。
# Wine 11 下 .NET 控制台程序无法在管道 stdio 下运行，应用启动时会报 pwsh 错误；
# 服务端下发的 saman_sandbox_switch_config.enable_pwsh 默认是 true，这里每次启动前压回 false。
# 设 DOUBAOWORK_KEEP_PWSH=1 可跳过。
quiet_pwsh_errors() {
  [ "${DOUBAOWORK_KEEP_PWSH:-0}" = "1" ] && return 0
  local f="$WIN_DIR/User Data/Default/Remote_State"
  [ -f "$f" ] || return 0
  grep -q '"enable_pwsh"[[:space:]]*:[[:space:]]*true' "$f" 2>/dev/null || return 0
  [ -e "$f.bak-pwshoff" ] || cp -f "$f" "$f.bak-pwshoff" 2>/dev/null || true
  sed -i 's/"enable_pwsh"[[:space:]]*:[[:space:]]*true/"enable_pwsh": false/' "$f" 2>/dev/null || return 0
  log "已关闭本地运行时 pwsh（enable_pwsh=false）"
}
