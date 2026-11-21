'use strict';
// scnet-porting: linux-window-controls.js 的最小桩测试（node scripts/linux-window-controls.test.cjs）
// 覆盖：注入顶部 titlebar 三按钮 + body 下移让位；页面自带 .window-tools 时隐藏并复位；
//       非主窗口不注入；不改动页面自定义按钮（无 .page-toolbar__actions 规则）；
//       body 下移后同步收缩 100vh 元素（底部输入框不被挤出容器）；
//       顶部 fixed toast 动态插入时下移 36px 避开 titlebar（安装报错提示不被裁切）。
const assert = require('assert');
const path = require('path');
const vm = require('vm');

const SRC = path.join(__dirname, 'linux-window-controls.js');

function makeEnv(opts) {
  opts = opts || {};
  let appHas = !!opts.appHas;
  const listeners = {};

  function el(tag) {
    const classes = new Set();
    const node = {
      tagName: tag,
      nodeType: 1,
      type: '',
      id: '',
      title: '',
      tabIndex: 0,
      className: '',
      textContent: '',
      style: {
        setProperty(k, v) { this[k] = v; },
        removeProperty(k) { delete this[k]; },
      },
      children: [],
      attrs: {},
      classList: {
        toggle(name, force) {
          const on = force === undefined ? !classes.has(name) : !!force;
          if (on) classes.add(name); else classes.delete(name);
          return on;
        },
        contains(name) { return classes.has(name); },
      },
      appendChild(c) { this.children.push(c); return c; },
      setAttribute(k, v) { this.attrs[k] = v; },
      hasAttribute(k) { return k in this.attrs; },
      removeAttribute(k) { delete this.attrs[k]; },
      addEventListener(name, fn) { (this._ev = this._ev || {})[name] = fn; },
    };
    Object.defineProperties(node, {
      firstChild: { get() { return this.children[0]; } },
      childNodes: { get() { return this.children; } },
    });
    return node;
  }

  const body = el('body');
  const documentElement = el('html');
  const document = {
    readyState: 'complete',
    body,
    documentElement,
    fullscreenElement: opts.fullscreen ? documentElement : null,
    createElement: (tag) => el(tag),
    createElementNS: (ns, tag) => el(tag),
    querySelector: (sel) => (sel === '.window-tools' && appHas ? el('div') : null),
    addEventListener() {},
  };
  const window = {
    innerWidth: 1200,
    addEventListener(name, fn) { listeners[name] = fn; },
  };
  const observers = []; // 捕获脚本注册的 MutationObserver，用例里手动触发
  const ipc = {
    sendSync: () => ({ isMainWindow: opts.mainWindow === false ? false : true }),
    invoke: () => Promise.resolve({ ok: true, value: false }),
  };
  const sandbox = {
    require: (name) => (name === 'electron' ? { ipcRenderer: ipc } : require(name)),
    process: { platform: 'linux' },
    document,
    window,
    Promise,
    setImmediate,
    console,
    getComputedStyle: (el) => el.__cs || { position: 'static', top: '', left: '', right: '' },
    MutationObserver: class {
      constructor(cb) { this.cb = cb; }
      observe(target) { observers.push({ cb: this.cb, target }); }
    },
    requestAnimationFrame: (fn) => fn(),
  };
  return {
    sandbox,
    body,
    documentElement,
    listeners,
    setAppHas(v) { appHas = v; },
    observers,
    injectedRoot: () => documentElement.children.find((c) => String(c.className).indexOf('scnet-linux-window-controls') === 0),
    styleEl: () => documentElement.children.find((c) => c.tagName === 'style' && c.id === 'scnet-linux-window-controls'),
  };
}

// 1) 注入 titlebar 三按钮 + body 下移让位
const env = makeEnv();
vm.runInNewContext(require('fs').readFileSync(SRC, 'utf8'), env.sandbox);
const root = env.injectedRoot();
assert.ok(root, '应注入按钮条');
assert.strictEqual(root.children.length, 3, '应为 min/max/close 三个按钮');
assert.ok(root.style.display === 'flex', '默认可见');
const css = env.styleEl().textContent;
assert.ok(css.indexOf('body.scnet-wc-shift{--scnet-wc-shift:36px;padding-top:var(--scnet-wc-shift)}') !== -1, '应包含 titlebar 让位规则（CSS 变量形式）');
assert.ok(css.indexOf('body.scnet-wc-shift .h-screen{height:calc(100vh - 36px)}') !== -1, '应包含 100vh 收缩补偿，避免底部输入框被挤出视口');
assert.ok(css.indexOf('.page-toolbar__actions') === -1, '不应改动页面自定义按钮');
assert.ok(env.body.classList.contains('scnet-wc-shift'), 'body 应下移让出 titlebar');

// 2) 页面自带 .window-tools（登录页）时：隐藏自己并复位 body
env.setAppHas(true);
env.listeners.resize();
assert.strictEqual(env.injectedRoot().style.display, 'none', '登录页应隐藏 titlebar');
assert.ok(!env.body.classList.contains('scnet-wc-shift'), '登录页 body 应复位');

// 3) 回到主界面恢复
env.setAppHas(false);
env.listeners.resize();
assert.strictEqual(env.injectedRoot().style.display, 'flex', '主界面应恢复');
assert.ok(env.body.classList.contains('scnet-wc-shift'), '主界面 body 应重新下移');

// 4) 非主窗口不注入
const env2 = makeEnv({ mainWindow: false });
vm.runInNewContext(require('fs').readFileSync(SRC, 'utf8'), env2.sandbox);
assert.ok(!env2.injectedRoot(), '非主窗口不应注入');
assert.ok(!env2.body.classList.contains('scnet-wc-shift'), '非主窗口 body 不应下移');

// 5) 顶部 fixed toast 动态插入 body 时下移 36px 避开 titlebar（安装报错提示不被裁切）
const bodyObs = env.observers.find((o) => o.target === env.body);
assert.ok(bodyObs, '应观察 body 子节点变化');
const toast = env.body.appendChild(env.sandbox.document.createElement('div'));
toast.__cs = { position: 'fixed', top: '16px', left: '600px' }; // Chrome 对 fixed 返回用值像素
bodyObs.cb([{ type: 'childList', addedNodes: [toast] }]);
assert.strictEqual(toast.attrs['data-scnet-wc-shifted'], '1', '贴顶 toast 应标记让位');
assert.strictEqual(toast.style.top, '36px', '贴顶 toast 应下移 36px 避开 titlebar');
// 非贴顶弹层（侧边抽屉等）不动
const drawer = env.body.appendChild(env.sandbox.document.createElement('div'));
drawer.__cs = { position: 'fixed', top: '0px', right: '0px', left: 'auto' };
bodyObs.cb([{ type: 'childList', addedNodes: [drawer] }]);
assert.ok(!('data-scnet-wc-shifted' in drawer.attrs), '侧边抽屉不应让位');

console.log('linux-window-controls.test.cjs OK');
