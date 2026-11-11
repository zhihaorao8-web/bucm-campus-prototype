(function () {
  'use strict';
  // Observed entry buttons and the verified HTTPS classroom entry only.
  // The extraction returns bounded state, never URLs or credentials.
  var prefix = '/https/77726476706e69737468656265737421e1ff5bd225256b5d300d8db9d6562d/';
  function result(state, stage, reason) { return JSON.stringify({state: state, stage: stage || '', reason: reason || ''}); }
  if (location.protocol !== 'https:' || location.port) return result('untrusted', '', 'scheme');
  var vpn = location.hostname === 'webvpn.bucm.edu.cn';
  var direct = location.hostname === 'qhz.bucm.edu.cn';
  if (location.hostname === 'cas.bucm.edu.cn') return result('authentication');
  if (!vpn && !direct) return result('untrusted', '', 'host');
  var root = vpn && (location.pathname === '/' ||
    /^\/portal\/?$/i.test(location.pathname) && /^WebVPN\b/i.test(document.title) ||
    /^\/[a-z0-9_-]+\/portal\/?$/i.test(location.pathname) &&
    !/^\/https?(?:-\d+)?\//i.test(location.pathname) && /^WebVPN\b/i.test(document.title));
  var cc = direct && /^\/cc\/?$/.test(location.pathname) || vpn &&
    (location.pathname === prefix + 'cc/' || location.pathname === prefix + 'cc');
  var body = document.body ? document.body.innerText : '';
  var portalReady = root && /^WebVPN\b/i.test(document.title) &&
    /最近访问/.test(body) && /办公系统|业务系统|其他资源/.test(body);
  var nativeVpn = vpn && !/^\/https?(?:-\d+)?\//i.test(location.pathname);
  // Authentication can be hosted on a native WebVPN login route rather than
  // '/'. Detect only presence/state, never field values or iframe contents.
  if (nativeVpn && !portalReady && (/^#\/?login(?:[/?]|$)/i.test(location.hash) ||
      /统一认证扫码|扫码登录/.test(body) || document.querySelector('input[type="password"]') || document.querySelector('iframe'))) return result('authentication');
  if (!root && !cc) return result('untrusted', '', 'route');
  if (/^#\/?login(?:[/?]|$)/i.test(location.hash) || document.querySelector('input[type="password"]')) return result('authentication');
  if (Array.from(document.querySelectorAll('.el-dialog__wrapper,.el-message-box__wrapper')).some(function (node) { return node.getClientRects().length; })) return result('waiting', root ? 'portal' : 'platform', 'modal');
  if (portalReady) {
    // The generic cc front page can loop in its own portal initialization.
    // This dedicated course entry and route were verified in the authorized
    // Android session. The school still performs its normal authentication.
    setTimeout(function () { location.assign(location.origin + prefix + 'coursePlatform/#/courseCenter/index?firstMenuId=11'); }, 0);
    return result('opening', 'portal', 'verified-entry');
  }
  var element;
  if (root) {
    element = Array.from(document.querySelectorAll('a')).find(function (node) {
      return node.getClientRects().length && node.textContent.includes('智慧教学平台');
    });
    if (!element) element = Array.from(document.querySelectorAll('*')).slice(0, 6000).find(function (node) {
      return !node.children.length && node.getClientRects().length && node.textContent.trim() === '智慧教学平台';
    });
  } else {
    element = Array.from(document.querySelectorAll('*')).slice(0, 6000).find(function (node) {
      return !node.children.length && node.getClientRects().length && node.textContent.trim() === '课程平台';
    });
  }
  if (!element) return result('waiting', root ? 'portal' : 'platform', 'no-entry');
  var base = root ? 'cc' : 'coursePlatform';
  function target(value) {
    try {
      var url = new URL(value, location.href);
      if (url.protocol !== 'https:' || url.port || url.username || url.password) return null;
      var path = '/' + base;
      if (url.hostname === 'qhz.bucm.edu.cn' && (url.pathname === path || url.pathname === path + '/')) {
        if (vpn) {
          var mapped = new URL(prefix + url.pathname.slice(1), location.origin);
          mapped.search = url.search; mapped.hash = url.hash;
          return mapped.href;
        }
        return url.href;
      }
      if (vpn && url.hostname === 'webvpn.bucm.edu.cn' &&
          (url.pathname === prefix + base || url.pathname === prefix + base + '/')) return url.href;
    } catch (_) { /* Never return exception payloads or the target. */ }
    return null;
  }
  var original = window.open, opened = false, blocked = false;
  try {
    // Both observed handlers call window.open synchronously. Convert just this
    // button's call into validated same-view navigation; leave popup policy off.
    window.open = function (value) {
      var next = typeof value === 'string' ? target(value) : null;
      if (!next || opened) { blocked = true; return null; }
      opened = true;
      setTimeout(function () { location.assign(next); }, 0);
      return null;
    };
    element.click();
  } catch (_) { blocked = true; }
  finally { window.open = original; }
  return result(opened ? 'opening' : blocked ? 'blocked' : 'waiting', root ? 'portal' : 'platform');
})();
