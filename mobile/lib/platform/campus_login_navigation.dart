import '../config/network_policy.dart';

enum CampusLoginTarget {
  portal(SchoolEndpoints.portal, SchoolEndpoints.portalHost, '数字北中医'),
  teaching(SchoolEndpoints.teaching, SchoolEndpoints.teachingHost, '教务系统'),
  vpn(SchoolEndpoints.vpn, SchoolEndpoints.vpnHost, '学校 WebVPN');

  const CampusLoginTarget(this.entry, this.host, this.label);

  final String entry;
  final String host;
  final String label;

  bool allows(String? address) {
    final uri = _schoolHttps(address);
    return uri != null &&
        (uri.host == host || uri.host == SchoolEndpoints.casHost);
  }

  bool isDestination(String? address) {
    final uri = _schoolHttps(address);
    if (uri == null || uri.host != host || campusLoginDocument(address)) {
      return false;
    }
    return switch (this) {
      portal => uri.path == '/tp_nup' || uri.path.startsWith('/tp_nup/'),
      teaching => true,
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
    final marker = switch (this) {
      portal => r'/我的首页|应用中心|个人中心/.test(text)',
      teaching => r'/个人课表信息|学期理论课表/.test(text)',
      vpn =>
        r'/^WebVPN\b/i.test(document.title) && '
            r'/最近访问/.test(text) && /办公系统|业务系统|其他资源/.test(text)',
    };
    return '''
(() => {
  if (location.origin !== 'https://$host' || !document.body) return false;
  const text = document.body.innerText;
  return $marker;
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
      location.pathname !== '${CampusLoginPolicy.casPath}') return false;
  if (![${values.map((method) => "'a#${method._tab}'").join(', ')}]
      .every(selector => document.querySelector(selector)?.getClientRects().length)) {
    return false;
  }
  document.querySelector('a#$_tab').click();
  return true;
})()
''';
}

bool campusCasForm(String? address) {
  final uri = _schoolHttps(address);
  return uri?.host == SchoolEndpoints.casHost &&
      uri?.path == CampusLoginPolicy.casPath;
}

bool campusLoginDocument(String? address) {
  final uri = _schoolHttps(address);
  if (uri == null) return false;
  return campusCasForm(address) ||
      (uri.host == SchoolEndpoints.vpnHost &&
          (uri.path == '/login' || uri.path == '/login/'));
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
