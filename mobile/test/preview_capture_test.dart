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
    }) async {
      await tester.pumpWidget(const SizedBox());
      tester.view.physicalSize = Size(width, 844);
      final theme = appTheme(dark ? Brightness.dark : Brightness.light);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ProviderScope(
            overrides: [
              ambientMotionEnabledProvider.overrideWithValue(ambient),
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
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
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
    await tester.tap(find.text('日'));
    await tester.pumpAndSettle();
    await capture('daily-large-text');
    // Navigation captures freeze only ambient light, retaining real UI motion.
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
  }, skip: !const bool.fromEnvironment('CAPTURE_PREVIEW'));
}
