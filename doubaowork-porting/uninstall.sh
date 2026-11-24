#!/bin/bash
# uninstall.sh — 用户级卸载（不涉及 root、/opt、/usr）
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$PROJECT/scripts/lib.sh"

KEEP_DATA=0; ASSUME_YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --keep-data) KEEP_DATA=1 ;;
    -y|--yes)    ASSUME_YES=1 ;;
    -h|--help)   sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
  shift
done

[ -d "$HOME_ROOT" ] || { log "未安装：$HOME_ROOT"; exit 0; }

if [ "$ASSUME_YES" != 1 ]; then
  printf '将删除：%s\n' "$HOME_ROOT"
  [ "$KEEP_DATA" = 1 ] || printf '（含 WINEPREFIX 与用户数据）\n'
  printf '确认？[y/N] '
  read -r ans
  case "$ans" in y|Y|yes) ;; *) echo "已取消"; exit 0 ;; esac
fi

log "停止豆包工作"
ws="$(dirname "$(wine_exec 2>/dev/null || echo wine)")/wineserver"
[ -x "$ws" ] && WINEPREFIX="$PREFIX" "$ws" -k 2>/dev/null || true
sleep 1
for d in /proc/[0-9]*/cmdline; do
  if cat "$d" 2>/dev/null | tr '\0' ' ' | grep -qF 'DoubaoWork\Application'; then
    pid="${d#/proc/}"; pid="${pid%/cmdline}"
    kill -TERM "$pid" 2>/dev/null || true
  fi
done

log "删除桌面入口与图标"
rm -f "$DESKTOP_DIR/doubaowork.desktop"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
rm -f "$ICON_DIR/doubaowork.png"

if [ "$KEEP_DATA" = 1 ]; then
  log "保留用户数据：$PREFIX"
  rm_rf "$BIN_DIR" "$HOME_ROOT/share" "$HOME_ROOT/updates"
  rm -f "$HOME_ROOT/lib.sh" "$HOME_ROOT/state.json" "$HOME_ROOT/.update.lock"
else
  log "删除整个安装根目录：$HOME_ROOT"
  rm_rf "$HOME_ROOT"
fi

log "卸载完成"
