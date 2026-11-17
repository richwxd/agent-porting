#!/bin/bash
# patch-workspace-open-linux.sh — Linux 修复"打开当前目录"卡死界面
#
# 用法: patch-workspace-open-linux.sh <asar解包目录>
# 目标（4 处 shell.openPath 的 await 调用，全部改为 fire-and-forget）：
#   1. build/electron/main/workspace/directoryOpeners.js    — openDirectoryWithOpener system 分支
#   2. build/electron/main/client/workspace/registerWorkspaceHandlers.js — "打开当前目录"按钮（open-task-workspace）
#   3. build/electron/main/client/bootstrap/registerRuntimeHandlers.js   — 渲染组件"打开目录"（open-runtime-directory）
#   4. build/electron/main/client/browser/embeddedBrowser.js            — 浏览器"在资源管理器中打开"（external）
#
# 为什么必须打：
#   * 这 4 处都是主进程 IPC handler / dispatch 内 `await electron.shell.openPath(path)`。
#   * 实测（Electron 41.0.1 / KDE Wayland）：shell.openPath() 的 Promise 在 Linux 上
#     永不 resolve（挂起）——内部经 xdg-open/gio 启动文件管理器后，resolve 依赖的
#     内部异步回调在 Wayland 下不触发。对照：shell.openExternal() 正常。
#   * 凡是 renderer 端 `await ipc.invoke(...)` 等待的 handler，openPath 挂起 →
#     IPC 不返回 → 前端 busy/loading 状态永不恢复 → 按钮/界面永久锁定（"禁止输入"）。
#     实测用户点「打开当前目录」→ 文件管理器弹出，但界面永久禁输入。
#   * 修复思路（用户要求）：这个功能本质是 dispatch——只要 dispatch 成功（把打开
#     文件管理器的请求发出去），界面就该立即恢复初始状态，**不该**把界面状态与
#     openPath 的 Promise 完成绑定。故改为 fire-and-forget：不 await shell.openPath，
#     dispatch 后立即返回成功（文件管理器在后台打开），界面立即恢复。
#     .catch(()=>{}) 吞掉可能的 reject，避免 unhandled rejection。
#   * 这 4 处全部在 IPC handler 内（renderer await），是锁界面的直接根因。
#     其余 openPath 调用点（workspace/file.js、runtimeProvisionController、
#     obsidianCliManager）在主进程内部流程，不直接锁前端，本补丁不动。
#
# 行为（Linux）：
#   * 点击"打开当前目录"/"在资源管理器中打开" → 立即返回（界面不卡），文件管理器在后台打开
set -euo pipefail

TREE="${1:?用法: patch-workspace-open-linux.sh <asar解包目录>}"

# ---------- 补丁 1：directoryOpeners.js（openDirectoryWithOpener system 分支）----------
F1="$TREE/build/electron/main/workspace/directoryOpeners.js"
[ -f "$F1" ] || { echo "错误: 找不到 $F1" >&2; exit 1; }

python3 - "$F1" <<'PY'
import io, sys

path = sys.argv[1]
src = io.open(path, encoding="utf-8").read()

OLD = (
    '            const error = await electron_1.shell.openPath(requestedPath);\n'
    '            return error ? { success: false, error } : { success: true };'
)
NEW = (
    '            // Linux: shell.openPath 在 KDE Wayland 下 Promise 永不 resolve（挂起）。\n'
    '            // 若 await 则 IPC 不返回、前端 S.busy 永不恢复、界面锁定。\n'
    '            // 改为 fire-and-forget：dispatch 成功即返回（文件管理器在后台打开），\n'
    '            // 界面立即恢复初始状态，不把界面状态与 openPath 完成绑定。\n'
    '            electron_1.shell.openPath(requestedPath).catch(() => {});\n'
    '            return { success: true };'
)

n = src.count(OLD)
if n != 1:
    print(f"错误: 目标片段出现 {n} 次（应为 1 次），中止:\n{OLD[:160]!r}", file=sys.stderr)
    sys.exit(2)
src = src.replace(OLD, NEW, 1)

io.open(path, "w", encoding="utf-8").write(src)
print(f"patch-workspace-open-linux: 补丁1 已打 -> {path}")
PY

# ---------- 补丁 2：registerWorkspaceHandlers.js（"打开当前目录"按钮 open-task-workspace）----------
F2="$TREE/build/electron/main/client/workspace/registerWorkspaceHandlers.js"
[ -f "$F2" ] || { echo "错误: 找不到 $F2" >&2; exit 1; }

python3 - "$F2" <<'PY'
import io, sys

