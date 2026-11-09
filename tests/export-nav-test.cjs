const fs=require('fs'),vm=require('vm'),assert=require('assert');
const script=fs.readFileSync(require('path').join(__dirname,'../assets/export-nav.js'),'utf8');
function node(text,tag='BUTTON',href=null,visible=true){return {innerText:text,textContent:text,tagName:tag,type:'button',form:null,clicked:0,getClientRects:()=>[{}],getBoundingClientRect:()=>({top:visible?10:2000,bottom:visible?40:2040,left:0,right:100}),contains(other){return other===this;},closest(selector){return selector==='a'&&this.tagName==='A'?this:null;},getAttribute:key=>key==='href'?href:null,click(){this.clicked++;}};}
function doc(nodes=[],opts={}){return {URL:opts.url||'https://webvpn.bucm.edu.cn/',body:{innerText:opts.title||''},defaultView:{innerHeight:1000,innerWidth:600},querySelector:s=>opts.login?{}:null,querySelectorAll:s=>s==='*'?nodes:s==='select'?(opts.selects||[]):(opts.frames||[])};}
function read(document){return JSON.parse(vm.runInNewContext(script,{document,URL,Event:class Event{constructor(type){this.type=type;}}}));}
let resource=node('本科教务系统','H3'),hidden=node('本科教务系统','H3',null,false);
assert.equal(read(doc([resource,hidden])).state,'navigating');assert.equal(resource.clicked,1);assert.equal(hidden.clicked,0);
let personal=node('个人课表信息','A','/term');assert.equal(read(doc([personal])).state,'navigating');
let all=node('(全部)','OPTION');all.value='all';let select={value:'all',options:[all],dispatchEvent(){this.changed=true;}};
let exp=node('导出');assert.equal(read(doc([exp],{title:'学期理论课表',selects:[select]})).state,'exportClicked');assert.equal(exp.clicked,1);
select.value='9';exp.clicked=0;assert.equal(read(doc([exp],{title:'学期理论课表',selects:[select]})).state,'navigating');assert(select.changed);assert.equal(exp.clicked,0);
assert.equal(read(doc([exp],{title:'学期理论课表'})).state,'filterMissing');
assert.equal(read(doc([node('导出'),node('导出')],{title:'学期理论课表',selects:[select]})).state,'ambiguous');
assert.equal(read(doc([node('个人课表信息','A','https://evil.test/')])).state,'blocked');
assert.equal(read(doc([node('个人课表信息')],{login:true})).state,'login');
assert.equal(read(doc([node('个人课表信息')],{url:'https://bucm.edu.cn.evil.test/'})).state,'waiting');
const secret={tagName:'INPUT',type:'hidden',get value(){throw Error('Must not read token fields');}};
assert.equal(read(doc([secret])).state,'waiting');
const blocked={get contentDocument(){throw Error('cross-origin');}};assert.equal(read(doc([],{frames:[blocked]})).state,'waiting');
console.log('Export navigation checks passed (official labels, all weeks, duplicates, login pause, domain checks, credential fields excluded)');
