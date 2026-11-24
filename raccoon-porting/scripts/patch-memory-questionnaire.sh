#!/bin/bash
# patch-memory-questionnaire.sh — 首页「完善资料」入口改走引导向导的记忆步骤
#
# 用法: patch-memory-questionnaire.sh <asar解包目录>
# 目标: out/_next/static/chunks/app/layout-*.js，2 处替换。
#
# 为什么: cloud 构建（package.json raccoonMemoryMode=cloud）里，首页提示
#   「完善资料，让商汤小浣熊更懂你」打开的是 **本地** 记忆问卷组件（gf），
#   保存走 desktop-client:save-memory-questionnaire → assertLegacyMemoryMode()，
#   该断言要求构建模式为 local，cloud 构建必然抛 MEMORY_MODE_MISMATCH，
#   前端只显示「资料保存失败，内容已保留」，重试无效。
#   引导向导的「记忆」步骤本身按 memory-v2 status 分流（local→本地问卷，
#   cloud→memory-v2 问卷），所以把入口接到向导步骤 1 即可两种构建都可用。
#
# 补丁内容:
#   1) openOnboarding:()=>setState(!0)  →  openOnboarding:(s=0)=>wizard.open(s)
#   2) 首页提示 onClick:()=>t.openOnboarding?.()  →  ...?.(1)
# 变量名（setState/wizard）按压缩产物自动识别，不绑定具体版本。
set -euo pipefail

TREE="${1:?用法: patch-memory-questionnaire.sh <asar解包目录>}"
[ -d "$TREE/out" ] || { echo "错误: 找不到 $TREE/out" >&2; exit 1; }

python3 - "$TREE" <<'PY'
import os
import re
import sys

tree = sys.argv[1]
HINT_OLD = "onClick:()=>t.openOnboarding?.()"
HINT_NEW = "onClick:()=>t.openOnboarding?.(1)"
ONB_RE = re.compile(r"openOnboarding:\(\)=>([A-Za-z_$][\w$]*)\(!0\)")
WIZ_RE = re.compile(
    r"([A-Za-z_$][\w$]*)=function\(\{signedIn:[A-Za-z_$][\w$]*,"
    r"prepared:[A-Za-z_$][\w$]*,blocked:[A-Za-z_$][\w$]*\}\)"
)

targets = []
for dirpath, _, names in os.walk(os.path.join(tree, "out")):
    for name in names:
        if not name.endswith(".js"):
            continue
        path = os.path.join(dirpath, name)
        with open(path, encoding="utf-8", errors="ignore") as fh:
            src = fh.read()
        if HINT_OLD in src or HINT_NEW in src:
            targets.append((path, src))

if len(targets) != 1:
    print(f"错误: 首页资料入口命中 {len(targets)} 个文件（应为 1 个），中止", file=sys.stderr)
    sys.exit(2)

path, src = targets[0]
if HINT_OLD not in src:
    if HINT_NEW in src:
        print("patch-memory-questionnaire: 已是补丁后状态，跳过")
        sys.exit(0)
    print("错误: 未找到首页资料入口 onClick 片段", file=sys.stderr)
    sys.exit(2)

# 向导 hook 变量（tF/tB/...）紧跟在 getOnboardingStatus 之前定义，自动识别。
status_pos = src.find("getOnboardingStatus")
prefix = src[:status_pos] if status_pos >= 0 else ""
wiz_matches = WIZ_RE.findall(prefix[-6000:])
if not wiz_matches:
    print("错误: 未能识别引导向导 hook 变量（getOnboardingStatus 结构变化？）", file=sys.stderr)
    sys.exit(2)
wizard = wiz_matches[-1]
tail = src[status_pos:status_pos + 3000] if status_pos >= 0 else ""
if "{initialStep:" not in tail or "open:" not in tail or "close:" not in tail:
    print(f"错误: {wizard} 不像引导向导 hook（缺 initialStep/open/close），中止", file=sys.stderr)
    sys.exit(2)

n_onb = len(ONB_RE.findall(src))
if n_onb != 1:
    print(f"错误: openOnboarding 定义命中 {n_onb} 处（应为 1 处），中止", file=sys.stderr)
    sys.exit(2)
if src.count(HINT_OLD) != 1:
    print(f"错误: 首页提示 onClick 命中 {src.count(HINT_OLD)} 处（应为 1 处），中止", file=sys.stderr)
    sys.exit(2)

src = ONB_RE.sub(f"openOnboarding:(s=0)=>{wizard}.open(s)", src, count=1)
src = src.replace(HINT_OLD, HINT_NEW, 1)

# 复核
assert src.count(HINT_NEW) == 1
assert HINT_OLD not in src
assert f"openOnboarding:(s=0)=>{wizard}.open(s)" in src
assert len(ONB_RE.findall(src)) == 0

with open(path, "w", encoding="utf-8") as fh:
    fh.write(src)

print(f"patch-memory-questionnaire: 已打 2 处补丁（向导变量 {wizard}）-> {os.path.relpath(path, tree)}")
PY
