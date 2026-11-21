#!/usr/bin/env node
// patch-linux-window-icon.cjs — 给 Linux 窗口设置真实应用图标
//
// Electron 在 Linux 上如果 BrowserWindow 没有 icon，窗口就没有 _NET_WM_ICON；
// Wayland 下 KDE 会按 app_id / StartupWMClass 查找 .desktop 的 Icon。
// 这里统一注入 512x512 的 minimax-code.png，保证标题栏、任务栏、Alt-Tab 一致。
const fs = require('node:fs');
const path = require('node:path');

const root = process.argv[2];
if (!root) {
  console.error('用法: node patch-linux-window-icon.cjs <app.asar 解包目录>');
  process.exit(1);
}

const file = path.join(root, 'dist/main/windows/desktopRendererWindow.js');
const before = `    const window = new electron_1.BrowserWindow({
        ...options,
        webPreferences: {`;
const after = `    const window = new electron_1.BrowserWindow({
        ...options,
        ...(process.platform === 'linux'
            ? { icon: electron_1.nativeImage.createFromPath(process.resourcesPath + '/../minimax-code.png') }
            : {}),
        webPreferences: {`;

let source = fs.readFileSync(file, 'utf8');
if (source.includes('minimax-code.png')) {
  console.log('  SKIP dist/main/windows/desktopRendererWindow.js: Linux 窗口图标（已打）');
  process.exit(0);
}
if (!source.includes(before)) {
  console.error('  错误: desktopRendererWindow.js 中未找到 BrowserWindow 目标片段');
  process.exit(2);
}
source = source.replace(before, after);
fs.writeFileSync(file, source);
console.log('  OK   dist/main/windows/desktopRendererWindow.js: Linux 窗口注入应用图标');
