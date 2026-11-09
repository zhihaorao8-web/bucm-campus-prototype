const fs=require('fs'),vm=require('vm'),assert=require('assert');
const script=fs.readFileSync(require('path').join(__dirname,'../assets/extract.js'),'utf8');
function cell(text,cs=1,rs=1){return {innerText:text,colSpan:cs,rowSpan:rs};}
function table(rows){return {rows:rows.map(cells=>({cells})),querySelector:()=>null,closest:()=>null};}
function doc(tables,frames=[],text=''){return {body:{innerText:text},querySelectorAll:s=>s==='table'?tables:s==='iframe,frame'?frames:[]};}
function read(document){return JSON.parse(vm.runInNewContext(script,{document}));}
const headers=[cell('节次'),...['一','二','三','四','五','六','日'].map(x=>cell('星期'+x))];
const course=table([headers,[cell('第1-2节'),cell('中医基础理论\n1-16周\n教室：101',1,2),cell(''),cell(''),cell(''),cell(''),cell(''),cell('')],[cell('第3节'),cell('周二课程'),cell(''),cell(''),cell(''),cell(''),cell('')]]);
let r=read(doc([course]));assert.equal(r.tables.length,1);assert.equal(r.tables[0].candidates.length,2);assert.equal(r.tables[0].candidates[1].day,2);assert.equal(r.tables[0].candidates[0].rowLabel,'第1-2节');
assert.equal(read(doc([table([[cell('账号'),cell('密码')]])])).tables.length,0);
const blocked={get contentDocument(){throw Error('cross origin');}};
r=read(doc([],[blocked]));assert.equal(r.blockedFrames,1);assert.equal(r.tables.length,0);
r=read(doc([],[{contentDocument:doc([course])}]));assert.equal(r.tables.length,1);
const multiText='合成课程甲\n示例教师甲\n9-17(周)[01-02-03节]\n合成楼101室\n---------------------\n合成课程甲\n示例教师乙\n4-8(周)[01-02-03节]\n合成楼202室\n\n合成课程乙\n1-3(周)[01-02-03-04节]';
r=read(doc([table([headers,[cell('第1-4节'),cell(multiText),...Array.from({length:6},()=>cell(''))]])]));
assert.equal(r.tables[0].candidates.length,1);assert.equal(r.tables[0].candidates[0].text,multiText);assert.equal(r.tables[0].candidates[0].day,1);
assert.equal(read(doc([course],[],'合成学校2026-2027-1学期')).semester,'2026-2027-1');
assert.equal(read(doc([course],[],'2026-2027-1及2026-2027-2')).semester,'');
console.log('DOM extraction checks passed (week columns, rowspan, login rejection, same/cross-origin frames)');
