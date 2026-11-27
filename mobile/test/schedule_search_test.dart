import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/ui/classroom_course_page.dart';
import 'package:campus_schedule/ui/course_widgets.dart';
import 'package:campus_schedule/ui/week_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'schedule_test.dart' show MemoryRepository, sample;
import 'ui_test.dart' show app;

final _searchButton = find.byKey(const ValueKey('course-search-button'));
final _searchInput = find.byKey(const ValueKey('course-search-input'));
final _searchResults = find.byKey(const ValueKey('course-search-results'));
final _searchCards = find.descendant(
  of: _searchResults,
  matching: find.byType(CourseRow),
);

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openTimetable(
  WidgetTester tester,
  ScheduleData data, {
  bool dark = false,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    app(MemoryRepository(data), dark: dark, scale: scale, reduceMotion: true),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('tab-1')));
  await tester.pumpAndSettle();
}

Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(_searchButton);
  await tester.pumpAndSettle();
  expect(find.text('学期内找课'), findsOneWidget);
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(_searchInput, query);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('search uses the same daily course cards and opens that date', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    final courses = [
      sample(
        id: 'split',
        name: '示例人体结构',
        teacher: '示例教师甲',
        place: '示例教室 101',
        day: DateTime.saturday,
        weeks: '1',
        segments: const [
          TeachingSegment('08:30', '09:15'),
          TeachingSegment('10:30', '11:15'),
        ],
      ),
      sample(
        id: 'same-name',
        name: '示例人体结构',
        teacher: '示例教师乙',
        place: '示例教室 202',
        day: DateTime.saturday,
        weeks: '1',
        segments: const [TeachingSegment('13:30', '15:00')],
      ),
      sample(
        id: 'overlap',
        name: '示例讨论课',
        day: DateTime.saturday,
        weeks: '1',
        segments: const [TeachingSegment('09:00', '09:45')],
      ),
    ];
    await _openTimetable(tester, ScheduleData(courses: courses));
    await tester.tap(
      find.descendant(
        of: find.byType(ScheduleModeSwitch),
        matching: find.text('日'),
      ),
    );
    await tester.pumpAndSettle();
    final saturday = find.text('周六');
    await Scrollable.of(
      tester.element(saturday),
      axis: Axis.horizontal,
    ).position.ensureVisible(tester.renderObject(saturday), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(saturday);
    await tester.pumpAndSettle();

    final dayCards = tester
        .widgetList<CourseRow>(find.byType(CourseRow))
        .where((card) => card.event.course.name == '示例人体结构')
        .toList();
    expect(dayCards, hasLength(3));
    expect(dayCards.map((card) => card.conflict), [true, false, false]);
    (String, String, String, String, DateTime, bool) cardDetails(
      CourseRow card,
    ) {
      final event = card.event;
      return (
        event.course.id,
        event.course.place,
        event.segment.start,
        event.segment.end,
        event.date,
        card.conflict,
      );
    }

    await _openSearch(tester);
    await _search(tester, '结构');
    final searchCards = tester.widgetList<CourseRow>(_searchCards).toList();
    expect(searchCards.map(cardDetails), dayCards.map(cardDetails));

    final lastCard = find.byWidget(searchCards.last);
    await tester.ensureVisible(lastCard);
    await tester.pumpAndSettle();
    await tester.tap(lastCard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final detailsFinder = find.byType(ClassroomCoursePage);
    final details = tester.widget<ClassroomCoursePage>(detailsFinder);
    expect(details.course.id, 'same-name');
    expect(details.course.teacher, '示例教师乙');
    expect(details.date, DateTime(2026, 9, 12));
    Navigator.of(tester.element(detailsFinder)).pop();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_searchInput).controller?.text, '结构');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'search filters names only within the semester selected in the timetable',
    (tester) async {
      final courses = [
        sample(id: 'current', name: '示例结构课', weeks: '1'),
        sample(
          id: 'older',
          name: '示例结构课',
          teacher: '专用教师关键词',
          place: '专用教室关键词',
          term: '2025-2026-1',
          termStart: '2025-09-08',
          weeks: '1',
        ),
      ];
      await _openTimetable(tester, ScheduleData(courses: courses));
      final termSelector = find.byType(DropdownButton<String>);
      await tester.tap(termSelector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('2025-2026-1 学期').last);
      await tester.pumpAndSettle();
      await _openSearch(tester);

      for (final query in ['专用教师关键词', '专用教室关键词']) {
        await _search(tester, query);
        expect(find.text('未找到匹配的课程'), findsOneWidget);
        expect(_searchCards, findsNothing);
      }
      await _search(tester, '结构');
      expect(tester.widget<CourseRow>(_searchCards).event.course.id, 'older');
      await tester.tap(find.byTooltip('清空课程名'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_searchInput).controller?.text, isEmpty);
      expect(_searchCards, findsNothing);
      expect(find.text('未找到匹配的课程'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_searchInput, findsNothing);
      expect(
        tester.widget<DropdownButton<String>>(termSelector).value,
        '2025-2026-1',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('search shows the import entry when there is no local schedule', (
    tester,
  ) async {
    await _openTimetable(tester, const ScheduleData());
    await _openSearch(tester);
    expect(find.text('尚未导入课表'), findsOneWidget);
    expect(find.text('从学校导入课表'), findsOneWidget);
    expect(_searchInput, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('large dark layout scrolls results above the keyboard at 320dp', (
    tester,
  ) async {
    _setViewport(tester, const Size(320, 720));
    final course = sample(name: '示例人体结构实验', weeks: '1-12');
    await _openTimetable(
      tester,
      ScheduleData(courses: [course]),
      dark: true,
      scale: 2,
    );
    await _openSearch(tester);
    await _search(tester, '结构');
    tester.view.viewInsets = const FakeViewPadding(bottom: 244);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(tester.getRect(_searchResults).bottom, lessThanOrEqualTo(476));
    expect(_searchCards, findsWidgets);
    final courseName = find.descendant(
      of: _searchCards.first,
      matching: find.text(course.name),
    );
    expect(
      tester.renderObject<RenderParagraph>(courseName).didExceedMaxLines,
      isFalse,
    );
    final position = Scrollable.of(
      tester.element(_searchCards.first),
      axis: Axis.vertical,
    ).position;
    final before = position.pixels;
    await tester.drag(_searchResults, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(before));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
