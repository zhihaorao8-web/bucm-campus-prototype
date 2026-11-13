import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/domain/classroom.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'schedule_test.dart' show sample;

Map<String, dynamic> course() => {
  'id': 'synthetic',
  'name': '合成课程',
  'teacher': '合成教师',
  'code': 'S001',
  'group': '合成班',
  'semester': '2030-2031-1',
};
Map<String, dynamic> row(String id, String date) => {
  'id': id,
  'label': '合成课次',
  'date': date,
  'place': '合成教室',
  'published': true,
};
Map<String, dynamic> page(List<Map<String, dynamic>> rows) => {
  'course': course(),
  'page': 1,
  'pageSize': 10,
  'total': 12,
  'records': rows,
};

void main() {
  test(
    'parenthesis width matches the complete name without changing titles',
    () {
      final local = Course.fromJson(sample().toJson()..['name'] = '合成课程Ⅱ(方向甲)');
      ClassroomCourse source(
        String name, {
        String? semester,
        String id = 'synthetic',
      }) => ClassroomCourse.fromJson(
        course()
          ..['name'] = name
          ..['id'] = id
          ..['semester'] = semester ?? local.semester,
      );
      final full = source('合成课程Ⅱ（方向甲）');
      expect(full.matches(local), isTrue);
      expect(full.name, '合成课程Ⅱ（方向甲）');
      expect(local.name, '合成课程Ⅱ(方向甲)');
      expect(source('合成课程Ⅱ(方向甲）').matches(local), isTrue);
      for (final name in [
        '合成课程Ⅱ',
        '合成课程Ⅱ(方向乙)',
        '合成课程Ⅰ(方向甲)',
        '合成课程2(方向甲)',
        '合成课程Ⅱ(方向甲)扩展',
      ]) {
        expect(source(name).matches(local), isFalse);
      }
      expect(
        source(full.name, semester: '2030-2031-2').matches(local),
        isFalse,
      );
      expect(
        matchingClassroomCourses(local, [
          full,
          source(local.name, id: 'other'),
        ]).length,
        2,
      );
      expect(
        () => matchingClassroomCourses(local, [full, source(local.name)]),
        throwsFormatException,
      );
    },
  );

  test(
    'recordings sort by school date, retain publication and validate page bounds',
    () {
      final data = RecordingPage.fromJson(
        page([
          row('one', '2030-09-02'),
          row('two', '2030-09-09')..['published'] = false,
        ]),
      );
      expect(data.records.first.id, 'two');
      expect(data.records.first.published, isFalse);
      expect(data.hasNext, isTrue);
      expect(
        () => RecordingPage.fromJson(
          page([row('one', '2030-09-02'), row('one', '2030-09-02')]),
        ),
        throwsFormatException,
      );
      expect(
        () => RecordingPage.fromJson(page([])..['pageSize'] = 101),
        throwsFormatException,
      );
      expect(
        () => ClassroomRecording.fromJson(row('one', '2030-02-30')),
        throwsFormatException,
      );
      expect(
        () => ClassroomCourse.fromJson(course()..['semester'] = ''),
        throwsFormatException,
      );
    },
  );
}
