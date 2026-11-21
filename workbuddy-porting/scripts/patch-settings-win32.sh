#!/bin/bash
# patch-settings-win32.sh — 设置界面与官方 Windows 版对齐补丁（2 处定点替换）
# 用法: patch-settings-win32.sh <asar-extract-tree>
#
#  E 平台探测对齐: detectPlatform 尾部三元加 /Linux/→win32（navigator.platform=Linux x86_64
#     原判定 other → isWindows()=false → 智能体页电脑操控/浏览器操控、设备连接远程控制、
#     设置搜索索引、UserMenu 通知引导全被隐藏/错参；对齐 Windows 渲染）
#  F 安全中心本地 isHostWindows 含 linux → 运行时卡 nodejs/python/gitbash 与 Windows 一致
#     （只改 SecurityCenterPanel 本地函数；environment 共享模块 isHostWindows 不动——
#      其消费方 isWorkspacePathTooLong 是 Win 100 字符路径限制，翻转会误拒 Linux 长路径）
#  ceiling: G（CommandDetail 程序名 win32/unix 归一化=真实校验行为）、viewportPadding、
#     hostDefaultOpenPlatform 上报 win32（raccoon「Linux 走 win32 流」哲学）见 PORTING.md
set -euo pipefail

TREE=${1:?用法: patch-settings-win32.sh <asar-extract-tree>}
ASSETS="$TREE/renderer/assets"
[ -d "$ASSETS" ] || { echo "缺少 $ASSETS" >&2; exit 1; }

# 文件名带内容哈希，glob 前缀定位、恰 1 命中否则 FAIL
SYS=$(ls "$ASSETS"/system-platform-*.js 2>/dev/null || true)
SEC=$(ls "$ASSETS"/SecurityCenterPanel-*.js 2>/dev/null || true)
[ "$(echo "$SYS" | grep -c .)" = 1 ] || { echo "system-platform-*.js 命中非 1: $SYS" >&2; exit 1; }
[ "$(echo "$SEC" | grep -c .)" = 1 ] || { echo "SecurityCenterPanel-*.js 命中非 1: $SEC" >&2; exit 1; }

python3 - "$SYS" "$SEC" <<'PY'
import sys

sys_path, sec_path = sys.argv[1], sys.argv[2]
BT = chr(96)

# (file, old, new, tag)
REPLACEMENTS = [
    (sys_path,
     '/^Win/u.test(e)?' + BT + 'win32' + BT + ':' + BT + 'other' + BT + '}',
     '/^Win/u.test(e)||/Linux/u.test(e)?' + BT + 'win32' + BT + ':' + BT + 'other' + BT + '}',
     'E detectPlatform Linux→win32'),
    (sec_path,
     'function isHostWindows(){return getHostPlatform()===' + BT + 'win32' + BT + '}',
     'function isHostWindows(){return getHostPlatform()===' + BT + 'win32' + BT + '||getHostPlatform()===' + BT + 'linux' + BT + '}',
     'F 安全中心 isHostWindows 含 linux'),
]

cache = {}
for path, old, new, tag in REPLACEMENTS:
    if path not in cache:
        cache[path] = open(path, encoding='utf-8').read()
    src = cache[path]
    n_old, n_new = src.count(old), src.count(new)
    # 先查 new：新串不含旧串，但保持与 patch-update-check.sh 同幂等顺序
    if n_new >= 1:
        print(f'SKIP[{tag}] 已打过')
    elif n_old == 1:
        src = src.replace(old, new, 1)
        cache[path] = src
        print(f'OK  [{tag}] 1 处替换')
    else:
        print(f'FAIL[{tag}] 目标片段出现 {n_old} 次（期望 1）: {old[:60]}...')
        sys.exit(2)

for path, src in cache.items():
    open(path, 'w', encoding='utf-8').write(src)
print('2 处设置对齐补丁完成')
PY