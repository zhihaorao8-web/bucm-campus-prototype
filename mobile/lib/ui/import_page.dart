import 'app_icons.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/schedule_controller.dart';
import '../domain/schedule.dart';
import '../platform/school_adapter.dart';
import '../platform/classroom_session_cache.dart';

class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key, this.recoverUnreadable = false});
  final bool recoverUnreadable;
  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  InAppWebViewController? controller;
  final adapter = SchoolAdapter();
  String status = '请本人在学校官方页面完成登录，然后点击自动导入。';
  String semester = '';
  bool running = false, busy = false, waitingFile = false;
  int steps = 0, generation = 0;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    ClassroomSessionCache.shared.clear();
  }

  @override
  void dispose() {
    timer?.cancel();
    generation++;
    super.dispose();
  }

  void update(String text) {
    if (mounted) setState(() => status = text);
  }

  Future<void> stop() async {
    timer?.cancel();
    generation++;
    running = false;
    waitingFile = false;
    await controller?.setSettings(
      settings: InAppWebViewSettings(
        javaScriptCanOpenWindowsAutomatically: false,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<Map<String, dynamic>> script(String asset) async {
    final source = await rootBundle.loadString(asset);
    final result = await controller!.evaluateJavascript(source: source);
    if (result is String) return jsonDecode(result) as Map<String, dynamic>;
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> start() async {
    if (busy || controller == null) return;
    await stop();
    running = true;
    steps = 0;
    semester = '';
    await controller!.setSettings(
      settings: InAppWebViewSettings(
        javaScriptCanOpenWindowsAutomatically: true,
      ),
    );
    if (!mounted) return;
    setState(() {});
    await step(generation);
  }

  Future<void> step(int session) async {
    if (!mounted || session != generation || !running || busy || waitingFile) {
      return;
    }
    if (++steps > 120) {
      await stop();
      update('自动导航已暂停。完成登录后，请重新点击自动导入。');
      return;
    }
    try {
      final url = (await controller!.getUrl())?.toString() ?? '';
      if (!schoolUrl(url)) {
        update('请在学校官方认证页面完成登录，返回学校后继续。');
      } else {
        final result = await script('assets/export-nav.js');
        if (!mounted || session != generation || !running) return;
        switch (result['state']) {
          case 'exportClicked':
            semester = result['semester'] as String? ?? '';
            waitingFile = true;
            update('已触发学校官方导出，正在等待文件。');
            timer = Timer(const Duration(seconds: 20), () async {
              if (mounted && session == generation && waitingFile && !busy) {
                await stop();
                update('尚未收到导出文件。请检查页面，或手动点击学校的导出按钮。');
              }
            });
            return;
          case 'blocked':
          case 'ambiguous':
          case 'filterMissing':
            await stop();
            update('无法唯一确认全部周次或导出入口。请手动打开学期理论课表，选择全部周次后重试。');
            return;
          case 'login':
            update('请本人完成学校登录，完成后将继续导入。');
          default:
            update('正在打开学期理论课表并选择全部周次。');
        }
      }
      timer = Timer(const Duration(milliseconds: 1500), () => step(session));
    } catch (_) {
      await stop();
      update('自动导航未完成。请进入学期理论课表后重试，或使用页面读取。');
    }
  }

  Future<void> download(
    InAppWebViewController web,
    DownloadStartRequest request,
  ) async {
    if (busy) return;
    final url = request.url.toString();
    if (!schoolUrl(url)) {
      update('已阻止非学校 HTTPS 地址的导出。');
      return;
    }
    busy = true;
    timer?.cancel();
    update('正在本机读取并校验官方 Excel，原有课表暂不改动。');
    final sourceSemester = semester;
    await stop();
    try {
      final batch = await adapter.download(
        url,
        request.userAgent ?? '',
        sourceSemester,
      );
      if (mounted) await finishBatch(batch, '官方 Excel');
    } catch (_) {
      update('官方 Excel 未能完整读取。请确认已登录并重新导出；旧课表未改动。');
    } finally {
      busy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> extract() async {
    if (busy || controller == null) return;
    await stop();
    busy = true;
    update('正在读取当前课表页面。');
    try {
      if (!schoolUrl((await controller!.getUrl())?.toString() ?? '')) {
        throw const FormatException();
      }
      final coverage = await script('assets/coverage-check.js');
      if (coverage['full'] != true) {
        update('页面读取暂未确认“学期理论课表 / 全部周次”。请先选择全部周次，避免用一周课表覆盖整学期。');
        return;
      }
      final result = await script('assets/extract.js');
      final tables = (result['tables'] as List).cast<Map>();
      if (tables.isEmpty) throw const FormatException();
      int? selected = 0;
      if (tables.length > 1 && mounted) {
        selected = await showDialog<int>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('选择要导入的课表'),
            children: [
              for (var i = 0; i < tables.length; i++)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, i),
                  child: Text(
                    '表格 ${i + 1}，${(tables[i]['candidates'] as List).length} 个源单元格',
                  ),
                ),
            ],
          ),
        );
      }
      if (selected == null) {
        update('已取消页面读取。');
        return;
      }
      final batch = await adapter.parseDom(
        Map<String, dynamic>.from(tables[selected]),
        result['semester'] as String? ?? '',
      );
      batch.payload['hasUnscheduled'] = coverage['hasUnscheduled'] == true;
      if (mounted) await finishBatch(batch, '页面读取');
    } catch (_) {
      update('没有完整读取课表。请打开学期理论课表并选择全部周次后重试，旧课表未改动。');
    } finally {
      busy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> finishBatch(ParsedBatch batch, String source) async {
    final saved = ref
        .read(scheduleProvider.notifier)
        .importBaseline(recoverUnreadable: widget.recoverUnreadable);
    final previous = saved.courses
        .where((c) => c.semester == batch.semester)
        .firstOrNull;
    String term = batch.semester;
    DateTime? monday =
        previous?.termStart ??
        (term == '2026-2027-1' ? DateTime(2026, 9, 7) : null);
    if (term.isEmpty || monday == null) {
      final config = await configureTerm(term);
      if (!mounted || config == null) {
        update('已取消导入，旧课表未改动。');
        return;
      }
      term = config.$1;
      monday = config.$2;
    }
    final courses = await adapter.validate(batch, term, monday);
    if (!mounted) return;
    final duplicate = batch.count - courses.length;
    final summary =
        '$source导入 ${courses.length} 条排课规则，${batch.count} 段来源，合并 $duplicate 项完全重复。\n学期 $term，第1周周一 ${isoDate(monday)}。'
        '${batch.hasUnscheduled ? '\n另有“无课表课程”区域，因无排课时间，未排入课表。' : ''}'
        '\n已通过本批结构与时间校验；完整学期准确性仍需单独核对。';
    await ref
        .read(scheduleProvider.notifier)
        .importBatch(
          courses,
          summary,
          recoverUnreadable: widget.recoverUnreadable,
        );
    if (mounted) Navigator.pop(context, term);
  }

  Future<(String, DateTime)?> configureTerm(String detected) async {
    final term = TextEditingController(text: detected),
        date = TextEditingController();
    final form = GlobalKey<FormState>();
    try {
      return await showDialog<(String, DateTime)>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('首次设置学期起点'),
          content: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('每个学期设置一次，不根据今天猜测开学日期。'),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: term,
                    enabled: detected.isEmpty,
                    decoration: const InputDecoration(
                      labelText: '学期',
                      hintText: '2027-2028-1',
                    ),
                    validator: (v) =>
                        RegExp(r'^20\d{2}-20\d{2}-[12]$').hasMatch(v ?? '')
                        ? null
                        : '请填写有效学期',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: date,
                    decoration: const InputDecoration(
                      labelText: '第1周周一',
                      hintText: 'YYYY-MM-DD',
                    ),
                    keyboardType: TextInputType.datetime,
                    validator: (v) {
                      final value = DateTime.tryParse(v ?? '');
                      return value != null &&
                              value.weekday == 1 &&
                              isoDate(value) == v
                          ? null
                          : '请输入有效的周一日期';
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(context, (
                    term.text,
                    DateTime.parse(date.text),
                  ));
                }
              },
              child: const Text('设置并导入'),
            ),
          ],
        ),
      );
    } finally {
      term.dispose();
      date.dispose();
    }
  }

  Future<void> resizeWeb(
    InAppWebViewController? web, {
    double? factor,
    bool report = true,
  }) async {
    if (web == null) return;
    try {
      if (factor == null) {
        // Only layout dimensions, never form fields or authentication state.
        final source = await rootBundle.loadString('assets/school-viewport.js');
        final result = await web
            .callAsyncJavaScript(functionBody: source)
            .timeout(const Duration(seconds: 3));
        final raw = result?.value;
        if (raw is! String || raw.length > 256) return;
        final sizes = jsonDecode(raw) as Map;
        final viewport = (sizes['viewport'] as num).toDouble();
        final content = (sizes['content'] as num).toDouble();
        if (!viewport.isFinite ||
            !content.isFinite ||
            viewport <= 0 ||
            content <= 0) {
          return;
        }
        factor = (viewport / content).clamp(.1, 3.0).toDouble();
      }
      await web.zoomBy(zoomFactor: factor);
    } catch (_) {
      if (mounted && report) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('页面缩放暂不可用，请尝试双指缩放。')));
      }
    }
  }

  Widget webTools(InAppWebViewController? Function() web) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        tooltip: '缩小网页',
        onPressed: () => resizeWeb(web(), factor: .8),
        icon: const AppIcon(AppIcons.zoomOut),
      ),
      TextButton.icon(
        onPressed: () => resizeWeb(web()),
        icon: const AppIcon(AppIcons.zoomFit),
        label: const Text('适应宽度'),
      ),
      IconButton(
        tooltip: '放大网页',
        onPressed: () => resizeWeb(web(), factor: 1.25),
        icon: const AppIcon(AppIcons.zoomIn),
      ),
    ],
  );

  Future<void> popup(int id) async {
    InAppWebViewController? popupController;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('学校页面'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: webTools(() => popupController),
            ),
          ),
          body: SafeArea(
            child: InAppWebView(
              windowId: id,
              initialSettings: settings(),
              onWebViewCreated: (web) => popupController = web,
              onLoadStop: (web, _) => resizeWeb(web, report: false),
              shouldOverrideUrlLoading: (_, action) async =>
                  authenticationUrl(action.request.url?.toString() ?? '')
                  ? NavigationActionPolicy.ALLOW
                  : NavigationActionPolicy.CANCEL,
              onDownloadStartRequest: (web, request) async {
                if (context.mounted) Navigator.pop(context);
                await download(web, request);
              },
              onReceivedServerTrustAuthRequest: (web, challenge) async =>
                  ServerTrustAuthResponse(
                    action: ServerTrustAuthResponseAction.CANCEL,
                  ),
              onPermissionRequest: (_, request) async => PermissionResponse(
                resources: request.resources,
                action: PermissionResponseAction.DENY,
              ),
            ),
          ),
        ),
      ),
    );
  }

  InAppWebViewSettings settings() => InAppWebViewSettings(
    preferredContentMode: UserPreferredContentMode.DESKTOP,
    useWideViewPort: true,
    loadWithOverviewMode: true,
    supportZoom: true,
    builtInZoomControls: true,
    displayZoomControls: false,
    javaScriptEnabled: true,
    domStorageEnabled: true,
    useShouldOverrideUrlLoading: true,
    useOnDownloadStart: true,
    supportMultipleWindows: true,
    javaScriptCanOpenWindowsAutomatically: running,
    allowFileAccess: false,
    allowContentAccess: false,
    allowFileAccessFromFileURLs: false,
    allowUniversalAccessFromFileURLs: false,
    thirdPartyCookiesEnabled: false,
    saveFormData: false,
    isInspectable: false,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
  );
  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Scaffold(
        appBar: AppBar(title: const Text('导入课表')),
        body: const Center(child: Text('当前仅 Android 已接入官方 XLS 解析。')),
      );
    }
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('学校官方页面'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: webTools(() => controller),
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const AppIcon(AppIcons.moreVertical),
              tooltip: '学校入口',
              enabled: !busy,
              onSelected: (url) async {
                await stop();
                await controller?.loadUrl(
                  urlRequest: URLRequest(url: WebUri(url)),
                );
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'https://webvpn.bucm.edu.cn/',
                  child: Text('学校 WebVPN'),
                ),
                PopupMenuItem(
                  value: 'https://i.bucm.edu.cn/',
                  child: Text('数字北中医'),
                ),
                PopupMenuItem(
                  value: 'https://jw.bucm.edu.cn/',
                  child: Text('教务系统（校内）'),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.all(16),
                child: Text(status),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: busy
                          ? null
                          : running
                          ? () {
                              stop();
                              update('自动导入已暂停。');
                            }
                          : start,
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : AppIcon(
                              running ? AppIcons.pause : AppIcons.download,
                            ),
                      label: Text(
                        running
                            ? '暂停导入'
                            : busy
                            ? '正在校验'
                            : '自动导入',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: busy ? null : extract,
                      child: const Text('页面读取（备用）'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: InAppWebView(
                  initialUrlRequest: URLRequest(
                    url: WebUri('https://webvpn.bucm.edu.cn/'),
                  ),
                  initialSettings: settings(),
                  onWebViewCreated: (value) => controller = value,
                  onLoadStop: (web, _) => resizeWeb(web, report: false),
                  shouldOverrideUrlLoading: (_, action) async {
                    if (authenticationUrl(
                      action.request.url?.toString() ?? '',
                    )) {
                      return NavigationActionPolicy.ALLOW;
                    }
                    update('已阻止学校及指定认证域名以外的跳转。');
                    return NavigationActionPolicy.CANCEL;
                  },
                  onCreateWindow: (_, action) async {
                    if (!running && action.hasGesture != true) return false;
                    unawaited(popup(action.windowId));
                    return true;
                  },
                  onDownloadStartRequest: download,
                  onReceivedServerTrustAuthRequest: (web, challenge) async {
                    update('学校连接的证书未通过校验，已停止加载。');
                    return ServerTrustAuthResponse(
                      action: ServerTrustAuthResponseAction.CANCEL,
                    );
                  },
                  onReceivedError: (web, request, error) {
                    if (request.isForMainFrame == true) {
                      update('网页未能加载，请检查网络或切换学校入口。旧课表不受影响。');
                    }
                  },
                  onPermissionRequest: (_, request) async => PermissionResponse(
                    resources: request.resources,
                    action: PermissionResponseAction.DENY,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
