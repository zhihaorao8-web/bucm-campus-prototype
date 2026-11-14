import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/ui/quiet_backdrop.dart';
import 'package:campus_schedule/ui/acrylic_surface.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/application/appearance_controller.dart';
import 'support/memory_appearance.dart';
import 'ui_test.dart' show app;
import 'schedule_test.dart' show MemoryRepository;
import 'week_grid_test.dart' show weeklyPreviewData;

void main() {
  for (final brightness in [Brightness.dark, Brightness.light]) {
    for (final tab in [1, 2]) {
      testWidgets(
        '${brightness.name} reading light fields reach the page body tab=$tab',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final boundary = GlobalKey();
          Future<List<int>> pixels(Size size, bool lights) async {
            tester.view.physicalSize = size;
            await tester.pumpWidget(
              ProviderScope(
                key: ValueKey(lights),
                overrides: [
                  currentAppearanceProvider.overrideWithValue(
                    AppearanceSettings(aurora: lights, paperTexture: false),
                  ),
                ],
                child: MaterialApp(
                  theme: appTheme(brightness),
                  home: RepaintBoundary(
                    key: boundary,
                    child: QuietBackdrop(tab: tab, child: const SizedBox()),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              tester.binding.transientCallbackCount,
              0,
              reason: 'Reading pages must remain static',
            );
            return (await tester.runAsync(() async {
              final render =
                  boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await render.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              final colors = <int>[];
              for (final point in [
                const Offset(.12, .15),
                const Offset(.88, .40),
                const Offset(.14, .66),
                const Offset(.80, .88),
              ]) {
                final offset =
                    ((point.dy * image.height).floor() * image.width +
                        (point.dx * image.width).floor()) *
                    4;
                colors.addAll(bytes!.buffer.asUint8List(offset, 3));
              }
              image.dispose();
              return colors;
            }))!;
          }

          for (final size in [const Size(390, 844), const Size(320, 720)]) {
            final lit = await pixels(size, true);
            final plain = await pixels(size, false);
            for (var i = 0; i < 4; i++) {
              final difference = List.generate(
                3,
                (c) => (lit[i * 3 + c] - plain[i * 3 + c]).abs(),
              ).reduce((a, b) => a + b);
              expect(
                difference,
                greaterThan(18),
                reason:
                    '${brightness.name} light field must remain visible at body sample $i, $size',
              );
            }
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'light today diffusion shows vivid color and clear motion across phases',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      Future<List<int>> samplePixels() async => (await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage();
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final colors = <int>[];
        for (final point in [
          const Offset(.22, .18),
          const Offset(.75, .36),
          const Offset(.28, .62),
          const Offset(.72, .80),
        ]) {
          final offset =
              ((point.dy * image.height).floor() * image.width +
                  (point.dx * image.width).floor()) *
              4;
          colors.addAll(bytes!.buffer.asUint8List(offset, 3));
        }
        image.dispose();
        return colors;
      }))!;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentAppearanceProvider.overrideWithValue(
              const AppearanceSettings(aurora: true, paperTexture: false),
            ),
          ],
          child: MaterialApp(
            theme: appTheme(Brightness.light),
            home: RepaintBoundary(
              key: boundary,
              child: const QuietBackdrop(tab: 0, child: SizedBox()),
            ),
          ),
        ),
      );
      await tester.pump();
      final t0 = await samplePixels();
      var maxChroma = 0;
      for (var i = 0; i < 4; i++) {
        final r = t0[i * 3], g = t0[i * 3 + 1], b = t0[i * 3 + 2];
        final chroma = [r, g, b].reduce((a, b) => a > b ? a : b) -
            [r, g, b].reduce((a, b) => a < b ? a : b);
        if (chroma > maxChroma) maxChroma = chroma;
        expect(
          chroma,
          greaterThan(20),
          reason: 'Light diffusion sample $i should stay tinted ($r,$g,$b)',
        );
      }
      expect(
        maxChroma,
        greaterThan(70),
        reason: 'Light diffusion should include vivid focal color zones',
      );
      await tester.pump(const Duration(milliseconds: 2250));
      final t3 = await samplePixels();
      await tester.pump(const Duration(milliseconds: 2250));
      final t6 = await samplePixels();
      int maxDelta(List<int> a, List<int> b) {
        var best = 0;
        for (var i = 0; i < 4; i++) {
          final d = List.generate(
            3,
            (c) => (a[i * 3 + c] - b[i * 3 + c]).abs(),
          ).reduce((x, y) => x + y);
          if (d > best) best = d;
        }
        return best;
      }

      expect(maxDelta(t0, t3), greaterThan(70));
      expect(maxDelta(t3, t6), greaterThan(70));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'ambient motion stops in background, hidden routes and reduced motion',
    (tester) async {
      Future<void> mount({
        bool reduced = false,
        bool visible = true,
        int tab = 0,
      }) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appearanceRepositoryProvider.overrideWithValue(
                MemoryAppearanceRepository(),
              ),
            ],
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: TickerMode(
                  enabled: visible,
                  child: QuietBackdrop(tab: tab, child: const SizedBox()),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await mount();
      await tester.pump(const Duration(seconds: 6));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await mount(visible: false);
      expect(tester.binding.transientCallbackCount, 0);
      await mount(reduced: true);
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.byKey(const ValueKey('aurora-0')), findsOneWidget);
      await mount(tab: 1);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final highContrast in [false, true]) {
    testWidgets(
      'focus surface preserves content and honors contrast=$highContrast',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appearanceRepositoryProvider.overrideWithValue(
                MemoryAppearanceRepository(),
              ),
            ],
            child: MaterialApp(
              theme: appTheme(Brightness.light),
              home: MediaQuery(
                data: MediaQueryData(highContrast: highContrast),
                child: const Scaffold(
                  body: AcrylicSurface(child: Text('课程名称与地点')),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('课程名称与地点'), findsOneWidget);
        expect(
          tester
              .widget<BackdropFilter>(
                find.byKey(const ValueKey('focus-acrylic-blur')),
              )
              .enabled,
          !highContrast,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final dark in [false, true]) {
    testWidgets(
      'main headers share blur and follow the active scroll dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(390, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          app(MemoryRepository(weeklyPreviewData(DateTime.now())), dark: dark),
        );
        await tester.pumpAndSettle();
        final radius = tester
            .widget<MiuixTopAppBar>(find.byKey(const ValueKey('topbar-0')))
            .blurRadius;
        for (final (index, page) in [
          (0, 'today-page'),
          (1, 'timetable-page'),
          (1, 'timetable-day-page'),
          (2, 'settings-page'),
        ]) {
          await tester.tap(find.byKey(ValueKey('tab-$index')));
          await tester.pumpAndSettle();
          if (page == 'timetable-day-page') {
            await tester.tap(find.text('日'));
            await tester.pumpAndSettle();
          }
          final header = find.byKey(ValueKey('topbar-$index'));
          final initial = tester.widget<MiuixTopAppBar>(header).blurTintAlpha;
          expect(initial, closeTo(.04, .001));
          expect(tester.widget<MiuixTopAppBar>(header).blurRadius, radius);
          expect(tester.widget<MiuixTopAppBar>(header).blurred, isTrue);
          await tester.drag(
            find.byKey(PageStorageKey(page)),
            const Offset(0, -240),
          );
          await tester.pumpAndSettle();
          expect(
            tester.widget<MiuixTopAppBar>(header).blurTintAlpha,
            greaterThan(initial),
          );
        }
        final container = ProviderScope.containerOf(
          tester.element(find.byType(QuietBackdrop)),
        );
        await container
            .read(appearanceProvider.notifier)
            .change((p) => p.copyWith(glass: false));
        for (final index in [0, 1, 2]) {
          await tester.tap(find.byKey(ValueKey('tab-$index')));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<MiuixTopAppBar>(find.byKey(ValueKey('topbar-$index')))
                .blurred,
            isFalse,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
