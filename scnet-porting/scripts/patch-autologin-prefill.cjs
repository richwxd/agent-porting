'use strict';
// scnet-porting: 登录页回填已存密码与「自动登录」勾选（patch-autologin-prefill.cjs）
// 症状：会话失效或重启后初始化仍要重新填写用户名密码，勾选状态也没了
// （用户反馈「自动登录需要保存密码，本地化存储没有成功，可以本地indexdb存储密码，并存储jwt token,避免失效」）。
// 事实：凭据其实已经本地保存——config.json 的 desktopAutoLogin（safeStorage 密文）与
// ~/.config/scnet-client/auto-login.json 都在，注入脚本每次启动 hasCreds=true 也能自动重登；
// 缺的只是登录页回填：
//  1) auth.read-remembered-login 只回 {username}，渲染层拿不到密码和勾选状态。
//     改成顺带用同模块的 C(baseUrl,userId) 解出已存密码，返回 {username,password,autoLogin}。
//  2) 登录页 onMounted 只回填用户名，密码框与「自动登录」勾选不动 ⇒ 初始化必须重填。
//     改成一并回填（不覆盖已有输入）并按 autoLogin 勾上。
// 不引入 IndexedDB：主进程 safeStorage 密文已是更安全的本地存储，再造一份密文副本没有收益。
// 两串在 app 树各唯一；出现次数 !=1 直接失败（客户端改版后需人工核对）。
const fs = require('fs');
const path = require('path');

const root = process.argv[2];
if (!root) {
  console.error('用法: node patch-autologin-prefill.cjs <app树根>');
  process.exit(2);
}

const NEEDLES = [
  {
    // 主进程：read-remembered-login 顺带解出已存密码 + 自动登录标记
    file: path.join(root, 'dist-electron/main/index.js'),
    from: 'function _(e=(0,o.gU)()){let t=b(e);return t?{username:String(t.userName||"")}:null}',
    to: 'function _(e=(0,o.gU)()){let t=b(e);if(!t)return null;let r={username:String(t.userName||"")},i=C(e,String(t.userId||""));return i&&(r.password=i.password,r.autoLogin=!0),r}',
    what: 'read-remembered-login 返回密码与 autoLogin',
  },
  {
    // 渲染层：登录页 onMounted 回填密码与勾选（chunk 文件名带 hash，按内容定位）
    dir: path.join(root, 'dist/static/js/async'),
    from: 'o.readRememberedLogin().then(e=>{!g.value&&e?.username&&(g.value=e.username)}).catch(()=>{})',
    to: 'o.readRememberedLogin().then(e=>{if(!e)return;g.value||e.username&&(g.value=e.username);e.password&&!k.value&&(k.value=e.password),e.autoLogin&&(C.value=!0)}).catch(()=>{})',
    what: '登录页回填密码与自动登录勾选',
  },
];

function locate(n) {
  if (n.file) return [n.file];
  const hits = fs.readdirSync(n.dir).filter((f) => {
    const p = path.join(n.dir, f);
    return fs.statSync(p).isFile() && fs.readFileSync(p, 'utf8').includes(n.from);
  });
  if (hits.length !== 1) {
    console.error('patch-autologin-prefill: 登录页 chunk 命中 ' + hits.length + ' 个（期望 1，' + n.dir + '）');
    process.exit(1);
  }
  return [path.join(n.dir, hits[0])];
}

const srcs = NEEDLES.map((n) => {
  const file = locate(n)[0];
  return { n, file, src: fs.readFileSync(file, 'utf8') };
});

for (const { n, file, src } of srcs) {
  const count = src.split(n.from).length - 1;
  if (count !== 1) {
    console.error('patch-autologin-prefill: 期望唯一 ' + JSON.stringify(n.from.slice(0, 48)) + '…，实际 ' + count + ' 处（' + file + '）');
    process.exit(1);
  }
}
for (const s of srcs) fs.writeFileSync(s.file, s.src.replace(s.n.from, s.n.to));
console.log('patch-autologin-prefill: ' + NEEDLES.map((n) => n.what).join('；'));
