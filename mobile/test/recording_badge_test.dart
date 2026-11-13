import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/ui/course_widgets.dart';
import 'package:campus_schedule/ui/week_grid.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/ui/app_icons.dart';
import 'schedule_test.dart' show sample;

void main() {
  Finder recordingIcon() => find.byWidgetPredicate(
    (widget) => widget is AppIcon && widget.icon == AppIcons.mediaLibrary,
  );
  testWidgets(
    'local playback badge is explicit in rows and does not force icons into tight grid cells',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final date = DateTime(2026, 9, 7), course = sample();
      final event = occurrencesOn([course], date).first;
      Widget surface(Widget child) => MaterialApp(
        theme: appTheme(Brightness.dark),
        builder: (context, child) => MiuixThemeBridge(
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
        ),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );
      await tester.pumpWidget(
        surface(CourseRow(event: event, hasRecordings: true)),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('本地目录中有可播放录播'), findsOneWidget);
      expect(find.text(course.name), findsOneWidget);
      await tester.pumpWidget(surface(CourseRow(event: event)));
      await tester.pumpAndSettle();
      expect(recordingIcon(), findsNothing);
      await tester.pumpWidget(
        surface(
          SizedBox(
            height: 600,
            child: WeekGrid(
              courses: [course],
              monday: date,
              today: date,
              hasRecordings: (_) => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(recordingIcon(), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              (widget.properties.label?.contains('本地目录中有可播放录播') ?? false),
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpWidget(
        surface(
          SizedBox(
            height: 1500,
            child: WeekGrid(
              courses: [course],
              monday: date,
              today: date,
              hasRecordings: (_) => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(recordingIcon(), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
