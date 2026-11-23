const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, '../assets/classroom-entry.js'), 'utf8');
const prefix = '/https/77726476706e69737468656265737421e1ff5bd225256b5d300d8db9d6562d/';
function run(address, target, {password = false, iframe = false, modal = false, label, throwing = false, body = '', cardsOnly = false, title = 'WebVPN - 资源站点'} = {}) {
  const location = new URL(address), assigned = [], pending = [];
  location.assign = value => assigned.push(value);
  const original = () => {throw Error('Native popup must never be opened');};
  const window = {open: original};
  let clicks = 0;
  const element = {textContent: label ?? (location.pathname === '/' ? '智慧教学平台 https://qhz.bucm.edu.cn/cc/' : '课程平台'), children: [], getClientRects: () => [{}], click() {clicks++;if (throwing) throw Error('Synthetic click error');window.open(target, '_blank');}};
  const document = {title, body: {innerText: body}, querySelector: selector => selector === 'iframe' ? iframe ? {} : null : password ? {} : null,
    querySelectorAll: selector => selector.startsWith('.el-') ? modal ? [element] : [] : cardsOnly && selector === 'a' ? [] : [element]};
  const result = JSON.parse(vm.runInNewContext(source, {window, location, document, URL, setTimeout: fn => pending.push(fn)}));
  assert.equal(window.open, original);
  assert.equal(assigned.length, 0); // navigation waits until the result is returned.
  pending.forEach(fn => fn());
  return {result, assigned, clicks};
}
const resource = 'https://webvpn.bucm.edu.cn' + prefix + 'cc/?synthetic-session=NEVER_EXPORT';
const root = run('https://webvpn.bucm.edu.cn/', resource);
assert.equal(root.result.state, 'opening');assert.equal(root.assigned[0], resource);
assert(!JSON.stringify(root.result).includes('NEVER_EXPORT'));
const card = run('https://webvpn.bucm.edu.cn/', resource, {cardsOnly: true, label: '智慧教学平台'});
assert.equal(card.result.state, 'opening');assert.equal(card.assigned[0], resource);
const mobile = run('https://webvpn.bucm.edu.cn/synthetic/portal', resource, {cardsOnly: true, label: '智慧教学平台'});
assert.equal(mobile.result.state, 'opening');assert.equal(mobile.assigned[0], resource);
assert.equal(run('https://webvpn.bucm.edu.cn/synthetic/portal', resource, {title: 'Other platform'}).result.state, 'untrusted');
assert.equal(run('https://webvpn.bucm.edu.cn/https/portal', resource).result.state, 'untrusted');
const platform = run('https://webvpn.bucm.edu.cn' + prefix + 'cc/', 'https://qhz.bucm.edu.cn/coursePlatform?synthetic-session=NEVER_EXPORT#/courseCenter/index');
assert.equal(platform.result.state, 'opening');
assert.equal(platform.assigned[0], 'https://webvpn.bucm.edu.cn' + prefix + 'coursePlatform?synthetic-session=NEVER_EXPORT#/courseCenter/index');
assert(!JSON.stringify(platform.result).includes('NEVER_EXPORT'));
assert.equal(run('https://qhz.bucm.edu.cn/cc/', 'https://qhz.bucm.edu.cn/coursePlatform/').assigned[0], 'https://qhz.bucm.edu.cn/coursePlatform/');
for (const bad of ['http://qhz.bucm.edu.cn/coursePlatform/', 'https://evil.test/coursePlatform/', 'https://qhz.bucm.edu.cn:8880/coursePlatform/', 'https://user@qhz.bucm.edu.cn/coursePlatform/', 'https://webvpn.bucm.edu.cn/https/other/coursePlatform/', 'https://qhz.bucm.edu.cn/other/']) {
  const result = run('https://webvpn.bucm.edu.cn' + prefix + 'cc/', bad);
  assert.equal(result.result.state, 'blocked');assert.deepEqual(result.assigned, []);
}
for (const page of ['https://webvpn.bucm.edu.cn.evil.test/', 'http://webvpn.bucm.edu.cn/', 'https://webvpn.bucm.edu.cn/https/other/cc/', 'https://qhz.bucm.edu.cn/coursePlatform/']) {
  const result = run(page, resource);assert.equal(result.result.state, 'untrusted');assert.equal(result.clicks, 0);
}
assert.equal(run('https://webvpn.bucm.edu.cn/#/login', resource).result.state, 'authentication');
assert.equal(run('https://webvpn.bucm.edu.cn/', resource, {password: true}).clicks, 0);
assert.equal(run('https://webvpn.bucm.edu.cn/', resource, {label: '无关资源', body: '统一认证扫码'}).result.state, 'authentication');
assert.equal(run('https://qhz.bucm.edu.cn/cc/', resource, {modal: true}).clicks, 0);
assert.equal(run('https://qhz.bucm.edu.cn/cc/', resource, {throwing: true}).result.state, 'blocked');
// A verified portal may render before its resource is available. Wait for the
// school link and keep its query rather than jumping to a static course route.
for (const route of ['/', '/portal', '/synthetic/portal']) {
  const address = 'https://webvpn.bucm.edu.cn'+route;
  const portal = {body:'最近访问 办公系统 业务系统 其他资源'};
  const visible = run(address,resource,{...portal,label:'智慧教学平台'});
  assert.equal(visible.result.state,'opening');
  assert.equal(visible.clicks,1);
  assert.deepEqual(visible.assigned,[resource]);
  assert(!JSON.stringify(visible.result).includes('NEVER_EXPORT'));
  const missing = run(address,resource,{...portal,label:'数字北中医'});
  assert.equal(missing.result.state,'waiting');
  assert.equal(missing.result.reason,'no-entry');
  assert.equal(missing.clicks,0);
  assert.deepEqual(missing.assigned,[]);
}
const badPortalTarget = run('https://webvpn.bucm.edu.cn/', 'https://webvpn.bucm.edu.cn.example/cc/', {body:'最近访问 办公系统'});
assert.equal(badPortalTarget.result.state, 'blocked');
assert.deepEqual(badPortalTarget.assigned, []);
const framed=run('https://webvpn.bucm.edu.cn/',resource,{iframe:true,label:'无关资源'});
assert.equal(framed.result.state,'authentication');assert.equal(framed.clicks,0);
assert.deepEqual(framed.assigned,[]);
for (const options of [{body:'统一认证扫码'},{iframe:true},{password:true}]) {
  const login=run('https://webvpn.bucm.edu.cn/synthetic/sign-in',resource,{label:'无关资源',...options});
  assert.equal(login.result.state,'authentication');assert.equal(login.clicks,0);assert.deepEqual(login.assigned,[]);
}
assert.equal(run('https://webvpn.bucm.edu.cn/https/other/login',resource,{body:'统一认证扫码'}).result.state,'untrusted');
assert.equal(run('https://webvpn.bucm.edu.cn/',resource,{label:'无关资源'}).result.reason,'no-entry');
assert.equal(run('https://webvpn.bucm.edu.cn/portal',resource,{label:'数字北中医',body:'最近访问 办公系统',title:'Other platform'}).result.state,'untrusted');
console.log('Classroom automatic entry checks passed; no credentials or school network used.');

// Synthetic proxy HTML may contain a frame/login link: errors take precedence.
const proxyFailure = '出错啦！该网站无法访问！ 错误代码：CONNECTION_FAILED 错误信息：synthetic-only';
for (const path of ['/', '/http/synthetic/cc/', prefix + 'coursePlatform/']) {
  const failure = run('https://webvpn.bucm.edu.cn' + path, resource,
    {body: proxyFailure, iframe: true, password: true});
  assert.equal(failure.result.state, 'serviceUnavailable');
  assert.equal(failure.clicks, 0); assert.deepEqual(failure.assigned, []);
  assert(!JSON.stringify(failure.result).includes('synthetic-only'));
}
assert.notEqual(run('https://webvpn.bucm.edu.cn/', resource,
  {body: '普通说明 CONNECTION_FAILED', iframe: true}).result.state, 'serviceUnavailable');
assert.equal(run('https://evil.test/',resource,{body:proxyFailure}).result.state,'untrusted');
