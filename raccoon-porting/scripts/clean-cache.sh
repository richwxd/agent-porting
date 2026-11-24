#!/bin/bash
# clean-cache.sh — 构建后清理：删 .migrate（中间产物）+ .cache 下除 electron/ 以外的缓存
#
# 保留：.cache/electron/（版本化 Linux Electron 运行时缓存，下次同版本直接复用）
# 清除：.migrate/（winapp 解包树、stage、asar 临时目录）
#        .cache/ 内的官方 deb、pandoc 压缩包、旧布局解压目录等（下次构建按需重下）
#
# 用法: clean-cache.sh [--dry-run]
set -euo pipefail
unset LD_LIBRARY_PATH LD_PRELOAD LD_AUDIT 2>/dev/null || true
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DRY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "未知参数: $a（支持 --dry-run）" >&2; exit 2 ;;
  esac
done

log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }

removed=0
purge() {
  [ -e "$1" ] || return 0
  local sz
  sz="$(du -sh "$1" 2>/dev/null | cut -f1)"
  if [ "$DRY" = 1 ]; then
    log "[dry-run] 将删除 $1 ($sz)"
  else
    log "删除 $1 ($sz)"
    rm -rf "$1"
  fi
  removed=1
}

# .migrate：winapp 解包树 / stage / asar 临时目录，全部可从 win/ + .cache/electron 重建
purge "$ROOT/.migrate"

# .cache：只保留 electron/（版本化运行时缓存）
if [ -d "$ROOT/.cache" ]; then
  for e in "$ROOT/.cache"/* "$ROOT/.cache"/.[!.]*; do
    [ -e "$e" ] || continue
    [ "$(basename "$e")" = "electron" ] && continue
    purge "$e"
  done
fi

if [ "$removed" = 1 ]; then
  log "清理完成"
else
  log "缓存已是干净状态（.migrate 不存在，.cache 仅 electron/）"
fi
if [ -d "$ROOT/.cache/electron" ]; then
  log "保留: .cache/electron/（$(du -sh "$ROOT/.cache/electron" 2>/dev/null | cut -f1)）: $(ls "$ROOT/.cache/electron" | tr '\n' ' ')"
fi
