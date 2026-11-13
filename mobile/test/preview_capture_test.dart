import 'package:campus_schedule/ui/quiet_backdrop.dart';
// Optional visual QA using synthetic data only. Not a school screenshot capture.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/application/schedule_controller.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/ui/app_shell.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'schedule_test.dart' show MemoryRepository;
import 'week_grid_test.dart' show weeklyPreviewData;
import 'support/memory_appearance.dart';
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/platform/app_platform.dart';

void main() {
  const captureEnabled =
      bool.fromEnvironment('CAPTURE_PREVIEW') ||
      bool.fromEnvironment('CAPTURE_REVIEW_FIX') ||
      bool.fromEnvironment('CAPTURE_NAVIGATION_FIX');
  testWidgets('capture synthetic UI previews', (tester) async {
    const fontPath = String.fromEnvironment(
      'PREVIEW_FONT',
      defaultValue: 'C:/Windows/Fonts/msyh.ttc',
    );
    await tester.runAsync(() async {
      final bytes = await File(fontPath).readAsBytes();
      final loader = FontLoader('PreviewChinese')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      final icons = await File(
        '../build/toolchain/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(icons)))).load();
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    Future<void> setup({
      bool dark = false,
      bool ambient = false,
      double scale = 1,
      double width = 390,
      ScheduleData? data,
      AppearanceSettings? settings,
      bool highContrast = false,
      bool reducedMotion = false,
    }) async {
      await tester.pumpWidget(const SizedBox());
      tester.view.physicalSize = Size(width, 844);
      final theme = appTheme(
        dark ? Brightness.dark : Brightness.light,
        settings: settings ?? const AppearanceSettings(),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ProviderScope(
            overrides: [
              ambientMotionEnabledProvider.overrideWithValue(ambient),
              if (settings != null)
                currentAppearanceProvider.overrideWithValue(settings),
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
              repositoryProvider.overrideWithValue(
                MemoryRepository(data ?? const ScheduleData()),
              ),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'PreviewChinese'),
              ),
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  highContrast: highContrast,
                  disableAnimations: reducedMotion,
                ),
                child: MiuixThemeBridge(child: child!),
              ),
              home: const AppShell(),
            ),
          ),
        ),
      );
      if (ambient) {
        await tester.pump(const Duration(milliseconds: 500));
      } else {
        await tester.pumpAndSettle();
      }
    }

    Future<void> capture(String name) async {
      expect(
        find.byType(Icon),
        findsNothing,
        reason: 'Legacy font icons remain in the $name application preview',
      );
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      await tester.runAsync(() async {
        for (final image in images) {
          await precacheImage(image.image, boundary.currentContext!);
        }
      });
      await tester.pump();
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('../dist/flutter-preview/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    Future<void> sampleTransition(
      String name,
      Future<void> Function() action,
    ) async {
      await capture('$name-00');
      await action();
      await tester.pump();
      for (var frame = 1; frame <= 14; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        await capture('$name-${frame.toString().padLeft(2, '0')}');
      }
      await tester.pumpAndSettle();
    }

    if (const bool.fromEnvironment('CAPTURE_NAVIGATION_FIX')) {
      for (final dark in [false, true]) {
        final label = dark ? 'dark' : 'light';
        await setup(dark: dark, data: weeklyPreviewData(schoolNow()));
        await tester.drag(
          find.byKey(const PageStorageKey('today-page')),
          const Offset(0, -220),
        );
        await tester.pumpAndSettle();
        await sampleTransition(
          'navfix-$label-adjacent',
          () => tester.tap(find.byKey(const ValueKey('tab-1'))),
        );
        await tester.tap(find.byKey(const ValueKey('tab-0')));
        await tester.pumpAndSettle();
        await sampleTransition(
          'navfix-$label-direct',
          () => tester.tap(find.byKey(const ValueKey('tab-2'))),
        );
        await tester.tap(find.byKey(const ValueKey('tab-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('日'));
        await tester.pumpAndSettle();
        await capture('navfix-$label-date-controls');
      }
      await setup(
        dark: true,
        width: 320,
        scale: 1.5,
        data: weeklyPreviewData(schoolNow()),
      );
      await tester.tap(find.byKey(const ValueKey('tab-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('日'));
      await tester.pumpAndSettle();
      await capture('navfix-dark-large-date-controls');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      return;
    }
    if (const bool.fromEnvironment('CAPTURE_REVIEW_FIX')) {
      for (final dark in [false, true]) {
        for (final large in [false, true]) {
          final name =
              'review-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}';
          await setup(
            dark: dark,
            width: large ? 320 : 390,
            scale: large ? 1.5 : 1,
            data: weeklyPreviewData(schoolNow()),
          );
          await tester.tap(find.byKey(const ValueKey('tab-1')));
          await tester.pumpAndSettle();
          await capture('$name-week');
          await tester.drag(
            find.byKey(const PageStorageKey('timetable-page')),
            const Offset(0, -170),
          );
          await tester.pumpAndSettle();
          await capture('$name-week-scrolled');
          await tester.tap(find.text('日'));
          await tester.pumpAndSettle();
          await capture('$name-day');
          await tester.tap(find.byKey(const ValueKey('tab-2')));
          await tester.pumpAndSettle();
          await capture('$name-settings');
          await tester.tap(find.text('外观设置'));
          await tester.pumpAndSettle();
          await capture('$name-appearance');
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox());
      return;
    }
    await setup();
    await capture('empty');
    await tester.tap(find.text('先体验合成示例'));
    await tester.pumpAndSettle();
    await capture('today');
    await tester.tap(find.text('课表').last);
    await tester.pumpAndSettle();
    await capture('week');
    await tester.drag(
      find.byKey(const PageStorageKey('timetable-page')),
      const Offset(0, -360),
    );
    await tester.pumpAndSettle();
    await capture('week-scrolled');
    await tester.tap(find.byKey(const ValueKey('tab-2')));
    await tester.pumpAndSettle();
    await capture('settings');
    final about = find.byKey(const ValueKey('project-info-entry'));
    await tester.scrollUntilVisible(
      about,
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const PageStorageKey('settings-page')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(tester.element(about), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(find.text('项目信息'));
    await tester.pumpAndSettle();
    await capture('project-info');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('外观设置')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('外观设置'));
    await tester.pumpAndSettle();
    await capture('appearance');
    final effects = find.byKey(const ValueKey('appearance-模糊'));
    await tester.scrollUntilVisible(
      effects,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('settings-route-外观设置')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(tester.element(effects), alignment: .3);
    await tester.pumpAndSettle();
    await capture('appearance-effects');
    await setup(dark: true);
    await tester.tap(find.text('先体验合成示例'));
    await tester.pumpAndSettle();
    await capture('dark');
    await tester.tap(find.byKey(const ValueKey('tab-2')));
    await tester.pumpAndSettle();
    final darkAbout = find.byKey(const ValueKey('project-info-entry'));
    await tester.scrollUntilVisible(
      darkAbout,
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const PageStorageKey('settings-page')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(tester.element(darkAbout), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(find.text('项目信息'));
    await tester.pumpAndSettle();
    await capture('project-info-dark');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('外观设置')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('外观设置'));
    await tester.pumpAndSettle();
    await capture('appearance-dark');
    await setup(scale: 1.5, width: 320);
    await tester.ensureVisible(find.text('先体验合成示例'));
    await tester.tap(find.text('先体验合成示例'));
    await tester.pumpAndSettle();
    await capture('large-text');
    for (final dark in [false, true]) {
      await setup(dark: dark, data: weeklyPreviewData(schoolNow()));
      await tester.tap(find.byKey(const ValueKey('tab-1')));
      await tester.pumpAndSettle();
      await capture(dark ? 'week-overview-dark' : 'week-overview');
      final conflict = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.key.toString().contains('week-stack-'),
      );
      await tester.tap(conflict);
      await tester.pumpAndSettle();
      await capture(dark ? 'conflict-drawer-dark' : 'conflict-drawer-light');
      await tester.tap(find.byTooltip('关闭重叠课程'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('日'));
      await tester.pumpAndSettle();
      await capture(dark ? 'daily-dark' : 'daily');
    }
    await setup(scale: 1.5, width: 320, data: weeklyPreviewData(schoolNow()));
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pumpAndSettle();
    await capture('week-overview-large-text');
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.key.toString().contains('week-stack-'),
      ),
    );
    await tester.pumpAndSettle();
    await capture('conflict-drawer-large-text');
    await tester.tap(find.byTooltip('关闭重叠课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日'));
    await tester.pumpAndSettle();
    await capture('daily-large-text');
    for (final variant in ['light', 'dark', 'large']) {
      await setup(
        dark: variant == 'dark',
        width: variant == 'large' ? 320 : 390,
        scale: variant == 'large' ? 1.5 : 1,
      );
      await tester.tap(find.text('先体验合成示例'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('today-focus')));
      await tester.pumpAndSettle();
      await capture('stage4-course-$variant');
      await tester.tap(find.text('课程信息'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('查看完整课程信息'));
      await tester.tap(find.text('查看完整课程信息'));
      await tester.pumpAndSettle();
      await capture('stage4-information-$variant');
      await tester.ensureVisible(find.text('完成').last);
      await tester.tap(find.text('完成').last);
      await tester.pumpAndSettle();
      expect(find.text('课程课堂'), findsOneWidget);
    }
    for (final variant in ['large', 'no-glass', 'contrast', 'reduced']) {
      await setup(
        dark: variant != 'large',
        width: 320,
        scale: 1.5,
        settings: AppearanceSettings(glass: variant != 'no-glass'),
        highContrast: variant == 'contrast',
        reducedMotion: variant == 'reduced',
      );
      await tester.tap(find.byKey(const ValueKey('tab-2')));
      await tester.pumpAndSettle();
      await capture('stage4-settings-$variant');
      await tester.tap(find.text('外观设置'));
      await tester.pumpAndSettle();
      await capture('stage4-appearance-$variant');
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-0')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('先体验合成示例'));
      await tester.tap(find.text('先体验合成示例'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('today-focus')));
      await tester.pumpAndSettle();
      await capture('stage4-course-$variant');
      await tester.tap(find.text('课程信息'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('查看完整课程信息'));
      await tester.tap(find.text('查看完整课程信息'));
      await tester.pumpAndSettle();
      await capture('stage4-information-$variant');
      await tester.ensureVisible(find.text('完成').last);
      await tester.tap(find.text('完成').last);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await setup(
        dark: variant != 'large',
        width: 320,
        scale: 1.5,
        data: weeklyPreviewData(schoolNow()),
        settings: AppearanceSettings(glass: variant != 'no-glass'),
        highContrast: variant == 'contrast',
        reducedMotion: variant == 'reduced',
      );
      await tester.tap(find.byKey(const ValueKey('tab-1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.key.toString().contains('week-stack-'),
        ),
      );
      await tester.pumpAndSettle();
      await capture('stage4-conflict-$variant');
      await tester.tap(find.byTooltip('关闭重叠课程'));
      await tester.pumpAndSettle();
    }
    // Navigation captures freeze only ambient light, retaining real UI motion.
    await setup(data: weeklyPreviewData(schoolNow()));
    await sampleTransition(
      'navigation-transition',
      () => tester.tap(find.byKey(const ValueKey('tab-1'))),
    );
    await sampleTransition('mode-transition', () => tester.tap(find.text('日')));
    await tester.tap(find.text('周'));
    await tester.pumpAndSettle();
    await sampleTransition(
      'week-transition',
      () => tester.tap(find.byTooltip('下一周')),
    );
    await setup();
    await tester.tap(find.text('先体验合成示例'));
    await tester.pumpAndSettle();
    await capture('course-press-00');
    final contact = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('today-focus'))),
    );
    await tester.pump();
    for (var frame = 1; frame <= 8; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      await capture('course-press-${frame.toString().padLeft(2, '0')}');
    }
    await contact.cancel();
    await tester.pump();
    for (var frame = 9; frame <= 24; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      await capture('course-press-${frame.toString().padLeft(2, '0')}');
    }
    await tester.pumpAndSettle();
    await sampleTransition(
      'course-open',
      () => tester.tap(find.byKey(const ValueKey('today-focus'))),
    );
    await sampleTransition('course-return', () async {
      Navigator.of(tester.element(find.text('课程课堂'))).pop();
    });
    // Capture real widget motion at fixed phases, not an image-editor effect.
    for (final dark in [false, true]) {
      await setup(ambient: true, dark: dark);
      await tester.tap(find.text('先体验合成示例'));
      await tester.pump(const Duration(milliseconds: 500));
      for (var frame = 0; frame < 12; frame++) {
        final prefix = dark ? 'dark-atmosphere' : 'atmosphere';
        await capture('$prefix-motion-${frame.toString().padLeft(2, '0')}');
        await tester.pump(const Duration(seconds: 2));
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, skip: !captureEnabled);
}
