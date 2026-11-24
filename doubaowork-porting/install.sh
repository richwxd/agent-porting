#!/bin/bash
# install.sh — 豆包工作（DoubaoWork）用户级安装
#
# 只写 ~/.local/share/doubaowork 与 ~/.local/share/applications，不碰 /opt、/usr。
# 安装器跑在 WINEPREFIX 内（per-user），程序落到 %LOCALAPPDATA%\DoubaoWork。
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$PROJECT/scripts/lib.sh"

usage() {
  cat <<'EOF'
用法: ./install.sh [选项]

  --seed DIR        从已安装的 DoubaoWork 目录（含 Application/app）复制安装树
  --zip FILE        从 DoubaoWork.zip（Windows 绿色/安装目录打包）解出并安装
  --installer EXE   用官方在线安装器安装（需要点“立即安装”）
  --provision-pwsh ZIP
                    把给定 PowerShell win-x64 zip 装进应用自带的 sandbox 运行时
                    （应用首次使用本地运行时后才有 bases/*/pwsh；应用自带 net10，对应 7.6 LTS）
  --wine NAME       指定 wine 命令（默认自动探测系统 wine，需要 11+）
  --no-desktop      不写 ~/.local/share/applications/doubaowork.desktop
  --force           覆盖已有安装树
  --check           只做体检，不安装
  -h, --help        显示帮助

默认安装根目录: ~/.local/share/doubaowork（可用 DOUBAOWORK_HOME 覆盖）
EOF
}

SEED=""; ZIPF=""; INSTALLER=""; FORCE=0; NO_DESKTOP=0; CHECK_ONLY=0; PROVISION_PWSH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --seed)      SEED="${2:-}"; shift ;;
    --zip)       ZIPF="${2:-}"; shift ;;
    --installer) INSTALLER="${2:-}"; shift ;;
    --provision-pwsh) PROVISION_PWSH="${2:-}"; shift ;;
    --wine)      export DOUBAOWORK_WINE="${2:-}"; shift ;;
    --no-desktop) NO_DESKTOP=1 ;;
    --force)     FORCE=1 ;;
    --check)     CHECK_ONLY=1 ;;
    -h|--help)   usage; exit 0 ;;
    *) die "未知参数：$1（--help 查看用法）" ;;
  esac
  shift
done

need python3

pwsh_dirs() {
  # 只匹配 bases/<hash>/pwsh/pwsh.exe，避免把 pwsh.bak-* 备份目录也算进去
  find "$WIN_DIR/User Data/sandbox_runtime/bases" -maxdepth 3 -type f -path '*/pwsh/pwsh.exe' 2>/dev/null
}

pwsh_probe() {   # pwsh_probe <pwsh.exe> -> 0 可用
  local exe="$1" probe=/tmp/doubaowork-pwsh-probe.txt w
  w="$(wine_exec 2>/dev/null)" || return 1
  rm -f "$probe"
  WINEPREFIX="$PREFIX" WINEDEBUG=-all timeout 30 "$w" "$exe" -NoProfile -NonInteractive \
    -Command "Set-Content -Path 'Z:\tmp\doubaowork-pwsh-probe.txt' -Value ok" >/dev/null 2>&1 || true
  [ -s "$probe" ]
}

pwsh_status() {
  local exe any=0
  while IFS= read -r exe; do
    [ -f "$exe" ] || continue
    any=1
    if pwsh_probe "$exe"; then printf '可用（%s）' "$(dirname "$exe")"; return 0; fi
  done < <(pwsh_dirs)
  [ "$any" = 1 ] && { printf '不可用（.NET 在 Wine 11 下无法启动，见 PORTING.md 第十一节）'; return 1; }
  printf '未准备（应用首次使用本地运行时后才会生成）'; return 2
}

provision_pwsh() {
  local zip="$1" tmp exe d
  [ -f "$zip" ] || die "zip 不存在：$zip"
  need unzip
  tmp="$(mktemp -d)"
  unzip -q "$zip" -d "$tmp" || die "解压失败：$zip"
  [ -f "$tmp/pwsh.exe" ] || die "zip 根目录缺少 pwsh.exe（要 PowerShell win-x64 包）"
  local n=0
  while IFS= read -r exe; do
    [ -f "$exe" ] || continue
    d="$(dirname "$exe")"
    mv "$d" "$d.bak-$(date +%s)" || die "备份失败：$d"
    mkdir -p "$d"
    cp -a "$tmp/." "$d/" || die "复制失败：$d"
    log "已替换运行时：$d"
    n=$((n+1))
  done < <(pwsh_dirs)
  rm_rf "$tmp"
  [ "$n" -gt 0 ] || warn "没有找到 bases/*/pwsh，先启动一次应用再执行"
}

