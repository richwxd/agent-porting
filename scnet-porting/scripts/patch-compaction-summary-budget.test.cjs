'use strict';
// scnet-porting: patch-compaction-summary-budget.cjs 的最小桩测试（node scripts/patch-compaction-summary-budget.test.cjs）
// 覆盖：目标唯一出现时替换 8192→32768；缺失时非零退出且不改写；多处出现时非零退出且不改写。
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const SRC = path.join(__dirname, 'patch-compaction-summary-budget.cjs');
const NEEDLE = 'Math.min(t.summaryBudgetTokens??1/0,8192,';
const REPL = 'Math.min(t.summaryBudgetTokens??1/0,32768,';

function run(content) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'patch-budget-'));
  const f = path.join(dir, 'b.js');
  fs.writeFileSync(f, content);
  let status = 0;
  try {
    execFileSync(process.execPath, [SRC, f], { stdio: 'pipe' });
  } catch (e) {
    status = e.status || 1;
  }
  return { status, out: fs.readFileSync(f, 'utf8') };
}

// 1) 唯一出现 → 替换成功
const once = run('function tK(e,t,r){let n=' + NEEDLE + 'Math.max(512,1))}');
assert.strictEqual(once.status, 0, '唯一出现应成功');
assert.ok(once.out.includes(REPL), '应包含新值');
assert.ok(!once.out.includes(NEEDLE), '应不含旧值');

// 2) 缺失 → 非零退出且不改写
const missSrc = 'function tK(e,t,r){return 0}';
const miss = run(missSrc);
assert.notStrictEqual(miss.status, 0, '缺失应失败');
assert.strictEqual(miss.out, missSrc, '失败时不得改写');

// 3) 两处 → 非零退出且不改写
const dupSrc = NEEDLE + ';' + NEEDLE;
const dup = run(dupSrc);
assert.notStrictEqual(dup.status, 0, '多处应失败');
assert.strictEqual(dup.out, dupSrc, '失败时不得改写');

console.log('patch-compaction-summary-budget.test.cjs OK');
