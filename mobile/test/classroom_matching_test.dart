import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/domain/classroom.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/platform/classroom_access.dart';
import 'package:campus_schedule/ui/classroom_course_page.dart';
import 'schedule_test.dart' show sample;
import 'support/memory_classroom_library.dart';
import 'support/memory_appearance.dart';

void main() {
  final local = Course.fromJson(
    sample().toJson()
      ..['name'] = '合成医学 A'
      ..['dataSource'] = 'school',
  );
  ClassroomCourse school(String id, {String? name, String? semester}) =>
      ClassroomCourse(
        id: id,
        name: name ?? local.name,
        semester: semester ?? local.semester,
        teacher: '合成教师',
        code: 'S001',
        group: '合成班',
      );
  test('名称匹配限定学期，不使用模糊匹配或教师条件', () {
    final right = school('right', name: '　合成医学\u00a0 A　');
    expect(
      matchingClassroomCourses(local, [
        school('old', semester: '2031-2032-1'),
        right,
      ]).single.id,
      'right',
    );
    expect(
      matchingClassroomCourses(local, [
        school('different', name: '合成医学 A（选修）'),
      ]),
      isEmpty,
    );
    expect(
      matchingClassroomCourses(local, [school('different', name: '合成医学A')]),
      isEmpty,
    );
    expect(matchingClassroomCourses(local, []), isEmpty);
  });
  test('同名条目全部关联，重复学校ID拒绝而不任意选一门', () {
    final a = school('a'), b = school('b');
    expect(matchingClassroomCourses(local, [a, b]).map((c) => c.id), [
      'a',
      'b',
    ]);
    expect(
      matchingClassroomCourses(local, [
        a,
        school('b', name: '其他合成课'),
      ]).single.id,
      'a',
    );
    expect(
      () => matchingClassroomCourses(local, [a, school('a', name: '其他合成课')]),
      throwsFormatException,
    );
  });
  testWidgets('进入本人课程自动检测，失败保留重试；合成示例不连接', (tester) async {
    final calls = <String>[];
    Future<AccessProbe> probe(String url) async {
      calls.add(url);
      return const AccessProbe(ProbeState.unavailable);
    }

    await tester.pumpWidget(
      appearanceScope(
        MaterialApp(
          home: ClassroomCoursePage(
            course: local,
            library: MemoryClassroomLibrary(),
            onDetails: (_) {},
            probe: probe,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, [classroomProbe, vpnEntry]);
    expect(find.text('重新获取学校录播'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    calls.clear();
    await tester.pumpWidget(
      appearanceScope(
        MaterialApp(
          home: ClassroomCoursePage(
            course: Course.fromJson(
              local.toJson()..['dataSource'] = 'synthetic',
            ),
            onDetails: (_) {},
            probe: probe,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('离开页面后忽略迟到的自动连接结果', (tester) async {
    final response = Completer<AccessProbe>();
    await tester.pumpWidget(
      appearanceScope(
        MaterialApp(
          home: ClassroomCoursePage(
            course: local,
            library: MemoryClassroomLibrary(),
            onDetails: (_) {},
            probe: (_) => response.future,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    response.complete(const AccessProbe(ProbeState.unavailable));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
