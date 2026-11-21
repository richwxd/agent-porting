'use strict';
// scnet-porting: composer 支持一次追加多个技能（patch-composer-multi-skill.cjs）
// 症状：输入框里已有一个技能 chip 后，再按 "/" 或 "+" 打开下拉，技能分组整个消失，
// 无法追加第二个技能（用户反馈「对话框只能加载一次技能，想要追加技能，下拉备选没有了」）。
// 根因（dist/static/js/async/vq.*.js 四处联动，同一个开关）：
//  1) 下拉项工厂 function q(){return t.value?[]:a.value.map(...)} —— t=hasSelectedSkill，
//     只要文档里存在一个 skill 段就整体返回空数组；q() 同时喂手动 palette(H) 和 "/" 下拉
//     (ee 的 slash 分支)，于是两处一起丢掉技能分组。
//     设计意图是「已选的那条不重复出现在下拉里」，不是「整个技能组隐藏」——
//     改成按已选 id 过滤：q() = suggestions 里排除已在文档中的技能。
//  2) hasSelectedSkill 存的是布尔（eo=ref(!1) + eo.value=a.some(...)），没法做过滤，
//     改存已选技能 id 数组：init []、ty() 里 filter().map(e=>e.id)。
//  3) 段规范化器 _() 的 i||(s.push(t),i=!0) 只保留第一个 skill 段 —— 草稿恢复走
//     setSegments()→_() 时会把第二个 chip 静默丢掉（UI 能选、payload 没有 ⇒ 断链）。
//  4) selectPaletteItem 还有第二道单选闸门 !t.value&&(...)：t 变成 id 数组后数组恒真，
//     闸门恒关 ⇒ 点下拉项插不进任何技能（用户反馈「没有办法选中任何技能」），必须放开。
// 发送主路径 tp()/getSegments() 不去重，无需改。
// 五个串在 app 树各唯一；出现次数 !=1 时直接失败（升级客户端后需人工核对）。
const fs = require('fs');

const file = process.argv[2];
if (!file) {
  console.error('用法: node patch-composer-multi-skill.cjs <vq chunk 路径>');
  process.exit(2);
}
const NEEDLES = [
  // 1) 下拉技能分组：已选的按 id 排除，而不是整个清空
  { from: 'function q(){return t.value?[]:a.value.map(e=>({kind:"skill"',
    to: 'function q(){return a.value.filter(e=>!t.value.includes(e.id)).map(e=>({kind:"skill"',
    what: '下拉只排除已选技能而非整体隐藏' },
  // 2) hasSelectedSkill 改存已选技能 id 数组
  { from: 'en=(0,s.IJ)(0),ei=(0,s.IJ)(!1),eo=(0,s.IJ)(!1),er=(0,s.IJ)(!1)',
    to: 'en=(0,s.IJ)(0),ei=(0,s.IJ)(!1),eo=(0,s.IJ)([]),er=(0,s.IJ)(!1)',
    what: 'hasSelectedSkill 初始化为空数组' },
  { from: 'eo.value=a.some(e=>"skill"===e.type),er.value=a.some(e=>"text"!==e.type)',
    to: 'eo.value=a.filter(e=>"skill"===e.type).map(e=>e.id),er.value=a.some(e=>"text"!==e.type)',
    what: '记录已选技能 id 列表' },
  // 3) 规范化时保留全部技能段（不再只留第一个）
  { from: 'if("skill"===t.type){i||(s.push(t),i=!0),o=!1;continue}',
    to: 'if("skill"===t.type){s.push(t),i=!0,o=!1;continue}',
    what: '技能段规范化保留全部' },
  // 4) 放开 selectPaletteItem 的单选闸门
  { from: 's=e.skill,!t.value&&(L.value?L.value.command(s):F.value?.insertSkill(s),(0,d.c_)("SCNetClientAgentAction",{action_type:"select_skill",action_result:"succeeded"}),el(),F.value?.focusEditor()))',
    to: 's=e.skill,L.value?L.value.command(s):F.value?.insertSkill(s),(0,d.c_)("SCNetClientAgentAction",{action_type:"select_skill",action_result:"succeeded"}),el(),F.value?.focusEditor())',
    what: '放开选技能的单选闸门' },
];

const src = fs.readFileSync(file, 'utf8');
for (const n of NEEDLES) {
  const count = src.split(n.from).length - 1;
  if (count !== 1) {
    console.error('patch-composer-multi-skill: 期望唯一 ' + JSON.stringify(n.from.slice(0, 48)) + '…，实际 ' + count + ' 处（' + file + '）');
    process.exit(1);
  }
}
let out = src;
for (const n of NEEDLES) out = out.replace(n.from, n.to);
fs.writeFileSync(file, out);
console.log('patch-composer-multi-skill: ' + NEEDLES.map(n => n.what).join('；'));
