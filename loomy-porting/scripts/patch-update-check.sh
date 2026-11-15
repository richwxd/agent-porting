#!/bin/bash
# patch-update-check.sh — 修正 Linux 下“检查更新”报“请求参数错误”
#
# 根因：electron/update/update-check.js 的 normalizePlatform() 只映射
#   win32→windows、darwin→mac，Linux 原样传 platform=linux，讯飞服务端
#   只认 windows/mac，返回 code≠000000 → 前端弹“请求参数错误”。
#
# 改法：Linux 检查更新时把 platform 归一为 windows 拿到最新版本号，
#   并把下载地址指向 Windows 绿色版 zip（便于下载后本地重跑打包脚本升级）。
#
# 幂等：重复执行不会二次插入。用法：patch-update-check.sh <asar解包根目录>
set -euo pipefail

FILE="$1/electron/update/update-check.js"
[ -f "$FILE" ] || { echo "未找到 $FILE（先 asar extract）" >&2; exit 1; }

GREEN_URL='https://loomy.xunfei.cn/download'

if grep -q "LOOMY_LINUX_UPDATE_PATCH" "$FILE"; then
  echo "已打过补丁，跳过"
  exit 0
fi

python3 - "$FILE" "$GREEN_URL" <<'PY'
import sys, io
path, green = sys.argv[1], sys.argv[2]
src = io.open(path, encoding='utf-8').read()
orig = src

# 1) 顶部加绿色版地址常量
anchor = "const DEFAULT_ERROR_MESSAGE ="
assert anchor in src, "找不到常量区锚点"
const_block = (
    "// LOOMY_LINUX_UPDATE_PATCH: Linux 绿色版下载地址（Windows zip，用于本地打包升级）\n"
    f"const LOOMY_LINUX_GREEN_ZIP_URL = '{green}'\n"
    "const DEFAULT_ERROR_MESSAGE ="
)
src = src.replace(anchor, const_block, 1)

# 2) normalizePlatform：Linux → windows（让服务端能识别）
old_np = """function normalizePlatform(platform) {
  if (platform === 'win32') {
    return 'windows'
  }

  if (platform === 'darwin') {
    return 'mac'
  }

  return platform
}"""
new_np = """function normalizePlatform(platform) {
  if (platform === 'win32') {
    return 'windows'
  }

  if (platform === 'darwin') {
    return 'mac'
  }

  // LOOMY_LINUX_UPDATE_PATCH: 服务端无 linux 平台，用 windows 查最新版本号
  if (platform === 'linux') {
    return 'windows'
  }

  return platform
}"""
assert old_np in src, "normalizePlatform 与预期不符"
src = src.replace(old_np, new_np, 1)

# 3) successResult：Linux 下载地址指向绿色版 zip
old_dl = """  const downloadUrl = hasUpdate
    ? DEFAULT_DOWNLOAD_URL
    : ''"""
new_dl = """  // LOOMY_LINUX_UPDATE_PATCH: Linux 指向 Windows 绿色版 zip，供本地打包升级
  const downloadUrl = hasUpdate
    ? (process.platform === 'linux' ? LOOMY_LINUX_GREEN_ZIP_URL : DEFAULT_DOWNLOAD_URL)
    : ''"""
assert old_dl in src, "downloadUrl 与预期不符"
src = src.replace(old_dl, new_dl, 1)

assert src != orig
io.open(path, 'w', encoding='utf-8').write(src)
print("补丁写入完成：", path)
PY

echo "--- 关键改动预览 ---"
grep -n "LOOMY_LINUX_UPDATE_PATCH\|LOOMY_LINUX_GREEN_ZIP_URL\|=== 'linux'" "$FILE" || true
