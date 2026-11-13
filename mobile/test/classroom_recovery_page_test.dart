import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/platform/classroom_access.dart';
import 'package:campus_schedule/ui/classroom_course_page.dart';
import 'schedule_test.dart' show sample;
import 'package:campus_schedule/platform/classroom_session_cache.dart';
import 'support/memory_appearance.dart';

class RecoveryController extends PlatformInAppWebViewController {
  RecoveryController()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 'synthetic'),
      );
  String state = 'authentication';
  String snapshotState = 'navigate';
  Map<String, dynamic>? snapshotData;
  Completer<dynamic>? snapshotPending;
  bool created = false;
  PlatformInAppWebViewWidgetCreationParams? viewParams;
  int reads = 0;
  final commands = <String>[];
  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    reads++;
    if (source.contains('var command =')) {
      final text = RegExp(r'var command = (.*);').firstMatch(source)!.group(1)!;
      final action = (jsonDecode(text) as Map)['action'] as String;
      commands.add(action);
      if (snapshotPending != null) return snapshotPending!.future;
      return jsonEncode(snapshotData ?? {'state': snapshotState});
    }
    return jsonEncode({
      'state': state,
      'stage': 'portal',
      'reason': state == 'waiting' ? 'no-entry' : 'route',
    });
  }

  @override
  Future<void> disposeKeepAlive(InAppWebViewKeepAlive keepAlive) async {}
}

class RecoveryPlatform extends InAppWebViewPlatform {
  RecoveryPlatform(this.controller);
  final RecoveryController controller;
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => RecoveryView(params, controller);
  @override
  PlatformInAppWebViewController createPlatformInAppWebViewControllerStatic() =>
      controller;
}

class RecoveryView extends PlatformInAppWebViewWidget {
  RecoveryView(super.params, this.controller) : super.implementation();
  final RecoveryController controller;
  @override
  Widget build(BuildContext context) {
    controller.viewParams = params;
    if (!controller.created) {
      controller.created = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final web = params.controllerFromPlatform!(controller);
        params.onWebViewCreated?.call(web);
        params.onLoadStop?.call(web, WebUri(vpnEntry));
      });
    }
    return const Text('合成学校页面');
  }

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;
  @override
  void dispose() {}
}

