'use strict';
// scnet-porting: patch-autologin-prefill.cjs 的最小桩测试
// 覆盖：两处各唯一时替换成功；登录页串缺失时非零且不改写；主进程串重复时非零且不改写；幂等重跑失败。
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const SRC = path.join(__dirname, 'patch-autologin-prefill.cjs');
const MAIN_FROM = 'function _(e=(0,o.gU)()){let t=b(e);return t?{username:String(t.userName||"")}:null}';
const MAIN_TO = 'function _(e=(0,o.gU)()){let t=b(e);if(!t)return null;let r={username:String(t.userName||"")},i=C(e,String(t.userId||""));return i&&(r.password=i.password,r.autoLogin=!0),r}';
const LOGIN_FROM = 'o.readRememberedLogin().then(e=>{!g.value&&e?.username&&(g.value=e.username)}).catch(()=>{})';
const LOGIN_TO = 'o.readRememberedLogin().then(e=>{if(!e)return;g.value||e.username&&(g.value=e.username);e.password&&!k.value&&(k.value=e.password),e.autoLogin&&(C.value=!0)}).catch(()=>{})';

function run(main, login) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'patch-al-prefill-'));
  const mf = path.join(dir, 'dist-electron/main/index.js');
  const lf = path.join(dir, 'dist/static/js/async/chunk.js');
  fs.mkdirSync(path.dirname(mf), { recursive: true });
  fs.mkdirSync(path.dirname(lf), { recursive: true });
  fs.writeFileSync(mf, main);
  fs.writeFileSync(lf, login);
  let status = 0;
  try {
    execFileSync(process.execPath, [SRC, dir], { stdio: 'pipe' });
  } catch (e) {
    status = e.status || 1;
  }
  return { status, main: fs.readFileSync(mf, 'utf8'), login: fs.readFileSync(lf, 'utf8') };
}

// 1) 两处各唯一 → 替换成功
const ok = run(MAIN_FROM, LOGIN_FROM);
assert.strictEqual(ok.status, 0, '唯一出现应成功');
assert.ok(ok.main.includes(MAIN_TO) && !ok.main.includes(MAIN_FROM), '主进程应换成新值');
assert.ok(ok.login.includes(LOGIN_TO) && !ok.login.includes(LOGIN_FROM), '登录页应换成新值');

// 2) 登录页串缺失 → 非零且不改写
const miss = run(MAIN_FROM, 'x=1');
assert.notStrictEqual(miss.status, 0, '缺失应失败');
assert.strictEqual(miss.main, MAIN_FROM, '失败时主进程不得改写');

// 3) 主进程串重复 → 非零且不改写
const dup = run(MAIN_FROM + '|' + MAIN_FROM, LOGIN_FROM);
assert.notStrictEqual(dup.status, 0, '多处应失败');
assert.strictEqual(dup.main, MAIN_FROM + '|' + MAIN_FROM, '失败时不得改写');
assert.strictEqual(dup.login, LOGIN_FROM, '失败时登录页不得改写');

// 4) 幂等：改完再跑一次应失败（旧串已消失），不产生二次改写
const again = run(ok.main, ok.login);
assert.notStrictEqual(again.status, 0, '重复执行应失败');
assert.strictEqual(again.main, ok.main, '重复执行不得改写主进程');
assert.strictEqual(again.login, ok.login, '重复执行不得改写登录页');

console.log('patch-autologin-prefill.test.cjs OK');
