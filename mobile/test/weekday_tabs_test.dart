import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/ui/weekday_tabs.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/ui/course_widgets.dart';
import 'schedule_test.dart' show MemoryRepository;
import 'ui_test.dart' show app;
import 'week_grid_test.dart' show weeklyPreviewData;

void main() {
  for (final mode in [
    'blur-off',
    'glass-off',
    'app-contrast',
    'system-contrast',
  ]) {
    testWidgets('date controls retain an opaque fallback: $mode', (
      tester,
    ) async {
      final settings = AppearanceSettings(
        blur: mode != 'blur-off',
        glass: mode != 'glass-off',
        contrast: mode == 'app-contrast' ? 1 : 0,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [currentAppearanceProvider.overrideWithValue(settings)],
          child: MaterialApp(
            theme: appTheme(Brightness.dark),
            home: MediaQuery(
              data: MediaQueryData(highContrast: mode == 'system-contrast'),
              child: MiuixThemeBridge(
                child: Scaffold(body: WeekdayTabs(day: 1, onSelected: (_) {})),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final filter = tester.widget<BackdropFilter>(
        find.byKey(const ValueKey('weekday-acrylic-blur')),
      );
      expect(filter.enabled, isFalse);
      final decoration =
          (filter.child! as DecoratedBox).decoration as BoxDecoration;
      expect(decoration.color!.a, 1);
      expect(decoration.gradient, isNull);
      expect(find.text('周一'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
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
          expect(
            tester
                .widget<BackdropFilter>(
                  find.byKey(const ValueKey('weekday-acrylic-blur')),
                )
                .enabled,
            isTrue,
          );
          expect(
            tester
                .widget<MiuixTabRow>(find.byKey(const ValueKey('weekday-tabs')))
                .colors!
                .backgroundColor
                .a,
            0,
            reason:
                'The tab row must not cover its own backdrop blur with an opaque fill',
          );
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
