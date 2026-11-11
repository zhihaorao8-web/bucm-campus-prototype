import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/platform/classroom_access.dart';
import 'package:campus_schedule/ui/classroom_course_page.dart';
import 'schedule_test.dart' show sample;
import 'package:campus_schedule/platform/classroom_session_cache.dart';

class RecoveryController extends PlatformInAppWebViewController {
  RecoveryController()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 'synthetic'),
      );
  String state = 'authentication';
  String snapshotState = 'navigate';
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
      return jsonEncode({'state': snapshotState});
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
  Future<RecoveryController> open(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    ClassroomSessionCache.shared.clear();
    final controller = RecoveryController();
    InAppWebViewPlatform.instance = RecoveryPlatform(controller);
    final course = Course.fromJson(
      sample().toJson()..['dataSource'] = 'school',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ClassroomCoursePage(
          course: course,
          importCourses: [course],
          onDetails: (_) {},
          probe: (url) async => AccessProbe(
            url == vpnEntry ? ProbeState.available : ProbeState.unavailable,
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
