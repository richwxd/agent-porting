#!/usr/bin/env node
// patch-update-check.cjs — Linux 下「检查更新」走 Windows 版本流（幂等）
//
// 用法: node scripts/patch-update-check.cjs <app.asar 解包目录>
//
// 为什么必须打：
//   1) electron-updater 在 Linux 默认拿 AppImageUpdater（有 package-type=deb 时拿
//      DebUpdater），它按 `latest-linux.yml` 找更新，而官方 Windows feed 只有
//      `latest.yml` + NSIS `.exe` → 检查更新永远 404/无结果。
//   2) 需求：Linux 版的版本号/更新检测与 Windows 完全一致，发现更新时下载的也是
//      Windows 安装包。因此固定用 NsisUpdater + 平台报告 win32。
//   3) 差量更新基于 Windows blockmap，Linux 上关闭，直接整包下载。
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const tree = process.argv[2];
if (!tree) {
  console.error('用法: node patch-update-check.cjs <asar 解包目录>');
  process.exit(2);
}

const EU = path.join(tree, 'node_modules/electron-updater/out');
const MAKER = 'LINUX_PORT_WINDOWS_UPDATE';

function patch(file, replacements) {
  const abs = path.join(tree, file);
  if (!fs.existsSync(abs)) {
    console.error(`错误: 缺少 ${file}（electron-updater 结构可能已变化）`);
    process.exit(2);
  }
  let src = fs.readFileSync(abs, 'utf8');
  let changed = 0;
  for (const [oldText, newText, label] of replacements) {
    if (src.includes(newText) && newText !== oldText) {
      console.log(`  SKIP ${label}（已打）`);
      continue;
    }
    const n = src.split(oldText).length - 1;
    if (n !== 1) {
      console.error(`错误: ${file} 中「${label}」目标片段出现 ${n} 次（应为 1），中止`);
      process.exit(2);
    }
    src = src.replace(oldText, newText);
    changed += 1;
    console.log(`  OK   ${label}`);
  }
  if (changed > 0) fs.writeFileSync(abs, src);
}

// 1) Linux 也实例化 NsisUpdater（读取 latest.yml / Windows NSIS 包）
patch('node_modules/electron-updater/out/main.js', [
  [
    '    if (process.platform === "win32") {\n        _autoUpdater = new (require("./NsisUpdater").NsisUpdater)();',
    `    // ${MAKER}: Linux 版沿用 Windows NSIS 更新流\n    if (process.platform === "win32" || process.platform === "linux") {\n        _autoUpdater = new (require("./NsisUpdater").NsisUpdater)();`,
    'main.js: Linux → NsisUpdater',
  ],
]);

// 2) provider 上报 win32：getChannelFilePrefix() 才不会拼出 -linux，请求 latest.yml
patch('node_modules/electron-updater/out/AppUpdater.js', [
  [
    'platform: this._testOnlyOptions == null ? process.platform : this._testOnlyOptions.platform,',
    `platform: this._testOnlyOptions == null ? (process.platform === "linux" ? "win32" : process.platform) : this._testOnlyOptions.platform, // ${MAKER}`,
    'AppUpdater.js: provider platform=win32',
  ],
]);

// 3) 关闭差量更新：blockmap 描述的是 Windows 安装包，Linux 直接整包下载
patch('dist/main/modules/updater/config.js', [
  [
    "    if (process.platform === 'win32') {\n        electron_updater_1.autoUpdater.disableDifferentialDownload = true;",
    "    if (process.platform === 'win32' || process.platform === 'linux') {\n        // LINUX_PORT_WINDOWS_UPDATE: Windows blockmap 无法在 Linux 上差量合并，整包下载\n        electron_updater_1.autoUpdater.disableDifferentialDownload = true;",
    "config.js: Linux 关闭差量下载",
  ],
]);

// 4) test 分支 feed 平台目录：Linux 走 win/
patch('dist/main/modules/updater/test-branch.js', [
  [
    "const platform = process.platform === 'win32' ? 'win' : 'mac';",
    "const platform = process.platform === 'win32' || process.platform === 'linux' ? 'win' : 'mac'; // LINUX_PORT_WINDOWS_UPDATE",
    'test-branch.js: Linux → win 分支目录',
  ],
]);

// 5) test 分支 channel 文件名：Linux 用 test.yml（Windows）而不是 test-linux.yml
patch('dist/main/modules/updater/test-branch-switch.js', [
  [
    "const feed = process.platform === 'win32' ? 'test.yml' : 'test-mac.yml';",
    "const feed = process.platform === 'win32' || process.platform === 'linux' ? 'test.yml' : 'test-mac.yml'; // LINUX_PORT_WINDOWS_UPDATE",
    'test-branch-switch.js: Linux → test.yml',
  ],
]);

console.log('patch-update-check: 完成（Linux 检查/下载均走 Windows 版本流）');
