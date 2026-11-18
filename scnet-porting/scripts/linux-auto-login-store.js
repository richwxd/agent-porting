// scnet-porting: 自动登录凭据的主进程侧加密存储
//
// 为什么在主进程：safeStorage 是主进程专属模块，preload（隔离世界）里取不到，
// 实测 typeof electron.safeStorage === "undefined"。判定与主进程 I() 一致
// （isEncryptionAvailable 且 Linux 上不能退化到 basic_text）。
// 构建期追加到 dist-electron/main/index.js 末尾（其末尾是 module.exports，CJS 顶层可用 require）。
;(function () {
  'use strict';
  if (process.platform !== 'linux') return;

  var electron, fs, path;
  try {
    electron = require('electron');
    fs = require('fs');
    path = require('path');
  } catch (e) {
    return;
  }
  var ipcMain = electron && electron.ipcMain;
  var safeStorage = electron && electron.safeStorage;
  var app = electron && electron.app;
  if (!ipcMain || typeof ipcMain.handle !== 'function' || !app) return;

  var CHANNEL = 'scnet-porting:auto-login';

  function file() {
    return path.join(app.getPath('userData'), 'auto-login.json');
  }

  function cryptoOk() {
    try {
      if (!safeStorage || typeof safeStorage.encryptString !== 'function') return false;
      if (!safeStorage.isEncryptionAvailable()) return false;
      if (process.platform === 'linux' && typeof safeStorage.getSelectedStorageBackend === 'function' && safeStorage.getSelectedStorageBackend() === 'basic_text') return false;
      return true;
    } catch (e) {
      return false;
    }
  }

  function read() {
    try {
      var raw = JSON.parse(fs.readFileSync(file(), 'utf8'));
      if (raw && raw.v === 1) return raw;
    } catch (e) {}
    return { v: 1, suppressed: false, enc: null };
  }

  function write(raw) {
    var p = file();
    fs.writeFileSync(p, JSON.stringify(raw), { mode: 0o600 });
    try { fs.chmodSync(p, 0o600); } catch (e) {}
  }

  // 只放行可直接重放的登录入参，形状不对就当没有
  function decryptCreds(enc) {
    var arg = JSON.parse(safeStorage.decryptString(Buffer.from(enc, 'base64')));
    if (!arg || typeof arg !== 'object') return null;
    if (arg.type !== 'userNameLogin') return null;
    if (typeof arg.password !== 'string' || !arg.password) return null;
    if (typeof arg.username !== 'string' || !arg.username) return null;
    return arg;
  }

  try {
    ipcMain.handle(CHANNEL, function (event, op, arg) {
      try {
        if (op === 'get') {
          var raw = read();
          var out = { ok: true, suppressed: !!raw.suppressed, crypto: cryptoOk(), creds: null, dir: app.getPath('userData') };
          if (raw.enc && out.crypto) {
            try { out.creds = decryptCreds(raw.enc); }
            catch (e) { out.decryptError = String((e && e.message) || e); }
          }
          return out;
        }
        if (op === 'save') {
          if (!cryptoOk()) return { ok: false, reason: 'crypto-unavailable' };
          if (!arg || typeof arg !== 'object') return { ok: false, reason: 'bad-arg' };
          var raw2 = read();
          raw2.enc = safeStorage.encryptString(JSON.stringify(arg)).toString('base64');
          raw2.suppressed = false; // 手工登录成功 = 解除退出抑制
          write(raw2);
          return { ok: true };
        }
        if (op === 'suppress') {
          var raw3 = read();
          raw3.suppressed = !!arg;
          write(raw3);
          return { ok: true };
        }
        return { ok: false, reason: 'unknown-op' };
      } catch (e) {
        return { ok: false, reason: String((e && e.message) || e) };
      }
    });
  } catch (e) {
    // 重复注册（理论上每次构建都是新树）：保留既有 handler
  }
})();
