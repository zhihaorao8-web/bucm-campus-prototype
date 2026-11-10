import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/ui/course_widgets.dart';
import 'schedule_test.dart' show MemoryRepository;
import 'ui_test.dart' show app;
import 'week_grid_test.dart' show weeklyPreviewData;

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'weekday glyphs paint fully and all days switch: dark=$dark scale=$scale',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            app(
              MemoryRepository(weeklyPreviewData(schoolNow())),
              dark: dark,
              scale: scale,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('tab-1')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('日'));
          await tester.pumpAndSettle();
          for (var d = 1; d <= 7; d++) {
            final label = find.text('周${weekdays[d - 1]}');
            expect(label, findsOneWidget);
            final text = tester.renderObject<RenderParagraph>(label);
            expect(
              text.didExceedMaxLines,
              isFalse,
              reason: 'weekday $d must be painted, not just in the widget tree',
            );
            await Scrollable.of(
              tester.element(label),
              axis: Axis.horizontal,
            ).position.ensureVisible(tester.renderObject(label), alignment: .5);
            await tester.pumpAndSettle();
            await tester.tap(label);
            await tester.pumpAndSettle();
            final selected = find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.label == '周${weekdays[d - 1]}，标签 $d / 7',
            );
            expect(
              tester.widget<Semantics>(selected).properties.selected,
              isTrue,
            );
            expect(tester.getSize(selected).height, greaterThanOrEqualTo(48));
            expect(
              tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
              isFalse,
            );
            final visibleCourses = tester.widgetList<CourseRow>(
              find.byType(CourseRow),
            );
            expect(visibleCourses, isNotEmpty);
            expect(
              visibleCourses.every((row) => row.event.course.day == d),
              isTrue,
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
