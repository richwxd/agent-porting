#!/bin/bash
# patch-quit-timeout-linux.sh — Linux 托盘/窗口"退出"挂起兜底：清理超时强制退出
#
# 用法: patch-quit-timeout-linux.sh <asar解包目录>
# 目标: dist/electron/client-main.cjs，1 处定点替换（quit() 加超时兜底）。
#
# 为什么必须打：
#   * 托盘"退出"（click: () => app.quit()）→ beforeQuit 拦截 → shutdown.quit()
#     → await close()。Linux 下 createClientShutdown 的 close() 走 !bounded 分支，
#     无超时（SHUTDOWN_TIMEOUT_MS 只用于 win32/darwin）。
#   * options.close() 串行清理资源，其中一个（实测 agent-host 的 host.close()）
#     永不 resolve → close() 永不完成 → quit() 的 .then 永不执行 → options.quit()
#     永不调用 → app.quit() 永不真正执行 → 进程不退出（实测日志停在
#     "cleanup started { resource: 'agent-host' }"，PID 仍存活）。
#   * 本补丁在 quit() 启动清理后设一个 2s 兜底定时器：若清理挂起（quitAllowed 未置位），
#     options.forceQuit()（app.exit(0)）强制退出，保证"退出"一定生效。
#     正常路径不受影响：close() 完成后 clearTimeout。
#
# 行为（Linux，托盘"退出"或窗口关闭触发 app.quit() 时）：
#   * 清理正常完成 → 照常优雅退出（不触发兜底）
#   * 清理挂起 >2s → app.exit(0) 强制退出，不再留僵尸
set -euo pipefail

TREE="${1:?用法: patch-quit-timeout-linux.sh <asar解包目录>}"
F="$TREE/dist/electron/client-main.cjs"
[ -f "$F" ] || { echo "错误: 找不到 $F" >&2; exit 1; }

python3 - "$F" <<'PY'
import io, sys

path = sys.argv[1]
src = io.open(path, encoding="utf-8").read()

OLD = """    quitPending = true;
    void close().then(() => {
      quitAllowed = true;
      options.quit();
    }).catch((error) => {"""

NEW = """    quitPending = true;
    // Linux 兜底：close() 走 !bounded 分支无超时，若某个资源清理挂起（如
    // agent-host 的 host.close() 永不 resolve）则永不退出。设 2s 强制退出兜底。
    const quitForceTimer = setTimeout(() => {
      if (!quitAllowed) options.forceQuit();
    }, 2000);
    void close().then(() => {
      clearTimeout(quitForceTimer);
      quitAllowed = true;
      options.quit();
    }).catch((error) => {
      clearTimeout(quitForceTimer);
      if (!bounded) {
        quitPending = false;
        options.error(error);
        return;
      }"""

n = src.count(OLD)
if n != 1:
    print(f"错误: 目标片段出现 {n} 次（应为 1 次），中止:\n{OLD[:120]!r}", file=sys.stderr)
    sys.exit(2)
src = src.replace(OLD, NEW, 1)

io.open(path, "w", encoding="utf-8").write(src)
print(f"patch-quit-timeout-linux: 已打 1 处补丁 -> {path}")
PY
