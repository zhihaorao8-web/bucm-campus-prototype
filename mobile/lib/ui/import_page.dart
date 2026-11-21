import '../config/runtime_config.dart';
import '../config/network_policy.dart';
import '../design/app_tokens.dart';
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
import '../platform/campus_login_navigation.dart';
import '../platform/school_adapter.dart';
import '../platform/classroom_session_cache.dart';
import '../platform/webview_identity.dart';
import 'app_controls.dart';
import 'campus_login_page.dart';

enum _ImportAction { automatic, pageRead }

class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key, this.recoverUnreadable = false});
  final bool recoverUnreadable;
  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  InAppWebViewController? controller;
  final adapter = SchoolAdapter();
  String status = '请选择学校入口，打开学期理论课表后可自动导入。';
  String semester = '';
  bool running = false, busy = false, waitingFile = false;
  int steps = 0, generation = 0;
  Timer? timer;
  CampusLoginTarget _entry = CampusLoginTarget.vpn;
  CampusLoginTarget? _authTarget;
  (CampusLoginTarget, _ImportAction?)? _waitingForSchool;
  bool _loginOpen = false;
  bool _resumedImport = false;
  int _document = 0;

  bool get _connecting => _loginOpen || _waitingForSchool != null;

  @override
  void initState() {
    super.initState();
    ClassroomSessionCache.shared.clear();
    SchoolAdapter.sessionChanges.addListener(_sessionCleared);
  }

  @override
  void dispose() {
    SchoolAdapter.sessionChanges.removeListener(_sessionCleared);
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
    _waitingForSchool = null;
    await controller?.setSettings(
      settings: InAppWebViewSettings(
        javaScriptCanOpenWindowsAutomatically: false,
      ),
    );
    if (mounted) setState(() {});
  }

  void _sessionCleared() {
    unawaited(stop());
    update('学校会话已清除，离线课表保留。');
  }

  Future<void> _selectEntry(CampusLoginTarget entry) async {
    _entry = entry;
    _authTarget = null;
    await stop();
    if (!mounted) return;
    update('正在打开${entry.label}。');
    await controller?.loadUrl(urlRequest: URLRequest(url: WebUri(entry.entry)));
  }

  Future<void> _authenticate(
    CampusLoginTarget target, [
    _ImportAction? action,
  ]) async {
    if (!mounted ||
        busy ||
        _connecting ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _authTarget = target;
    _loginOpen = true;
    final revision = SchoolAdapter.sessionChanges.value;
    try {
      await stop();
      final loginGeneration = generation;
      if (!mounted || revision != SchoolAdapter.sessionChanges.value) return;
      final available = await openCampusLogin(
        context,
        target: target,
        reason: switch (action) {
          _ImportAction.automatic => '登录后继续自动导入课表',
          _ImportAction.pageRead => '登录后继续读取课表页面',
          null => '登录后返回课表导入',
        },
      );
      if (!mounted ||
          revision != SchoolAdapter.sessionChanges.value ||
          loginGeneration != generation) {
        return;
      }
      if (!available) {
        update('已取消登录，离线课表保留。');
        return;
      }
      _waitingForSchool = (target, action);
      showAppNotice(
        context,
        '校园账号登录成功，正在返回${target.label}',
        success: true,
      );
      update('校园账号登录成功，正在返回${target.label}。');
      timer = Timer(CampusLoginPolicy.pageTimeout, () {
        _waitingForSchool = null;
        update('学校页面暂未恢复，请先打开学期理论课表，再重试导入。');
      });
      await controller?.loadUrl(
        urlRequest: URLRequest(url: WebUri(target.entry)),
      );
    } catch (_) {
      timer?.cancel();
      _waitingForSchool = null;
      update('学校登录暂未完成，请重试。离线课表保留。');
    } finally {
      if (mounted) setState(() => _loginOpen = false);
    }
  }

  void _authenticationNeeded(CampusLoginTarget target) {
    _authTarget = target;
    if (!running || waitingFile) {
      update('需要登录校园账号后继续。');
    } else if (_resumedImport) {
      unawaited(stop());
      update('学校页面仍需登录，请重新选择入口或重试。离线课表保留。');
    } else {
      unawaited(_authenticate(target, _ImportAction.automatic));
    }
  }

  Future<bool> _isAuthentication(
    InAppWebViewController web,
    String? address,
  ) async {
    if (campusLoginDocument(address)) return true;
    if (!CampusLoginTarget.vpn.isDestination(address)) return false;
    try {
      return await web.evaluateJavascript(source: campusVpnLoginScript) == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _pageLoaded(
    InAppWebViewController web,
    WebUri? url, {
    required bool complete,
  }) async {
    if (!mounted || !sameWebViewController(web, controller)) return;
    final document = ++_document;
    final address = url?.toString();
    final authentication = await _isAuthentication(web, address);
    if (!mounted ||
        !sameWebViewController(web, controller) ||
        document != _document) {
      return;
    }
    final queued = _waitingForSchool;
    if (queued != null) {
      if (authentication) {
        timer?.cancel();
        _waitingForSchool = null;
        _authTarget = campusLoginTargetFor(address, _entry);
        update('学校页面仍需登录，请重试。离线课表保留。');
      } else if (complete && queued.$1.isDestination(address)) {
        timer?.cancel();
        _waitingForSchool = null;
        _authTarget = null;
        update('已返回学校页面。');
        switch (queued.$2) {
          case _ImportAction.automatic:
            unawaited(start(resumed: true));
          case _ImportAction.pageRead:
            unawaited(extract());
          case null:
            break;
        }
      }
    } else if (authentication && !_loginOpen) {
      _authenticationNeeded(campusLoginTargetFor(address, _entry));
    } else if (_authTarget != null &&
        schoolUrl(address ?? '') &&
        !authentication) {
      setState(() => _authTarget = null);
    }
    if (!authentication && complete) {
      unawaited(resizeWeb(web, report: false));
    }
  }

  void _pageFailed(String message) {
    if (_waitingForSchool != null) {
      timer?.cancel();
      _waitingForSchool = null;
    }
    update(message);
  }

  Future<Map<String, dynamic>> script(String asset) async {
    final source = await rootBundle.loadString(asset);
    final result = await controller!.evaluateJavascript(source: source);
    if (result is String) return jsonDecode(result) as Map<String, dynamic>;
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> start({bool resumed = false}) async {
    if (busy || controller == null) return;
    final target = _authTarget;
    if (!resumed && target != null) {
      await _authenticate(target, _ImportAction.automatic);
      return;
    }
    final stopped = stop();
    final session = generation;
    await stopped;
    if (!mounted || session != generation) return;
    running = true;
    _resumedImport = resumed;
    steps = 0;
    semester = '';
    await controller!.setSettings(
      settings: InAppWebViewSettings(
        javaScriptCanOpenWindowsAutomatically: true,
      ),
    );
    if (!mounted || session != generation) return;
    setState(() {});
    await step(session);
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
      final web = controller!;
      final url = (await web.getUrl())?.toString() ?? '';
      if (!mounted || session != generation || !running) return;
      final authentication = await _isAuthentication(web, url);
      if (!mounted || session != generation || !running) return;
      if (authentication) {
        _authenticationNeeded(campusLoginTargetFor(url, _entry));
        return;
      }
      if (!schoolUrl(url)) {
        update('请在学校官方认证页面完成登录，返回学校后继续。');
      } else {
        final result = await script(AppAssets.exportNavigation);
        if (!mounted || session != generation || !running) return;
        switch (result['state']) {
          case 'exportClicked':
            semester = result['semester'] as String? ?? '';
            waitingFile = true;
            update('已触发学校官方导出，正在等待文件。');
            timer = Timer(ImportPolicy.exportWait, () async {
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
            _authenticationNeeded(_entry);
            return;
          default:
            update('正在打开学期理论课表并选择全部周次。');
        }
      }
      timer = Timer(ImportPolicy.navigationPoll, () => step(session));
    } catch (_) {
      if (!mounted || session != generation || !running) return;
      await stop();
      update('自动导航未完成。请进入学期理论课表后重试，或使用页面读取。');
    }
  }

  Future<void> download(
    InAppWebViewController web,
    DownloadStartRequest request,
  ) async {
    if (!mounted || busy || _connecting) return;
    final url = request.url.toString();
    if (!schoolUrl(url)) {
      update('已阻止非学校 HTTPS 地址的导出。');
      return;
    }
    busy = true;
    timer?.cancel();
    update('正在本机读取并校验官方 Excel，原有课表暂不改动。');
    final sourceSemester = semester;
    final revision = SchoolAdapter.sessionChanges.value;
    try {
      await stop();
      if (!mounted || revision != SchoolAdapter.sessionChanges.value) return;
      final batch = await adapter.download(
        url,
        request.userAgent ?? '',
        sourceSemester,
      );
      if (mounted && revision == SchoolAdapter.sessionChanges.value) {
        await finishBatch(batch, '官方 Excel', revision);
      }
    } catch (_) {
      update('官方 Excel 未能完整读取。请确认已登录并重新导出；旧课表未改动。');
    } finally {
      busy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> extract() async {
    if (busy || controller == null) return;
    final target = _authTarget;
    if (target != null) {
      await _authenticate(target, _ImportAction.pageRead);
      return;
    }
    busy = true;
    final revision = SchoolAdapter.sessionChanges.value;
    update('正在读取当前课表页面。');
    try {
      await stop();
      final web = controller!;
      final url = (await web.getUrl())?.toString() ?? '';
      final authentication = await _isAuthentication(web, url);
      if (!mounted || revision != SchoolAdapter.sessionChanges.value) return;
      if (authentication) {
        busy = false;
        await _authenticate(
          campusLoginTargetFor(url, _entry),
          _ImportAction.pageRead,
        );
        return;
      }
      if (!schoolUrl(url)) {
        throw const FormatException();
      }
      final coverage = await script(AppAssets.coverage);
      if (coverage['full'] != true) {
        update('页面读取暂未确认“学期理论课表 / 全部周次”。请先选择全部周次，避免用一周课表覆盖整学期。');
        return;
      }
      final result = await script(AppAssets.extract);
      if (!mounted || revision != SchoolAdapter.sessionChanges.value) return;
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
      if (!mounted || revision != SchoolAdapter.sessionChanges.value) return;
      final batch = await adapter.parseDom(
        Map<String, dynamic>.from(tables[selected]),
        result['semester'] as String? ?? '',
      );
      batch.payload['hasUnscheduled'] = coverage['hasUnscheduled'] == true;
      if (mounted && revision == SchoolAdapter.sessionChanges.value) {
        await finishBatch(batch, '页面读取', revision);
      }
    } catch (_) {
      update('没有完整读取课表。请打开学期理论课表并选择全部周次后重试，旧课表未改动。');
    } finally {
      busy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> finishBatch(
    ParsedBatch batch,
    String source,
    int revision,
  ) async {
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
      if (!mounted || revision != SchoolAdapter.sessionChanges.value) return;
      if (config == null) {
        update('已取消导入，旧课表未改动。');
        return;
      }
      term = config.$1;
      monday = config.$2;
    }
    final courses = await adapter.validate(batch, term, monday);
    if (!mounted || revision != SchoolAdapter.sessionChanges.value) return;
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
        final source = await rootBundle.loadString(AppAssets.viewport);
        final result = await web
            .callAsyncJavaScript(functionBody: source)
            .timeout(ImportPolicy.viewportTimeout);
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
    final target = await Navigator.of(context).push<CampusLoginTarget>(
      MaterialPageRoute<CampusLoginTarget>(
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
              onLoadStop: (web, url) {
                final address = url?.toString();
                if (campusLoginDocument(address) &&
                    context.mounted &&
                    ModalRoute.of(context)?.isCurrent == true) {
                  Navigator.pop(context, campusLoginTargetFor(address, _entry));
                } else {
                  unawaited(resizeWeb(web, report: false));
                }
              },
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
    if (mounted && target != null) _authenticationNeeded(target);
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
          bottom: _authTarget == null
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(48),
                  child: webTools(() => controller),
                )
              : null,
          actions: [
            PopupMenuButton<CampusLoginTarget>(
              icon: const AppIcon(AppIcons.moreVertical),
              tooltip: '学校入口',
              enabled: !busy && !_connecting,
              onSelected: _selectEntry,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: CampusLoginTarget.vpn,
                  child: Text('学校 WebVPN'),
                ),
                PopupMenuItem(
                  value: CampusLoginTarget.portal,
                  child: Text('数字北中医'),
                ),
                PopupMenuItem(
                  value: CampusLoginTarget.teaching,
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
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Text(status),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md,
                  vertical: AppSpace.sm,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: busy || _connecting
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
                      onPressed: busy || _connecting ? null : extract,
                      child: const Text('页面读取（备用）'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Visibility(
                  visible: _authTarget == null,
                  maintainState: true,
                  replacement: Center(
                    child: AppActionButton(
                      label: '登录校园账号',
                      icon: AppIcons.globe,
                      onPressed:
                          _authTarget == null || busy || _connecting || running
                          ? null
                          : () => _authenticate(_authTarget!),
                    ),
                  ),
                  child: InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(_entry.entry)),
                    initialSettings: settings(),
                    onWebViewCreated: (value) => controller = value,
                    onLoadStart: (_, _) => _document++,
                    onPageCommitVisible: (web, url) =>
                        _pageLoaded(web, url, complete: false),
                    onLoadStop: (web, url) =>
                        _pageLoaded(web, url, complete: true),
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
                      if (busy ||
                          _connecting ||
                          (!running && action.hasGesture != true)) {
                        return false;
                      }
                      unawaited(popup(action.windowId));
                      return true;
                    },
                    onDownloadStartRequest: download,
                    onReceivedServerTrustAuthRequest: (web, challenge) async {
                      _pageFailed('学校连接的证书未通过校验，已停止加载。');
                      return ServerTrustAuthResponse(
                        action: ServerTrustAuthResponseAction.CANCEL,
                      );
                    },
                    onReceivedError: (web, request, error) {
                      if (request.isForMainFrame == true) {
                        _pageFailed('网页未能加载，请检查网络或切换学校入口。旧课表不受影响。');
                      }
                    },
                    onReceivedHttpError: (web, request, _) {
                      if (request.isForMainFrame == true) {
                        _pageFailed('学校服务暂时无法打开，请稍后重试。离线课表保留。');
                      }
                    },
                    onPermissionRequest: (_, request) async =>
                        PermissionResponse(
                          resources: request.resources,
                          action: PermissionResponseAction.DENY,
                        ),
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
