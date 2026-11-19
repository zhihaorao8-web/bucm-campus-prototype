import '../config/network_policy.dart';

final _httpsAuthority = RegExp(r'^https://([^/?#]+)', caseSensitive: false);

String? _httpsHost(String? value) {
  if (value == null) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.port != 443) return null;
  // Check the original authority because Uri normalizes an empty userinfo.
  final authority = _httpsAuthority.firstMatch(value)?.group(1)?.toLowerCase();
  if (authority != uri.host && authority != '${uri.host}:443') return null;
  return uri.host;
}

bool librarySeatPage(String? url) =>
    _httpsHost(url) == SchoolEndpoints.librarySeatHost;

/// The observed main-document flow stays on the booking site and school CAS.
/// The booking WebView doesn't inherit the classroom or export allowlists.
bool librarySeatNavigation(String? url) => switch (_httpsHost(url)) {
  SchoolEndpoints.librarySeatHost || 'cas.bucm.edu.cn' => true,
  _ => false,
};
