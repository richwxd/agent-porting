'use strict';
// scnet-porting: linux-auto-login.js 的最小桩测试（node linux-auto-login.test.js）
// 覆盖：登录成功落盘 / 启动探针（已登录不重登、未登录重登）/ 过期事件重登 /
//       手工退出抑制且跨"重启"保留 / 连续失败 3 次后停手 / 非主窗口不生效。
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');

const SRC = path.join(__dirname, 'linux-auto-login.js');
const flush = () => new Promise((r) => setImmediate(r));

const CRED = {
  username: 'richwxd',
  password: 'RSA-CIPHERTEXT',
  captcha: '',
  captchaKey: '',
  type: 'userNameLogin',
  isSevenDaysValidity: true,
};

function makeEnv(opts) {
  opts = opts || {};
  const udd = fs.mkdtempSync(path.join(os.tmpdir(), 'al-test-'));
  if (opts.seed) {
    fs.writeFileSync(
      path.join(udd, 'auto-login.json'),
      JSON.stringify({
        v: 1,
        suppressed: !!opts.seed.suppressed,
        enc: Buffer.from('ENC:' + JSON.stringify(opts.seed.arg || CRED)).toString('base64'),
      })
    );
  }
  const calls = [];
  const timers = [];
  const listeners = {};
  const state = { loggedIn: !!opts.loggedIn };

  const storeFile = path.join(udd, 'auto-login.json');
  const readStoreFile = () => {
    try {
      return JSON.parse(fs.readFileSync(storeFile, 'utf8'));
    } catch (e) {
      return { v: 1, suppressed: false, enc: null };
    }
  };
  const cryptoOk = () => opts.crypto !== false && (opts.backend || 'kwallet5') !== 'basic_text';

  const safeStorage = {
    isEncryptionAvailable: () => opts.crypto !== false,
    getSelectedStorageBackend: () => opts.backend || 'kwallet5',
    encryptString: (s) => Buffer.from('ENC:' + s),
    decryptString: (b) => {
      const t = b.toString();
      if (t.slice(0, 4) !== 'ENC:') throw new Error('bad blob');
      return t.slice(4);
    },
  };

  const ipc = {
    sendSync: () => ({ platform: opts.platform || 'linux', isMainWindow: opts.mainWindow !== false }),
    invoke: (channel, op, arg) => {
      calls.push({ channel, op, arg });
      if (channel === 'scnet-porting:auto-login') {
        // 桩主进程侧存储通道（真实实现见 linux-auto-login-store.js）
        const raw = readStoreFile();
        if (op === 'get') {
          const out = { ok: true, suppressed: !!raw.suppressed, crypto: cryptoOk(), creds: null, dir: udd };
          if (raw.enc && out.crypto) {
            try {
              const a = JSON.parse(safeStorage.decryptString(Buffer.from(raw.enc, 'base64')));
              if (a && a.type === 'userNameLogin' && a.password && a.username) out.creds = a;
            } catch (e) {
              out.decryptError = e.message;
            }
          }
          return Promise.resolve(out);
        }
        if (op === 'save') {
          if (!cryptoOk()) return Promise.resolve({ ok: false, reason: 'crypto-unavailable' });
          fs.writeFileSync(
            storeFile,
            JSON.stringify({ v: 1, suppressed: false, enc: Buffer.from('ENC:' + JSON.stringify(arg)).toString('base64') }),
            { mode: 0o600 }
          );
          return Promise.resolve({ ok: true });
        }
        if (op === 'suppress') {
          const r = readStoreFile();
          r.suppressed = !!arg;
          fs.writeFileSync(storeFile, JSON.stringify(r), { mode: 0o600 });
          return Promise.resolve({ ok: true });
        }
        return Promise.resolve({ ok: false, reason: 'unknown-op' });
      }
      if (op === 'auth.refresh-snapshot') {
        return Promise.resolve(
          state.loggedIn
            ? { ok: true, value: { status: 'authenticated' } }
            : { ok: false, failure: { code: 'common.unexpected', message: 'No authenticated session' } }
        );
      }
      if (op === 'auth.login') {
        const res = opts.loginResult ? opts.loginResult(arg) : { ok: true, value: { code: '0' } };
        if (res.ok && res.value && String(res.value.code) === '0') state.loggedIn = true;
        return Promise.resolve(res);
      }
      return Promise.resolve({ ok: true, value: null });
    },
    on: (channel, cb) => {
      (listeners[channel] = listeners[channel] || []).push(cb);
    },
  };

  const sandbox = {
    require: (name) => {
      if (name === 'electron') return { ipcRenderer: ipc, safeStorage };
      return require(name);
    },
    process: { platform: opts.platform || 'linux', env: { SACP_SMOKE_USER_DATA_DIR: udd } },
    setTimeout: (fn) => {
      timers.push(fn);
      return timers.length;
    },
    clearTimeout: () => {},
    Buffer,
    console,
  };
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(SRC, 'utf8'), sandbox, { filename: 'linux-auto-login.js' });

  async function drain(limit) {
    let n = 0;
    await flush(); // 启动先走 storeOp('get') 微任务，再由它排 setTimeout
    while (timers.length && n < (limit || 50)) {
      const fn = timers.shift();
      fn();
      n += 1;
      await flush();
    }
  }

  const readStore = () => JSON.parse(fs.readFileSync(path.join(udd, 'auto-login.json'), 'utf8'));
  const readLog = () => {
    try {
      return fs.readFileSync(path.join(udd, 'auto-login.log'), 'utf8');
    } catch (e) {
      return '';
    }
  };
  const ops = () => calls.map((c) => c.op);
  const cleanup = () => fs.rmSync(udd, { recursive: true, force: true });
  return { udd, ipc, calls, timers, state, drain, readStore, readLog, ops, listeners, cleanup };
}

