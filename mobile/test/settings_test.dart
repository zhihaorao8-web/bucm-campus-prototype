import 'package:campus_schedule/ui/quiet_backdrop.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:campus_schedule/main.dart';
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/application/schedule_controller.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/data/classroom_library.dart';
import 'package:campus_schedule/data/classroom_playback_progress.dart';
import 'package:campus_schedule/platform/app_platform.dart';
import 'package:campus_schedule/platform/campus_login_navigation.dart';
import 'package:campus_schedule/platform/school_adapter.dart';
import 'package:campus_schedule/ui/campus_login_page.dart';
import 'package:campus_schedule/ui/project_info_page.dart';
import 'package:campus_schedule/ui/settings_scaffold.dart';
import 'package:campus_schedule/ui/course_surface.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:flutter_miuix/miuix.dart';
import 'schedule_test.dart' show MemoryRepository, sample;
import 'support/campus_login_webview.dart';
import 'support/memory_appearance.dart';
import 'ui_test.dart' show app;

Future<void> reveal(WidgetTester tester, Finder target) async {
  final list = find.byType(CustomScrollView).last;
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: find
          .descendant(of: list, matching: find.byType(Scrollable))
          .first,
    );
  }
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
}

void main() {
  // Shared queues must be created outside each widget test's FakeAsync zone.
  setUpAll(() {
    expect(ClassroomLibrary.shared.revision, 0);
    expect(ClassroomPlaybackProgressStore.shared.revision, 0);
  });
  test('campus login permits only HTTPS CAS and the selected service', () {
    const target = CampusLoginTarget.portal;
    expect(target.allows('https://cas.bucm.edu.cn/cas/login'), isTrue);
    expect(target.isDestination('https://i.bucm.edu.cn/tp_nup/'), isTrue);
    expect(target.isDestination('https://cas.bucm.edu.cn/cas/login'), isFalse);
    expect(target.isDestination('https://i.bucm.edu.cn/'), isFalse);
    for (final address in [
      'http://i.bucm.edu.cn/tp_nup/',
      'https://@cas.bucm.edu.cn/cas/login',
      'https://cas.bucm.edu.cn:444/cas/login',
      'https://cas.bucm.edu.cn.example/cas/login',
      'https://jw.bucm.edu.cn/',
      'wxwork://login',
    ]) {
      expect(target.allows(address), isFalse, reason: address);
    }
  });

  testWidgets('settings login keeps the official page until portal is ready', (
    tester,
  ) async {
    final platform = CampusLoginTestPlatform();
    final previous = InAppWebViewPlatform.instance;
    InAppWebViewPlatform.instance = platform;
    if (previous != null) {
      addTearDown(() => InAppWebViewPlatform.instance = previous);
    }
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(MemoryRepository(const ScheduleData()), dark: true, scale: 2),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-3')));
    await tester.pumpAndSettle();
    final login = find.text('登录校园账号');
    await reveal(tester, login);
    await tester.tap(login);
    await tester.pump();
    final view = platform.views.single;
    const cas = 'https://cas.bucm.edu.cn/cas/login';
    view.visit(cas);
    await tester.pumpAndSettle();
    expect(find.text('校园账号登录'), findsOneWidget);
    expect(find.text('账号密码'), findsOneWidget);
    expect(view.controller.scripts.single, contains('a#password_login'));
    await tester.tap(find.widgetWithText(ChoiceChip, '手机号'));
    await tester.pumpAndSettle();
    expect(
      view.controller.scripts.last,
      contains("querySelector('a#loginByMobile').click()"),
    );
    view.visit(CampusLoginTarget.portal.entry);
    await tester.pumpAndSettle();
    expect(find.text('校园账号登录'), findsOneWidget);
    view.controller.ready = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('数字北中医已可访问'), findsOneWidget);
    expect(find.byType(CampusLoginPage), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('campus login retries a timeout and exits on cancellation', (
    tester,
  ) async {
    final platform = CampusLoginTestPlatform();
    final previous = InAppWebViewPlatform.instance;
    InAppWebViewPlatform.instance = platform;
    if (previous != null) {
      addTearDown(() => InAppWebViewPlatform.instance = previous);
    }
    final outcomes = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => outcomes.add(
              await openCampusLogin(
                context,
                target: CampusLoginTarget.vpn,
                reason: '继续访问教务系统',
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 26));
    await tester.pumpAndSettle();
    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(platform.views, hasLength(2));
    platform.views.last.visit('https://cas.bucm.edu.cn/cas/login');
    await tester.pumpAndSettle();
    expect(find.text('用另一台设备的企业微信扫描官方页面二维码。'), findsOneWidget);
    expect(platform.views.last.controller.scripts, isEmpty);
    final vpn = platform.views.last;
    vpn.controller.execute = (source) => source == campusVpnLoginScript;
    vpn.visit(CampusLoginTarget.vpn.entry, loaded: false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 26));
    expect(find.text('重试'), findsNothing);
    expect(find.byType(CampusLoginPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(outcomes, [false]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  for (final pageRead in [false, true]) {
    testWidgets(
      'course import resumes once after login (page read: $pageRead)',
      (tester) async {
        final platform = CampusLoginTestPlatform();
        final previous = InAppWebViewPlatform.instance;
        InAppWebViewPlatform.instance = platform;
        if (previous != null) {
          addTearDown(() => InAppWebViewPlatform.instance = previous);
        }
        final course = sample();
        final repo = MemoryRepository(ScheduleData(courses: [course]));
        await tester.pumpWidget(app(repo));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('tab-3')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('导入或刷新课表'));
        await tester.pumpAndSettle();
        final importer = platform.views.single;
        final controller = importer.controller;
        await tester.tap(find.byTooltip('学校入口'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('教务系统（校内）'));
        await tester.pumpAndSettle();
        const teaching = CampusLoginTarget.teaching;
        const cas =
            'https://cas.bucm.edu.cn/cas/login'
            '?service=https%3A%2F%2Fjw.bucm.edu.cn%2F';
        expect(controller.loads, [teaching.entry]);
        importer.visit(cas);
        await tester.pumpAndSettle();
        final action = find.text(pageRead ? '页面读取（备用）' : '自动导入');
        await tester.tap(action);
        await tester.pump();
        platform.views.last.visit(cas);
        await tester.pumpAndSettle();
        expect(find.byType(CampusLoginPage), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('已取消登录，离线课表保留。'), findsOneWidget);
        expect(controller.loads, [teaching.entry]);
        expect(controller.scripts, isEmpty);

        await tester.tap(action);
        await tester.pump();
        final login = platform.views.last;
        login.controller.ready = true;
        login.visit(teaching.entry);
        await tester.pumpAndSettle();
        expect(find.byType(CampusLoginPage), findsNothing);
        expect(login.controller.scripts, hasLength(1));
        expect(controller.loads, [teaching.entry, teaching.entry]);
        expect(controller.scripts, isEmpty);
        await tester.runAsync(() async {
          final operation = Completer<void>();
          controller.execute = (_) {
            if (!operation.isCompleted) operation.complete();
            return pageRead ? {'full': false} : {'state': 'waiting'};
          };
          importer.visit(teaching.entry);
          importer.visit(teaching.entry);
          await operation.future.timeout(const Duration(seconds: 5));
        });
        await tester.pump();
        expect(controller.scripts.length, 1);
        expect(repo.value.courses, [course]);
        if (!pageRead) {
          importer.visit(cas);
          await tester.pumpAndSettle();
          expect(find.byType(CampusLoginPage), findsNothing);
          expect(find.textContaining('学校页面仍需登录'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
  testWidgets('WebVPN sign-in at its root is recognized before page reading', (
    tester,
  ) async {
    final platform = CampusLoginTestPlatform();
    final previous = InAppWebViewPlatform.instance;
    InAppWebViewPlatform.instance = platform;
    if (previous != null) {
      addTearDown(() => InAppWebViewPlatform.instance = previous);
    }
    await tester.pumpWidget(app(MemoryRepository(const ScheduleData())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从学校导入课表'));
    await tester.pumpAndSettle();
    final view = platform.views.single;
    view.controller.execute = (source) => source == campusVpnLoginScript;
    view.visit(CampusLoginTarget.vpn.entry, loaded: false);
    await tester.pumpAndSettle();
    expect(find.text('需要登录校园账号后继续。'), findsOneWidget);
    await tester.tap(find.text('页面读取（备用）'));
    await tester.pump();
    platform.views.last.visit('https://webvpn.bucm.edu.cn/login');
    await tester.pumpAndSettle();
    expect(find.text('登录后继续读取课表页面'), findsOneWidget);
    expect(view.controller.scripts, [campusVpnLoginScript]);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  for (final scale in [1.0, 1.5]) {
    testWidgets('settings reverse keyboard focus clears the header: $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final nodes = List.generate(10, (_) => FocusNode());
      addTearDown(() {
        for (final node in nodes) {
          node.dispose();
        }
      });
      const settings = AppearanceSettings();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [currentAppearanceProvider.overrideWithValue(settings)],
          child: MaterialApp(
            theme: appTheme(Brightness.dark, settings: settings),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.only(top: 24, bottom: 20),
                textScaler: TextScaler.linear(scale),
              ),
              child: MiuixThemeBridge(child: child!),
            ),
            home: SettingsScaffold(
              title: '设置合成测试',
              children: [
                for (var i = 0; i < nodes.length; i++)
                  settingsGroup([
                    ListTile(
                      key: ValueKey('focus-setting-$i'),
                      focusNode: nodes[i],
                      title: Text('设置项目 $i'),
                      onTap: () {},
                    ),
                  ]),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final last = find.byKey(const ValueKey('focus-setting-9'));
      await tester.scrollUntilVisible(last, 180);
      await Scrollable.ensureVisible(tester.element(last));
      nodes.last.requestFocus();
      await tester.pumpAndSettle();
      for (var i = nodes.length - 2; i >= 0; i--) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
        await tester.pumpAndSettle();
        expect(
          nodes[i].hasFocus,
          isTrue,
          reason:
              'setting $i; focused: ${nodes.indexWhere((node) => node.hasFocus)}',
        );
        final tile = tester.getRect(find.byKey(ValueKey('focus-setting-$i')));
        final header = tester.getRect(find.byType(MiuixTopAppBar));
        expect(tile.top, greaterThanOrEqualTo(header.bottom - .5));
        expect(tile.bottom, lessThanOrEqualTo(700.5));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final scale in [1.0, 1.5]) {
    testWidgets('settings homepage reveal clears the header: $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(MemoryRepository(const ScheduleData()), dark: true, scale: scale),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-3')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const PageStorageKey('settings-page')),
        const Offset(0, -420),
      );
      await tester.pumpAndSettle();
      final appearance = find.text('外观设置');
      await reveal(tester, appearance);
      await Scrollable.ensureVisible(tester.element(appearance));
      await tester.pumpAndSettle();
      final header = tester.getRect(find.byType(MiuixTopAppBar));
      expect(
        tester.getRect(appearance).top,
        greaterThanOrEqualTo(header.bottom),
      );
      await tester.tap(appearance);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-route-外观设置')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final mode in [
    'glass',
    'no-blur',
    'no-glass',
    'contrast',
    'system-contrast',
  ]) {
    testWidgets('settings surfaces and scrolled header: $mode', (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = AppearanceSettings(
        blur: mode != 'no-blur',
        glass: mode != 'no-glass',
        contrast: mode == 'contrast' ? 1 : 0,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [currentAppearanceProvider.overrideWithValue(settings)],
          child: MaterialApp(
            theme: appTheme(Brightness.dark, settings: settings),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                highContrast: mode == 'system-contrast',
                textScaler: const TextScaler.linear(1.5),
              ),
              child: MiuixThemeBridge(child: child!),
            ),
            home: SettingsScaffold(
              title: '设置合成测试',
              children: [
                for (var i = 0; i < 12; i++)
                  settingsGroup([ListTile(title: Text('设置项目 $i'))]),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final header = find.byType(MiuixTopAppBar);
      expect(tester.widget<MiuixTopAppBar>(header).blurred, mode == 'glass');
      final surface = find.byType(CourseSurface).first;
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: surface,
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.gradient != null, mode == 'glass');
      expect(
        tester.widget<MiuixTopAppBar>(header).blurTintAlpha,
        closeTo(.04, .001),
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MiuixTopAppBar>(header).blurTintAlpha,
        closeTo(.8, .001),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  test('build identity distinguishes unknown, clean and modified sources', () {
    expect(const AppPlatformInfo().sourceLabel, '源码未知');
    expect(const AppPlatformInfo(source: 'untrusted text').sourceLabel, '源码未知');
    const sha = '0123456789abcdef0123456789abcdef01234567';
    expect(const AppPlatformInfo(source: sha).sourceLabel, '源码 01234567');
    expect(
      const AppPlatformInfo(source: '$sha-modified').sourceLabel,
      '源码 01234567 · 含未提交修改',
    );
  });
  testWidgets(
    'settings exposes new sync card and preserves separate session/course confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MemoryRepository(
        ScheduleData(courses: [sample()], summary: '合成导入摘要'),
      );
      final folder = await tester.runAsync(
        () => Directory.systemTemp.createTemp('synthetic-logout-'),
      );
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paths, (_) async => folder!.path);
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(paths, null);
        await folder!.delete(recursive: true);
      });
      var sessionClears = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SchoolAdapter.channel, (call) async {
            if (call.method == 'clearSession') sessionClears++;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SchoolAdapter.channel, null),
      );
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-3')));
      await tester.pumpAndSettle();
      expect(find.text('外观设置'), findsOneWidget);
      expect(find.text('登录与隐私'), findsOneWidget);
      expect(find.byKey(const ValueKey('schedule-sync-card')), findsOneWidget);
      expect(find.text('导入或刷新课表'), findsOneWidget);
      expect(find.text('本学期更新时间未知，已保存的课表可离线查看'), findsOneWidget);
      for (final removed in ['体验合成示例', '导入结果', '合成导入摘要']) {
        expect(find.text(removed), findsNothing);
      }
      await reveal(tester, find.text('退出学校会话'));
      await tester.tap(find.text('退出学校会话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(sessionClears, 0);
      await tester.tap(find.text('退出学校会话'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('确认'));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      final sessionControl = find.ancestor(
        of: find.text('退出学校会话'),
        matching: find.byType(MiuixBasicComponent),
      );
      // File cleanup spans multiple IO completions outside the fake test clock.
      for (
        var i = 0;
        i < 100 && !tester.widget<MiuixBasicComponent>(sessionControl).enabled;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }
      expect(
        tester.widget<MiuixBasicComponent>(sessionControl).enabled,
        isTrue,
      );
      expect(sessionClears, 1);
      expect(repo.value.courses.length, 1);
      await reveal(tester, find.text('清空本地课表'));
      final clearControl = find.ancestor(
        of: find.text('清空本地课表'),
        matching: find.byType(MiuixBasicComponent),
      );
      expect(tester.widget<MiuixBasicComponent>(clearControl).enabled, isTrue);
      await tester.tap(find.text('清空本地课表'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(repo.value.courses.length, 1);
      await tester.tap(find.text('清空本地课表'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(repo.value.courses, isEmpty);
      expect(sessionClears, 1);
      await reveal(tester, find.byKey(const ValueKey('project-info-entry')));
      expect(find.text('项目信息'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'project page uses package metadata and real links/copy with browser fallback',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final links = <String>[];
      String? copied;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(appChannel, (call) async {
        if (call.method == 'openProjectLink') {
          links.add(call.arguments as String);
          if (call.arguments == 'repository') {
            throw PlatformException(code: 'NO_BROWSER');
          }
        }
        return null;
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(appChannel, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      final container = ProviderContainer(
        overrides: [
          ambientMotionEnabledProvider.overrideWithValue(false),
          appearanceRepositoryProvider.overrideWithValue(
            MemoryAppearanceRepository(),
          ),
          repositoryProvider.overrideWithValue(
            MemoryRepository(const ScheduleData()),
          ),
          appInfoProvider.overrideWith(
            (ref) async => const AppPlatformInfo(
              name: '合成应用名称',
              version: '9.9-test',
              build: '99',
              sdk: 36,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CampusApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-3')));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('project-info-entry')));
      await tester.tap(find.text('项目信息'));
      await tester.pumpAndSettle();
      expect(find.text('合成应用名称'), findsOneWidget);
      expect(find.text('版本 9.9-test (99)'), findsOneWidget);
      expect(find.text('调试构建\n源码未知'), findsOneWidget);
      final icon = find.byKey(const ValueKey('project-app-icon'));
      await tester.runAsync(
        () => precacheImage(
          tester.widget<Image>(icon).image,
          tester.element(icon),
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<RawImage>(
              find.descendant(of: icon, matching: find.byType(RawImage)),
            )
            .image,
        isNotNull,
      );
      expect(
        tester
            .getRect(find.byKey(const ValueKey('project-app-icon')))
            .center
            .dx,
        closeTo(195, 1),
      );
      await reveal(tester, find.text(developerName));
      final avatar = find.byKey(const ValueKey('developer-avatar'));
      await tester.runAsync(
        () => precacheImage(
          tester.widget<Image>(avatar).image,
          tester.element(avatar),
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<RawImage>(
              find.descendant(of: avatar, matching: find.byType(RawImage)),
            )
            .image,
        isNotNull,
      );
      await tester.tap(avatar);
      await tester.pumpAndSettle();
      expect(links, ['developer']);
      await reveal(tester, find.text('bucm-campus-prototype'));
      await tester.tap(find.text('bucm-campus-prototype'));
      await tester.pumpAndSettle();
      expect(links, ['developer', 'repository']);
      expect(find.text('无法打开浏览器，可复制地址后访问'), findsOneWidget);
      await reveal(tester, find.byKey(const ValueKey('copy-repository')));
      await tester.tap(find.byKey(const ValueKey('copy-repository')));
      await tester.pumpAndSettle();
      expect(copied, repositoryUrl);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'small dark phone with large text keeps appearance and project pages usable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(MemoryRepository(const ScheduleData()), dark: true, scale: 1.5),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外观设置'));
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.byKey(const ValueKey('interface-scale-slider')),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('project-info-entry')));
      await tester.tap(find.text('项目信息'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('copy-repository')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
