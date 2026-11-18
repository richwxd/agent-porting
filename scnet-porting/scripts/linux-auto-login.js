// scnet-porting: Linux 会话自动登录 / 过期自动重登
//
// 背景（为什么每天都要手工登录一次）：
//   1) 服务端会话约一天失效，主进程刷新拿到 401 后清掉 accessToken 并广播 "auth.session-expired"；
//   2) 启动逻辑 "auth.ensure-startup-login" 在 accessToken 缺失时直接 skipped —— 只有还留着
//      token 才做 tokenLogin，tokenLogin 失败才会用 desktopAutoLogin 兜底；
//   3) 登录页只有勾了"自动登录"才会写 desktopAutoLogin，实测 config.json 里没有这个键，
//      于是每天都要手工登录一次。
//
// 本脚本在 preload（隔离世界）里补上这条链路：
//   a) 拦截 ipcRenderer.invoke —— 登录成功（auth.login / userNameLogin）后把整条入参
//      （含 RSA 密文密码，可长期重放）交给主进程侧加密存储 linux-auto-login-store.js
//      （safeStorage 是主进程专属模块，preload 取不到，实测 undefined）；
//   b) 监听 sacp:host:event 的 "auth.session-expired"，以及启动 8s 后的探针
//      "auth.refresh-snapshot" —— 未登录就用存下的入参重放 auth.login；
//   c) 主进程登录成功会向所有窗口广播 "auth.snapshot"，渲染层据此恢复登录态
//      （与内置启动自动登录同一条路径）；
//   d) 用户手工退出（auth.request-logout）后抑制自动登录，直到下次手工登录成功；
//      抑制标志落盘，跨重启生效。
//
// 只在 Linux + 主窗口生效；诊断写 <userData>/auto-login.log（目录由存储通道返回）。
;(function () {
  'use strict';
  if (process.platform !== 'linux') return;

  var electron;
  try {
    electron = require('electron');
  } catch (e) {
    return;
  }
  var ipc = electron && electron.ipcRenderer;
  if (!ipc || typeof ipc.invoke !== 'function') return;

  var ctx = null;
  try {
    ctx = ipc.sendSync('sacp:host:context');
  } catch (e) {
    return;
  }
  if (!ctx || !ctx.isMainWindow) return;

  var fs;
  var path;
  try {
    fs = require('fs');
    path = require('path');
  } catch (e) {
    return;
  }

  var STORE_CHANNEL = 'scnet-porting:auto-login';
  var STARTUP_DELAY = 8000; // 等内置启动登录先跑完
  var EVENT_DELAY = 2000; // 收到过期事件后的延迟
  var RETRY_DELAY = 60000; // 失败退避
  var COOLDOWN = 30000; // 两次尝试的最小间隔
  var MAX_ATTEMPTS = 3; // 每轮最多连续尝试次数
  var LOG_CAP = 65536;

  var LOG = null;

  function log(msg) {
    var line = new Date().toISOString() + ' [auto-login] ' + msg;
    if (!LOG) {
      // 目录要等存储通道返回；在此之前只进控制台
      try { console.warn(line); } catch (e) {}
      return;
    }
    try {
      try {
        if (fs.existsSync(LOG) && fs.statSync(LOG).size > LOG_CAP) fs.writeFileSync(LOG, '');
      } catch (e) {}
      fs.appendFileSync(LOG, line + '\n');
    } catch (e) {}
  }

  // 存储全部走主进程（加密、路径、抑制标志），本侧不留副本
  function storeOp(op, arg) {
    try {
      return Promise.resolve(ipc.invoke(STORE_CHANNEL, op, arg)).then(
        function (r) { return r; },
        function () { return null; }
      );
    } catch (e) {
      return Promise.resolve(null);
    }
  }

  function brief(res) {
    try {
      if (!res) return String(res);
      if (res.ok) {
        var v = res.value || {};
        return 'ok code=' + v.code + ' message=' + (v.message || v.msg || '');
      }
      var f = res.failure || {};
      return 'failure code=' + f.code + ' message=' + (f.message || '');
    } catch (e) {
      return 'unprintable-response';
    }
  }

  // ---------- 拦截渲染层调用 ----------
  var origInvoke = ipc.invoke;
  try {
    ipc.invoke = function (channel, op, arg) {
      var out = origInvoke.apply(ipc, arguments);
      try {
        if (channel === 'sacp:host:invoke') {
          if (op === 'auth.request-logout') {
            // 用户主动退出：抑制自动登录（落盘，跨重启生效），直到下次手工登录
            storeOp('suppress', true);
            log('检测到手工退出，自动登录已抑制');
          } else if (op === 'auth.login' && arg && arg.type === 'userNameLogin' && typeof arg.password === 'string' && arg.password) {
            Promise.resolve(out).then(function (res) {
              try {
                if (res && res.ok && res.value && String(res.value.code) === '0') {
                  storeOp('save', arg).then(function (r) {
                    if (r && r.ok) log('已保存登录凭据: ' + arg.username);
                    else log('保存登录凭据失败: ' + (r && r.reason ? r.reason : '存储通道不可用'));
                  });
                }
              } catch (e) {}
            }, function () {});
          }
        }
      } catch (e) {}
      return out;
    };
  } catch (e) {
    log('无法拦截 ipc.invoke: ' + e.message);
    return;
  }

  function rawInvoke(op, arg) {
    return Promise.resolve(origInvoke.call(ipc, 'sacp:host:invoke', op, arg));
  }

  // ---------- 自动重登 ----------
  var inFlight = false;
  var attempts = 0;
  var lastAttemptAt = 0;
  var pendingTimer = null;

  function queueLogin(reason, delay) {
    if (pendingTimer) return;
    var wait = delay || 0;
    var since = Date.now() - lastAttemptAt;
    if (since < COOLDOWN) wait = Math.max(wait, COOLDOWN - since);
    pendingTimer = setTimeout(function () {
      pendingTimer = null;
      tryLogin(reason);
    }, wait);
  }

  function tryLogin(reason) {
    if (inFlight) return;
    if (attempts >= MAX_ATTEMPTS) {
      log('放弃（' + reason + '）：已连续失败 ' + attempts + ' 次，等待下次会话过期');
      return;
    }
    inFlight = true;
    storeOp('get').then(function (s) {
      if (!s || !s.ok) {
        inFlight = false;
        log('跳过（' + reason + '）：存储通道不可用 ' + (s && s.reason ? s.reason : ''));
        return;
      }
      if (s.suppressed) {
        inFlight = false;
        log('跳过（' + reason + '）：已按用户退出抑制');
        return;
      }
      if (!s.creds) {
        inFlight = false;
        log('跳过（' + reason + '）：没有已保存的凭据' + (s.crypto === false ? '（safeStorage 不可用）' : (s.decryptError ? '（' + s.decryptError + '）' : '')));
        return;
      }
      var creds = s.creds;
      lastAttemptAt = Date.now();
      return rawInvoke('auth.refresh-snapshot').then(function (res) {
        // 未登录时主进程返回 {ok:false}（handler 内部 catch 成 failure 信封）
        if (res && res.ok) {
          inFlight = false;
          log('跳过（' + reason + '）：会话仍有效');
          return;
        }
        log('会话无效（' + reason + '），以 ' + creds.username + ' 自动登录: ' + brief(res));
        return rawInvoke('auth.login', creds).then(function (r) {
          inFlight = false;
          if (r && r.ok && r.value && String(r.value.code) === '0') {
            attempts = 0;
            log('自动登录成功（' + reason + '）');
          } else {
            attempts++;
            log('自动登录失败（' + reason + '）第 ' + attempts + ' 次: ' + brief(r));
            if (attempts < MAX_ATTEMPTS) queueLogin(reason, RETRY_DELAY);
          }
        });
      });
    }).catch(function (e) {
      inFlight = false;
      attempts++;
      log('探针/登录异常（' + reason + '）第 ' + attempts + ' 次: ' + (e && e.message));
      if (attempts < MAX_ATTEMPTS) queueLogin(reason, RETRY_DELAY);
    });
  }

  // ---------- 事件 ----------
  try {
    ipc.on('sacp:host:event', function (event, name) {
      try {
        if (name === 'auth.session-expired') {
          attempts = 0; // 新一轮过期给新的尝试额度
          log('收到 auth.session-expired');
          setTimeout(function () { tryLogin('session-expired'); }, EVENT_DELAY);
        }
      } catch (e) {}
    });
  } catch (e) {
    log('监听 sacp:host:event 失败: ' + e.message);
  }

  // ---------- 启动 ----------
  storeOp('get').then(function (s) {
    if (s && s.dir) LOG = path.join(s.dir, 'auto-login.log');
    if (!s || !s.ok) {
      log('启动: 存储通道不可用，自动登录不生效');
      return;
    }
    log('启动: dir=' + s.dir + ' suppressed=' + s.suppressed + ' hasCreds=' + !!s.creds + ' crypto=' + s.crypto);
    if (!s.suppressed && s.creds) {
      setTimeout(function () { tryLogin('startup'); }, STARTUP_DELAY);
    }
  }).catch(function () {
    log('启动: 存储通道异常，自动登录不生效');
  });
})();
