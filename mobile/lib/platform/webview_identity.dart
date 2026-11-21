import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// flutter_inappwebview on Android constructs separate wrapper objects for
/// [onWebViewCreated] and subsequent callbacks around the same platform
/// controller, and [InAppWebViewController] uses default identity equality.
bool sameWebViewController(
  InAppWebViewController? a,
  InAppWebViewController? b,
) => a != null && b != null && identical(a.platform, b.platform);
