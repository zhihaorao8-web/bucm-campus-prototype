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
      await tester.pumpAndSettle();
    }

    Future<void> capture(String name) async {
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
    await setup(dark: true);
    await tester.tap(find.text('先体验合成示例'));
    await tester.pumpAndSettle();
    await capture('dark');
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
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, skip: !const bool.fromEnvironment('CAPTURE_PREVIEW'));
}
