#!/usr/bin/env node
// patch-computer-use-linux.cjs — 让 MiniMax Code 的 Computer Use 在 Linux 上可用
//
// 用法: node scripts/patch-computer-use-linux.cjs <app.asar 解包目录> <linux component.json sha256>
//
// 背景：
//   - 官方组件发现/清单校验只接受 darwin/win32（`@mavis/computer-use`）。
//   - Linux 版上游 cua-driver 0.34.1 与 Windows 组件使用同一套
//     `serve --socket ...` + JSONL 生命周期协议，metadata 完全匹配
//     （driver_version 0.34.1 / contract 0.8.0）。
//   - 因此补上 linux-x64 组件并放开平台判断即可。
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const tree = process.argv[2];
const linuxDigest = process.argv[3];
if (!tree || !linuxDigest || !/^[a-f0-9]{64}$/.test(linuxDigest)) {
  console.error('用法: node patch-computer-use-linux.cjs <asar 解包目录> <component.json sha256>');
  process.exit(2);
}

function patch(file, replacements) {
  const abs = path.join(tree, file);
  if (!fs.existsSync(abs)) {
    console.error(`错误: 缺少 ${file}`);
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
      console.error(`错误: ${file} 中「${label}」目标片段出现 ${n} 次（应为 1）`);
      process.exit(2);
    }
    src = src.replace(oldText, newText);
    changed += 1;
    console.log(`  OK   ${label}`);
  }
  if (changed) fs.writeFileSync(abs, src);
}

const CU = 'node_modules/@mavis/computer-use/dist';

// 1) 组件发现/清单：允许 linux
patch(`${CU}/component.js`, [
  [
    "if (!['darwin', 'win32'].includes(platform) || !['arm64', 'x64'].includes(arch)) {",
    "if (!['darwin', 'linux', 'win32'].includes(platform) || !['arm64', 'x64'].includes(arch)) {",
    'component.js: 允许 linux',
  ],
  [
    "const executable = platform === 'darwin'\n        ? 'MiniMax Computer Use.app/Contents/MacOS/minimax-computer-use'\n        : 'minimax-computer-use.exe';",
    "const executable = platform === 'darwin'\n        ? 'MiniMax Computer Use.app/Contents/MacOS/minimax-computer-use'\n        : platform === 'linux'\n            ? 'minimax-computer-use'\n            : 'minimax-computer-use.exe';",
    'component.js: linux 可执行文件名',
  ],
]);

// 2) packaged component：允许 linux target；release token 允许 linux-x64
patch(`${CU}/packaged-component.js`, [
  [
    'if (!/^(darwin|win32)-(arm64|x64)$/.test(target)) {',
    'if (!/^(darwin|linux|win32)-(arm64|x64)$/.test(target)) {',
    'packaged-component.js: 允许 linux target',
  ],
  [
    '!/^(darwin|win32)-(arm64|x64)$/.test(key)',
    '!/^(darwin|linux|win32)-(arm64|x64)$/.test(key)',
    'packaged-component.js: token 允许 linux key',
  ],
]);

// 3) SDK runtime：Linux 直接解析 @trycua/cua-driver（asar 内 ESM 可加载）
patch(`${CU}/cua-driver-runtime.js`, [
  [
    "if (!['darwin', 'win32'].includes(process.platform))",
    "if (!['darwin', 'linux', 'win32'].includes(process.platform))",
    'cua-driver-runtime.js: 允许 linux',
  ],
  [
    "export function cuaDriverModuleSpecifier(runtimeDirectory) {\n    let directory = runtimeDirectory;",
    "export function cuaDriverModuleSpecifier(runtimeDirectory) {\n    // LINUX_CU: 从 resources/computer-use-sdk 加载真实文件系统上的 SDK，\n    // 避免 Electron 从 app.asar 内解析原生 .node/.so。\n    if (process.platform === 'linux')\n        return pathToFileURL(path.join(process.resourcesPath, 'computer-use-sdk', 'node_modules', '@trycua', 'cua-driver', 'dist', 'index.js')).href;\n    let directory = runtimeDirectory;",
    'cua-driver-runtime.js: Linux SDK 解析',
  ],
]);

// 4) 权限状态：Linux 无 macOS/Windows 的 OS 级授权，直接视为就绪
patch(`dist/main/modules/local-runtime/computer-use/component-permissions.js`, [
  [
    "    if (process.platform === 'win32') {",
    "    if (process.platform === 'linux') {\n        return { accessibility: 'not-required', screenRecording: 'not-required', captureReady: true };\n    }\n    if (process.platform === 'win32') {",
    'component-permissions.js: Linux 权限就绪',
  ],
]);

// 4b) 客户端权限快照：Linux 与 Windows 一样无 macOS 的 TCC 授权，直接视为就绪
patch(`${CU}/client.js`, [
  [
    "if (process.platform === 'win32')\n            return permissionStatus({}, false);",
    "if (process.platform === 'win32' || process.platform === 'linux')\n            return permissionStatus({}, false);",
    'client.js: Linux 直接取权限快照',
  ],
  [
    "    function permissionStatus(status, probed) {\n        if (process.platform === 'win32')",
    "    function permissionStatus(status, probed) {\n        if (process.platform === 'win32' || process.platform === 'linux')",
    'client.js: Linux 权限无需 OS 授权',
  ],
  [
    "if (!runtime)\n            return {\n                supported: ['darwin', 'win32'].includes(process.platform),",
    "if (!runtime)\n            return {\n                supported: ['darwin', 'linux', 'win32'].includes(process.platform),",
    'client.js: Linux supported=true (no runtime)',
  ],
  [
    "catch (error) {\n            return {\n                supported: ['darwin', 'win32'].includes(process.platform),",
    "catch (error) {\n            return {\n                supported: ['darwin', 'linux', 'win32'].includes(process.platform),",
    'client.js: Linux supported=true (error)',
  ],
]);

// 5) release token：在原 win32 摘要基础上加入 linux-x64 的 component.json 摘要
const releaseFile = path.join(tree, 'dist/main/modules/local-runtime/computer-use/component-release.js');
if (!fs.existsSync(releaseFile)) {
  console.error('错误: 缺少 component-release.js');
  process.exit(2);
}
let releaseSrc = fs.readFileSync(releaseFile, 'utf8');
const tokenRe = /minimax-cu-release-v1\.([A-Za-z0-9_-]+)/;
const match = releaseSrc.match(tokenRe);
if (!match) {
  console.error('错误: 未找到 packagedComponentRelease token');
  process.exit(2);
}
const existing = JSON.parse(Buffer.from(match[1], 'base64url').toString('utf8'));
if (existing['linux-x64'] !== linuxDigest) {
  existing['linux-x64'] = linuxDigest;
  const canonical = Object.fromEntries(Object.keys(existing).sort().map((k) => [k, existing[k]]));
  const token = `minimax-cu-release-v1.${Buffer.from(JSON.stringify(canonical)).toString('base64url')}`;
  releaseSrc = releaseSrc.replace(tokenRe, token);
  fs.writeFileSync(releaseFile, releaseSrc);
  console.log('  OK   component-release.js: 注入 linux-x64 摘要');
} else {
  console.log('  SKIP component-release.js（已注入）');
}

console.log('patch-computer-use-linux: 完成（Linux Computer Use 组件已接入）');
