#!/bin/bash
# patch-update-saveas.sh — 更新包改为「点下载 → 询问保存路径 → 下载到所选路径」
#
# 用法: patch-update-saveas.sh <asar解包目录>
# 目标: dist/electron/client-main.cjs 的 downloadUpdate()，1 处整函数替换。
#
# 为什么: feed 是 Windows 安装包（.exe），Linux 上自动下载/自动安装毫无意义；
# 移植流程需要的是把 Windows 官方包存到指定位置，再用 build-deb.sh 手工移植。
# 交互: 点「下载」→ showSaveDialog 选路径 → electron-updater 下载校验 →
#       移动/复制到所选路径 → 弹框告知保存位置，状态回到 available（不进安装流）。
set -euo pipefail

TREE="${1:?用法: patch-update-saveas.sh <asar解包目录>}"
F="$TREE/dist/electron/client-main.cjs"
[ -f "$F" ] || { echo "错误: 找不到 $F" >&2; exit 1; }

python3 - "$F" <<'PY'
import io, sys

path = sys.argv[1]
src = io.open(path, encoding="utf-8").read()

OLD = """  async function downloadUpdate() {
    if (downloadInFlight) return downloadInFlight;
    if (status.state !== "available") {
      return { ok: false, status: snapshot(), error: "No update is ready to download" };
    }
    update({ state: "downloading", progress: null, error: null, errorPhase: null });
    downloadInFlight = import_electron_updater.autoUpdater.downloadUpdate().then(() => ({ ok: true, status: snapshot() })).catch((error) => {
      import_electron_log3.default.error("[app-update] download failed", error);
      if (status.state !== "error") fail2(error);
      return { ok: false, status: snapshot(), error: errorText(error) };
    }).finally(() => {
      downloadInFlight = null;
    });
    return downloadInFlight;
  }"""

NEW = """  async function downloadUpdate() {
    if (downloadInFlight) return downloadInFlight;
    if (status.state !== "available") {
      return { ok: false, status: snapshot(), error: "No update is ready to download" };
    }
    const save = await import_electron9.dialog.showSaveDialog({
      title: "保存更新包",
      defaultPath: `商汤小浣熊-${status.updateVersion || ""}-x64.exe`,
      filters: [{ name: "Windows 安装包", extensions: ["exe"] }]
    });
    if (save.canceled || !save.filePath) {
      return { ok: false, status: snapshot(), error: "已取消保存" };
    }
    update({ state: "downloading", progress: null, error: null, errorPhase: null });
    downloadInFlight = import_electron_updater.autoUpdater.downloadUpdate().then(async (saved) => {
      const fs = require("node:fs");
      const src = Array.isArray(saved) && saved.length ? saved[0] : null;
      if (src && src !== save.filePath) {
        try {
          fs.renameSync(src, save.filePath);
        } catch (e) {
          fs.copyFileSync(src, save.filePath);
        }
      }
      update({ state: "available", downloadedAt: null, progress: null });
      import_electron_log3.default.info("[app-update] update package saved", save.filePath);
      await import_electron9.dialog.showMessageBox({
        type: "info",
        title: "更新包已保存",
        message: `更新包已保存到：\n${save.filePath}`
      });
      return { ok: true, status: snapshot() };
    }).catch((error) => {
      import_electron_log3.default.error("[app-update] download failed", error);
      if (status.state === "error") {} else { fail2(error); }
      return { ok: false, status: snapshot(), error: errorText(error) };
    }).finally(() => {
      downloadInFlight = null;
    });
    return downloadInFlight;
  }"""

n = src.count(OLD)
if n != 1:
    print(f"错误: 目标片段出现 {n} 次（应为 1 次），中止", file=sys.stderr)
    sys.exit(2)
src = src.replace(OLD, NEW, 1)
io.open(path, "w", encoding="utf-8").write(src)
print("patch-update-saveas: 已打 1 处补丁 ->", path)
PY
