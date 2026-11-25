import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/design/app_palette.dart';
import 'package:campus_schedule/ui/quiet_backdrop.dart';
import 'package:campus_schedule/ui/acrylic_surface.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/domain/library_seats.dart';
import 'package:campus_schedule/platform/library_seat_reader.dart';
import 'support/memory_appearance.dart';
import 'ui_test.dart' show app;
import 'schedule_test.dart' show MemoryRepository;
import 'week_grid_test.dart' show weeklyPreviewData;

class _AtmosphereLibraryReader extends LibrarySeatReader {
  @override
  Future<List<LibraryArea>> areas() async => const [
    LibraryArea('32', '二层北区', '图书馆二层'),
    LibraryArea('33', '三层北区', '图书馆三层'),
    LibraryArea('34', '四层北区', '图书馆四层'),
    LibraryArea('35', '五层北区', '图书馆五层'),
    LibraryArea('36', '六层北区', '图书馆六层'),
    LibraryArea('37', '七层北区', '图书馆七层'),
    LibraryArea('38', '八层北区', '图书馆八层'),
  ];

  @override
  Future<List<LibrarySeat>> seats(String area, DateTime date) async => [
    for (var i = 1; i <= 12; i++)
      LibrarySeat(
        id: '$i',
        label: 'A${i.toString().padLeft(3, '0')}',
        open: true,
        viewOnly: false,
        hours: const [(510, 1320)],
        reservations: const [],
      ),
  ];

  @override
  Future<void> reset() async {}
}

