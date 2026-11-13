import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/ui/course_surface.dart';
import 'package:campus_schedule/ui/navigation_motion.dart';
import 'package:campus_schedule/ui/week_grid.dart';
import 'package:campus_schedule/ui/week_navigation.dart';
import 'schedule_test.dart' show MemoryRepository, sample;
import 'ui_test.dart' show app;
import 'week_grid_test.dart' show weeklyPreviewData;

void main() {
  test(
    'stack sweep preserves every duration in chained overlaps; touching endpoints do not conflict',
    () {
      Occurrence occurrence(String id, String start, String end) => Occurrence(
        Course.fromJson({...sample().toJson(), 'id': id}),
        TeachingSegment(start, end),
        DateTime(2026, 11, 13),
      );
      final events = [
        occurrence('a', '08:30', '09:15'),
        occurrence('b', '09:00', '10:00'),
        occurrence('c', '09:45', '10:30'),
      ];
      final bands = stackEvents(events.reversed.toList());
      expect(
        bands
            .map((band) => band.events.map((event) => event.course.id).join())
            .toList(),
        ['a', 'ab', 'b', 'bc', 'c'],
      );
      for (final event in events) {
        final minutes = bands
            .where((band) => band.events.contains(event))
            .fold<int>(
              0,
              (total, band) =>
                  total + band.end.difference(band.start).inMinutes,
            );
        expect(minutes, event.end.difference(event.start).inMinutes);
      }
      expect(
        stackEvents([
          occurrence('a', '08:30', '10:00'),
          occurrence('b', '10:00', '12:00'),
        ]).every((band) => band.events.length == 1),
        isTrue,
      );
    },
  );
  testWidgets(
    'week swipe, return to current, modes and optional weekends affect real grid',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(MemoryRepository(weeklyPreviewData(schoolNow()))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-1')));
      await tester.pumpAndSettle();
      expect(find.text('第 10 周'), findsOneWidget);
      final modeButtons = find.descendant(
        of: find.byType(ScheduleModeSwitch),
        matching: find.byType(MiuixPressable),
      );
      for (final element in modeButtons.evaluate()) {
        final size = tester.getSize(
          find.byElementPredicate((candidate) => candidate == element),
        );
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      expect(find.text('本周'), findsNothing);
      await tester.drag(
        find.byKey(const ValueKey('week-navigation')),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('第 11 周'), findsOneWidget);
      await tester.tap(find.text('本周'));
      await tester.pumpAndSettle();
      expect(find.text('第 10 周'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(WeekGrid)),
      );
      await container
          .read(appearanceProvider.notifier)
          .change((v) => v.copyWith(showWeekend: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('week-day-6')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('week-event-evening-7-18:00')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('week-day-6')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ScheduleModeSwitch>(find.byType(ScheduleModeSwitch))
            .daily,
        isTrue,
      );
      expect(find.text('合成晚课7'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'small dark large-text conflict drawer scrolls, prioritizes and opens original course route',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(
          MemoryRepository(weeklyPreviewData(schoolNow())),
          dark: true,
          scale: 1.5,
          reduceMotion: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-1')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(WeekGrid)),
      );
      await container
          .read(appearanceProvider.notifier)
          .change((v) => v.copyWith(showWeekend: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('week-day-6')), findsOneWidget);
      final stack = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.key.toString().contains('week-stack-'),
      );
      await tester.ensureVisible(stack);
      await tester.tap(stack);
      await tester.pumpAndSettle();
      final prefer = find.byKey(const ValueKey('prefer-course-morning-4'));
      await tester.ensureVisible(prefer);
      await tester.tap(prefer);
      await tester.pumpAndSettle();
      await tester.tap(stack);
      await tester.pumpAndSettle();
      final entry = find.text('查看课程与录播').last;
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.text('重叠课程'), findsNothing);
      expect(find.text('课程信息'), findsOneWidget);
      expect(find.text('录播'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  Finder conflictStack() => find.byWidgetPredicate(
    (widget) =>
        widget is Semantics && widget.key.toString().contains('week-stack-'),
  );
  Future<void> openWeek(
    WidgetTester tester, {
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        MemoryRepository(weeklyPreviewData(schoolNow())),
        reduceMotion: reduceMotion,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pumpAndSettle();
  }

  for (final opaque in [false, true]) {
    testWidgets(
      'conflict drawer is one quiet sheet and dismisses without a choice; opaque=$opaque',
      (tester) async {
        await openWeek(tester);
        if (opaque) {
          await ProviderScope.containerOf(tester.element(find.byType(WeekGrid)))
              .read(appearanceProvider.notifier)
              .change((v) => v.copyWith(glass: false));
          await tester.pumpAndSettle();
        }
        final stack = conflictStack();
        bool primary(String id) => find
            .descendant(
              of: stack,
              matching: find.byKey(ValueKey('week-primary-$id')),
            )
            .evaluate()
            .isNotEmpty;
        final before = primary('conflict');
        await tester.tap(stack);
        await tester.pump();
        final sheet = find.byType(QuietSheet);
        final route =
            ModalRoute.of(tester.element(sheet))! as ModalBottomSheetRoute;
        expect(route.transitionDuration, const Duration(milliseconds: 280));
        expect(
          route.reverseTransitionDuration,
          const Duration(milliseconds: 220),
        );
        expect(route.sheetAnimationStyle?.curve, navigationCurve);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: sheet, matching: find.byType(QuietCard)),
          findsNWidgets(2),
        );
        expect(
          tester
              .widget<BackdropFilter>(
                find.descendant(
                  of: sheet,
                  matching: find.byType(BackdropFilter),
                ),
              )
              .enabled,
          !opaque,
        );
        for (final element in find.byType(BackdropFilter).evaluate()) {
          if ((element.widget as BackdropFilter).enabled) {
            expect(
              (element.renderObject! as RenderBox).size.height,
              lessThan(844),
            );
          }
        }
        final surface = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find
                    .descendant(of: sheet, matching: find.byType(CourseSurface))
                    .first,
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        expect((surface.decoration as BoxDecoration).gradient == null, opaque);
        expect(find.text('设为优先显示'), findsOneWidget);
        expect(find.text('当前优先显示'), findsOneWidget);
        expect(find.text('查看课程与录播'), findsNWidgets(2));
        expect(find.text('合成教师'), findsWidgets);
        await tester.tapAt(const Offset(195, 40));
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(find.text('课程信息'), findsNothing);
        expect(primary('conflict'), before);
        await tester.tap(stack);
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(primary('conflict'), before);
        await tester.tap(stack);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('关闭重叠课程'));
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final keyboard in [false, true]) {
    testWidgets(
      'conflict drawer appears at once for ${keyboard ? 'keyboard focus' : 'reduced motion'}',
      (tester) async {
        if (keyboard) {
          FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.alwaysTraditional;
          addTearDown(
            () => FocusManager.instance.highlightStrategy =
                FocusHighlightStrategy.automatic,
          );
        }
        await openWeek(tester, reduceMotion: !keyboard);
        await tester.tap(conflictStack());
        await tester.pump();
        final sheet = find.byType(QuietSheet);
        final route =
            ModalRoute.of(tester.element(sheet))! as ModalBottomSheetRoute;
        expect(route.transitionDuration, Duration.zero);
        expect(route.reverseTransitionDuration, Duration.zero);
        await tester.pump();
        final shown = tester.getRect(sheet);
        await tester.pumpAndSettle();
        expect(tester.getRect(sheet), shown);
        await tester.tap(find.byTooltip('关闭重叠课程'));
        await tester.pump();
        await tester.pump();
        expect(sheet, findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
