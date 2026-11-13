// Function body for callAsyncJavaScript. Credentials remain in the official client.
const command = __RECORDING_API_COMMAND__;
const prefix = '/https/77726476706e69737468656265737421e1ff5bd225256b5d300d8db9d6562d/';
if (location.protocol !== 'https:' || location.port ||
    !(location.hostname === 'qhz.bucm.edu.cn' && location.pathname.startsWith('/coursePlatform/') ||
      location.hostname === 'webvpn.bucm.edu.cn' && location.pathname.startsWith(prefix + 'coursePlatform/'))) {
  return JSON.stringify({state:'untrusted'});
}
const key = '__campusRecordingApiV1';
const sequenceKey = key + '_sequence';
// This is the official document's category, not a Wi-Fi or network inference.
function result(data) {
  return JSON.stringify({...data, officialContext:
    location.hostname === 'webvpn.bucm.edu.cn' ? 'webvpn' :
      location.hostname === 'qhz.bucm.edu.cn' ? 'direct' : 'unknown'});
}
if (typeof command.requestId !== 'string' || !/^directory_[1-9]\d{0,14}$/.test(command.requestId)) {
  return result({state:'unsupported'});
}
if (command.action === 'cancel') {
  if (window[key]?.requestId === command.requestId) {
    window[key].api.cancel();
    delete window[key];
  }
  return result({state:'cancelled'});
}
if (!['catalog','records'].includes(command.action)) return result({state:'unsupported'});
if (window[key]?.requestId !== command.requestId) {
  // Only a newer catalog task may replace the context. Late records/cleanup
  // must never acquire or cancel the task that resumed after authentication.
  const sequence = Number(command.requestId.slice('directory_'.length));
  if (command.action !== 'catalog' || sequence <= (window[sequenceKey] || 0)) return result({state:'cancelled'});
  window[sequenceKey] = sequence;
  if (window[key]) window[key].api.cancel();
  delete window[key];
  if (!Array.isArray(window.webpackJsonp) || typeof window.createCampusRecordingApi !== 'function') return result({state:'unsupported'});
  let req;
  const id = 'campus_directory_' + Date.now() + '_' + Math.random().toString(36).slice(2);
  try {
    window.webpackJsonp.push([[id],{[id]:(m,e,r)=>{req=r;}},[[id]]]);
    // Current official bundle capability. A changed bundle falls back before requesting.
    if (!req || !req.m || !req.m.b775) return result({state:'unsupported'});
    const client = req('b775').a;
    if (typeof client !== 'function') return result({state:'unsupported'});
    window[key] = {requestId:command.requestId, api:window.createCampusRecordingApi(client, location)};
  } catch (_) {
    return result({state:'unsupported'});
  } finally {
    if (req && req.m) delete req.m[id];
    if (req && req.c) delete req.c[id];
  }
}
if (command.action === 'catalog') {
  const components = [];
  function walk(v,depth) { if(!v || depth>20 || components.length>=500)return;components.push(v);(v.$children||[]).forEach(c=>walk(c,depth+1)); }
  walk(document.querySelector('#app')?.__vue__,0);
  const catalog = components.find(v=>Array.isArray(v.courseList));
  if (!catalog || catalog.activeName === '1') return result({state:'unsupported'});
  const raw = String(catalog.xqCode || '');
  const m = raw.match(/^(20\d{2})-?(20\d{2})-?0?([12])$/);
  if (!m || m[1]+'-'+m[2]+'-'+m[3] !== command.semester) return result({state:'unsupported'});
  return result(await window[key].api.catalog(raw,catalog.boy));
}
return result(await window[key].api.records(command.id,command.page));
