import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/application/schedule_controller.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/ui/app_shell.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/ui/glass_navigation.dart';
import 'schedule_test.dart' show MemoryRepository, sample;
import 'support/memory_appearance.dart';
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/platform/app_platform.dart';

Widget app(
  MemoryRepository repo, {
  bool dark = false,
  double scale = 1,
  bool highContrast = false,
  bool reduceMotion = false,
}) => ProviderScope(
  overrides: [
    repositoryProvider.overrideWithValue(repo),
    appearanceRepositoryProvider.overrideWithValue(
      MemoryAppearanceRepository(),
    ),
    appInfoProvider.overrideWith(
      (ref) async => const AppPlatformInfo(
        version: 'test',
        build: '7',
        sdk: 36,
        systemAccent: 0xff00897b,
      ),
    ),
  ],
  child: MaterialApp(
    theme: appTheme(dark ? Brightness.dark : Brightness.light),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        highContrast: highContrast,
        disableAnimations: reduceMotion,
      ),
      child: MiuixThemeBridge(child: child!),
    ),
    home: const AppShell(),
  ),
);

void main() {
  testWidgets(
    'switching tabs preserves each page position without transferring scroll offset',
    (tester) async {
      tester.view.physicalSize = const Size(390, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(MemoryRepository(ScheduleData(courses: [sample()])), scale: 1.5),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-1')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const PageStorageKey('timetable-page')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ScrollView>(
              find.byKey(const PageStorageKey('timetable-page')),
            )
            .controller!
            .offset,
        greaterThan(100),
      );
      await tester.tap(find.byKey(const ValueKey('tab-2')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ListView>(find.byKey(const PageStorageKey('settings-page')))
            .controller!
            .offset,
        0,
      );
      await tester.tap(find.byKey(const ValueKey('tab-1')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ScrollView>(
              find.byKey(const PageStorageKey('timetable-page')),
            )
            .controller!
            .offset,
        greaterThan(100),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'high contrast uses opaque dock and reduced motion keeps tabs operable',
    (tester) async {
      await tester.pumpWidget(
        app(
          MemoryRepository(const ScheduleData()),
          highContrast: true,
          reduceMotion: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BackdropFilter>(find.byKey(const ValueKey('dock-blur')))
            .enabled,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('tab-2')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('tab-2')))
            .properties
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'floating glass dock has real blur, safe hit targets and reachable page end',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(MemoryRepository(const ScheduleData())));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsAtLeastNWidgets(2));
      final dock = tester.getRect(find.byKey(const ValueKey('dock-blur')));
      expect(dock.left, greaterThan(0));
      expect(dock.right, lessThan(390));
      expect(dock.bottom, lessThanOrEqualTo(832));
      for (var i = 0; i < 3; i++) {
        final bounds = tester.getSize(find.byKey(ValueKey('tab-$i')));
        expect(bounds.width, greaterThanOrEqualTo(48));
        expect(bounds.height, greaterThanOrEqualTo(48));
      }
      await tester.tap(find.byKey(const ValueKey('tab-2')));
      await tester.pumpAndSettle();
      final selected = tester.widget<Semantics>(
        find.byKey(const ValueKey('tab-2')),
      );
      expect(selected.properties.selected, isTrue);
      final footer = find.text('项目信息');
      await tester.scrollUntilVisible(
        footer,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('settings-page')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(footer);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(footer).bottom,
        lessThan(tester.getRect(find.byKey(const ValueKey('dock-blur'))).top),
      );
      expect(find.byType(GlassNavigation), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'empty, preview, navigation, course details and restore ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = MemoryRepository(const ScheduleData());
        await tester.pumpWidget(app(repo, dark: dark));
        await tester.pumpAndSettle();
        expect(find.text('从学校导入课表'), findsOneWidget);
        await tester.tap(find.text('先体验合成示例'));
        await tester.pumpAndSettle();
        expect(find.textContaining('合成示例，仅用于体验'), findsOneWidget);
        expect(repo.value.courses, isEmpty);
        await tester.tap(find.text('课表').last);
        await tester.pumpAndSettle();
        expect(find.textContaining('第 10 周'), findsOneWidget);
        await tester.tap(find.text('日'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('示例课程：中医基础').first);
        await tester.pumpAndSettle();
        expect(find.text('示例教师'), findsOneWidget);
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('退出示例'));
        await tester.pumpAndSettle();
        expect(find.text('从学校导入课表'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('small phone and large system text keep navigation usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(MemoryRepository(const ScheduleData()), scale: 1.5),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('先体验合成示例'));
    await tester.tap(find.text('先体验合成示例'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课表').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
