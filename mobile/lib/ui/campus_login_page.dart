import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../config/network_policy.dart';
import '../design/app_tokens.dart';
import '../platform/campus_login_navigation.dart';
import '../platform/school_adapter.dart';
import 'app_controls.dart';
import 'app_icons.dart';

/// Completes when the selected service is usable in the official WebView.
/// Callers retain their own task context and receive only a success result.
Future<bool> openCampusLogin(
  BuildContext context, {
  required CampusLoginTarget target,
  required String reason,
}) async =>
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CampusLoginPage(target: target, reason: reason),
      ),
    ) ??
    false;

class CampusLoginPage extends StatefulWidget {
  const CampusLoginPage({
    super.key,
    required this.target,
    required this.reason,
  });

  final CampusLoginTarget target;
  final String reason;

  @override
  State<CampusLoginPage> createState() => _CampusLoginPageState();
}

class _CampusLoginPageState extends State<CampusLoginPage> {
  InAppWebViewController? _web;
  Timer? _timeout;
  Timer? _poll;
  int _document = 0;
  bool _loading = true;
  bool _switching = false;
  bool _completed = false;
  CampusLoginMethod? _method;
  String? _error;

  bool _current(InAppWebViewController web, int document) =>
      mounted && !_completed && web == _web && document == _document;

  @override
  void initState() {
    super.initState();
    SchoolAdapter.sessionChanges.addListener(_sessionCleared);
  }

  @override
  void dispose() {
    SchoolAdapter.sessionChanges.removeListener(_sessionCleared);
    _cancelTimers();
    super.dispose();
  }

  void _cancelTimers() {
    _timeout?.cancel();
    _poll?.cancel();
  }

  void _sessionCleared() {
    final web = _web;
    if (web != null) _fail(web, '学校会话已清除，请重新登录。');
  }

  void _fail(InAppWebViewController web, String message) {
    if (!mounted || web != _web || _completed) return;
    _cancelTimers();
    setState(() {
      _web = null;
      _document++;
      _loading = false;
      _method = null;
      _switching = false;
      _error = message;
    });
  }

  void _waitForPage(InAppWebViewController web, String message) {
    _timeout?.cancel();
    _timeout = Timer(CampusLoginPolicy.pageTimeout, () => _fail(web, message));
  }

  bool _checkDocument(InAppWebViewController web, WebUri? url) {
    if (!mounted || web != _web || _completed) return false;
    if (url == null) return false;
    if (widget.target.allows(url.toString())) return true;
    _fail(web, '已停止打开非当前学校服务或统一身份认证的页面。');
    return false;
  }

  Future<void> _inspectPage(InAppWebViewController web, int document) async {
    if (!_current(web, document)) return;
    bool ready;
    try {
      ready =
          await web.evaluateJavascript(source: widget.target.readinessScript) ==
          true;
    } catch (_) {
      ready = false;
    }
    if (!mounted || !_current(web, document)) return;
    if (ready && ModalRoute.of(context)?.isCurrent == true) {
      _completed = true;
      _cancelTimers();
      Navigator.of(context).pop(true);
      return;
    }
    _poll = Timer(
      CampusLoginPolicy.readinessPoll,
      () => _inspectPage(web, document),
    );
  }

  Future<void> _select(CampusLoginMethod method) async {
    final web = _web;
    if (web == null || _switching || _completed) return;
    final document = _document;
    setState(() => _switching = true);
    bool selected;
    try {
      selected =
          await web.evaluateJavascript(source: method.selectScript) == true;
    } catch (_) {
      selected = false;
    }
    if (!_current(web, document)) return;
    setState(() {
      _method = selected ? method : null;
      _switching = false;
    });
  }

  void _loaded(InAppWebViewController web, WebUri? url) {
    if (!_checkDocument(web, url)) return;
    _cancelTimers();
    setState(() => _loading = false);
    final address = url.toString();
    if (widget.target != CampusLoginTarget.vpn && campusCasForm(address)) {
      unawaited(_select(_method ?? CampusLoginMethod.password));
    } else if (widget.target.isDestination(address)) {
      _waitForPage(web, '学校服务暂未就绪，请检查网络后重试。');
      unawaited(_inspectPage(web, _document));
    }
  }

