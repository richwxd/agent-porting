// scnet-porting: Linux 主窗口右上角窗口控制按钮（最小化 / 最大化 / 关闭）
//
// 根因：win 版主窗口靠原生 titleBarOverlay（titleBarStyle:"hidden" + win32 overlay）画出三个按钮，
// Linux 上 titleBarOverlay 为 undefined 且窗口 frameless，渲染层只在登录页渲染 .window-tools，
// 主界面右上角因此是空白。
// 本脚本在 preload 末尾执行（隔离世界），仅 Linux 主窗口注入同样三个按钮，走同一套
// sacp:host:invoke 通道与 --window-control-* 主题变量；检测到页面自带 .window-tools 时自动隐藏。
// 布局（模仿 workbuddy）：顶部注入一条 36px titlebar，标准按钮固定在条内右端；
// 页面内容整体下移 36px（body.scnet-wc-shift），页面头部自定义按钮保持原位、不再重叠。
;(function () {
  'use strict';
  if (process.platform !== 'linux') return;
  var electron;
  try {
    electron = require('electron');
  } catch (e) {
    return;
  }
  var ipc = electron.ipcRenderer;
  if (!ipc) return;
  var ctx = null;
  try {
    ctx = ipc.sendSync('sacp:host:context');
  } catch (e) {
    return;
  }
  if (!ctx || !ctx.isMainWindow) return;

  var STYLE_ID = 'scnet-linux-window-controls';
  var CLS = 'scnet-linux-window-controls';

  function invoke(op) {
    return Promise.resolve(ipc.invoke('sacp:host:invoke', op, undefined)).catch(function () {});
  }

  function svg(children) {
    var el = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    el.setAttribute('viewBox', '0 0 24 24');
    el.setAttribute('width', '16');
    el.setAttribute('height', '16');
    el.setAttribute('fill', 'none');
    el.setAttribute('stroke', 'currentColor');
    el.setAttribute('stroke-width', '1.9');
    el.setAttribute('stroke-linecap', 'round');
    el.setAttribute('stroke-linejoin', 'round');
    el.setAttribute('aria-hidden', 'true');
    children.forEach(function (c) {
      el.appendChild(document.createElementNS('http://www.w3.org/2000/svg', c[0]));
    });
    return el;
  }

  var ICON = {
    min: function () {
      var l = svg([['line']]);
      l.firstChild.setAttribute('x1', '5');
      l.firstChild.setAttribute('y1', '12');
      l.firstChild.setAttribute('x2', '19');
      l.firstChild.setAttribute('y2', '12');
      return l;
    },
    max: function () {
      var r = svg([['rect']]);
      r.firstChild.setAttribute('x', '5');
      r.firstChild.setAttribute('y', '5');
      r.firstChild.setAttribute('width', '14');
      r.firstChild.setAttribute('height', '14');
      r.firstChild.setAttribute('rx', '1.5');
      return r;
    },
    restore: function () {
      return svg([
        ['rect'],
        ['rect']
      ]);
    },
    close: function () {
      var s = svg([['line'], ['line']]);
      var a = s.childNodes;
      a[0].setAttribute('x1', '6');
      a[0].setAttribute('y1', '6');
      a[0].setAttribute('x2', '18');
      a[0].setAttribute('y2', '18');
      a[1].setAttribute('x1', '18');
      a[1].setAttribute('y1', '6');
      a[1].setAttribute('x2', '6');
      a[1].setAttribute('y2', '18');
      return s;
    }
  };

  // restore 图标两个方框（默认 5,5,14,14）
  function restoreIcon() {
    var s = ICON.restore();
    var a = s.childNodes;
    a[0].setAttribute('x', '4');
    a[0].setAttribute('y', '4');
    a[0].setAttribute('width', '11');
    a[0].setAttribute('height', '11');
    a[0].setAttribute('rx', '1.5');
    a[1].setAttribute('x', '9');
    a[1].setAttribute('y', '9');
    a[1].setAttribute('width', '11');
    a[1].setAttribute('height', '11');
    a[1].setAttribute('rx', '1.5');
    return s;
  }

  function button(name, label, cls) {
    var b = document.createElement('button');
    b.type = 'button';
    b.className = cls || '';
    b.setAttribute('aria-label', label);
    b.title = label;
    b.tabIndex = -1;
    return b;
  }

  var mounted = false;
  var root = null;
  var maxBtn = null;
  var maxIcon = null;
  var restoreEl = null;
  var maximized = false;

  function renderMaxIcon() {
    if (!maxBtn) return;
    if (maximized) {
      if (maxIcon) maxIcon.style.display = 'none';
      if (restoreEl) restoreEl.style.display = '';
    } else {
      if (maxIcon) maxIcon.style.display = '';
      if (restoreEl) restoreEl.style.display = 'none';
    }
  }

  function refreshMaximized() {
    Promise.resolve(ipc.invoke('sacp:host:invoke', 'window.is-maximized', undefined))
      .then(function (res) {
        if (!res || !res.ok) return;
        maximized = !!res.value;
        renderMaxIcon();
      })
      .catch(function () {});
  }

  function syncVisibility() {
    if (!root) return;
    // 页面自带窗口控件（登录页 AuthShell）时隐藏自己，避免两套按钮重叠
    var appHas = !!document.querySelector('.window-tools');
    var fullscreen = !!document.fullscreenElement;
    var visible = !(appHas || fullscreen);
    root.style.display = visible ? 'flex' : 'none';
    // 可见时内容整体下移 36px 让出顶部 titlebar（页面自定义按钮原位不动）
    if (document.body) {
      document.body.classList.toggle('scnet-wc-shift', visible);
      rescanTopLayers(); // 让位状态变化时同步已挂载的顶部弹层
    }
  }

  // ---------- 顶部 fixed 弹层避让 ----------
  // 顶部居中的 toast/弹层（如"检查更新"的"当前已是最新版本"提示）由渲染层在运行时动态插入、
  // position:fixed 贴视口 top:0，会被本注入的 36px titlebar 盖住。这里观察 body 直接子节点，
  // 命中"fixed + top 很小"的层就让位下移 36px（仅让位可见时）；容器销毁即放行，无残留。
  var SHIFTED_ATTR = 'data-scnet-wc-shifted';
  function isTopLayer(el) {
    if (!el || el.nodeType !== 1 || el === root) return false;
    var cs;
    try { cs = getComputedStyle(el); } catch (e) { return false; }
    if (!cs || cs.position !== 'fixed') return false;
    // 只避让"贴顶"的层：top 解析 < 我们的高度(36px) 才算被 titlebar 压住
    var top = parseFloat(cs.top);
    if (!isFinite(top) || top < 0 || top >= 36) return false;
    // 必须水平居中或居中区域（left≈50% 或 left/right 同时有限），避开侧边抽屉等
    var left = parseFloat(cs.left);
    var right = parseFloat(cs.right);
    var centered = (isFinite(left) && Math.abs(left - window.innerWidth / 2) < window.innerWidth * 0.25) ||
                   (isFinite(left) && isFinite(right));
    return centered;
  }
  function applyShift(el) {
    if (!document.body) return;
    var visible = document.body.classList.contains('scnet-wc-shift');
    if (visible && isTopLayer(el)) {
      el.setAttribute(SHIFTED_ATTR, '1');
      el.style.setProperty('top', '36px');
    } else if (el.hasAttribute && el.hasAttribute(SHIFTED_ATTR)) {
      el.removeAttribute(SHIFTED_ATTR);
      el.style.removeProperty('top');
    }
  }
  function rescanTopLayers() {
    if (!document.body) return;
    var kids = document.body.children;
    for (var i = 0; i < kids.length; i++) applyShift(kids[i]);
  }
  function observeTopLayers() {
    if (typeof MutationObserver === 'undefined' || !document.body) return;
    new MutationObserver(function (muts) {
      for (var i = 0; i < muts.length; i++) {
        var m = muts[i];
        if (m.type === 'childList') {
          for (var j = 0; j < m.addedNodes.length; j++) applyShift(m.addedNodes[j]);
        } else if (m.type === 'attributes' && m.target) {
          applyShift(m.target);
        }
      }
    }).observe(document.body, { childList: true, subtree: false, attributes: true, attributeFilter: ['style', 'class'] });
    rescanTopLayers();
  }

  function mount() {
    if (mounted || !document.documentElement) return;
    mounted = true;

    var style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = [
      // 顶部 titlebar：整条可拖动（-webkit-app-region:drag），标准按钮固定右端
      // 让位量做成变量：body padding 与下方 JS 下移的 fixed 弹层共用同一数值。
      'body.scnet-wc-shift{--scnet-wc-shift:36px;padding-top:var(--scnet-wc-shift)}',
      // body 下移 36px 后，100vh 元素（.agent-product-layout 等）仍按视口高排布，
      // 底部会溢出视口 36px 并被 body overflow:hidden 裁掉——输入框被挤出容器下缘，
      // 且 100vh 恒等于视口、拖拽窗口边框无法修正。让位时同步收缩这些元素。
      'body.scnet-wc-shift .h-screen{height:calc(100vh - 36px)}',
      // 顶部居中的 fixed 弹层（toast 等，如"当前已是最新版本"提示）在挂载时动态插入且贴视口
      // top:0，会被本注入的 36px titlebar 盖住。改由下方 observeTopLayers() 用 JS 精确处理，
      // 避免宽 CSS 选择器误命中无关 fixed 元素。
      '.' + CLS + '{position:fixed;top:0;left:0;right:0;height:36px;display:flex;align-items:center;justify-content:flex-end;',
      'background:var(--bg-main,#fff);border-bottom:.5px solid var(--border-main,rgba(0,0,0,.08));',
      '-webkit-app-region:drag;z-index:2147483647;user-select:none;pointer-events:auto}',
      '.' + CLS + ' .scnet-wc-item{display:flex;align-items:center;justify-content:center;',
      'width:46px;height:36px;padding:0;margin:0;border:0;background:transparent;',
      'color:var(--window-control-text,#1a1c1f);cursor:default;outline:none;',
      '-webkit-app-region:no-drag;appearance:none}',
      '.' + CLS + ' .scnet-wc-item:hover{background:var(--window-control-hover-bg,#f3f4f6)}',
      '.' + CLS + ' .scnet-wc-item:focus-visible{outline:1px solid currentColor;outline-offset:-4px}',
      '.' + CLS + ' .scnet-wc-close:hover{color:var(--window-control-close-text,#ffffff);',
      'background:var(--window-control-close-bg,#e81123)}'
    ].join('');
    document.documentElement.appendChild(style);

    root = document.createElement('div');
    root.className = CLS;
    root.setAttribute('role', 'group');
    root.setAttribute('aria-label', '窗口控制');

    var minBtn = button('min', '最小化', 'scnet-wc-item scnet-wc-min');
    minBtn.appendChild(ICON.min());

    maxBtn = button('max', '最大化', 'scnet-wc-item scnet-wc-maximize');
    maxIcon = ICON.max();
    restoreEl = restoreIcon();
    restoreEl.style.display = 'none';
    maxBtn.appendChild(maxIcon);
    maxBtn.appendChild(restoreEl);

    var closeBtn = button('close', '关闭', 'scnet-wc-item scnet-wc-close');
    closeBtn.appendChild(ICON.close());

    minBtn.addEventListener('click', function () {
      invoke('window.minimize');
    });
    maxBtn.addEventListener('click', function () {
      invoke('window.maximize').then(refreshMaximized);
    });
    closeBtn.addEventListener('click', function () {
      invoke('window.request-main-close');
    });

    root.appendChild(minBtn);
    root.appendChild(maxBtn);
    root.appendChild(closeBtn);
    document.documentElement.appendChild(root);

    window.addEventListener('resize', function () {
      refreshMaximized();
      syncVisibility();
    });
    window.addEventListener('focus', refreshMaximized);

    if (typeof MutationObserver !== 'undefined') {
      var scheduled = false;
      new MutationObserver(function () {
        if (scheduled) return;
        scheduled = true;
        requestAnimationFrame(function () {
          scheduled = false;
          syncVisibility();
        });
      }).observe(document.documentElement, { childList: true, subtree: true });
    }

    syncVisibility();
    refreshMaximized();
    observeTopLayers();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', mount, { once: true });
  } else {
    mount();
  }
})();