doctor() {
  log "安装根目录: $HOME_ROOT"
  log "WINEPREFIX:   $PREFIX"
  log "wine:         $(wine_exec 2>/dev/null || echo '未找到')"
  if [ -f "$PAYLOAD_DIR/DoubaoWork.exe" ]; then
    log "应用:         $(app_version 2>/dev/null || echo '版本未知')  ($PAYLOAD_DIR)"
  else
    warn "应用未安装：$PAYLOAD_DIR"
  fi
  [ -f "$HOME_ROOT/bin/doubaowork" ] && log "启动器:       $HOME_ROOT/bin/doubaowork"
  [ -f "$DESKTOP_DIR/doubaowork.desktop" ] && log "桌面入口:     $DESKTOP_DIR/doubaowork.desktop"
  local st="$HOME_ROOT/updates"
  [ -d "$st" ] && log "更新缓存：     $st"
  log "本地 pwsh:    $(pwsh_status || true)"
  return 0
}

init_prefix() {
  [ -d "$PREFIX" ] && return 0
  log "初始化 WINEPREFIX（$PREFIX）"
  local w wb
  w="$(wine_exec)" || die "未找到 wine（可用 --wine 指定）"
  wb="$(dirname "$w")/wineboot"
  [ -x "$wb" ] || wb="wineboot"
  WINEPREFIX="$PREFIX" WINEDEBUG=-all WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=}" \
    "$wb" -u >/dev/null 2>&1 || warn "wineboot 返回非零（继续）"
}

copy_tree() {
  local src="$1"
  [ -f "$src/Application/app/DoubaoWork.exe" ] || die "seed 目录缺少 Application/app/DoubaoWork.exe：$src"
  mkdir -p "$WIN_DIR"
  if [ -n "$(ls -A "$WIN_DIR" 2>/dev/null)" ] && [ "$FORCE" != 1 ]; then
    die "目标已存在内容：$WIN_DIR（加 --force 覆盖）"
  fi
  log "复制安装树：$src/Application → $WIN_DIR/Application"
  mkdir -p "$WIN_DIR"
  local aside=""
  if [ -e "$WIN_DIR/Application" ]; then
    [ "$FORCE" = 1 ] || die "目标已存在：$WIN_DIR/Application（加 --force 覆盖）"
    aside="$WIN_DIR/Application.replaced-$(date +%s)"
    mv "$WIN_DIR/Application" "$aside"
  fi
  if ! cp -a --reflink=auto "$src/Application" "$WIN_DIR/Application" 2>/dev/null; then
    cp -a "$src/Application" "$WIN_DIR/Application" || die "复制失败"
  fi
  [ -n "$aside" ] && rm_rf "$aside"
  mkdir -p "$WIN_DIR/User Data"
}

install_from_zip() {
  local zip="$1" stage="$PROJECT/.migrate/seed"
  need unzip
  [ -f "$zip" ] || die "zip 不存在：$zip"
  log "解压 zip 到 $stage"
  rm_rf "$stage"; mkdir -p "$stage"
  unzip -q "$zip" -d "$stage"
  local root
  root="$(python3 - "$stage" <<'PY'
import os, sys
for dirpath, dirnames, _ in os.walk(sys.argv[1]):
    if os.path.basename(dirpath) == "Application" and os.path.isdir(os.path.join(dirpath, "app")):
        print(os.path.dirname(dirpath)); raise SystemExit
raise SystemExit("zip 内未找到 Application/app")
PY
)" || die "zip 内未找到 Application/app"
  copy_tree "$root"
}

install_from_installer() {
  local exe="$1"
  [ -f "$exe" ] || die "安装器不存在：$exe"
  exe="$(readlink -f "$exe")"
  log "启动官方在线安装器（在窗口里点“立即安装”；约 805 MB 下载，视网络 10–30 分钟）"
  WINEPREFIX="$PREFIX" WINEDEBUG=-all WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=}" \
    "$(wine_exec)" "$exe" &
  local pid=$! i
  for i in $(seq 1 120); do
    [ -f "$PAYLOAD_DIR/DoubaoWork.exe" ] && { sleep 3; break; }
    sleep 20
  done
  wait "$pid" 2>/dev/null || true
  [ -f "$PAYLOAD_DIR/DoubaoWork.exe" ] || die "安装器未完成（未出现 $PAYLOAD_DIR/DoubaoWork.exe）"
}

write_registry() {
  local ver="$1" w
  w="$(wine_exec)" || return 0
  WINEPREFIX="$PREFIX" WINEDEBUG=-all "$w" reg add 'HKCU\Software\DoubaoWork' /f \
      /v InstallDir /d 'C:\users\%USERNAME%\AppData\Local\DoubaoWork\Application\' >/dev/null 2>&1 || true
  WINEPREFIX="$PREFIX" WINEDEBUG=-all "$w" reg add 'HKCU\Software\DoubaoWork' /f /v Version /d "$ver" >/dev/null 2>&1 || true
  WINEPREFIX="$PREFIX" WINEDEBUG=-all "$w" reg add 'HKCU\Software\DoubaoWork' /f /v ExeFileName /d 'DoubaoWork.exe' >/dev/null 2>&1 || true
  WINEPREFIX="$PREFIX" WINEDEBUG=-all "$w" reg add 'HKCU\Software\DoubaoWork' /f \
      /v DataDir /d 'C:\users\%USERNAME%\AppData\Local\DoubaoWork\User Data' >/dev/null 2>&1 || true
}

