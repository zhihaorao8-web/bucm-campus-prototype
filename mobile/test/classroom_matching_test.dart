import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/domain/classroom.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/platform/classroom_access.dart';
import 'package:campus_schedule/ui/classroom_course_page.dart';
import 'schedule_test.dart' show sample;

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
  test('名称唯一时自动关联，限定学期且不使用模糊或教师匹配', () {
    final right = school('right', name: '　合成医学\u00a0 A　');
    expect(
      matchClassroomCourse(local, [
        school('old', semester: '2031-2032-1'),
        right,
      ])?.id,
      'right',
    );
    expect(
      matchClassroomCourse(local, [school('different', name: '合成医学 A（选修）')]),
      isNull,
    );
    expect(
      matchClassroomCourse(local, [school('different', name: '合成医学A')]),
      isNull,
    );
    expect(matchClassroomCourse(local, []), isNull);
  });
  test('同名不随意关联，确认ID必须仍在同学期同名候选中且唯一', () {
    final a = school('a'), b = school('b');
    expect(matchClassroomCourse(local, [a, b]), isNull);
    expect(matchClassroomCourse(local, [a, b], confirmedId: 'b')?.id, 'b');
    expect(matchClassroomCourse(local, [a, b], confirmedId: 'expired'), isNull);
    expect(
      matchClassroomCourse(local, [
        a,
        school('b', name: '其他合成课'),
      ], confirmedId: 'b')?.id,
      'a',
    );
    expect(
      matchClassroomCourse(local, [
        a,
        school('a', name: '其他合成课'),
      ], confirmedId: 'a'),
      isNull,
    );
  });
  testWidgets('进入本人课程自动检测，失败保留重试；合成示例不连接', (tester) async {
    final calls = <String>[];
    Future<AccessProbe> probe(String url) async {
      calls.add(url);
      return const AccessProbe(ProbeState.unavailable);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ClassroomCoursePage(
          course: local,
          onDetails: (_) {},
          probe: probe,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, [classroomProbe, vpnEntry]);
    expect(find.text('重新获取学校录播'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    calls.clear();
    await tester.pumpWidget(
      MaterialApp(
        home: ClassroomCoursePage(
          course: Course.fromJson(local.toJson()..['dataSource'] = 'synthetic'),
          onDetails: (_) {},
          probe: probe,
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
      MaterialApp(
        home: ClassroomCoursePage(
          course: local,
          onDetails: (_) {},
          probe: (_) => response.future,
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
