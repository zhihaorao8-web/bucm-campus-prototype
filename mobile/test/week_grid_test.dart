import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/ui/week_grid.dart';
import 'package:campus_schedule/ui/course_widgets.dart';
import 'schedule_test.dart' show MemoryRepository;
import 'ui_test.dart' show app;

// Entirely invented data, unrelated to the user's reference screenshot.
ScheduleData weeklyPreviewData(DateTime now) {
  final monday = calendarAdd(dateOnly(now), 1 - now.weekday - 9 * 7);
  Course course(
    String id,
    int day,
    String name,
    List<TeachingSegment> segments,
  ) => Course(
    id: id,
    name: name,
    teacher: '合成教师',
    place: '示例楼201',
    day: day,
    weeks: '1-16',
    periods: [1, 2],
    segments: segments,
    semester: '2026-2027-1',
    termStart: monday,
    dataSource: 'synthetic',
  );
  return ScheduleData(
    courses: [
      for (var d = 1; d <= 7; d++) ...[
        course('morning-$d', d, '合成基础课$d', [
          const TeachingSegment('08:30', '10:00'),
        ]),
        course('evening-$d', d, '合成晚课$d', [
          const TeachingSegment('18:00', '20:25'),
        ]),
      ],
      course('split', 2, '合成分段实验', [
        const TeachingSegment('13:30', '15:00'),
        const TeachingSegment('15:30', '16:15'),
      ]),
      course('conflict', 4, '合成冲突讨论', [
        const TeachingSegment('08:30', '10:00'),
      ]),
    ],
  );
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'adjacent same-name cards have different ${dark ? 'dark' : 'light'} colors',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final data = weeklyPreviewData(schoolNow());
        final sameNames = ScheduleData(
          courses: [
            for (final c in data.courses)
              Course.fromJson({...c.toJson(), 'name': '同名合成课程'}),
          ],
        );
        await tester.pumpWidget(app(MemoryRepository(sameNames), dark: dark));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('tab-1')));
        await tester.pumpAndSettle();
        Color? color(String id, String start) => tester
            .widget<Material>(
              find
                  .descendant(
                    of: find.byKey(ValueKey('week-event-$id-$start')),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color;
        final morning = [
          for (var d = 1; d <= 5; d++) color('morning-$d', '08:30'),
        ];
        for (var d = 0; d < 2; d++) {
          expect(morning[d], isNot(morning[d + 1]));
        }
        expect(morning[2], isNot(color('conflict', '08:30')));
        expect(color('conflict', '08:30'), isNot(morning[3]));
        expect(morning[3], isNot(morning[4]));
        expect(morning[1], isNot(color('split', '13:30')));
        expect(color('split', '13:30'), isNot(color('split', '15:30')));
        expect(color('split', '15:30'), isNot(color('evening-2', '18:00')));
        await tester.tap(find.byKey(const ValueKey('week-day-1')));
        await tester.pumpAndSettle();
        final rows = find.byType(CourseRow);
        expect(rows.evaluate().length, greaterThanOrEqualTo(2));
        final rowColors = [
          for (var i = 0; i < rows.evaluate().length; i++)
            (tester
                        .widget<Container>(
                          find
                              .descendant(
                                of: rows.at(i),
                                matching: find.byKey(
                                  const ValueKey('course-color-rail'),
                                ),
                              )
                              .first,
                        )
                        .decoration!
                    as BoxDecoration)
                .color,
        ];
        for (var i = 1; i < rowColors.length; i++) {
          expect(rowColors[i], isNot(rowColors[i - 1]));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final size in [const Size(390, 844), const Size(360, 800)]) {
    testWidgets(
      'working week including Friday evening fits $size without scrolling',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          app(MemoryRepository(weeklyPreviewData(schoolNow()))),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('tab-1')));
        await tester.pumpAndSettle();
        final grid = tester.getRect(
          find.byKey(const ValueKey('week-overview')),
        );
        final dock = tester.getRect(find.byKey(const ValueKey('dock-blur')));
        expect(grid.left, greaterThanOrEqualTo(0));
        expect(grid.right, lessThanOrEqualTo(size.width));
        expect(grid.bottom, lessThanOrEqualTo(dock.top));
        for (var d = 1; d <= 5; d++) {
          final card = tester.getRect(
            find.byKey(ValueKey('week-event-evening-$d-18:00')),
          );
          expect(card.right, lessThanOrEqualTo(size.width));
          expect(card.bottom, lessThan(dock.top));
          expect(
            find.byKey(ValueKey('week-event-evening-$d-18:00')).hitTestable(),
            findsOneWidget,
          );
        }
        expect(find.byKey(const ValueKey('week-day-5')), findsNothing);
        expect(find.byKey(const ValueKey('week-day-6')), findsNothing);
        expect(
          find.byKey(const ValueKey('week-event-evening-7-18:00')),
          findsNothing,
        );
        final view = tester.widget<CustomScrollView>(
          find.byKey(const PageStorageKey('timetable-page')),
        );
        expect(view.controller!.position.maxScrollExtent, closeTo(0, .1));
        expect(
          find.descendant(
            of: find.byType(WeekGrid),
            matching: find.byType(Scrollable),
          ),
          findsNothing,
        );
        expect(find.text('午休'), findsOneWidget);
        expect(find.text('晚休'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'conflicts remain separate, partial segments retain duration and details open',
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
      final first = tester.getRect(
        find.byKey(const ValueKey('week-event-morning-4-08:30')),
      );
      final overlap = tester.getRect(
        find.byKey(const ValueKey('week-event-conflict-08:30')),
      );
      expect(first.overlaps(overlap), isFalse);
      final full = tester.getRect(
        find.byKey(const ValueKey('week-event-split-13:30')),
      );
      final half = tester.getRect(
        find.byKey(const ValueKey('week-event-split-15:30')),
      );
      expect((half.height + 4) / (full.height + 4), closeTo(.5, .001));
      await tester.tap(
        find.byKey(const ValueKey('week-event-evening-5-18:00')),
      );
      await tester.pumpAndSettle();
      expect(find.text('合成晚课5'), findsWidgets);
      expect(find.text('合成教师'), findsWidgets);
      await tester.tap(find.text('课程信息'));
      await tester.pumpAndSettle();
      expect(find.text('18:00–20:25'), findsOneWidget);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('week-day-4')));
      await tester.pumpAndSettle();
      expect(find.byType(WeekGrid), findsNothing);
      expect(find.text('合成晚课5'), findsOneWidget);
      await tester.ensureVisible(find.text('周日'));
      await tester.tap(find.text('周日'));
      await tester.pumpAndSettle();
      expect(find.text('合成晚课7'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'small dark phone with large text keeps all five columns and evening reachable',
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
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-1')));
      await tester.pumpAndSettle();
      final last = find.byKey(const ValueKey('week-event-evening-5-18:00'));
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      expect(tester.getRect(last).right, lessThanOrEqualTo(320));
      expect(
        tester.getRect(last).bottom,
        lessThan(tester.getRect(find.byKey(const ValueKey('dock-blur'))).top),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
