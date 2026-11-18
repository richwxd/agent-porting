#!/bin/bash
# patch-update-check.sh — WorkBuddy 更新检查补丁（3 处定点替换）
# 用法: patch-update-check.sh <asar-extract-tree>
#
#  A 检查走 Windows 通道: getPlatformAssetId → win32-x64-user
#     （linux-x64-deb 通道只到 5.6.2，win32-x64-user 是 5.11.3 最新）
#  B available 带下载地址: url:l.url（feed json 含 url/sha256hash）
#  C 点击触发下载: openUpdateDestination 前把 officialDownloadUrl 换成 feed url
#     （linux-external-update-opener official-website 分支 openExternal(url) → 浏览器下载 .exe）
#  （已移除 D「强制5.11.2」：会恒报有更新误弹「发现新版本」；
#    现走诚实检查——5.11.3→feed 204「已是最新」；官方发 5.11.4 后 A/B/C 自动生效可点下载。）
set -euo pipefail

TREE="${1:?用法: patch-update-check.sh <asar-extract-tree>}"
LINUX="$TREE/main/update-service.linux.js"
BASE="$TREE/main/update-service.js"
[ -f "$LINUX" ] || { echo "缺少 $LINUX" >&2; exit 1; }
[ -f "$BASE" ] || { echo "缺少 $BASE" >&2; exit 1; }

python3 - "$LINUX" "$BASE" <<'PY'
import sys

linux_path, base_path = sys.argv[1], sys.argv[2]

# (file, old, new, tag)
REPLACEMENTS = [
    (linux_path,
     'getPlatformAssetId(){return this.target.platformAssetId}',
     'getPlatformAssetId(){return`win32-x64-user`}',
     'A 检查走 Windows 通道'),
    (linux_path,
     'releaseNotes:l.releaseNotes,action:',
     'releaseNotes:l.releaseNotes,url:l.url,action:',
     'B available 带 url'),
    (linux_path,
     'async openUpdateDestination(){',
     'async openUpdateDestination(){if(this.updateInfo&&this.updateInfo.url){this.externalOpener.options.officialDownloadUrl=this.updateInfo.url}',
     'C 点击用 feed url 下载'),
]

cache = {}
for path, old, new, tag in REPLACEMENTS:
    if path not in cache:
        cache[path] = open(path, encoding="utf-8").read()
    src = cache[path]
    n_old, n_new = src.count(old), src.count(new)
    # 先查 new：C 的 old 是 new 的前缀，重跑时 n_old 仍为 1，须先判已打过
    if n_new >= 1:
        print(f"SKIP[{tag}] 已打过")
    elif n_old == 1:
        src = src.replace(old, new, 1)
        cache[path] = src
        print(f"OK  [{tag}] 1 处替换")
    else:
        print(f"FAIL[{tag}] 目标片段出现 {n_old} 次（期望 1）: {old[:60]}...")
        sys.exit(2)

for path, src in cache.items():
    open(path, "w", encoding="utf-8").write(src)
print("3 处更新补丁完成")
PY
