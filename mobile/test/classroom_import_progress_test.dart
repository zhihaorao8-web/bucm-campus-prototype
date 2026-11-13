import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/application/classroom_import_progress.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'schedule_test.dart' show sample;

void main() {
  test(
    'parenthesis variants share one task while different content stays separate',
    () {
      final first = Course.fromJson(sample().toJson()..['name'] = '合成课程Ⅱ(方向甲)');
      final second = Course.fromJson(
        sample(id: 'second').toJson()..['name'] = '合成课程Ⅱ（方向甲）',
      );
      final different = Course.fromJson(
        sample(id: 'third').toJson()..['name'] = '合成课程Ⅱ（方向乙）',
      );
      final progress = ClassroomImportProgress([first, second, different]);
      expect(progress.items.length, 2);
      expect(progress.items.first.courses, [first, second]);
      expect(progress.items.first.course.name, first.name);
    },
  );

  test(
    'same semester normalized names share one task regardless of teacher and local id',
    () {
      final second = Course.fromJson(
        sample(id: 'second').toJson()
          ..['teacher'] = '其他教师'
          ..['name'] = '  合成课程  ',
      );
      final progress = ClassroomImportProgress([
        sample(),
        second,
        sample(id: 'third', term: '2027-2028-1'),
      ]);
      expect(progress.items.length, 2);
      expect(progress.totalLocalItems, 3);
      expect(progress.items.first.courses.length, 2);
      progress.update(0, ImportTaskStatus.failed, 'synthetic failure');
      progress.update(1, ImportTaskStatus.unmatched, 'not found');
      expect(progress.failures, [0]);
      progress.update(0, ImportTaskStatus.running);
      expect(progress.items.first.reason, isNull);
      progress.update(0, ImportTaskStatus.completed);
      expect(progress.count(ImportTaskStatus.completed), 1);
      expect(progress.count(ImportTaskStatus.unmatched), 1);
      expect(progress.failures, isEmpty);
    },
  );
}
