const assert = require('node:assert/strict');
const create = require('../assets/recording-api.cjs');
const loc = {protocol:'https:',hostname:'qhz.bucm.edu.cn',pathname:'/coursePlatform/',port:''};
const row = {id:'synthetic',name:'合成课程',teacherName:'合成教师',className:'合成班',course_num:'S1',fz_id:'G1',xq_code:'2030203101',token:'DO_NOT_EXPORT'};
const record = {rpId:'v1',rpName:'合成录播',date_time:'2030-09-02',roomName:'合成教室',shareType:1,token:'DO_NOT_EXPORT'};
async function main() {
 const calls=[];
 let response={total:1,list:[record]};
 const api=create(async c=>{calls.push(c);return c.url.endsWith('getCourseList')?[row]:response;},loc);
 assert.equal((await api.catalog(row.xq_code)).state,'catalog');
 const result=await api.records(row.id);
 assert.equal(result.state,'records');assert.equal(result.records[0].published,true);
 assert(!JSON.stringify(result).includes('DO_NOT_EXPORT'));
 assert.deepEqual(calls[1].data,{courseCode:'S1',fz_id:'G1',beginTime:'',endTime:'',xqCode:row.xq_code,page:1,pageSize:10});
 assert.equal((await api.records('unknown')).state,'invalid-data');
 assert.equal((await api.records(row.id,1.5)).state,'invalid-data');
 assert.equal((await api.catalog(row.xq_code,'role:3')).state,'invalid-data');
 response={total:11,list:[]};assert.equal((await api.records(row.id,2)).state,'invalid-data');
 response={total:2,list:[record,record]};assert.equal((await api.records(row.id)).state,'invalid-data');
 response={total:1,list:[{...record,date_time:'2030-02-30'}]};assert.equal((await api.records(row.id)).state,'invalid-data');
 response={total:0,list:[]};assert.equal((await api.records(row.id)).state,'records');
 for(const patch of [{hostname:'qhz.bucm.edu.cn.evil.test'},{protocol:'http:'},{port:'8880'},
  {hostname:'webvpn.bucm.edu.cn',pathname:'/https/other/coursePlatform/'}]) {
  const a=create(()=>{throw Error('must not request');},{...loc,...patch});
  assert.equal((await a.catalog(row.xq_code)).state,'untrusted');
 }
 for(const status of [401,403,500]) {
  const a=create(async()=>{throw {response:{status},config:{headers:{token:'secret'}}};},loc);
  assert.deepEqual(await a.catalog(row.xq_code),{state:status===401?'authentication':status===403?'forbidden':'error'});
 }
 const wrong=create(async()=>[row,{...row,id:'other',xq_code:'2031203201'}],loc);
 assert.equal((await wrong.catalog(row.xq_code)).state,'invalid-data');
 const duplicate=create(async()=>[row,row],loc);
 assert.equal((await duplicate.catalog(row.xq_code)).state,'invalid-data');
 const vpn=create(async()=>[row],{...loc,hostname:'webvpn.bucm.edu.cn',pathname:'/https/77726476706e69737468656265737421e1ff5bd225256b5d300d8db9d6562d/coursePlatform/'});
 assert.equal((await vpn.catalog(row.xq_code)).state,'catalog');
 let resolve;
 const pending=create(()=>new Promise(r=>resolve=r),loc,50);
 const p=pending.catalog(row.xq_code);
 assert.equal((await pending.catalog(row.xq_code)).state,'busy');
 pending.cancel();resolve([row]);assert.equal((await p).state,'cancelled');
 assert.equal((await pending.records(row.id)).state,'invalid-data');
 let movedResolve;
 const movedLocation={...loc};
 const moved=create(()=>new Promise(r=>movedResolve=r),movedLocation);
 const movedRequest=moved.catalog(row.xq_code);movedLocation.hostname='evil.test';movedResolve([row]);
 assert.equal((await movedRequest).state,'cancelled');
 const slow=create(()=>new Promise(()=>{}),loc,5);
 assert.equal((await slow.catalog(row.xq_code)).state,'timeout');
 // A timeout must also invalidate a late successful response before it changes sources.
 let late;
 const timed=create(()=>new Promise(r=>late=r),loc,5);
 assert.equal((await timed.catalog(row.xq_code)).state,'timeout');late([row]);
 await new Promise(r=>setImmediate(r));
 assert.equal((await timed.records(row.id)).state,'invalid-data');
 console.log('Recording API synthetic checks passed (boundaries, validation, cancellation and late responses).');
}
main().catch(e=>{console.error(e);process.exitCode=1;});
