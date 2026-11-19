import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../config/network_policy.dart';
import '../design/app_tokens.dart';
import '../platform/library_seat_navigation.dart';
import 'app_controls.dart';
import 'app_icons.dart';

class LibrarySeatPage extends StatefulWidget {
  const LibrarySeatPage({super.key});

  @override
  State<LibrarySeatPage> createState() => _LibrarySeatPageState();
}

class _LibrarySeatPageState extends State<LibrarySeatPage> {
  InAppWebViewController? _web;
  bool _loading = true;
  bool _canGoBack = false;
  bool _goingBack = false;
  int _historyRevision = 0;
  String? _error;

  void _showError(InAppWebViewController web, String message) {
    if (!mounted || web != _web) return;
    setState(() {
      _historyRevision++;
      _web = null;
      _canGoBack = false;
      _loading = false;
      _error = message;
    });
  }

  bool _checkDocument(InAppWebViewController web, WebUri? url) {
    if (!mounted || web != _web) return false;
    if (url == null || librarySeatNavigation(url.toString())) return true;
    _showError(web, '已停止加载非预约平台或学校认证页面。');
    return false;
  }

  Future<void> _updateHistory(InAppWebViewController web) async {
    final revision = ++_historyRevision;
    final history = await web.getCopyBackForwardList();
    if (!mounted || web != _web || revision != _historyRevision) return;
    final entries = history?.list;
    final index = history?.currentIndex ?? -1;
    // Follow in-site history without resubmitting an earlier login form.
    final canGoBack =
        entries != null &&
        index > 0 &&
        index < entries.length &&
        librarySeatPage(entries[index].url?.toString()) &&
        librarySeatPage(entries[index - 1].url?.toString());
    if (canGoBack != _canGoBack) setState(() => _canGoBack = canGoBack);
  }

  Future<void> _goBack() async {
    final web = _web;
    if (web == null || _goingBack) return;
    _goingBack = true;
    try {
      await web.goBack();
    } finally {
      _goingBack = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _canGoBack) unawaited(_goBack());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('图书馆座位预约'),
          leading: IconButton(
            tooltip: '返回',
            icon: const AppIcon(AppIcons.arrowBack),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          bottom: _loading && defaultTargetPlatform == TargetPlatform.android
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(4),
                  child: LinearProgressIndicator(),
                )
              : null,
        ),
        body: SafeArea(
          child: defaultTargetPlatform == TargetPlatform.android
              ? _error == null
                    ? _buildWebView()
                    : _buildRecovery(_error!)
              : const Center(child: Text('座位预约目前支持 Android。')),
        ),
      ),
    );
  }

  Widget _buildRecovery(String message) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpace.comfortable),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: AppSpace.comfortable),
          AppActionButton(
            label: '重新打开预约首页',
            icon: AppIcons.refresh,
            onPressed: () => setState(() {
              _error = null;
              _loading = true;
            }),
          ),
        ],
      ),
    ),
  );

  Widget _buildWebView() => InAppWebView(
    initialUrlRequest: URLRequest(url: WebUri(SchoolEndpoints.librarySeatHome)),
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
      thirdPartyCookiesEnabled: false,
      cacheEnabled: false,
      saveFormData: false,
      isInspectable: false,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
    ),
    onWebViewCreated: (web) => _web = web,
    shouldOverrideUrlLoading: (web, action) async {
      if (librarySeatNavigation(action.request.url?.toString())) {
        return NavigationActionPolicy.ALLOW;
      }
      if (mounted && web == _web && action.hasGesture == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('仅在此页面打开官方预约和统一身份认证。')));
      }
      return NavigationActionPolicy.CANCEL;
    },
    onCreateWindow: (_, _) async => false,
    onLoadStart: (web, url) {
      if (!_checkDocument(web, url)) return;
      setState(() {
        _historyRevision++;
        _loading = true;
        _canGoBack = false;
      });
    },
    onLoadStop: (web, url) {
      if (!_checkDocument(web, url)) return;
      setState(() => _loading = false);
      unawaited(_updateHistory(web));
    },
    onUpdateVisitedHistory: (web, url, _) {
      if (_checkDocument(web, url)) unawaited(_updateHistory(web));
    },
    onReceivedError: (web, request, _) {
      if (request.isForMainFrame == true) {
        _showError(web, '预约页面无法加载。请检查网络，重新打开后可在个人预约中核对状态。');
      }
    },
    onReceivedHttpError: (web, request, _) {
      if (request.isForMainFrame == true) {
        _showError(web, '学校预约服务暂时无法打开，请稍后再试。');
      }
    },
    onReceivedServerTrustAuthRequest: (_, _) async =>
        ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.CANCEL),
    onPermissionRequest: (_, request) async => PermissionResponse(
      resources: request.resources,
      action: PermissionResponseAction.DENY,
    ),
  );
}