path = sys.argv[1]
src = io.open(path, encoding="utf-8").read()

OLD = (
    '        await requireDirectory(directory);\n'
    '        const error = await electron_1.shell.openPath(directory);\n'
    '        if (error) {\n'
    '            // The folder may have disappeared while the OS was opening it.\n'
    '            await requireDirectory(directory);\n'
    '            throw new Error(\'打开工作目录失败\');\n'
    '        }\n'
)
NEW = (
    '        await requireDirectory(directory);\n'
    '        // Linux: shell.openPath 在 KDE Wayland 下 Promise 永不 resolve（挂起）。\n'
    '        // 若 await 则 IPC 不返回、前端 S 的 await t() 永不完成、u(!1) 不执行、\n'
    '        // 界面永久"禁止输入"。改为 fire-and-forget：dispatch 成功即返回，\n'
    '        // 文件管理器在后台打开，界面立即恢复。（目录已 requireDirectory 校验存在）\n'
    '        electron_1.shell.openPath(directory).catch(() => {});\n'
)

n = src.count(OLD)
if n != 1:
    print(f"错误: 目标片段出现 {n} 次（应为 1 次），中止:\n{OLD[:160]!r}", file=sys.stderr)
    sys.exit(2)
src = src.replace(OLD, NEW, 1)

io.open(path, "w", encoding="utf-8").write(src)
print(f"patch-workspace-open-linux: 补丁2 已打 -> {path}")
PY

# ---------- 补丁 3：registerRuntimeHandlers.js（渲染组件"打开目录" open-runtime-directory）----------
F3="$TREE/build/electron/main/client/bootstrap/registerRuntimeHandlers.js"
[ -f "$F3" ] || { echo "错误: 找不到 $F3" >&2; exit 1; }

python3 - "$F3" <<'PY'
import io, sys

path = sys.argv[1]
src = io.open(path, encoding="utf-8").read()

OLD = (
    '        const dir = (0, renderRuntimeManager_1.ensureRenderRuntimeDir)();\n'
    '        const error = await electron_1.shell.openPath(dir);\n'
    '        return error ? { ok: false, error, dir } : { ok: true, dir };'
)
NEW = (
    '        const dir = (0, renderRuntimeManager_1.ensureRenderRuntimeDir)();\n'
    '        // Linux: shell.openPath 在 KDE Wayland 下 Promise 永不 resolve（挂起）。\n'
    '        // 若 await 则 IPC 不返回、前端 busy 永不恢复。改 fire-and-forget：\n'
    '        // dispatch 成功即返回 ok，界面立即恢复。\n'
    '        electron_1.shell.openPath(dir).catch(() => {});\n'
    '        return { ok: true, dir };'
)

n = src.count(OLD)
if n != 1:
    print(f"错误: 目标片段出现 {n} 次（应为 1 次），中止:\n{OLD[:160]!r}", file=sys.stderr)
    sys.exit(2)
src = src.replace(OLD, NEW, 1)

io.open(path, "w", encoding="utf-8").write(src)
print(f"patch-workspace-open-linux: 补丁3 已打 -> {path}")
PY

# ---------- 补丁 4：embeddedBrowser.js（浏览器"在资源管理器中打开" external）----------
F4="$TREE/build/electron/main/client/browser/embeddedBrowser.js"
[ -f "$F4" ] || { echo "错误: 找不到 $F4" >&2; exit 1; }

python3 - "$F4" <<'PY'
import io, sys

path = sys.argv[1]
src = io.open(path, encoding="utf-8").read()

OLD = (
    '                const error = await electron_1.shell.openPath(entry.path);\n'
    '                if (error)\n'
    '                    throw new Error(\'BROWSER_EXTERNAL_FAILED\');\n'
    '                return;'
)
NEW = (
    '                // Linux: shell.openPath 在 KDE Wayland 下 Promise 永不 resolve（挂起）。\n'
    '                // 若 await 则 IPC 不返回、前端 busy 永不恢复。改 fire-and-forget：\n'
    '                // dispatch 成功即返回，界面立即恢复。\n'
    '                electron_1.shell.openPath(entry.path).catch(() => {});\n'
    '                return;'
)

n = src.count(OLD)
if n != 1:
    print(f"错误: 目标片段出现 {n} 次（应为 1 次），中止:\n{OLD[:160]!r}", file=sys.stderr)
    sys.exit(2)
src = src.replace(OLD, NEW, 1)

io.open(path, "w", encoding="utf-8").write(src)
print(f"patch-workspace-open-linux: 补丁4 已打 -> {path}")
PY

echo "patch-workspace-open-linux: 全部 4 处补丁完成"
