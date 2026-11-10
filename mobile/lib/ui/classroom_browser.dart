import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../platform/classroom_policy.dart';
import '../platform/classroom_access.dart';

/// Visible official browser. Cookies remain owned by Android's shared WebView.
class ClassroomBrowser extends StatefulWidget {
  const ClassroomBrowser({
    super.key,
    this.windowId,
    this.depth = 0,
    this.probe = probeClassroomEndpoint,
  });
  final ProbeEndpoint probe;
  final int? windowId;
  final int depth;
  @override
  State<ClassroomBrowser> createState() => _ClassroomBrowserState();
}

class _ClassroomBrowserState extends State<ClassroomBrowser> {
  InAppWebViewController? controller;
  String? problem;
  bool loading = true;
  bool selecting = false;
  String? entry;
  String accessMessage = '';
  int selection = 0;

  @override
  void initState() {
    super.initState();
    if (widget.windowId == null) {
      unawaited(selectAccess(ClassroomAccess.automatic));
    }
  }

  @override
  void dispose() {
    selection++;
    super.dispose();
  }

  Future<void> selectAccess(ClassroomAccess mode) async {
    final ticket = ++selection;
    setState(() {
      selecting = true;
      problem = null;
    });
    final decision = mode == ClassroomAccess.automatic
        ? await chooseClassroomAccess(widget.probe)
        : AccessDecision(
            mode,
            mode == ClassroomAccess.direct ? '已手动选择直接访问。' : '已手动选择学校 WebVPN。',
          );
    if (!mounted || ticket != selection) return;
    setState(() {
      selecting = false;
      accessMessage = decision.message;
      if (decision.url != null) entry = decision.url;
      loading = decision.url != null;
    });
    if (decision.url != null && controller != null) {
      await controller!.loadUrl(
        urlRequest: URLRequest(url: WebUri(decision.url!)),
      );
    }
  }

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
          PopupMenuButton<ClassroomAccess>(
            tooltip: '学校访问方式',
            onSelected: selectAccess,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: ClassroomAccess.automatic,
                child: Text('自动选择（重新检测）'),
              ),
              PopupMenuItem(
                value: ClassroomAccess.vpn,
                child: Text('校外访问（学校 WebVPN）'),
              ),
              PopupMenuItem(
                value: ClassroomAccess.direct,
                child: Text('数字北中医（直接访问）'),
              ),
            ],
          ),
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
            if (loading || selecting) const LinearProgressIndicator(),
            if (selecting || accessMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(selecting ? '正在检查学校服务访问路径…' : accessMessage),
              ),
            if (widget.windowId == null)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '使用 WebVPN 时，请登录后从“数字北中医”进入轻新课堂；也可在 WebVPN 地址栏选择 https，输入 qhz.bucm.edu.cn/cc/ 后跳转。右上角可手动切换访问方式。',
                ),
              ),
            if (problem != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(problem!)),
            Expanded(
              child: entry == null && widget.windowId == null
                  ? Center(
                      child: TextButton(
                        onPressed: selecting
                            ? null
                            : () => selectAccess(ClassroomAccess.automatic),
                        child: const Text('重新检测访问路径'),
                      ),
                    )
                  : AbsorbPointer(
                      absorbing: selecting,
                      child: InAppWebView(
                        windowId: widget.windowId,
                        initialUrlRequest: widget.windowId == null
                            ? URLRequest(url: WebUri(entry!))
                            : null,
                        initialSettings: InAppWebViewSettings(
                          preferredContentMode:
                              UserPreferredContentMode.DESKTOP,
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
                          mixedContentMode:
                              MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                        ),
                        onWebViewCreated: (web) {
                          controller = web;
                        },
                        shouldOverrideUrlLoading: (_, action) async {
                          final allow = classroomNavigation(
                            action.request.url?.toString() ?? '',
                          );
                          if (!allow && mounted) {
                            setState(() {
                              loading = false;
                              problem = '已阻止非学校或非 HTTPS 跳转，请从右上角切换学校 WebVPN。';
                            });
                          }
                          return allow
                              ? NavigationActionPolicy.ALLOW
                              : NavigationActionPolicy.CANCEL;
                        },
                        onLoadStart: (_, url) {
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
                          if (action.hasGesture != true || widget.depth >= 8) {
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
                        onReceivedServerTrustAuthRequest: (_, _) async {
                          if (mounted) {
                            setState(() {
                              loading = false;
                              problem = '学校连接证书校验失败，已停止加载。';
                            });
                          }
                          return ServerTrustAuthResponse(
                            action: ServerTrustAuthResponseAction.CANCEL,
                          );
                        },
                        onPermissionRequest: (_, request) async =>
                            PermissionResponse(
                              resources: request.resources,
                              action: PermissionResponseAction.DENY,
                            ),
                        onDownloadStartRequest: (_, _) async {
                          if (mounted) {
                            setState(() => problem = '此页面仅用于在线观看，不下载课程资料。');
                          }
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
            ),
          ],
        ),
      ),
    ),
  );
}
