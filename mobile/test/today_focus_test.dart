import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/design/app_tokens.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/ui/acrylic_surface.dart';
import 'package:campus_schedule/ui/liquid_glass_surface.dart';
import 'package:campus_schedule/ui/quiet_backdrop.dart';
import 'package:campus_schedule/ui/today_focus.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/application/appearance_controller.dart';
import 'support/memory_appearance.dart';
import 'schedule_test.dart' show sample;

final date = DateTime(2026, 11, 13);
Occurrence event(String start, String end, [String id = 'a']) => Occurrence(
  Course.fromJson({...sample().toJson(), 'id': id}),
  TeachingSegment(start, end),
  date,
);
Widget frame(Widget child, {bool large = false}) => ProviderScope(
  overrides: [
    appearanceRepositoryProvider.overrideWithValue(
      MemoryAppearanceRepository(),
    ),
  ],
  child: MaterialApp(
    theme: appTheme(large ? Brightness.dark : Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: true,
        textScaler: TextScaler.linear(large ? 1.5 : 1),
      ),
      child: MiuixThemeBridge(child: child!),
    ),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);
void main() {
  test('progress and remaining time respect exact segment endpoints', () {
    final lesson = event('13:30', '15:00');
    expect(lessonProgress(lesson, DateTime(2026, 11, 13, 13)), 0);
    expect(lessonProgress(lesson, DateTime(2026, 11, 13, 14, 15)), .5);
    expect(lessonProgress(lesson, DateTime(2026, 11, 13, 15, 1)), 1);
    expect(remainingMinutes(lesson.end, DateTime(2026, 11, 13, 14, 59, 59)), 1);
    expect(remainingMinutes(lesson.end, lesson.end), 0);
    expect(lesson.activeAt(lesson.end), isFalse);
    expect(lessonGaps([event('10:30', '12:00'), event('13:30', '15:00')]), [
      (DateTime(2026, 11, 13, 12), DateTime(2026, 11, 13, 13, 30)),
    ]);
  });
  test(
    'breaks use union coverage for chained overlaps and touching lessons',
    () {
      expect(
        lessonGaps([
          event('08:30', '12:00'),
          event('09:00', '10:00'),
          event('11:00', '12:00'),
          event('12:00', '13:00'),
        ]),
        isEmpty,
      );
    },
  );
  for (final large in [false, true]) {
    testWidgets(
      'focus and timeline states remain usable ${large ? 'small dark large' : 'light'}',
      (tester) async {
        tester.view.physicalSize = Size(large ? 320 : 390, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final lesson = event('13:30', '15:00');
        final now = DateTime(2026, 11, 13, 14, 15);
        await tester.pumpWidget(
          frame(
            Column(
              children: [
                FocusCourseCard(event: lesson, now: now, overlaps: 2),
                TodayCourseTimeline(
                  events: [
                    event('10:30', '12:00', 'past'),
                    lesson,
                    event('18:00', '20:25', 'future'),
                  ],
                  now: now,
                  hasRecordings: (_) => false,
                ),
              ],
            ),
            large: large,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('剩 45 分钟'), findsOneWidget);
        expect(find.text('有2门课程重叠'), findsOneWidget);
        expect(
          tester
              .widget<WavyProgressIndicator>(
                find.byKey(const ValueKey('today-lesson-progress')),
              )
              .value,
          .5,
        );
        for (final value in [
          'past-10:30-已结束',
          'a-13:30-进行中',
          'future-18:00-未开始',
        ]) {
          expect(find.byKey(ValueKey('timeline-$value')), findsOneWidget);
        }
        expect(find.text('午休 · 12:00–13:30'), findsOneWidget);
        await tester.pumpWidget(
          frame(
            FocusCourseCard(event: lesson, now: DateTime(2026, 11, 13, 13)),
            large: large,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('下一节课'), findsOneWidget);
        expect(find.text('30 分钟后开始'), findsOneWidget);
        expect(find.byType(WavyProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'focus card enables restrained liquid glass optics with natural height in ListView across light/dark and 320dp 2.0x',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final lesson = event('13:30', '15:00');
      final now = DateTime(2026, 11, 13, 14, 15);
      for (final dark in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                currentAppearanceProvider.overrideWithValue(
                  const AppearanceSettings(),
                ),
              ],
              child: MaterialApp(
                theme: appTheme(dark ? Brightness.dark : Brightness.light),
                builder: (context, child) => MediaQuery(
                  data: MediaQueryData(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: MiuixThemeBridge(child: child!),
                ),
                home: Scaffold(
                  body: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      FocusCourseCard(event: lesson, now: now, overlaps: 2),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final surfaceFinder = find.byType(LiquidGlassSurface);
          expect(surfaceFinder, findsOneWidget);
          final surface = tester.widget<LiquidGlassSurface>(surfaceFinder);
          expect(surface.radius, AppRadius.focus);
          expect(surface.blur, AppSurface.focusBlur);
          expect(surface.edgeDepth, AppLiquidGlass.focusEdgeDepth);
          expect(surface.refraction, AppLiquidGlass.focusRefraction);
          expect(surface.blurKey, const ValueKey('focus-acrylic-blur'));

          final acrylicSize = tester.getSize(find.byType(AcrylicSurface));
          final surfaceSize = tester.getSize(surfaceFinder);
          expect(surfaceSize.width, closeTo(288, .1));
          expect(surfaceSize.height.isFinite, isTrue);
          expect(surfaceSize.height, greaterThan(100));
          expect(surfaceSize.height, closeTo(acrylicSize.height, .1));

          final blurFinder = find.byKey(const ValueKey('focus-acrylic-blur'));
          expect(find.byType(BackdropFilter), findsOneWidget);
          expect(blurFinder, findsOneWidget);
          expect(tester.widget<BackdropFilter>(blurFinder).enabled, isTrue);

          expect(find.text(lesson.course.name), findsOneWidget);
          expect(
            find.descendant(
              of: surfaceFinder,
              matching: find.text(lesson.course.name),
            ),
            findsNothing,
          );
          expect(
            find.descendant(
              of: blurFinder,
              matching: find.text(lesson.course.name),
            ),
            findsNothing,
          );

          final gesture = await tester.startGesture(
            tester.getCenter(find.byKey(const ValueKey('today-focus'))),
          );
          await tester.pump();
          await gesture.cancel();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'focus card unmounts liquid glass and degrades cleanly under glass/blur/contrast overrides',
    (tester) async {
      final lesson = event('13:30', '15:00');
      final now = DateTime(2026, 11, 13, 14, 15);
      for (final mode in [
        'glass-off',
        'blur-off',
        'app-contrast',
        'system-contrast',
      ]) {
        final settings = AppearanceSettings(
          glass: mode != 'glass-off',
          blur: mode != 'blur-off',
          contrast: mode == 'app-contrast' ? .5 : 0,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [currentAppearanceProvider.overrideWithValue(settings)],
            child: MaterialApp(
              theme: appTheme(Brightness.light),
              builder: (context, child) => MediaQuery(
                data: MediaQueryData(
                  highContrast: mode == 'system-contrast',
                  disableAnimations: true,
                ),
                child: MiuixThemeBridge(child: child!),
              ),
              home: Scaffold(
                body: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [FocusCourseCard(event: lesson, now: now)],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(LiquidGlassSurface), findsNothing, reason: mode);
        final blurFinder = find.byKey(const ValueKey('focus-acrylic-blur'));
        expect(find.byType(BackdropFilter), findsOneWidget, reason: mode);
        expect(blurFinder, findsOneWidget, reason: mode);
        expect(
          tester.widget<BackdropFilter>(blurFinder).enabled,
          isFalse,
          reason: mode,
        );
        expect(find.text(lesson.course.name), findsOneWidget, reason: mode);
        expect(tester.takeException(), isNull, reason: mode);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'wavy lesson progress animates smoothly in foreground and stops under reduced motion, hidden route, background, and boundary values',
    (tester) async {
      Future<void> mountWave({
        required double value,
        bool dark = false,
        bool highContrast = false,
        bool reduced = false,
        bool visible = true,
        bool ambientEnabled = true,
      }) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ambientMotionEnabledProvider.overrideWithValue(ambientEnabled),
              appearanceRepositoryProvider.overrideWithValue(
                MemoryAppearanceRepository(),
              ),
            ],
            child: MaterialApp(
              theme: appTheme(dark ? Brightness.dark : Brightness.light),
              themeAnimationDuration: Duration.zero,
              home: MediaQuery(
                data: MediaQueryData(
                  disableAnimations: reduced,
                  highContrast: highContrast,
                ),
                child: TickerMode(
                  enabled: visible,
                  child: Scaffold(
                    body: Padding(
                      padding: const EdgeInsets.all(16),
                      child: WavyProgressIndicator(
                        key: const ValueKey('test-wavy-progress'),
                        value: value,
                        semanticsLabel: '当前授课分段进度',
                        semanticsValue: '${(value * 100).round()}%',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        if (reduced || !visible || !ambientEnabled) {
          await tester.pumpAndSettle();
        } else {
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        }
      }

      for (final dark in [false, true]) {
        for (final highContrast in [false, true]) {
          for (final value in [0.0, 0.5, 1.0]) {
            await mountWave(
              value: value,
              dark: dark,
              highContrast: highContrast,
              reduced: true,
            );
            expect(find.byType(WavyProgressIndicator), findsOneWidget);
            expect(tester.binding.transientCallbackCount, 0);
            expect(tester.takeException(), isNull);
          }
        }
      }

      await tester.pumpWidget(const SizedBox());
      await mountWave(value: 0.5);
      final semantics = tester.getSemantics(
        find.byKey(const ValueKey('test-wavy-progress')),
      );
      expect(semantics.label, '当前授课分段进度');
      expect(semantics.value, '50%');
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      await mountWave(value: 0.5, visible: false);
      expect(tester.binding.transientCallbackCount, 0);

      await mountWave(value: 0.5, reduced: true);
      expect(find.byType(WavyProgressIndicator), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);

      await mountWave(value: 0.5, ambientEnabled: false);
      expect(tester.binding.transientCallbackCount, 0);

      await tester.pumpWidget(const SizedBox());
    },
  );
}
