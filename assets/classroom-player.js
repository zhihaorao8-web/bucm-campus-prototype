(function () {
  'use strict';
  // Evaluated ONLY by the Android adapter; its payload never crosses into Dart.
  var command = __PLAYER_COMMAND__;
  var prefix = '/https/77726476706e69737468656265737421e1ff5bd225256b5d300d8db9d6562d/';
  var trusted = location.protocol === 'https:' && !location.port &&
    (location.hostname === 'qhz.bucm.edu.cn' && location.pathname.indexOf('/coursePlatform/') === 0 ||
      location.hostname === 'webvpn.bucm.edu.cn' && location.pathname.indexOf(prefix + 'coursePlatform/') === 0);
  function result(state) { return JSON.stringify({state: state}); }
  if (!trusted) return result('untrusted');
  var key = '__campusNativePlayback';
  var state = window[key];
  if (command.action === 'install') {
    if (state) return result('busy');
    if (typeof command.record !== 'string' || !command.record || command.record.length > 500) return result('missing');
    state = {record: command.record, watermark: null, sources: null, pending: false, error: false};
    state.open = XMLHttpRequest.prototype.open;
    state.wrapper = function (method, url) {
      var request = this;
      // Observe only the official watermark response. Never read request headers,
      // credentials, generic responses, user fields, or the Vue auth store.
      if (String(url).split('?')[0].endsWith('/bd/teachingVisitConfig/getWaterMarkStatus')) {
        request.addEventListener('load', function () {
          if (window[key] !== state) return;
          try {
            var payload = JSON.parse(request.responseText);
            var data = payload.data;
            if (request.status !== 200 || !payload.meta || payload.meta.success !== true || !data || !['0', '1'].includes(String(data.waterMark))) { state.error = 'watermark'; return; }
            var enabled = String(data.waterMark) === '1';
            var text = data.waterMarkContent;
            if (enabled && (typeof text !== 'string' || !text.trim() || text.length > 500)) { state.error = 'watermark'; return; }
            state.watermark = {enabled: enabled, text: enabled ? text : ''};
          } catch (_) { state.error = 'watermark'; }
        });
      }
      return state.open.apply(request, arguments);
    };
    XMLHttpRequest.prototype.open = state.wrapper;
    window[key] = state;
    return result('installed');
  }
  if (!state || state.record !== command.record) return result('missing');
  var components = [], visited = 0;
  function walk(v, depth) {
    if (!v || depth > 20 || ++visited > 500) return;
    components.push(v); (v.$children || []).forEach(function (c) { walk(c, depth + 1); });
  }
  var root = document.querySelector('#app'); walk(root && root.__vue__, 0);
  var component = components.find(function (v) { return v.videoInfo && String(v.videoInfo.rpId) === state.record && v.$route && String(v.$route.query.rpId) === state.record; });
  function stop() {
    if (component) {
      if (component.listenTimeInterval) clearInterval(component.listenTimeInterval);
      var player = component.jydH5PlayerObj;
      if (player) {
        try { if (typeof player.stopVideo === 'function') player.stopVideo(); } catch (_) { /* Some school layouts have no initialized decoder. */ }
        try { if (typeof player.disconnectStream === 'function') player.disconnectStream(); } catch (_) { /* DOM pause and route teardown still apply. */ }
      }
    }
    Array.from(document.querySelectorAll('video')).forEach(function (v) { v.pause(); });
    if (Array.from(document.querySelectorAll('video')).some(function (v) { return !v.paused; })) throw new Error('stop');
  }
  function clear() {
    if (XMLHttpRequest.prototype.open === state.wrapper) XMLHttpRequest.prototype.open = state.open;
    delete window[key];
  }
  if (command.action === 'abort') { try { stop(); } finally { clear(); } return result('stopped'); }
  if (command.action !== 'capture') return result('missing');
  if (state.error) return result('policy-' + state.error);
  if (!component || !state.watermark) return result('loading');
  if (state.sources) {
    // Shut down the official decoder BEFORE returning media to the native player.
    try { stop(); } catch (_) { clear(); return result('policy-stop'); }
    var payload = JSON.stringify({state: 'ready', sources: state.sources, watermark: state.watermark});
    clear();
    return payload;
  }
  if (!state.pending) {
    var info = component.videoInfo;
    var fields = [['ppt', 'vgaStreamHlsUrl', '1'], ['teacher', 'teaStreamHlsUrl', '3'], ['student', 'stuStreamHlsUrl', '2']];
    var available = fields.filter(function (f) { return typeof info[f[1]] === 'string' && info[f[1]] && (!component.$route.query.limitSee || String(info.publicRpType || '').includes(f[2])); });
    if (!available.length) return result('missing');
    state.pending = true;
    Promise.all(available.map(async function (f) {
      var url = new URL(info[f[1]]);
      var mappings = {
        'qxkt3.bucm.edu.cn': '/https-8880/77726476706e69737468656265737421e1ef4a88747e6a457d05c7a99c406d3626/',
        'qxkt4.bucm.edu.cn': '/https-8880/77726476706e69737468656265737421e1ef4a88737e6a457d05c7a99c406d3652/',
        'qxkt2.bucm.edu.cn': '/https-8880/77726476706e69737468656265737421e1ef4a88757e6a457d05c7a99c406d3643/'
      };
      if (url.protocol !== 'https:' || !Object.prototype.hasOwnProperty.call(mappings, url.hostname) || url.port !== '8880' || url.username || url.password) throw new Error('boundary');
      // WebVPN's official fetch wrapper supplies the actual tunnel URL. Do not
      // invent an encrypted mapping or fall back to direct media off campus.
      var response = await fetch(url.href, {credentials: 'include', signal: AbortSignal.timeout(8000)});
      if (!response.ok) throw new Error('media');
      var actual = new URL(response.url);
      var expected = mappings[url.hostname];
      if (location.hostname === 'webvpn.bucm.edu.cn' && (actual.protocol !== 'https:' || actual.hostname !== 'webvpn.bucm.edu.cn' || actual.port || !actual.pathname.startsWith(expected))) throw new Error('boundary');
      // Body is unused. Native HLS parsing/streaming starts only after teardown.
      if (response.body) await response.body.cancel();
      return {kind: f[0], url: actual.href};
    })).then(function (sources) { if (window[key] === state) state.sources = sources; })
      .catch(function (error) { if (window[key] === state) state.error = ['boundary', 'media'].includes(error.message) ? error.message : 'network'; });
  }
  return result('loading');
})();
