import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../platform/classroom_policy.dart';

/// Visible official browser. Cookies remain owned by Android's shared WebView.
class ClassroomBrowser extends StatefulWidget {
  const ClassroomBrowser({super.key, this.windowId, this.depth = 0});
  final int? windowId;
  final int depth;
  @override
  State<ClassroomBrowser> createState() => _ClassroomBrowserState();
}

class _ClassroomBrowserState extends State<ClassroomBrowser> {
  InAppWebViewController? controller;
  String? problem;
  bool loading = true;

  Future<void> back() async {
    if (await controller?.canGoBack() == true) {
      await controller?.goBack();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(back());
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('轻新课堂官方页面'),
        leading: IconButton(
          onPressed: back,
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            tooltip: '返回课程',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (loading) const LinearProgressIndicator(),
            if (problem != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(problem!)),
            Expanded(
              child: InAppWebView(
                windowId: widget.windowId,
                initialUrlRequest: widget.windowId == null
                    ? URLRequest(url: WebUri('https://i.bucm.edu.cn/'))
                    : null,
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  supportMultipleWindows: true,
                  javaScriptCanOpenWindowsAutomatically: false,
                  useShouldOverrideUrlLoading: true,
                  useOnDownloadStart: true,
                  thirdPartyCookiesEnabled: false,
                  saveFormData: false,
                  isInspectable: false,
                  allowFileAccess: false,
                  allowContentAccess: false,
                  allowFileAccessFromFileURLs: false,
                  allowUniversalAccessFromFileURLs: false,
                  mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                ),
                onWebViewCreated: (web) => controller = web,
                shouldOverrideUrlLoading: (_, action) async =>
                    classroomNavigation(action.request.url?.toString() ?? '')
                    ? NavigationActionPolicy.ALLOW
                    : NavigationActionPolicy.CANCEL,
                onLoadStart: (_, _) {
                  if (mounted) {
                    setState(() {
                      loading = true;
                      problem = null;
                    });
                  }
                },
                onLoadStop: (_, _) {
                  if (mounted) setState(() => loading = false);
                },
                onCreateWindow: (_, action) async {
                  if (action.hasGesture != true || widget.depth >= 4) {
                    return false;
                  }
                  unawaited(
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ClassroomBrowser(
                          windowId: action.windowId,
                          depth: widget.depth + 1,
                        ),
                      ),
                    ),
                  );
                  return true;
                },
                onCloseWindow: (_) {
                  if (mounted) Navigator.pop(context);
                },
                onReceivedServerTrustAuthRequest: (_, _) async =>
                    ServerTrustAuthResponse(
                      action: ServerTrustAuthResponseAction.CANCEL,
                    ),
                onPermissionRequest: (_, request) async => PermissionResponse(
                  resources: request.resources,
                  action: PermissionResponseAction.DENY,
                ),
                onDownloadStartRequest: (_, _) async {
                  if (mounted) setState(() => problem = '此页面仅用于在线观看，不下载课程资料。');
                },
                onReceivedError: (_, request, _) {
                  if (mounted && request.isForMainFrame == true) {
                    setState(() {
                      loading = false;
                      problem = '学校页面加载失败，请检查网络后重新进入。';
                    });
                  }
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
