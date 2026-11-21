'use strict';
// scnet-porting: patch-composer-multi-skill.cjs 的最小桩测试
// 覆盖：五个目标各唯一出现时替换成功；任一缺失时非零退出且不改写；重复出现时非零退出且不改写。
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const SRC = path.join(__dirname, 'patch-composer-multi-skill.cjs');
const NEEDLES = [
  ['function q(){return t.value?[]:a.value.map(e=>({kind:"skill"', 'function q(){return a.value.filter(e=>!t.value.includes(e.id)).map(e=>({kind:"skill"'],
  ['en=(0,s.IJ)(0),ei=(0,s.IJ)(!1),eo=(0,s.IJ)(!1),er=(0,s.IJ)(!1)', 'en=(0,s.IJ)(0),ei=(0,s.IJ)(!1),eo=(0,s.IJ)([]),er=(0,s.IJ)(!1)'],
  ['eo.value=a.some(e=>"skill"===e.type),er.value=a.some(e=>"text"!==e.type)', 'eo.value=a.filter(e=>"skill"===e.type).map(e=>e.id),er.value=a.some(e=>"text"!==e.type)'],
  ['if("skill"===t.type){i||(s.push(t),i=!0),o=!1;continue}', 'if("skill"===t.type){s.push(t),i=!0,o=!1;continue}'],
  ['s=e.skill,!t.value&&(L.value?L.value.command(s):F.value?.insertSkill(s),(0,d.c_)("SCNetClientAgentAction",{action_type:"select_skill",action_result:"succeeded"}),el(),F.value?.focusEditor()))', 's=e.skill,L.value?L.value.command(s):F.value?.insertSkill(s),(0,d.c_)("SCNetClientAgentAction",{action_type:"select_skill",action_result:"succeeded"}),el(),F.value?.focusEditor())'],
];

function run(content) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'patch-multi-skill-'));
  const f = path.join(dir, 'vq.js');
  fs.writeFileSync(f, content);
  let status = 0;
  try {
    execFileSync(process.execPath, [SRC, f], { stdio: 'pipe' });
  } catch (e) {
    status = e.status || 1;
  }
  return { status, out: fs.readFileSync(f, 'utf8') };
}

const GOOD = NEEDLES.map(n => n[0]).join('|');

// 1) 五处各唯一 → 替换成功
const ok = run(GOOD);
assert.strictEqual(ok.status, 0, '唯一出现应成功');
assert.ok(NEEDLES.every(n => ok.out.includes(n[1])), '应包含新值');
assert.ok(NEEDLES.every(n => !ok.out.includes(n[0])), '应不含旧值');

// 2) 缺一个 → 非零退出且不改写
const missSrc = NEEDLES.slice(0, 4).map(n => n[0]).join('|');
const miss = run(missSrc);
assert.notStrictEqual(miss.status, 0, '缺失应失败');
assert.strictEqual(miss.out, missSrc, '失败时不得改写');

// 3) 一个重复 → 非零退出且不改写
const dupSrc = NEEDLES.map(n => n[0]).join('|') + '|' + NEEDLES[4][0];
const dup = run(dupSrc);
assert.notStrictEqual(dup.status, 0, '多处应失败');
assert.strictEqual(dup.out, dupSrc, '失败时不得改写');

// 4) 幂等：改完再跑一次应失败（旧串已消失），不产生二次改写
const again = run(ok.out);
assert.notStrictEqual(again.status, 0, '重复执行应失败');
assert.strictEqual(again.out, ok.out, '重复执行不得改写');

console.log('patch-composer-multi-skill.test.cjs OK');
