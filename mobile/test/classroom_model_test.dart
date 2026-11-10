import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/domain/classroom.dart';

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
