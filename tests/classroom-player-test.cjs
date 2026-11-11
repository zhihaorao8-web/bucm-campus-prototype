const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync(require('node:path').join(__dirname, '../assets/classroom-player.js'), 'utf8');
const media = 'https://qxkt4.bucm.edu.cn:8880/synthetic/index.m3u8';
function fixture(vpn = false) {
  let stops = 0, cancelled = 0;
  class Xhr {
    open() {}
    addEventListener(_, f) { this.listener = f; }
    respond(payload, status = 200) {this.status = status; this.responseText = JSON.stringify(payload);this.listener?.();}
  }
  const original = Xhr.prototype.open;
  const comp = {videoInfo: {rpId: 'sample', vgaStreamHlsUrl: media, teaStreamHlsUrl: media, stuStreamHlsUrl: media, token: 'NEVER_EXPORT'}, $route: {query: {rpId: 'sample'}}, jydH5PlayerObj: {stopVideo() {stops++;}, disconnectStream() {stops++;}}};
  const context = vm.createContext({location: {protocol: 'https:', port: '', hostname: vpn ? 'webvpn.bucm.edu.cn' : 'qhz.bucm.edu.cn', pathname: (vpn ? '/https/77726476706e69737468656265737421e1ff5bd225256b5d300d8db9d6562d' : '') + '/coursePlatform/'}, window: {}, document: {querySelector: () => ({__vue__: comp}), querySelectorAll: () => [{pause() {stops++;}}]}, XMLHttpRequest: Xhr, URL, AbortSignal, clearInterval() {}, fetch: async () => ({ok: true, url: vpn ? 'https://webvpn.bucm.edu.cn/https-8880/77726476706e69737468656265737421e1ef4a88737e6a457d05c7a99c406d3652/synthetic/index.m3u8?vpn-12-o2-qhz.bucm.edu.cn' : media, body: {async cancel() {cancelled++;}}})});
  const run = command => JSON.parse(vm.runInContext(source.replace('__PLAYER_COMMAND__', JSON.stringify(command)), context));
  const command = action => run({action, record: 'sample'});
  const watermark = data => {const request = new Xhr();request.open('POST', '/bd/teachingVisitConfig/getWaterMarkStatus');request.respond({meta: {success: true}, data});};
  return {context, comp, Xhr, original, command, run, watermark, stops: () => stops, cancelled: () => cancelled};
}
(async () => {
  for (const vpn of [false, true]) {
    const f = fixture(vpn);
    assert.equal(f.command('install').state, 'installed');
    assert.equal(f.command('install').state, 'busy');
    assert.equal(f.command('capture').state, 'loading'); // Missing watermark never means disabled.
    f.watermark({waterMark: '1', waterMarkContent: '合成水印', secret: 'NEVER_EXPORT'});
    assert.equal(f.command('capture').state, 'loading');
    await new Promise(setImmediate);
    const result = f.command('capture');
    assert.equal(result.state, 'ready');assert.equal(result.sources.length, 3);
    assert.equal(result.watermark.text, '合成水印');assert.equal(f.cancelled(), 3);
    assert.equal(f.stops(), 3);assert.equal(f.Xhr.prototype.open, f.original);
    assert.equal(f.context.window.__campusNativePlayback, undefined);
    assert(!JSON.stringify(result).includes('NEVER_EXPORT'));
    assert.equal(f.command('capture').state, 'missing');
  }
  const disabled = fixture();disabled.command('install');disabled.watermark({waterMark: 0});
  disabled.comp.$route.query.limitSee = '1';disabled.comp.videoInfo.publicRpType = '1';
  disabled.command('capture');await new Promise(setImmediate);
  assert.equal(disabled.command('capture').sources.length, 1); // Official public-source restriction.
  const denied = fixture();denied.command('install');denied.watermark({waterMark: '1'});
  assert.equal(denied.command('capture').state, 'policy');denied.command('abort');
  assert.equal(denied.Xhr.prototype.open, denied.original);
  const wrong = fixture();wrong.command('install');wrong.watermark({waterMark: '0'});wrong.comp.videoInfo.rpId = 'another';
  assert.equal(wrong.command('capture').state, 'loading');wrong.command('abort');
  const bad = fixture();bad.command('install');bad.watermark({waterMark: '0'});bad.comp.videoInfo.teaStreamHlsUrl = 'http://qxkt4.bucm.edu.cn:8880/x';
  bad.command('capture');await new Promise(setImmediate);assert.equal(bad.command('capture').state, 'policy');bad.command('abort');
  const evil = fixture();evil.context.location.hostname = 'evil.test';
  assert.equal(evil.command('install').state, 'untrusted');assert.equal(evil.Xhr.prototype.open, evil.original);
  console.log('Native player metadata synthetic checks passed; no school session or credentials used.');
})().catch(error => {console.error(error);process.exitCode = 1;});
