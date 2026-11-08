const fs=require('fs'),vm=require('vm'),assert=require('assert');
const script=fs.readFileSync(require('path').join(__dirname,'../assets/extract.js'),'utf8');
function cell(text,cs=1,rs=1){return {innerText:text,colSpan:cs,rowSpan:rs};}
function table(rows){return {rows:rows.map(cells=>({cells})),querySelector:()=>null,closest:()=>null};}
function doc(tables,frames=[]){return {querySelectorAll:s=>s==='table'?tables:frames};}
function read(document){return JSON.parse(vm.runInNewContext(script,{document}));}
const headers=[cell('节次'),...['一','二','三','四','五','六','日'].map(x=>cell('星期'+x))];
const course=table([headers,[cell('第1-2节'),cell('中医基础理论\n1-16周\n教室：101',1,2),cell(''),cell(''),cell(''),cell(''),cell(''),cell('')],[cell('第3节'),cell('周二课程'),cell(''),cell(''),cell(''),cell(''),cell('')]]);
let r=read(doc([course]));assert.equal(r.tables.length,1);assert.equal(r.tables[0].candidates.length,2);assert.equal(r.tables[0].candidates[1].day,2);assert.equal(r.tables[0].candidates[0].rowLabel,'第1-2节');
assert.equal(read(doc([table([[cell('账号'),cell('密码')]])])).tables.length,0);
const blocked={get contentDocument(){throw Error('cross origin');}};
r=read(doc([],[blocked]));assert.equal(r.blockedFrames,1);assert.equal(r.tables.length,0);
r=read(doc([],[{contentDocument:doc([course])}]));assert.equal(r.tables.length,1);
console.log('DOM extraction checks passed (week columns, rowspan, login rejection, same/cross-origin frames)');
