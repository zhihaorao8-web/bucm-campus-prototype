const fs=require('node:fs'),assert=require('node:assert/strict');
const source=fs.readFileSync('assets/recording-api-bridge.js','utf8');
const factory=require('../assets/recording-api.cjs');
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
const loc={protocol:'https:',port:'',hostname:'qhz.bucm.edu.cn',pathname:'/coursePlatform/'};
const row={id:'a',name:'合成课程',course_num:'S1',fz_id:'G1',xq_code:'2030203101'};
function setup(request=()=>[row]){
 let calls=0;const req=id=>({a:async c=>{calls++;return request(c);}});req.m={b775:()=>{}};req.c={};
 const window={createCampusRecordingApi:factory,webpackJsonp:{}};
 window.webpackJsonp=[];
 window.webpackJsonp.push=chunk=>{const id=Object.keys(chunk[1])[0];req.m[id]=chunk[1][id];req.m[id]({}, {},req);};
 const document={querySelector:()=>({__vue__:{courseList:[],xqCode:row.xq_code,boy:'',activeName:'0'}})};
 return {window,document,req,calls:()=>calls};
}
async function run(env,cmd,location=loc){return JSON.parse(await new AsyncFunction('window','document','location',source.replace('__RECORDING_API_COMMAND__',JSON.stringify({requestId:'directory_1',...cmd})))(env.window,env.document,location));}
(async()=>{
 const env=setup();
 const direct=await run(env,{action:'catalog',semester:'2030-2031-1'});
 assert.equal(direct.state,'catalog');assert.equal(direct.officialContext,'direct');
 const vpn=await run(setup(),{action:'catalog',semester:'2030-2031-1'},
  {...loc,hostname:'webvpn.bucm.edu.cn',pathname:'/https/77726476706e69737468656265737421e1ff5bd225256b5d300d8db9d6562d/coursePlatform/'});
 assert.equal(vpn.officialContext,'webvpn');assert(!JSON.stringify(vpn).includes('https://'));
 const moving={...loc},redirected=setup();
 redirected.window.createCampusRecordingApi=()=>({catalog:async()=>{
  moving.hostname='unrecognized.test';return {state:'cancelled'};
 }});
 assert.equal((await run(redirected,{action:'catalog',semester:'2030-2031-1'},moving)).officialContext,'unknown');
 assert.equal(env.calls(),1);assert.deepEqual(Object.keys(env.req.m),['b775']);
 assert.equal((await run(env,{action:'arbitrary',url:'https://evil.test'})).state,'unsupported');
 assert.equal((await run(env,{action:'cancel'})).state,'cancelled');assert(!env.window.__campusRecordingApiV1);
 const changed=setup();delete changed.req.m.b775;
 assert.equal((await run(changed,{action:'catalog',semester:'2030-2031-1'})).state,'unsupported');assert.equal(changed.calls(),0);
 const semester=setup();assert.equal((await run(semester,{action:'catalog',semester:'2031-2032-1'})).state,'unsupported');assert.equal(semester.calls(),0);
 assert.equal((await run(setup(),{action:'catalog'}, {...loc,hostname:'evil.test'})).state,'untrusted');
 // A resumed task must own its context even while the previous task is pending.
 let finishOld,finishRecords,catalogs=0;
 const overlap=setup(c=>c.url.endsWith('getCourseList')?
  (++catalogs===1?new Promise(resolve=>{finishOld=resolve;}):[row]):
  new Promise(resolve=>{finishRecords=resolve;}));
 const old=run(overlap,{action:'catalog',semester:'2030-2031-1'});
 const next={requestId:'directory_2'};
 assert.equal((await run(overlap,{...next,action:'catalog',semester:'2030-2031-1'})).state,'catalog');
 const reading=run(overlap,{...next,action:'records',id:row.id,page:1});
 finishOld([row]);assert.equal((await old).state,'cancelled');
 assert.equal((await run(overlap,{action:'cancel'})).state,'cancelled');
 assert.equal((await run(overlap,{action:'records',id:row.id,page:1})).state,'cancelled');
 assert.equal((await run(overlap,{action:'catalog',semester:'2030-2031-1'})).state,'cancelled');
 assert.equal(overlap.calls(),3);
 finishRecords({total:0,list:[]});assert.equal((await reading).state,'records');
 assert.equal((await run(overlap,{...next,action:'cancel'})).state,'cancelled');
 assert(!overlap.window.__campusRecordingApiV1);
 assert.equal((await run(overlap,{...next,action:'catalog',semester:'2030-2031-1'})).state,'cancelled');
 assert.equal(overlap.calls(),3);
 const invalid=setup();
 assert.equal((await run(invalid,{action:'catalog',requestId:'https://private.test',semester:'2030-2031-1'})).state,'unsupported');
 assert.equal(invalid.calls(),0);
 console.log('Recording API bridge checks passed (capability, boundary, task ownership, cleanup and no arbitrary actions).');
})().catch(e=>{console.error(e);process.exitCode=1;});
