import '../config/network_policy.dart';

enum CampusLoginTarget {
  portal(SchoolEndpoints.portal, SchoolEndpoints.portalHost, '数字北中医'),
  teaching(SchoolEndpoints.teaching, SchoolEndpoints.teachingHost, '教务系统'),
  classroom(
    SchoolEndpoints.classroomCourses,
    SchoolEndpoints.classroomHost,
    '轻新课堂',
  ),
  library(
    SchoolEndpoints.librarySeatHome,
    SchoolEndpoints.librarySeatHost,
    '图书馆座位预约',
  ),
  vpn(SchoolEndpoints.vpn, SchoolEndpoints.vpnHost, '学校 WebVPN');

  const CampusLoginTarget(this.entry, this.host, this.label);

  final String entry;
  final String host;
  final String label;

  String get loginEntry => switch (this) {
    teaching => SchoolEndpoints.teachingCasLogin,
    _ => entry,
  };

  bool get asyncReadiness => this == library;

  bool allows(String? address) {
    final uri = _schoolHttps(address);
    return uri != null &&
        (uri.host == host || uri.host == SchoolEndpoints.casHost);
  }

  /// Upgrade only an observed same-host HTTP/80 redirect on the teaching service.
  Uri? upgradeSameHostHttps(String? address) {
    if (this != teaching || address == null) return null;
    final uri = Uri.tryParse(address);
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.port != 80 ||
        uri.host != host) {
      return null;
    }
    final authority = RegExp(
      r'^http://([^/?#]+)',
      caseSensitive: false,
    ).firstMatch(address)?.group(1)?.toLowerCase();
    if (authority != host && authority != '$host:80') return null;
    return uri.replace(scheme: 'https', port: 443);
  }

  bool isDestination(String? address) {
    final uri = _schoolHttps(address);
    if (uri == null || uri.host != host || campusLoginDocument(address)) {
      return false;
    }
    return switch (this) {
      portal => uri.path == '/tp_nup' || uri.path.startsWith('/tp_nup/'),
      classroom => uri.path.startsWith('/coursePlatform/'),
      teaching || library => true,
      vpn =>
        uri.path == '/' ||
            RegExp(
              r'^/(?:[a-z0-9_-]+/)?portal/?$',
              caseSensitive: false,
            ).hasMatch(uri.path),
    };
  }

  /// Positive markers from the target service, never a CAS form or a URL alone.
  String get readinessScript {
    if (this == library) {
      return '''
if (location.origin !== '${LibrarySeatPolicy.origin}' || window !== window.top) {
  return false;
}
const stop = new AbortController();
const timer = setTimeout(() => stop.abort(), 3000);
try {
  const response = await fetch('${LibrarySeatPolicy.origin}/ic-web/seatMenu', {
    method: 'GET',
    credentials: 'same-origin',
    cache: 'no-store',
    redirect: 'manual',
    signal: stop.signal,
  });
  if (!response.ok || !(response.headers.get('content-type') ?? '').includes('json')) {
    return false;
  }
  const body = await response.json();
  return body?.code === 0 && Array.isArray(body.data);
} catch (_) {
  return false;
} finally {
  clearTimeout(timer);
}
''';
    }
    final marker = switch (this) {
      portal => r'/我的首页|应用中心|个人中心/.test(text)',
      teaching => r'/个人课表信息|学期理论课表/.test(text)',
      classroom || library => 'false',
      vpn =>
        r'/^WebVPN\b/i.test(page.title) && '
            r'/最近访问/.test(text) && /办公系统|业务系统|其他资源/.test(text)',
    };
    final teachingFrames = this == teaching
        ? '''
  for (let i = 0; i < pages.length && pages.length < 16; i++) {
    for (const frame of pages[i].querySelectorAll('frame, iframe')) {
      const child = frame.contentDocument;
      if (child?.location?.origin === location.origin) pages.push(child);
      if (pages.length === 16) break;
    }
  }
'''
        : '';
    return '''
(() => {
  if (location.origin !== 'https://$host') return false;
  const pages = [document];$teachingFrames
  return pages.some(page => {
    const text = page.body?.innerText ?? '';
    return $marker;
  });
})()
''';
  }
}

enum CampusLoginMethod {
  password('账号密码', 'password_login'),
  mobile('手机号', 'loginByMobile'),
  qr('企业微信扫码', 'qrcode_login');

  const CampusLoginMethod(this.label, this._tab);

  final String label;
  final String _tab;

  /// Only the three observed official anchors are inspected or clicked.
  String get selectScript =>
      '''
(() => {
  if (location.origin !== 'https://${SchoolEndpoints.casHost}' ||
      !/^\\/+cas\\/+login\\/?\$/.test(location.pathname)) return false;
  if (![${values.map((method) => "'a#${method._tab}'").join(', ')}]
      .every(selector => document.querySelector(selector)?.getClientRects().length)) {
    return false;
  }
  document.querySelector('a#$_tab').click();
  return document.querySelector('a#$_tab')?.classList?.contains('active') === true;
})()
''';
}

bool campusCasForm(String? address) {
  final uri = _schoolHttps(address);
  return uri?.host == SchoolEndpoints.casHost &&
      RegExp(r'^/+cas/+login/?$').hasMatch(uri!.path);
}

bool campusLoginDocument(String? address) {
  final uri = _schoolHttps(address);
  if (uri == null) return false;
  return campusCasForm(address) ||
      (uri.host == SchoolEndpoints.vpnHost &&
          (uri.path == '/login' || uri.path == '/login/'));
}

/// WebVPN can show the public authentication shell without changing from /.
const campusVpnLoginScript =
    '''
(() => {
  if (location.origin !== 'https://${SchoolEndpoints.vpnHost}') return false;
  return /统一认证扫码|CAS统一身份认证登录/.test(document.body?.innerText ?? '');
})()
''';

/// A portal can lead into the teaching CAS flow. Resume that service directly
/// while preserving the selected access mode. Only the known hosts are used.
CampusLoginTarget campusLoginTargetFor(
  String? address,
  CampusLoginTarget selected,
) {
  if (selected == CampusLoginTarget.vpn || !campusCasForm(address)) {
    return selected;
  }
  final service = _schoolHttps(Uri.parse(address!).queryParameters['service']);
  return switch (service?.host) {
    SchoolEndpoints.teachingHost => CampusLoginTarget.teaching,
    SchoolEndpoints.librarySeatHost => CampusLoginTarget.library,
    SchoolEndpoints.vpnHost => CampusLoginTarget.vpn,
    _ => selected,
  };
}

Uri? _schoolHttps(String? address) {
  if (address == null) return null;
  final uri = Uri.tryParse(address);
  if (uri == null || uri.scheme != 'https' || uri.port != 443) return null;
  // Uri normalizes empty userinfo, so validate the original authority too.
  final authority = RegExp(
    r'^https://([^/?#]+)',
    caseSensitive: false,
  ).firstMatch(address)?.group(1)?.toLowerCase();
  return authority == uri.host || authority == '${uri.host}:443' ? uri : null;
}
