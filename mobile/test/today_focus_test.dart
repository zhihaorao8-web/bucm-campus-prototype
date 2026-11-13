import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/domain/schedule.dart';
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
              .widget<LinearProgressIndicator>(
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
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