write_icon() {
  mkdir -p "$ICON_DIR"
  local src="$APP_DIR/app/icon.ico"
  [ -f "$src" ] || src="$APP_DIR/icon.ico"
  if [ -f "$src" ] && command -v convert >/dev/null 2>&1 && command -v identify >/dev/null 2>&1; then
    local idx
    idx="$(identify -format '%w %s\n' "$src" 2>/dev/null | sort -rn | head -n1 | awk '{print $2}')"
    [ -n "$idx" ] || idx=0
    if convert "${src}[$idx]" -resize 256x256 "$ICON_DIR/doubaowork.png" 2>/dev/null; then
      return 0
    fi
  fi
  for p in "$APP_DIR/app/Logo.png" "$APP_DIR/app/SmallLogo.png"; do
    [ -f "$p" ] && { cp -f "$p" "$ICON_DIR/doubaowork.png"; return 0; }
  done
  warn "未找到可用图标（桌面入口仍可用）"
}

write_desktop() {
  [ "$NO_DESKTOP" = 1 ] && return 0
  mkdir -p "$DESKTOP_DIR"
  sed -e "s|@BIN@|$BIN_DIR|g" -e "s|@ICON@|$ICON_DIR/doubaowork.png|g" \
    "$PROJECT/scripts/doubaowork.desktop.in" > "$DESKTOP_DIR/doubaowork.desktop"
  chmod 644 "$DESKTOP_DIR/doubaowork.desktop"
  command -v update-desktop-database >/dev/null 2>&1 \
    && update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
}

write_state() {
  local ver="$1" src="$2"
  python3 - "$STATE_FILE" "$ver" "$src" "$HOME_ROOT" "$(wine_exec 2>/dev/null || echo '')" <<'PY'
import json, sys, time
path, ver, src, root, wine = sys.argv[1:6]
json.dump({"app": "doubaowork", "display": "豆包工作", "version": ver, "source": src,
           "home": root, "wine": wine, "installed_at": time.strftime("%Y-%m-%dT%H:%M:%S")},
          open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
}

if [ "$CHECK_ONLY" = 1 ]; then doctor; exit 0; fi

if [ -n "$PROVISION_PWSH" ]; then provision_pwsh "$PROVISION_PWSH"; fi

log "1/6 安装脚本本体"
mkdir -p "$HOME_ROOT" "$BIN_DIR"
install -m 755 "$PROJECT/scripts/lib.sh" "$HOME_ROOT/lib.sh"
install -m 755 "$PROJECT/scripts/doubaowork" "$BIN_DIR/doubaowork"
install -m 755 "$PROJECT/scripts/doubaowork-update" "$BIN_DIR/doubaowork-update"

log "2/6 准备 WINEPREFIX"
init_prefix

log "3/6 安装应用树"
INSTALL_SOURCE="existing"
if [ -f "$PAYLOAD_DIR/DoubaoWork.exe" ] && [ "$FORCE" != 1 ]; then
  log "已检测到安装，复用：$PAYLOAD_DIR"
else
  if [ -n "$SEED" ]; then
    INSTALL_SOURCE="seed"
    copy_tree "$SEED"
  elif [ -n "$ZIPF" ]; then
    INSTALL_SOURCE="zip"
    install_from_zip "$ZIPF"
  else
    [ -n "$INSTALLER" ] || INSTALLER="$PROJECT/win/DoubaoWork_online_installer_2.36.15.exe"
    [ -f "$INSTALLER" ] || INSTALLER="$(ls "$PROJECT"/win/DoubaoWork_online_installer_*.exe 2>/dev/null | tail -1 || true)"
    [ -n "$INSTALLER" ] || die "没有可用的安装来源：给 --seed / --zip / --installer"
    INSTALL_SOURCE="installer"
    install_from_installer "$INSTALLER"
  fi
fi

VER="$(app_version)" || die "无法读取版本（$MANIFEST）"
log "4/6 安装版本：$VER"

log "5/6 注册表 / 图标 / 桌面入口"
write_registry "$VER"
write_icon
write_desktop

log "6/6 记录状态"
write_state "$VER" "$INSTALL_SOURCE"

doctor
cat <<EOF

安装完成。启动方式：
  $BIN_DIR/doubaowork
  或从应用菜单打开「豆包工作」

检查更新：
  $BIN_DIR/doubaowork --check-update
  $BIN_DIR/doubaowork-update --apply

卸载（保留用户数据可加 --keep-data）：
  $PROJECT/uninstall.sh
EOF
