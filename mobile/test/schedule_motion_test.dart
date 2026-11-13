import 'package:flutter/material.dart';
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
}
