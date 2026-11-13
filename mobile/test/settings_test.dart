import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/main.dart';
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/application/schedule_controller.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/platform/app_platform.dart';
import 'package:campus_schedule/platform/school_adapter.dart';
import 'package:campus_schedule/ui/project_info_page.dart';
import 'schedule_test.dart' show MemoryRepository, sample;
import 'support/memory_appearance.dart';
import 'ui_test.dart' show app;

Future<void> reveal(WidgetTester tester, Finder target) async {
  final list = find.byType(ListView).last;
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
      await tester.tap(find.byKey(const ValueKey('tab-2')));
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
      // File cleanup spans multiple IO completions outside the fake test clock.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }
      expect(sessionClears, 1);
      expect(repo.value.courses.length, 1);
      await reveal(tester, find.text('清空本地课表'));
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
      await tester.tap(find.byKey(const ValueKey('tab-2')));
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
      await tester.tap(find.byKey(const ValueKey('tab-2')));
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
