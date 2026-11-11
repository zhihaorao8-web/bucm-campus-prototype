import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/ui/classroom_course_page.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'schedule_test.dart' show sample;

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'course secondary page preserves details and live placeholder dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final synthetic = Course.fromJson(
          sample().toJson()..['dataSource'] = 'synthetic',
        );
        var opened = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(dark ? Brightness.dark : Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: ClassroomCoursePage(
              course: synthetic,
              onDetails: (_) => opened = true,
            ),
          ),
        );
        expect(find.text('示例教师'), findsOneWidget);
        await tester.tap(find.text('查看完整课程信息'));
        expect(opened, isTrue);
        await tester.tap(find.text('直播'));
        await tester.pumpAndSettle();
        expect(find.textContaining('学校直播暂未开放'), findsOneWidget);
        expect(find.text('连接学校录播'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
