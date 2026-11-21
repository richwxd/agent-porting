#!/usr/bin/env node
// patch-spark-toolargs.test.cjs — 讯飞 tool 参数清洗补丁的最小可运行校验
// 流程：从已安装 app.asar 抽 loomy-chat-headers-source.js → 跑 patch-spark-toolargs.sh →
//       1) 标记落位 + 幂等重跑 + node --check（由补丁脚本自身执行）
//       2) 取模板写成 .mjs 动态 import，调 experimental.chat.messages.transform：
//          非法 JSON 串 → {}；双重编码 → 解出对象；合法对象串 → 解析；
//          已是对象 → 原样；数组/标量串 → {}；output.messages 引用不变（原地改）
// 用法：node scripts/patch-spark-toolargs.test.cjs
"use strict";
const { execFileSync, execSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { pathToFileURL } = require("node:url");

const ROOT = path.join(__dirname, "..");
const ASAR = "/opt/xunfei/loomy/resources/app.asar";
const REL = "electron/opencode-plugin/loomy-chat-headers-source.js";
const MARK = "SPARK_TOOLARGS_PATCH";

function assert(cond, msg) {
  if (!cond) {
    console.error("FAIL: " + msg);
    process.exit(1);
  }
}

(async () => {
  assert(fs.existsSync(ASAR), "缺少 " + ASAR + "（先安装 loomy）");

  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "loomy-spark-test-"));
  const tree = path.join(tmp, "tree");
  const dir = path.join(tree, path.dirname(REL));
  fs.mkdirSync(dir, { recursive: true });

  // 1) 从 asar 抽目标文件
  const xcwd = fs.mkdtempSync(path.join(tmp, "x-"));
  execFileSync("asar", ["extract-file", ASAR, REL], { cwd: xcwd });
  fs.renameSync(path.join(xcwd, path.basename(REL)), path.join(tree, REL));

  // 2) 打补丁（幂等，重跑必须跳过）
  const script = path.join(ROOT, "scripts/patch-spark-toolargs.sh");
  execSync("bash " + JSON.stringify(script) + " " + JSON.stringify(tree), { stdio: "inherit" });
  execSync("bash " + JSON.stringify(script) + " " + JSON.stringify(tree), { stdio: "inherit" });

  const src = fs.readFileSync(path.join(tree, REL), "utf8");
  assert(src.includes(MARK), "源文件缺补丁标记");
  assert(src.includes("'experimental.chat.messages.transform'"), "源文件缺 transform hook");
  assert(src.includes("function coerceToolArgsLocal"), "源文件缺 coerce helper");

  // 3) 模板 → 真实 .mjs → import → 调 hook
  const srcMjs = path.join(tmp, "source.mjs");
  fs.copyFileSync(path.join(tree, REL), srcMjs);
  const sourceMod = await import(pathToFileURL(srcMjs).href);
  const pluginSrc = sourceMod.LOOMY_CHAT_HEADERS_PLUGIN_SOURCE;
  assert(typeof pluginSrc === "string" && pluginSrc.length > 0, "模板常量缺失");

  const pluginMjs = path.join(tmp, "loomy-chat-headers.mjs");
  fs.writeFileSync(pluginMjs, pluginSrc);
  execFileSync(process.execPath, ["--check", pluginMjs], { stdio: "inherit" });

  const pluginMod = await import(pathToFileURL(pluginMjs).href);
  const hooks = await pluginMod.default({ client: null });
  const transform = hooks["experimental.chat.messages.transform"];
  assert(typeof transform === "function", "hooks 缺 experimental.chat.messages.transform");

  function toolMsg(input) {
    return { info: { role: "assistant" }, parts: [{ type: "tool", state: { input } }] };
  }
  async function run(input) {
    const messages = [toolMsg(input)];
    const arrRef = messages;
    await transform({}, { messages });
    assert(messages === arrRef, "output.messages 引用被重赋值（原地改契约被破坏）");
    return messages[0].parts[0].state.input;
  }

  // 真实故障样本：内层 JSON 非法（图片路径没加引号）→ opencode 存了原始字符串
  const bad = '{"images":[.loomy-attachments/ses_x/1795095431497-0-image.png],"prompt":"看一下这张图"}';
  assert(JSON.stringify(await run(bad)) === "{}", "非法 JSON 串应清洗为 {}");

  // 双重编码（JSON 字符串套字符串）→ 解两层得到对象
  const doubleEnc = JSON.stringify(JSON.stringify({ prompt: "hi" }));
  assert(JSON.stringify(await run(doubleEnc)) === '{"prompt":"hi"}', "双重编码应解出对象");

  // 合法对象串 → 解析一层
  assert(JSON.stringify(await run('{"a":1}')) === '{"a":1}', "合法对象串应解析");

  // 已是对象 → 原样
  assert(JSON.stringify(await run({ b: 2 })) === '{"b":2}', "对象 input 应原样保留");

  // 数组串 / 标量串 / 垃圾串 → {}
  assert(JSON.stringify(await run("[1,2]")) === "{}", "数组串应清洗为 {}");
  assert(JSON.stringify(await run("5")) === "{}", "标量串应清洗为 {}");
  assert(JSON.stringify(await run("not json")) === "{}", "垃圾串应清洗为 {}");

  // 非 tool part 不动；缺 parts / 缺 messages 不抛
  const edge = { messages: [null, {}, { parts: null }, { parts: [{ type: "text", text: "x" }] }] };
  await transform({}, edge);
  assert(edge.messages[3].parts[0].text === "x", "非 tool part 被改动");
  await transform({}, {});
  await transform({}, { messages: "nope" });

  console.log("PASS: patch-spark-toolargs.test.cjs");
})().catch((err) => {
  console.error("FAIL:", err && err.stack ? err.stack : err);
  process.exit(1);
});
