#!/bin/bash
# patch-spark-toolargs.sh — 讯飞 spark-x2.6 tool_calls 参数清洗（Loomy 移植）
#
# 背景：xf-yun /v2/chat/completions 对 tool_calls[].function.arguments 强校验，
#   只接受"含合法 JSON 对象的字符串"；空串 / 双重编码 / 非法 JSON →
#   400 {"error":{"code":10005,"message":"invalid request"}}。
#   opencode 在工具参数 JSON 解析失败时把原始字符串存进 part.state.input，
#   发送时 JSON.stringify(字符串) 再包一层 → 双重编码 → 该 session 每次重试都 400。
#
# 改法（两处插入，幂等）：给 LOOMY_CHAT_HEADERS_PLUGIN_SOURCE 模板内加
#   1) coerceToolArgsLocal helper：字符串反复 JSON.parse（≤4 次）收敛为对象，
#      失败或非对象返回 {}
#   2) experimental.chat.messages.transform hook：原地把 type==='tool' 的
#      part.state.input 清洗为对象（不重赋值 output.messages，那是静默 no-op）
#   该 hook 在 toModelMessages 之前触发，对所有 provider 无害（arguments 本就该是对象）。
#
# 用法：patch-spark-toolargs.sh <asar解包根目录 | loomy-chat-headers-source(.mjs) 文件路径>
set -euo pipefail

ARG="${1:?用法：patch-spark-toolargs.sh <asar解包根目录 | 源文件路径>}"

if [ -d "$ARG" ]; then
  SRC="$ARG/electron/opencode-plugin/loomy-chat-headers-source.js"
else
  SRC="$ARG"
fi
[ -f "$SRC" ] || { echo "未找到 $SRC（先 asar extract）" >&2; exit 1; }

python3 - "$SRC" <<'PY'
import sys, io

MARK = "SPARK_TOOLARGS_PATCH"
src_path = sys.argv[1]

def load(p):
    return io.open(p, encoding="utf-8").read()

def save(p, s):
    io.open(p, "w", encoding="utf-8").write(s)

src = load(src_path)
if MARK in src:
    print("已补丁(跳过)：", src_path)
    sys.exit(0)

anchor_helper = "export const Plugin = async (pluginInput) => {"
anchor_hook = "    'shell.env': async (_input, output) => {"
assert src.count(anchor_helper) == 1, "Plugin 锚点与预期不符"
assert src.count(anchor_hook) == 1, "shell.env 锚点与预期不符"

helper = """// SPARK_TOOLARGS_PATCH: 讯飞 MaaS 要求 arguments 为合法 JSON 对象字符串。
// opencode 把解析失败的原始参数串存进 state.input，JSON.stringify 会双重编码 → 400。
function coerceToolArgsLocal(input) {
  let current = input
  for (let i = 0; i < 4; i += 1) {
    if (typeof current !== 'string') break
    try {
      current = JSON.parse(current)
    } catch (err) {
      return {}
    }
  }
  if (current === null || typeof current !== 'object' || Array.isArray(current)) return {}
  return current
}

"""

hook = """    // SPARK_TOOLARGS_PATCH: 发送前清洗历史工具参数，规避讯飞 10005 invalid request
    'experimental.chat.messages.transform': async (_input, output) => {
      try {
        const messages = output && Array.isArray(output.messages) ? output.messages : null
        if (!messages) return
        for (const message of messages) {
          if (!message || !Array.isArray(message.parts)) continue
          for (const part of message.parts) {
            if (!part || part.type !== 'tool') continue
            const state = part.state
            if (!state || typeof state !== 'object') continue
            if (typeof state.input !== 'string') continue
            state.input = coerceToolArgsLocal(state.input)
          }
        }
      } catch (err) {
        try {
          console.warn('[loomy-chat-headers] chat.messages.transform hook 失败:', err && err.message ? err.message : String(err))
        } catch {
          // 忽略 console 失败
        }
      }
    },
"""

src = src.replace(anchor_helper, helper + anchor_helper, 1)
src = src.replace(anchor_hook, hook + anchor_hook, 1)
save(src_path, src)
print("已补丁：", src_path)
PY

echo "--- 关键改动预览 ---"
grep -nE "SPARK_TOOLARGS_PATCH|chat.messages.transform" "$SRC" | head -10 || true
# 源文件是 ESM（export 语句），node --check 默认按 CJS 解析会误报，复制成 .mjs 再查
CHK="$(mktemp --suffix=.mjs)"
cp "$SRC" "$CHK"
node --check "$CHK" && echo "语法 OK: $SRC"
rm -f "$CHK"
