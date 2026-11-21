'use strict';
// scnet-porting: 压缩摘要输出预算硬顶 8192 → 32768（patch-compaction-summary-budget.cjs）
// 症状：长会话自动压缩时摘要生成撞 token 上限（stopReason=length →
// "Summarization failed: generation hit the token cap and the summary is incomplete"），
// 压缩失败后仍超阈值 ⇒ 抛 "Context remains above the safe request budget after compaction."。
// 根因：b.js 里 summaryBudgetTokens 被 Math.min(...,8192,...) 硬顶，settings 无法覆盖
// （getCompactionSettings 只返回 enabled/reserveTokens/keepRecentTokens）。
// 该 Math.min 在整个 app 树唯一；出现次数 ≠1 时直接失败（升级客户端后需人工核对）。
const fs = require('fs');

const file = process.argv[2];
if (!file) {
  console.error('用法: node patch-compaction-summary-budget.cjs <b.js 路径>');
  process.exit(2);
}
const NEEDLE = 'Math.min(t.summaryBudgetTokens??1/0,8192,';
const REPL = 'Math.min(t.summaryBudgetTokens??1/0,32768,';
const src = fs.readFileSync(file, 'utf8');
const count = src.split(NEEDLE).length - 1;
if (count !== 1) {
  console.error('patch-compaction-summary-budget: 期望唯一 ' + JSON.stringify(NEEDLE) + '，实际 ' + count + ' 处（' + file + '）');
  process.exit(1);
}
fs.writeFileSync(file, src.replace(NEEDLE, REPL));
console.log('patch-compaction-summary-budget: summaryBudgetTokens 硬顶 8192 → 32768');