  Widget _buildWeb() => InAppWebView(
    initialUrlRequest: URLRequest(url: WebUri(widget.target.entry)),
    initialSettings: InAppWebViewSettings(
      useWideViewPort: true,
      loadWithOverviewMode: true,
      supportZoom: true,
      builtInZoomControls: true,
      displayZoomControls: false,
      domStorageEnabled: true,
      useShouldOverrideUrlLoading: true,
      supportMultipleWindows: true,
      allowFileAccess: false,
      allowContentAccess: false,
      allowFileAccessFromFileURLs: false,
      allowUniversalAccessFromFileURLs: false,
      thirdPartyCookiesEnabled: false,
      cacheEnabled: false,
      saveFormData: false,
      isInspectable: false,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
    ),
    onWebViewCreated: (web) {
      _web = web;
      _waitForPage(web, '学校页面加载超时，请检查网络后重试。');
    },
    shouldOverrideUrlLoading: (web, action) async {
      if (widget.target.allows(action.request.url?.toString())) {
        return NavigationActionPolicy.ALLOW;
      }
      if (action.isForMainFrame && action.hasGesture != true) {
        _fail(web, '已停止打开非当前学校服务或统一身份认证的页面。');
      }
      return NavigationActionPolicy.CANCEL;
    },
    onLoadStart: (web, url) {
      if (!_checkDocument(web, url)) return;
      _document++;
      _poll?.cancel();
      _waitForPage(web, '学校页面加载超时，请检查网络后重试。');
      setState(() {
        _loading = true;
        _method = null;
        _switching = false;
      });
    },
    onLoadStop: _loaded,
    onReceivedError: (web, request, _) {
      if (request.isForMainFrame == true) {
        _fail(web, '学校页面无法加载，请检查网络后重试。');
      }
    },
    onReceivedHttpError: (web, request, _) {
      if (request.isForMainFrame == true) {
        _fail(web, '学校服务暂时无法打开，请稍后重试。');
      }
    },
    onCreateWindow: (_, _) async => false,
    onReceivedServerTrustAuthRequest: (_, _) async =>
        ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.CANCEL),
    onPermissionRequest: (_, request) async => PermissionResponse(
      resources: request.resources,
      action: PermissionResponseAction.DENY,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('校园账号登录'),
      bottom: _loading && defaultTargetPlatform == TargetPlatform.android
          ? const PreferredSize(
              preferredSize: Size.fromHeight(AppSpace.xs),
              child: LinearProgressIndicator(),
            )
          : null,
    ),
    body: SafeArea(
      child: defaultTargetPlatform != TargetPlatform.android
          ? const Center(child: Text('校园账号登录目前支持 Android。'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg,
                      vertical: AppSpace.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.reason),
                        Text(
                          '学校官方页面 · ${widget.target.label}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (_method != null)
                          Wrap(
                            spacing: AppSpace.sm,
                            children: [
                              for (final method in CampusLoginMethod.values)
                                ChoiceChip(
                                  selected: method == _method,
                                  label: Text(method.label),
                                  onSelected: _switching
                                      ? null
                                      : (_) => _select(method),
                                ),
                            ],
                          ),
                        if (_method == CampusLoginMethod.qr ||
                            widget.target == CampusLoginTarget.vpn)
                          const Text('用另一台设备的企业微信扫描官方页面二维码。'),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _error == null
                      ? _buildWeb()
                      : Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(AppSpace.lg),
                            child: Column(
                              children: [
                                Text(_error!, textAlign: TextAlign.center),
                                const SizedBox(height: AppSpace.lg),
                                AppActionButton(
                                  label: '重试',
                                  icon: AppIcons.refresh,
                                  onPressed: () => setState(() {
                                    _error = null;
                                    _loading = true;
                                  }),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            ),
    ),
  );
}
