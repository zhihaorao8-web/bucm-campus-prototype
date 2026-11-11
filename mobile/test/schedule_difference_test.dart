import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'schedule_test.dart' show sample;

void main() {
  test('generated ids and source counts do not imply a timetable change', () {
    final changed = Course.fromJson(
      sample(id: 'regenerated').toJson()..['sourceCount'] = 9,
    );
    final diff = scheduleDifference([sample()], [changed]);
    expect(diff.unchanged, 1);
    expect(diff.adjusted, 0);
    expect(diff.added, 0);
  });
  test(
    'unique anchor adjustment retains teacher, location, weeks and segments in comparison',
    () {
      final changed = Course.fromJson(
        sample(id: 'new').toJson()
          ..['teacher'] = '新合成教师'
          ..['place'] = '新合成教室'
          ..['weeks'] = '2-16',
      );
      final diff = scheduleDifference([sample()], [changed]);
      expect(diff.adjusted, 1);
      expect(diff.unchanged, 0);
      expect(diff.removed, 0);
      expect(diff.added, 0);
    },
  );
  test(
    'ambiguous same-time rules and moves are not guessed as adjustments',
    () {
      final a = sample(id: 'a', weeks: '1-8'),
          b = sample(id: 'b', weeks: '9-16');
      final changed = sample(id: 'c', weeks: '2-15');
      final diff = scheduleDifference([a, b], [changed]);
      expect(diff.adjusted, 0);
      expect(diff.added, 1);
      expect(diff.removed, 2);
      final moved = Course.fromJson(sample().toJson()..['day'] = 2);
      final move = scheduleDifference([sample()], [moved]);
      expect(move.added, 1);
      expect(move.removed, 1);
      expect(move.adjusted, 0);
    },
  );
  test('first import and different semesters have no comparable baseline', () {
    final diff = scheduleDifference([sample(term: '2027-2028-1')], [sample()]);
    expect(diff.comparable, isFalse);
    expect(diff.label, contains('暂无同学期旧数据'));
  });
}
