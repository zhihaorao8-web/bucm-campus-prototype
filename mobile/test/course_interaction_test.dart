import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/ui/course_interaction.dart';
import 'package:campus_schedule/ui/course_widgets.dart';
import 'package:campus_schedule/ui/today_focus.dart';
import 'package:campus_schedule/ui/classroom_course_page.dart';
import 'support/memory_appearance.dart';
import 'schedule_test.dart' show sample;

Widget frame(Widget child, {bool reduced = false}) => ProviderScope(
  overrides: [
    appearanceRepositoryProvider.overrideWithValue(
      MemoryAppearanceRepository(),
    ),
  ],
  child: MaterialApp(
    theme: appTheme(reduced ? Brightness.dark : Brightness.light),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
      child: MiuixThemeBridge(child: child!),
    ),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'press cancellation restores card and does not activate; reduced=$reduced',
      (tester) async {
        var activated = 0;
        await tester.pumpWidget(
          frame(
            CoursePressable(
              onPressed: () => activated++,
              child: const SizedBox(
                key: ValueKey('press-content'),
                width: 200,
                height: 80,
              ),
            ),
            reduced: reduced,
          ),
        );
        await tester.pumpAndSettle();
        final content = find.byKey(const ValueKey('press-content'));
        final original = tester.getRect(content);
        final gesture = await tester.startGesture(original.center);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        if (reduced) {
          expect(tester.getRect(content).width, closeTo(original.width, .01));
        } else {
          expect(tester.getRect(content).width, lessThan(original.width));
          expect(
            tester.getRect(content).width,
            greaterThan(original.width * .97),
          );
        }
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect(activated, 0);
        expect(tester.getRect(content).width, closeTo(original.width, .1));
        final drag = await tester.startGesture(original.center);
        await tester.pump();
        await drag.moveBy(const Offset(0, -60));
        await drag.up();
        await tester.pumpAndSettle();
        expect(activated, 0);
        expect(tester.getRect(content).width, closeTo(original.width, .1));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(activated, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'repeated course occurrences enter and return without duplicate heroes; reduced=$reduced',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final course = Course.fromJson({
          ...sample().toJson(),
          'dataSource': 'synthetic',
        });
        final event = Occurrence(
          course,
          course.segments.first,
          DateTime(2026, 11, 13),
        );
        await tester.pumpWidget(
          frame(
            Column(
              children: [
                FocusCourseCard(event: event, now: DateTime(2026, 11, 13, 8)),
                CourseRow(event: event),
                CourseRow(event: event),
              ],
            ),
            reduced: reduced,
          ),
        );
        await tester.pumpAndSettle();
        final tags = tester
            .widgetList<Hero>(find.byType(Hero))
            .map((h) => h.tag)
            .toList();
        expect(tags.toSet().length, tags.length);
        expect(tags.length, reduced ? 0 : 3);
        final source = find.byType(CourseRow).first;
        final location = tester.getTopLeft(source);
        await tester.tap(source);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        final page = find.byType(ClassroomCoursePage);
        expect(page, findsOneWidget);
        final route = ModalRoute.of(tester.element(page))!;
        expect(route, isA<CourseDetailsRoute>());
        expect(
          route.transitionDuration,
          reduced ? Duration.zero : const Duration(milliseconds: 280),
        );
        Navigator.of(tester.element(page)).pop();
        await tester.pumpAndSettle();
        expect(find.byType(ClassroomCoursePage), findsNothing);
        expect(tester.getTopLeft(find.byType(CourseRow).first), location);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('repeated taps cannot open a second pending course route', (
    tester,
  ) async {
    var openings = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(
      frame(
        CourseCardLink(
          onOpen: (_) {
            openings++;
            return pending.future;
          },
          child: const SizedBox(width: 200, height: 80, child: Text('打开课程')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开课程'));
    await tester.tap(find.text('打开课程'));
    await tester.pumpAndSettle();
    expect(openings, 1);
    pending.complete();
    await tester.pump();
    await tester.tap(find.text('打开课程'));
    await tester.pumpAndSettle();
    expect(openings, 2);
    await tester.pumpWidget(const SizedBox());
  });
}