void main() {
  for (final brightness in [Brightness.dark, Brightness.light]) {
    for (final tab in [1, 2, 3]) {
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
    'light today diffusion stays airy, luminous and clearly animated across phases',
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
        final minChannel = [r, g, b].reduce((a, b) => a < b ? a : b);
        final chroma = [r, g, b].reduce((a, b) => a > b ? a : b) - minChannel;
        if (chroma > maxChroma) maxChroma = chroma;
        expect(
          minChannel,
          greaterThan(175),
          reason: 'Airy light diffusion sample $i should stay high-key ($r,$g,$b)',
        );
        expect(
          chroma,
          greaterThan(6),
          reason: 'Airy light diffusion sample $i should stay gently tinted ($r,$g,$b)',
        );
      }
      expect(
        maxChroma,
        inInclusiveRange(22, 75),
        reason: 'Light diffusion should stay luminous without turning neon ($maxChroma)',
      );
      await tester.pump(const Duration(milliseconds: 2500));
      final t1 = await samplePixels();
      await tester.pump(const Duration(milliseconds: 2500));
      final t2 = await samplePixels();
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

      expect(maxDelta(t0, t1), greaterThan(28));
      expect(maxDelta(t1, t2), greaterThan(28));
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
          app(
            MemoryRepository(weeklyPreviewData(DateTime.now())),
            dark: dark,
            libraryReader: _AtmosphereLibraryReader(),
          ),
        );
        await tester.pumpAndSettle();
        final radius = tester
            .widget<MiuixTopAppBar>(find.byKey(const ValueKey('topbar-0')))
            .blurRadius;
        for (final (index, page) in [
          (0, 'today-page'),
          (1, 'timetable-page'),
          (1, 'timetable-day-page'),
          (2, 'library-tab-page'),
          (3, 'settings-page'),
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
        for (final index in [0, 1, 2, 3]) {
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

  test('backdrop sub-styles differ across pages and interpolate smoothly', () {
    for (final theme in [
      BackdropTheme.grainGradient,
      BackdropTheme.aurora,
      BackdropTheme.horizonGradient,
    ]) {
      for (final dark in [false, true]) {
        final specs = [
          for (var tab = 0; tab < 4; tab++)
            BackdropStyleSpec.forTab(theme, dark, tab),
        ];
        for (var i = 0; i < 3; i++) {
          expect(specs[i].colors, isNot(equals(specs[i + 1].colors)));
          final mid = BackdropStyleSpec.forPosition(theme, dark, i + 0.5);
          expect(mid.colors, isNot(equals(specs[i].colors)));
          expect(mid.colors, isNot(equals(specs[i + 1].colors)));
          for (var k = 0; k < specs[i].colors.length; k++) {
            final expected = Color.lerp(
              specs[i].colors[k],
              specs[i + 1].colors[k],
              0.5,
            )!;
            expect(mid.colors[k].toARGB32(), expected.toARGB32());
          }
        }
      }
    }
    final darkLab = BackdropStyleSpec.colorToOklab(const Color(0xFF070D14));
    final lightLab = BackdropStyleSpec.colorToOklab(const Color(0xFFFAFBFD));
    expect(lightLab.l, greaterThan(darkLab.l));
  });

  testWidgets(
    'shader themes load, differentiate pages, and respect policy fallbacks',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();

      Future<List<int>> sampleTheme({
        required BackdropTheme theme,
        required bool dark,
        required int tab,
        bool aurora = true,
        bool highContrast = false,
        bool reducedMotion = false,
        bool failLoad = false,
      }) async {
        final container = ProviderContainer(
          overrides: [
            ambientMotionEnabledProvider.overrideWithValue(!reducedMotion),
            currentAppearanceProvider.overrideWithValue(
              AppearanceSettings(
                aurora: aurora,
                paperTexture: false,
                contrast: highContrast ? 1 : 0,
              ),
            ),
            if (failLoad)
              backdropProgramProvider.overrideWith(
                (ref, _) => Future<ui.FragmentProgram>.error(
                  StateError('synthetic shader load failure'),
                ),
              ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: appTheme(dark ? Brightness.dark : Brightness.light),
              home: MediaQuery(
                data: MediaQueryData(
                  highContrast: highContrast,
                  disableAnimations: reducedMotion,
                ),
                child: RepaintBoundary(
                  key: boundary,
                  child: QuietBackdrop(
                    tab: tab,
                    theme: theme,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        );
        if (aurora && !highContrast && !failLoad) {
          await tester.runAsync(
            () => container.read(backdropProgramProvider(theme).future),
          );
        }
        await tester.pump();
        if (reducedMotion) {
          await tester.pumpAndSettle();
          expect(tester.binding.transientCallbackCount, 0);
        }
        expect(tester.takeException(), isNull);
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
            const Offset(.18, .16),
            const Offset(.82, .35),
            const Offset(.24, .65),
            const Offset(.76, .84),
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

      int totalDiff(List<int> a, List<int> b) => [
        for (var i = 0; i < a.length; i++) (a[i] - b[i]).abs(),
      ].reduce((x, y) => x + y);

      for (final theme in [
        BackdropTheme.grainGradient,
        BackdropTheme.aurora,
        BackdropTheme.horizonGradient,
      ]) {
        for (final dark in [false, true]) {
          final tab0 = await sampleTheme(
            theme: theme,
            dark: dark,
            tab: 0,
            reducedMotion: true,
          );
          final tab2 = await sampleTheme(
            theme: theme,
            dark: dark,
            tab: 2,
            reducedMotion: true,
          );
          final off = await sampleTheme(
            theme: theme,
            dark: dark,
            tab: 0,
            aurora: false,
            reducedMotion: true,
          );
          expect(
            totalDiff(tab0, off),
            greaterThan(16),
            reason: '$theme dark=$dark must visibly render over plain surface',
          );
          expect(
            totalDiff(tab0, tab2),
            greaterThan(12),
            reason: '$theme dark=$dark tab=0 and tab=2 must differ visually',
          );
        }
        final contrastPixels = await sampleTheme(
          theme: theme,
          dark: false,
          tab: 0,
          highContrast: true,
          reducedMotion: true,
        );
        final plainPixels = await sampleTheme(
          theme: theme,
          dark: false,
          tab: 0,
          aurora: false,
          reducedMotion: true,
        );
        expect(totalDiff(contrastPixels, plainPixels), 0);

        final fallbackPixels = await sampleTheme(
          theme: theme,
          dark: false,
          tab: 0,
          failLoad: true,
          reducedMotion: true,
        );
        expect(fallbackPixels.length, 12);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'cross-page position smoothly interpolates backdrop colors and AppShell shares one backdrop',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      final position = ValueNotifier<double>(0.0);
      addTearDown(position.dispose);

      for (final theme in [
        BackdropTheme.diffusion,
        BackdropTheme.grainGradient,
      ]) {
        position.value = 0.0;
        final container = ProviderContainer(
          overrides: [
            ambientMotionEnabledProvider.overrideWithValue(false),
            currentAppearanceProvider.overrideWithValue(
              const AppearanceSettings(aurora: true, paperTexture: false),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: appTheme(Brightness.light),
              home: RepaintBoundary(
                key: boundary,
                child: QuietBackdrop(
                  tab: 0,
                  theme: theme,
                  positionListenable: position,
                  positionResolver: () => position.value,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        );
        if (theme != BackdropTheme.diffusion) {
          await tester.runAsync(
            () => container.read(backdropProgramProvider(theme).future),
          );
        }
        await tester.pump();

        Future<List<int>> sampleAt(double pos) async {
          position.value = pos;
          await tester.pump();
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
              const Offset(.20, .20),
              const Offset(.80, .35),
              const Offset(.22, .72),
              const Offset(.78, .82),
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

        final p0 = await sampleAt(0.0);
        final pMid = await sampleAt(0.5);
        final p1 = await sampleAt(1.0);
        int diff(List<int> a, List<int> b) => [
          for (var i = 0; i < a.length; i++) (a[i] - b[i]).abs(),
        ].reduce((x, y) => x + y);

        expect(diff(p0, pMid), greaterThan(0));
        expect(diff(pMid, p1), greaterThan(0));
        expect(diff(p0, p1), greaterThan(0));
      }

      await tester.pumpWidget(
        app(
          MemoryRepository(weeklyPreviewData(DateTime.now())),
          libraryReader: _AtmosphereLibraryReader(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QuietBackdrop), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tab-2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(QuietBackdrop), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'QuietBackdrop follows currentAppearanceProvider backdropTheme when no explicit override is passed',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();

      Future<List<int>> sample(BackdropTheme theme) async {
        final container = ProviderContainer(
          overrides: [
            ambientMotionEnabledProvider.overrideWithValue(false),
            currentAppearanceProvider.overrideWithValue(
              AppearanceSettings(
                aurora: true,
                backdropTheme: theme,
                paperTexture: false,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: appTheme(Brightness.light),
              home: RepaintBoundary(
                key: boundary,
                child: const QuietBackdrop(tab: 0, child: SizedBox.expand()),
              ),
            ),
          ),
        );
        if (theme != BackdropTheme.diffusion) {
          await tester.runAsync(
            () => container.read(backdropProgramProvider(theme).future),
          );
        }
        await tester.pump();
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
            const Offset(.18, .12),
            const Offset(.82, .25),
            const Offset(.24, .65),
            const Offset(.76, .84),
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

      final diffusionPixels = await sample(BackdropTheme.diffusion);
      final horizonPixels = await sample(BackdropTheme.horizonGradient);
      final diff = [
        for (var i = 0; i < diffusionPixels.length; i++)
          (diffusionPixels[i] - horizonPixels[i]).abs(),
      ].reduce((a, b) => a + b);
      expect(diff, greaterThan(16));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
