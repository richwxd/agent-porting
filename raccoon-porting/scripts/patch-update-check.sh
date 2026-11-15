#!/bin/bash
# patch-update-check.sh — 升级检测始终按 Windows 版本（Linux 移植必打补丁）
#
# 用法: patch-update-check.sh <asar解包目录>
# 目标: dist/electron/client-main.cjs，4 处定点替换，每处断言唯一出现。
#
# 为什么必须打（Linux 直接跑原版的行为）：
#   1) 版本策略接口 /api/web/client/v1/version_policy 带 platform=linux，
#      服务端不认 → 报「请求参数错误」，升级提示永远出不来。
#   2) electron-updater 按平台挑更新器：Linux 走 AppImageUpdater，
#      非 AppImage 环境 isUpdaterActive()=false → checkForUpdates() 被静默跳过；
#      即便能跑，它找 latest-linux.yml，而 Windows feed 上只有 latest.yml。
#   3) feed 是 Windows 安装包（.exe），自动下载纯属浪费流量。
#   4) provider 的 platform=linux → 通道名变 latest-linux.yml，Windows feed 上没有 → 404。
set -euo pipefail

TREE="${1:?用法: patch-update-check.sh <asar解包目录>}"
F="$TREE/dist/electron/client-main.cjs"
[ -f "$F" ] || { echo "错误: 找不到 $F" >&2; exit 1; }

python3 - "$F" <<'PY'
import io, sys

path = sys.argv[1]
src = io.open(path, encoding="utf-8").read()

REPLACEMENTS = [
    (
        # 版本策略客户端固定按 Windows 上报
        'const policyClient = createVersionPolicyClient({\n'
        '    environment: process.env,\n'
        '    platform: process.platform,\n',
        'const policyClient = createVersionPolicyClient({\n'
        '    environment: process.env,\n'
        '    platform: "win32",\n',
    ),
    (
        # 更新器：Linux 也用 Windows 的 NsisUpdater（读 latest.yml / Windows feed）
        'function doLoadAutoUpdater() {\n'
        '      if (process.platform === "win32") {\n',
        'function doLoadAutoUpdater() {\n'
        '      if (process.platform === "win32" || process.platform === "linux") {\n',
    ),
    (
        # 关闭自动下载：feed 是 Windows 安装包，Linux 上下载了也装不了
        'let autoDownloadEnabled = options.getAutoDownloadEnabled?.() !== false;\n',
        'let autoDownloadEnabled = false; // Linux port: feed 是 Windows 安装包，不自动下载\n',
    ),
    (
        # provider 的 platform 固定 win32：否则 getChannelFilePrefix() 返回 "-linux"，
        # 去请求 Windows feed 上不存在的 latest-linux.yml → 404，检查必失败
        'platform: this._testOnlyOptions == null ? process.platform : this._testOnlyOptions.platform,\n',
        'platform: this._testOnlyOptions == null ? "win32" : this._testOnlyOptions.platform,\n',
    ),
]

for old, new in REPLACEMENTS:
    n = src.count(old)
    if n != 1:
        print(f"错误: 目标片段出现 {n} 次（应为 1 次），中止:\n{old[:120]!r}", file=sys.stderr)
        sys.exit(2)
    src = src.replace(old, new, 1)

io.open(path, "w", encoding="utf-8").write(src)
print(f"patch-update-check: 已打 {len(REPLACEMENTS)} 处补丁 -> {path}")
PY
