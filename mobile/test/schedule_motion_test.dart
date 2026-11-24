import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/design/app_tokens.dart';
import 'package:campus_schedule/ui/app_controls.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/ui/liquid_glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/ui/week_navigation.dart';
import 'package:campus_schedule/ui/week_grid.dart';
import 'ui_test.dart' show app;
import 'schedule_test.dart' show MemoryRepository;
import 'week_grid_test.dart' show weeklyPreviewData;

void main() {
  Future<void> mount(WidgetTester tester, {bool reduced = false}) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        MemoryRepository(weeklyPreviewData(DateTime.now())),
        scale: 1.5,
        reduceMotion: reduced,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'mode changes retain independent weekly and daily scroll positions under rapid reversal',
    (tester) async {
      await mount(tester);
      final changeMode = tester
          .widget<ScheduleModeSwitch>(find.byType(ScheduleModeSwitch))
          .onChanged;
      final weekly = find.byKey(const PageStorageKey('timetable-page'));
      await tester.drag(weekly, const Offset(0, -180));
      await tester.pumpAndSettle();
      final weeklyOffset = tester.widget<ScrollView>(weekly).controller!.offset;
      expect(weeklyOffset, greaterThan(0));
      // Invoke the same control callback without scrolling the header back to top.
      changeMode(true);
      await tester.pumpAndSettle();
      final daily = find.byKey(const PageStorageKey('timetable-day-page'));
      expect(tester.widget<ScrollView>(daily).controller!.offset, 0);
      await tester.drag(daily, const Offset(0, -120));
      await tester.pumpAndSettle();
      final dailyOffset = tester.widget<ScrollView>(daily).controller!.offset;
      changeMode(false);
      await tester.pump(const Duration(milliseconds: 60));
      // Reversing before the outgoing mode finishes must not duplicate controllers.
      changeMode(true);
      await tester.pumpAndSettle();
      expect(tester.widget<ScrollView>(daily).controller!.offset, dailyOffset);
      changeMode(false);
      await tester.pumpAndSettle();
      expect(
        tester.widget<ScrollView>(weekly).controller!.offset,
        weeklyOffset,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final reduced in [false, true]) {
    testWidgets(
      'week changes end on latest date and mode honors reduced motion=$reduced',
      (tester) async {
        await mount(tester, reduced: reduced);
        final monday = tester.widget<WeekGrid>(find.byType(WeekGrid)).monday;
        await tester.tap(find.byTooltip('下一周'));
        await tester.pump(const Duration(milliseconds: 35));
        await tester.tap(find.byTooltip('下一周'));
        await tester.pump(const Duration(milliseconds: 35));
        await tester.tap(find.byTooltip('上一周'));
        await tester.pumpAndSettle();
        expect(find.byType(WeekGrid), findsOneWidget);
        expect(
          tester
              .widget<WeekGrid>(find.byType(WeekGrid))
              .monday
              .difference(monday)
              .inDays,
          7,
        );
        await tester.tap(find.text('日'));
        if (reduced) {
          await tester.pump();
        } else {
          await tester.pumpAndSettle();
        }
        expect(
          find.byKey(const PageStorageKey('timetable-day-page')),
          findsOneWidget,
        );
        expect(find.byType(WeekGrid), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final dark in [false, true]) {
    testWidgets(
      'schedule mode switch renders compact liquid glass lens and slides cleanly dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var daily = false;
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
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: MiuixThemeBridge(child: child!),
              ),
              home: Scaffold(
                body: Center(
                  child: StatefulBuilder(
                    builder: (context, setState) => ScheduleModeSwitch(
                      daily: daily,
                      onChanged: (v) => setState(() => daily = v),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final modeSwitch = find.byType(ScheduleModeSwitch);
        final indicator = find.byKey(const ValueKey('schedule-mode-indicator'));
        final surfaceFinder = find.descendant(
          of: indicator,
          matching: find.byType(LiquidGlassSurface),
        );
        expect(indicator, findsOneWidget);
        expect(
          tester.widget<DecoratedBox>(indicator).decoration,
          isA<BoxDecoration>(),
        );
        expect(surfaceFinder, findsOneWidget);
        final surface = tester.widget<LiquidGlassSurface>(surfaceFinder);
        expect(surface.radius, AppRadius.small);
        expect(surface.blur, AppLiquidGlass.segmentLensBlur);
        expect(surface.edgeDepth, AppLiquidGlass.segmentLensEdgeDepth);
        expect(surface.refraction, AppLiquidGlass.segmentLensRefraction);
        expect(
          find.descendant(
            of: find.byType(AppSegmentIndicator),
            matching: find.byType(IgnorePointer),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(AppSegmentIndicator),
            matching: find.byType(ExcludeSemantics),
          ),
          findsOneWidget,
        );
        for (final label in ['周', '日']) {
          expect(
            find.descendant(of: surfaceFinder, matching: find.text(label)),
            findsNothing,
          );
          expect(
            find.descendant(
              of: find.byType(AppSegmentIndicator),
              matching: find.text(label),
            ),
            findsNothing,
          );
        }
        for (final element
            in find
                .descendant(
                  of: modeSwitch,
                  matching: find.byType(MiuixPressable),
                )
                .evaluate()) {
          final size = tester.getSize(
            find.byElementPredicate((candidate) => candidate == element),
          );
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }
        final switchRect = tester.getRect(modeSwitch);
        final indicatorRect = tester.getRect(indicator);
        expect(indicatorRect.left, greaterThanOrEqualTo(switchRect.left));
        expect(indicatorRect.right, lessThanOrEqualTo(switchRect.right));
        expect(indicatorRect.top, greaterThanOrEqualTo(switchRect.top));
        expect(indicatorRect.bottom, lessThanOrEqualTo(switchRect.bottom));
        final weekDx = tester.getCenter(find.text('周')).dx;
        final dayDx = tester.getCenter(find.text('日')).dx;
        expect(tester.getCenter(indicator).dx, closeTo(weekDx, 1));

        await tester.tap(find.text('日'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        final midDx = tester.getCenter(indicator).dx;
        expect(midDx, greaterThan(weekDx));
        expect(midDx, lessThan(dayDx));

        await tester.tap(find.text('周'));
        await tester.pump(const Duration(milliseconds: 40));
        await tester.tap(find.text('日'));
        await tester.pumpAndSettle();
        expect(daily, isTrue);
        expect(tester.getCenter(indicator).dx, closeTo(dayDx, 1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'schedule mode switch retains static lens and jumps under reduced motion',
    (tester) async {
      var daily = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentAppearanceProvider.overrideWithValue(
              const AppearanceSettings(),
            ),
          ],
          child: MaterialApp(
            theme: appTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: MiuixThemeBridge(child: child!),
            ),
            home: Scaffold(
              body: Center(
                child: StatefulBuilder(
                  builder: (context, setState) => ScheduleModeSwitch(
                    daily: daily,
                    onChanged: (v) => setState(() => daily = v),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final indicator = find.byKey(const ValueKey('schedule-mode-indicator'));
      expect(
        find.descendant(
          of: indicator,
          matching: find.byType(LiquidGlassSurface),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('日'));
      await tester.pump();
      expect(daily, isTrue);
      expect(
        tester.getCenter(indicator).dx,
        closeTo(tester.getCenter(find.text('日')).dx, 1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final dark in [false, true]) {
    for (final mode in [
      'blur-off',
      'glass-off',
      'app-contrast',
      'system-contrast',
    ]) {
      testWidgets(
        'schedule mode switch uses opaque fallback dark=$dark mode=$mode',
        (tester) async {
          final settings = AppearanceSettings(
            blur: mode != 'blur-off',
            glass: mode != 'glass-off',
            contrast: mode == 'app-contrast' ? .5 : 0,
          );
          var daily = false;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                currentAppearanceProvider.overrideWithValue(settings),
              ],
              child: MaterialApp(
                theme: appTheme(dark ? Brightness.dark : Brightness.light),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(highContrast: mode == 'system-contrast'),
                  child: MiuixThemeBridge(child: child!),
                ),
                home: Scaffold(
                  body: Center(
                    child: StatefulBuilder(
                      builder: (context, setState) => ScheduleModeSwitch(
                        daily: daily,
                        onChanged: (v) => setState(() => daily = v),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(LiquidGlassSurface), findsNothing);
          final indicator = find.byKey(
            const ValueKey('schedule-mode-indicator'),
          );
          final box =
              tester.widget<DecoratedBox>(indicator).decoration
                  as BoxDecoration;
          expect(box.color!.a, 1);
          expect(box.gradient, isNull);
          expect(box.boxShadow, isNull);
          expect(box.border, isNotNull);
          await tester.tap(find.text('日'));
          await tester.pumpAndSettle();
          expect(daily, isTrue);
          expect(
            tester.getCenter(indicator).dx,
            closeTo(tester.getCenter(find.text('日')).dx, 1),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'schedule mode switch supports keyboard focus and Enter activation',
    (tester) async {
      var daily = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentAppearanceProvider.overrideWithValue(
              const AppearanceSettings(),
            ),
          ],
          child: MaterialApp(
            theme: appTheme(Brightness.light),
            builder: (context, child) => MiuixThemeBridge(child: child!),
            home: Scaffold(
              body: Center(
                child: StatefulBuilder(
                  builder: (context, setState) => ScheduleModeSwitch(
                    daily: daily,
                    onChanged: (v) => setState(() => daily = v),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final indicator = find.byKey(const ValueKey('schedule-mode-indicator'));
      expect(
        tester.getCenter(indicator).dx,
        closeTo(tester.getCenter(find.text('周')).dx, 1),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(daily, isTrue);
      final daySemantics = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '日视图',
      );
      expect(
        tester.widget<Semantics>(daySemantics).properties.selected,
        isTrue,
      );
      expect(
        tester.getCenter(indicator).dx,
        closeTo(tester.getCenter(find.text('日')).dx, 1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
