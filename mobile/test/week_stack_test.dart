import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/application/appearance_controller.dart';
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
}
