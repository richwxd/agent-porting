#!/usr/bin/env node
// patch-linux-titlebar.test.cjs — Loomy Linux 自绘 titlebar 补丁的最小可运行校验
// 流程：从已安装 app.asar 抽 3 个目标文件 → 跑 patch-linux-titlebar.sh →
//      1) 三处改动落位 + node --check（由补丁脚本自身执行）
//       2) vm 跑注入段：linux 主窗口注入三按钮、点击发 IPC；win32/非主窗口不注入
// 用法：node scripts/patch-linux-titlebar.test.cjs
"use strict";
const { execFileSync, execSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const vm = require("node:vm");

const ROOT = path.join(__dirname, "..");
const ASAR = "/opt/xunfei/loomy/resources/app.asar";
const MARK = "// LOOMY_LINUX_TITLEBAR_PATCH: Linux 自绘 titlebar";
const FILES = [
  "electron/windows/main-window-controller.js",
  "electron/main.js",
  "electron/preload.js",
];

function assert(cond, msg) {
  if (!cond) {
    console.error("FAIL: " + msg);
    process.exit(1);
  }
}

assert(fs.existsSync(ASAR), "缺少 " + ASAR + "（先安装 loomy）");

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "loomy-titlebar-test-"));
const tree = path.join(tmp, "tree");
fs.mkdirSync(tree, { recursive: true });

// 1) 从 asar 抽目标文件（extract-file 写到 cwd，逐个在临时目录里抽再归位）
for (const rel of FILES) {
  const dir = path.join(tree, path.dirname(rel));
  fs.mkdirSync(dir, { recursive: true });
  const cwd = fs.mkdtempSync(path.join(tmp, "x-"));
  execFileSync("asar", ["extract-file", ASAR, rel], { cwd });
  fs.renameSync(path.join(cwd, path.basename(rel)), path.join(tree, rel));
}

// 2) 打补丁（幂等，已打过也直接继续）
execSync("bash " + JSON.stringify(path.join(ROOT, "scripts/patch-linux-titlebar.sh")) + " " + JSON.stringify(tree), {
  stdio: "inherit",
});

const wctrl = fs.readFileSync(path.join(tree, FILES[0]), "utf8");
const main = fs.readFileSync(path.join(tree, FILES[1]), "utf8");
const preload = fs.readFileSync(path.join(tree, FILES[2]), "utf8");

assert(/frame: isWindows \|\| platform === 'linux' \? false : undefined/.test(wctrl), "frame 行未改为 Linux 无边框");
assert(main.includes('ipcMain.handle("loomy:window-control"'), "main.js 缺窗口控制通道");
assert(main.includes("LOOMY_LINUX_TITLEBAR_PATCH"), "main.js 缺补丁标记");
assert(preload.includes(MARK), "preload.js 缺注入段");

const injStart = preload.indexOf(MARK);
const injection = preload.slice(injStart);
assert(injection.includes("--titlebar-overlay-height:36px"), "注入段缺 overlay 高度规则");
assert(injection.includes("loomy-linux-wc"), "注入段缺按钮容器");

// 3) vm 行为：stub document/window 环境跑注入段
function makeEl(tag) {
  return {
    tag, id: "", className: "", type: "", textContent: "", innerHTML: "",
    attrs: {}, children: [], handlers: {},
    setAttribute(k, v) { this.attrs[k] = v; },
    addEventListener(ev, fn) { this.handlers[ev] = fn; },
    appendChild(c) { this.children.push(c); return c; },
  };
}
function makeDoc() {
  const doc = {
    readyState: "complete",
    _appended: [],
    documentElement: makeEl("html"),
    listeners: {},
    createElement: (t) => makeEl(t),
    addEventListener(ev, fn) { this.listeners[ev] = fn; },
  };
  doc.documentElement.classList = (() => {
    const s = new Set();
    return { add: (c) => s.add(c), contains: (c) => s.has(c), toggle: (c, v) => (v ? s.add(c) : s.delete(c)) };
  })();
  doc.documentElement.appendChild = function (c) { this.children.push(c); doc._appended.push(c); return c; };
  doc.getElementById = function (id) {
    return doc._appended.find((el) => el.id === id) || null;
  };
  return doc;
}
function runInjection(platform, pathname, hash) {
  const doc = makeDoc();
  const invokes = [];
  const sandbox = {
    process: { platform },
    location: { pathname, hash },
    document: doc,
    ipcRenderer: { invoke: (ch, act) => { invokes.push([ch, act]); return Promise.resolve(true); } },
    console,
  };
  vm.runInNewContext(injection, sandbox, { filename: "injection.js" });
  return { doc, invokes };
}

// 3a) linux 主窗口 → 注入
{
  const { doc, invokes } = runInjection("linux", "/opt/xunfei/loomy/resources/app/dist/index.html", "");
  assert(doc.documentElement.classList.contains("loomy-linux-wc-on"), "html 未挂 loomy-linux-wc-on");
  const style = doc._appended.find((el) => el.tag === "style");
  assert(style && style.textContent.includes("--titlebar-overlay-height:36px"), "style 未注入 overlay 规则");
  assert(style && style.textContent.includes("loomy-titlebar-system-strip"), "style 未补 strip 分隔线");
  const box = doc._appended.find((el) => el.id === "loomy-linux-wc");
  assert(box, "按钮容器未注入");
  assert(box.children.length === 3, "按钮数应为 3，实际 " + box.children.length);
  const acts = box.children.map((b) => b.attrs["aria-label"]);
  assert(JSON.stringify(acts) === JSON.stringify(["minimize", "maximize", "close"]), "按钮顺序/名称不对: " + acts);
  assert(box.children.every((b) => b.innerHTML.includes("<svg")), "按钮缺 svg 图标");
  box.children[2].handlers.click({ preventDefault() {}, stopPropagation() {} });
  assert(invokes.length === 1 && invokes[0][0] === "loomy:window-control" && invokes[0][1] === "close", "close 点击未发 IPC");
}

// 3b) win32 → 不注入（Windows 用原生 overlay）
{
  const { doc } = runInjection("win32", "C:\\app\\dist\\index.html", "");
  assert(!doc._appended.some((el) => el.id === "loomy-linux-wc"), "win32 不应注入按钮");
}

// 3c) 非主窗口 pathname → 不注入
{
  const { doc } = runInjection("linux", "/opt/xunfei/loomy/resources/app/dist/markdown-viewer.html", "");
  assert(!doc._appended.some((el) => el.id === "loomy-linux-wc"), "非主窗口不应注入按钮");
}

// 3d) 全局搜索窗 → 不注入
{
  const { doc } = runInjection("linux", "/opt/xunfei/loomy/resources/app/dist/index.html", "#/global-search");
  assert(!doc._appended.some((el) => el.id === "loomy-linux-wc"), "全局搜索窗不应注入按钮");
}

fs.rmSync(tmp, { recursive: true, force: true });
console.log("patch-linux-titlebar.test.cjs OK");