void main() {
  setUpAll(() async {
    // Shared bundle futures must finish outside individual FakeAsync scopes.
    await rootBundle.loadString('assets/classroom.js');
    await rootBundle.loadString('assets/classroom-entry.js');
  });
  Future<RecoveryController> open(
    WidgetTester tester, {
    ProbeState? failure,
    bool direct = false,
    ProbeEndpoint? probe,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    ClassroomSessionCache.shared.clear();
    final controller = RecoveryController();
    InAppWebViewPlatform.instance = RecoveryPlatform(controller);
    final course = Course.fromJson(
      sample().toJson()..['dataSource'] = 'school',
    );
    await tester.pumpWidget(
      appearanceScope(
        MaterialApp(
          home: ClassroomCoursePage(
            course: course,
            importCourses: [course],
            onDetails: (_) {},
            probe:
                probe ??
                (url) async => AccessProbe(
                  failure ??
                      (direct || url == vpnEntry
                          ? ProbeState.available
                          : ProbeState.unavailable),
                ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    return controller;
  }

  Future<void> tick(WidgetTester tester, [int times = 1]) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(seconds: 2));
      // Asset-bundle script loading uses the real platform channel, while the
      // reader timers deliberately use the test clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  for (final failure in [ProbeState.unavailable, ProbeState.certificateError]) {
    testWidgets('manual official page opens after route probe $failure', (
      tester,
    ) async {
      final controller = await open(tester, failure: failure);
      expect(controller.created, isFalse);
      final button = find.text('打开学校页面');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      await tester.pump();
      expect(controller.created, isTrue);
      expect(
        controller.viewParams!.initialUrlRequest!.url.toString(),
        vpnEntry,
      );
      expect(
        find.byKey(const ValueKey('recording-native-layer')),
        findsNothing,
      );
      expect(find.text('合成学校页面'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }

  for (final snapshot in [false, true]) {
    testWidgets('direct authentication stays direct snapshot=$snapshot', (
      tester,
    ) async {
      final controller = await open(tester, direct: true);
      if (snapshot) controller.snapshotState = 'authentication';
      await tick(tester, 3);
      expect(
        controller.viewParams!.initialUrlRequest!.url.toString(),
        classroomProbe,
      );
      expect(find.textContaining('请在学校官方页面完成认证'), findsOneWidget);
      expect(find.textContaining('已选择学校 WebVPN'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }

  testWidgets('switching access detaches old login while probe is pending', (
    tester,
  ) async {
    var probes = 0;
    final pending = Completer<AccessProbe>();
    await open(
      tester,
      probe: (_) {
        if (++probes == 1) {
          return Future.value(const AccessProbe(ProbeState.available));
        }
        return pending.future;
      },
    );
    await tick(tester, 2);
    expect(find.text('合成学校页面'), findsOneWidget);
    await tester.tap(find.byTooltip('学校访问方式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自动选择（重新检测）'));
    await tester.pump();
    expect(find.byKey(const ValueKey('school-browser-layer')), findsNothing);
    expect(find.textContaining('正在检查学校服务访问路径'), findsOneWidget);
    pending.complete(const AccessProbe(ProbeState.available));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  for (final event in ['history', 'commit', 'deadline']) {
    testWidgets('readable SPA without load-stop recovers through $event', (
      tester,
    ) async {
      final controller = await open(tester, direct: true);
      final params = controller.viewParams!;
      final web = params.controllerFromPlatform!(controller);
      const page = 'https://qhz.bucm.edu.cn/coursePlatform/';
      controller.snapshotData = {'state': 'catalog', 'courses': <Object>[]};
      params.onLoadStart!(web, WebUri(page));
      if (event == 'history') {
        params.onUpdateVisitedHistory!(web, WebUri(page), false);
      } else if (event == 'commit') {
        params.onPageCommitVisible?.call(web, WebUri(page));
      }
      await tick(tester, event == 'deadline' ? 19 : 6);
      expect(find.textContaining('学校页面加载超时'), findsNothing);
      expect(find.textContaining('当前页面没有该学期的课程'), findsOneWidget);
      await tick(tester, 19);
      expect(find.textContaining('学校页面加载超时'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('visible authentication cancels the document load deadline', (
    tester,
  ) async {
    final controller = await open(tester, direct: true);
    final params = controller.viewParams!;
    final web = params.controllerFromPlatform!(controller);
    controller.snapshotState = 'authentication';
    params.onLoadStart!(web, WebUri(classroomProbe));
    params.onUpdateVisitedHistory!(web, WebUri(classroomProbe), false);
    await tick(tester, 22);
    expect(find.textContaining('学校页面加载超时'), findsNothing);
    expect(find.textContaining('请在学校官方页面完成认证'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'late load-deadline probe cannot replace a newer authentication page',
    (tester) async {
      final controller = await open(tester, direct: true);
      final params = controller.viewParams!;
      final web = params.controllerFromPlatform!(controller);
      final pending = Completer<dynamic>();
      controller.snapshotPending = pending;
      params.onLoadStart!(
        web,
        WebUri('https://qhz.bucm.edu.cn/coursePlatform/'),
      );
      await tick(tester, 15);
      controller.snapshotPending = null;
      controller.snapshotState = 'authentication';
      params.onLoadStart!(web, WebUri(classroomProbe));
      params.onUpdateVisitedHistory!(web, WebUri(classroomProbe), false);
      pending.complete(jsonEncode({'state': 'catalog', 'courses': <Object>[]}));
      await tick(tester, 20);
      expect(find.textContaining('当前页面没有该学期的课程'), findsNothing);
      expect(find.textContaining('学校页面加载超时'), findsNothing);
      expect(find.textContaining('请在学校官方页面完成认证'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'unresponsive deadline probe stays bounded and ignores a late readable result',
    (tester) async {
      final controller = await open(tester, direct: true);
      final params = controller.viewParams!;
      final web = params.controllerFromPlatform!(controller);
      final pending = Completer<dynamic>();
      controller.snapshotPending = pending;
      params.onLoadStart!(
        web,
        WebUri('https://qhz.bucm.edu.cn/coursePlatform/'),
      );
      await tick(tester, 18);
      expect(find.textContaining('学校页面加载超时'), findsOneWidget);
      pending.complete(jsonEncode({'state': 'catalog', 'courses': <Object>[]}));
      controller.snapshotPending = null;
      await tester.pump();
      expect(find.textContaining('学校页面加载超时'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('认证等待→门户超时→继续导入→后台暂停恢复→未知路径提示', (tester) async {
    final controller = await open(tester);
    await tick(tester, 32);
    expect(find.textContaining('请在学校官方页面完成认证'), findsOneWidget);
    expect(controller.reads, greaterThan(40));
    controller.state = 'waiting'; // Login completed without a top-frame event.
    await tick(tester, 23);
    expect(find.textContaining('尚未从 WebVPN 进入教学平台'), findsOneWidget);
    await tester.tap(find.byTooltip('继续导入'));
    await tester.pump();
    await tick(tester);
    expect(controller.commands, everyElement('snapshot'));
    expect(find.textContaining('正在等待 WebVPN 门户入口'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final reads = controller.reads;
    await tick(tester, 30);
    expect(controller.reads, reads);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    controller.state = 'untrusted';
    await tick(tester, 2);
    expect(find.textContaining('当前页面不属于已支持的学校入口路径'), findsOneWidget);
    expect(controller.commands, everyElement('snapshot'));
    controller.snapshotState = 'loading'; // Trusted SPA not initialized yet.
    await tester.tap(find.byTooltip('继续导入'));
    await tester.pump();
    await tick(tester, 23);
    expect(find.textContaining('课程数据读取超时'), findsOneWidget);
    expect(controller.commands, everyElement('snapshot'));
    for (final failureInSnapshot in [false, true]) {
      controller.state = 'serviceUnavailable';
      controller.snapshotState = failureInSnapshot
          ? 'serviceUnavailable'
          : 'navigate';
      final failureParams = controller.viewParams!;
      final failureWeb = failureParams.controllerFromPlatform!(controller);
      failureParams.onLoadStart!(failureWeb, WebUri(vpnEntry));
      failureParams.onLoadStop!(failureWeb, WebUri(vpnEntry));
      await tick(tester, 2);
      expect(find.textContaining('学校服务暂时无法连接'), findsOneWidget);
      expect(find.textContaining('请在学校官方页面完成认证'), findsNothing);
      final stoppedReads = controller.reads;
      failureParams.onTitleChanged!(failureWeb, 'WebVPN');
      await tick(tester, 25);
      expect(controller.reads, stoppedReads);
    }
    controller.state = 'waiting';
    controller.snapshotState = 'loading';
    var params = controller.viewParams!;
    var web = params.controllerFromPlatform!(controller);
    params.onLoadStart!(web, WebUri(vpnEntry));
    await tick(tester, 16);
    expect(find.textContaining('学校页面加载超时'), findsOneWidget);
    const cc =
        'https://webvpn.bucm.edu.cn/https/77726476706e69737468656265737421e1ff5bd225256b5d300d8db9d6562d/cc/';
    params = controller.viewParams!;
    web = params.controllerFromPlatform!(controller);
    for (var i = 0; i < 6; i++) {
      params.onLoadStart!(web, WebUri(cc));
    }
    await tester.pump();
    final views = tester.widgetList<InAppWebView>(find.byType(InAppWebView));
    expect(
      views.single.platform.params.initialUrlRequest!.url.toString(),
      contains('/coursePlatform/#/courseCenter/index?firstMenuId=11'),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