async function main() {
  // 1) 手工登录成功 → 凭据加密落盘
  {
    const env = makeEnv({});
    await env.ipc.invoke('sacp:host:invoke', 'auth.login', CRED);
    await flush();
    const store = env.readStore();
    assert.strictEqual(store.suppressed, false, 'T1 suppressed');
    assert.deepStrictEqual(JSON.parse(Buffer.from(store.enc, 'base64').toString().slice(4)), CRED, 'T1 round-trip');
    assert.ok(env.readLog().indexOf('已保存登录凭据') >= 0, 'T1 log');
    env.cleanup();
  }

  // 2) 启动探针：会话仍有效 → 不重登
  {
    const env = makeEnv({ loggedIn: true, seed: { arg: CRED } });
    await env.drain();
    assert.ok(env.ops().indexOf('auth.refresh-snapshot') >= 0, 'T2 probe ran');
    assert.strictEqual(env.ops().indexOf('auth.login'), -1, 'T2 no re-login');
    assert.ok(env.readLog().indexOf('会话仍有效') >= 0, 'T2 log');
    env.cleanup();
  }

  // 3) 启动探针：无会话 → 用存下的凭据重登
  {
    const env = makeEnv({ loggedIn: false, seed: { arg: CRED } });
    await env.drain();
    const i = env.ops().indexOf('auth.login');
    assert.ok(i >= 0, 'T3 re-login attempted');
    assert.strictEqual(JSON.stringify(env.calls[i].arg), JSON.stringify(CRED), 'T3 replayed payload');
    assert.ok(env.readLog().indexOf('自动登录成功') >= 0, 'T3 success log');
    env.cleanup();
  }

  // 4) 运行中会话过期事件 → 延迟后重登
  {
    const env = makeEnv({ loggedIn: true, seed: { arg: CRED } });
    await env.drain(); // 启动探针：会话有效，不登录
    assert.strictEqual(env.ops().indexOf('auth.login'), -1, 'T4 no login yet');
    env.state.loggedIn = false; // 模拟服务端 401
    env.listeners['sacp:host:event'].forEach((cb) => cb({}, 'auth.session-expired', undefined));
    await env.drain();
    assert.ok(env.ops().indexOf('auth.login') >= 0, 'T4 re-login after expiry');
    assert.ok(env.readLog().indexOf('收到 auth.session-expired') >= 0, 'T4 event log');
    env.cleanup();
  }

  // 5) 手工退出 → 抑制自动登录，且落盘跨"重启"保留；下次手工登录解除
  {
    const env = makeEnv({ loggedIn: true, seed: { arg: CRED } });
    await env.drain();
    await env.ipc.invoke('sacp:host:invoke', 'auth.request-logout', undefined);
    await flush();
    assert.strictEqual(env.readStore().suppressed, true, 'T5 suppressed after logout');
    env.state.loggedIn = false;
    env.listeners['sacp:host:event'].forEach((cb) => cb({}, 'auth.session-expired', undefined));
    await env.drain();
    assert.strictEqual(env.ops().indexOf('auth.login'), -1, 'T5 no auto login while suppressed');
    env.cleanup();

    // 新实例（重启）仍然抑制
    const env2 = makeEnv({ loggedIn: false, seed: { arg: CRED, suppressed: true } });
    await env2.drain();
    assert.strictEqual(env2.ops().indexOf('auth.login'), -1, 'T5 suppression survives restart');
    // 手工登录后解除
    await env2.ipc.invoke('sacp:host:invoke', 'auth.login', CRED);
    await flush();
    assert.strictEqual(env2.readStore().suppressed, false, 'T5 suppression cleared by manual login');
    env2.cleanup();
  }

  // 6) 连续失败 3 次后停手
  {
    const env = makeEnv({
      loggedIn: false,
      seed: { arg: CRED },
      loginResult: () => ({ ok: true, value: { code: '1', message: 'bad password' } }),
    });
    await env.drain(200);
    assert.strictEqual(env.ops().filter((o) => o === 'auth.login').length, 3, 'T6 stops after 3 attempts');
    assert.ok(env.readLog().indexOf('第 3 次') >= 0, 'T6 failure log');
    env.cleanup();
  }

  // 7) 非主窗口：完全不生效
  {
    const env = makeEnv({ mainWindow: false, seed: { arg: CRED } });
    await env.drain();
    assert.strictEqual(env.ops().length, 0, 'T7 sub-window inert');
    env.cleanup();
  }

  console.log('linux-auto-login.test.js: all assertions passed');
}

main().catch((e) => {
  console.error(e && e.stack ? e.stack : e);
  process.exit(1);
});
