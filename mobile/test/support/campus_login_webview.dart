import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class CampusLoginTestPlatform extends InAppWebViewPlatform {
  final views = <CampusLoginTestView>[];

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => CampusLoginTestView(params, this);
}

class CampusLoginTestView extends PlatformInAppWebViewWidget {
  CampusLoginTestView(super.params, this.platform) : super.implementation();

  final CampusLoginTestPlatform platform;
  final controller = CampusLoginTestController();
  late final InAppWebViewController web;

  @override
  Widget build(BuildContext context) => _CampusLoginSurface(view: this);

  void visit(String address) {
    final url = WebUri(address);
    controller.address = url;
    params.onLoadStart?.call(web, url);
    params.onLoadStop?.call(web, url);
  }

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;

  @override
  void dispose() {}
}

class _CampusLoginSurface extends StatefulWidget {
  const _CampusLoginSurface({required this.view});

  final CampusLoginTestView view;

  @override
  State<_CampusLoginSurface> createState() => _CampusLoginSurfaceState();
}

class _CampusLoginSurfaceState extends State<_CampusLoginSurface> {
  @override
  void initState() {
    super.initState();
    final view = widget.view;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      view.web = view.controllerFromPlatform<InAppWebViewController>(
        view.controller,
      );
      view.platform.views.add(view);
      view.params.onWebViewCreated?.call(view.web);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class CampusLoginTestController extends PlatformInAppWebViewController {
  CampusLoginTestController()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 'campus-test'),
      );

  bool hasTabs = true;
  bool ready = false;
  WebUri? address;
  final scripts = <String>[];

  @override
  Future<WebUri?> getUrl() async => address;

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    scripts.add(source);
    return source.contains('.click()') ? hasTabs : ready;
  }
}
