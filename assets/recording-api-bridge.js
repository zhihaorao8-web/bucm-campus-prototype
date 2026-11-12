// Function body for callAsyncJavaScript. Credentials remain in the official client.
const command = __RECORDING_API_COMMAND__;
const prefix = '/https/77726476706e69737468656265737421e1ff5bd225256b5d300d8db9d6562d/';
if (location.protocol !== 'https:' || location.port ||
    !(location.hostname === 'qhz.bucm.edu.cn' && location.pathname.startsWith('/coursePlatform/') ||
      location.hostname === 'webvpn.bucm.edu.cn' && location.pathname.startsWith(prefix + 'coursePlatform/'))) {
  return JSON.stringify({state:'untrusted'});
}
const key = '__campusRecordingApiV1';
if (command.action === 'cancel') {
  if (window[key]) window[key].cancel();
  delete window[key];
  return JSON.stringify({state:'cancelled'});
}
if (!['catalog','records'].includes(command.action)) return JSON.stringify({state:'unsupported'});
if (!window[key]) {
  if (!Array.isArray(window.webpackJsonp) || typeof window.createCampusRecordingApi !== 'function') return JSON.stringify({state:'unsupported'});
  let req;
  const id = 'campus_directory_' + Date.now() + '_' + Math.random().toString(36).slice(2);
  try {
    window.webpackJsonp.push([[id],{[id]:(m,e,r)=>{req=r;}},[[id]]]);
    // Current official bundle capability. A changed bundle falls back before requesting.
    if (!req || !req.m || !req.m.b775) return JSON.stringify({state:'unsupported'});
    const client = req('b775').a;
    if (typeof client !== 'function') return JSON.stringify({state:'unsupported'});
    window[key] = window.createCampusRecordingApi(client, location);
  } catch (_) {
    return JSON.stringify({state:'unsupported'});
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
  if (!catalog || catalog.activeName === '1') return JSON.stringify({state:'unsupported'});
  const raw = String(catalog.xqCode || '');
  const m = raw.match(/^(20\d{2})-?(20\d{2})-?0?([12])$/);
  if (!m || m[1]+'-'+m[2]+'-'+m[3] !== command.semester) return JSON.stringify({state:'unsupported'});
  return JSON.stringify(await window[key].catalog(raw,catalog.boy));
}
return JSON.stringify(await window[key].records(command.id,command.page));
