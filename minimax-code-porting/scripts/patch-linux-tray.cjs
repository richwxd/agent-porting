#!/usr/bin/env node
// patch-linux-tray.cjs — Linux 托盘必须走 StatusNotifier/AppIndicator 的上下文菜单
//
// Electron 在 Linux 的 Tray 由 StatusNotifierItem/AppIndicator 承载：
// - 不会派发 click / right-click 事件；
// - 只有 setContextMenu() 设置的菜单能显示。
// 因此保留 Windows/macOS 的左键唤起、右键弹菜单行为，Linux 改为常驻上下文菜单。
const fs = require('node:fs');
const path = require('node:path');

const root = process.argv[2];
if (!root) {
  console.error('用法: node patch-linux-tray.cjs <app.asar 解包目录>');
  process.exit(1);
}

const file = path.join(root, 'dist/main/modules/tray/index.js');
const before = `    t.setContextMenu(null);
    t.on('click', () => {`;
const after = `    t.setContextMenu(null);
    if (process.platform === 'linux') {
        // Linux StatusNotifier/AppIndicator 只暴露 setContextMenu，click/right-click 不会送达。
        // 设置菜单后，左键/右键点击托盘图标都会由桌面环境弹出该菜单。
        t.setContextMenu(createContextMenu());
        return;
    }
    t.on('click', () => {`;

let source = fs.readFileSync(file, 'utf8');
if (source.includes(after)) {
  console.log('  SKIP dist/main/modules/tray/index.js: Linux 上下文菜单（已打）');
  process.exit(0);
}
if (!source.includes(before)) {
  console.error('  错误: dist/main/modules/tray/index.js 中未找到托盘行为目标片段');
  process.exit(2);
}
source = source.replace(before, after);
fs.writeFileSync(file, source);
console.log('  OK   dist/main/modules/tray/index.js: Linux 托盘点击弹出菜单');
