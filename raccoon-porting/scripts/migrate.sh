#!/bin/bash
# migrate.sh — 一键迁移：构建 → 校验 → 安装（输入放好，一条命令出结果）
#
# 输入（放好即可；缺失的依赖会自动下载补齐，需联网一次）：
#   win/商汤小浣熊-<版本>-x64.exe      必须，Windows NSIS 安装包
#   electron-v<版本>-linux-x64.zip     可选，放项目根目录或 .cache/（放了就用、不删除）
#   .cache/raccoon-linux-<版本>.deb    可选，官方 Linux deb（Linux 原生依赖来源）
#
# 用法：
#   ./scripts/migrate.sh               构建 + 校验 + dpkg 安装（覆盖升级）
#   ./scripts/migrate.sh --no-install  只构建 + 校验，不安装
#   ./scripts/migrate.sh --smoke       构建 + 校验 + 安装 + 冒烟（启动与升级检测日志）
set -euo pipefail
unset LD_LIBRARY_PATH LD_PRELOAD LD_AUDIT 2>/dev/null || true
cd "$(dirname "$0")/.."

INSTALL=1
SMOKE=0
for a in "$@"; do
  case "$a" in
    --no-install) INSTALL=0 ;;
    --smoke)      SMOKE=1 ;;
    -h|--help)    sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "未知参数: $a（支持 --no-install / --smoke）" >&2; exit 2 ;;
  esac
done

echo "==> 1/3 构建（版本号全部动态匹配 Windows 包）"
./scripts/build-deb.sh

echo "==> 2/3 校验（verify-deb.sh 断言）"
./scripts/verify-deb.sh

DEB="$(ls -t dist/raccoon-ai_*_amd64.deb | head -1)"
echo "==> 产物: $DEB"

if [ "$INSTALL" = 1 ]; then
  echo "==> 3/3 安装（prerm 关旧实例 → postinst 启动新实例）"
  sudo dpkg -i "$DEB"
  if [ "$SMOKE" = 1 ]; then
    ./scripts/smoke-test.sh
  else
    echo "✅ 完成。启动: raccoon-ai（或从应用菜单）"
  fi
else
  echo "==> 3/3 跳过安装（--no-install）"
  echo "手动安装: sudo dpkg -i $DEB"
fi
