import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'schedule_test.dart' show sample;

void main() {
  test(
    'new imports preserve per-semester timestamps and summaries across serialization',
    () {
      final first = DateTime.utc(2030, 9, 1, 3);
      final second = first.add(const Duration(days: 2));
      final data = const ScheduleData()
          .mergeImport([sample()], 'first', first)
          .mergeImport(
            [sample(id: 'other', term: '2027-2028-1')],
            'second',
            second,
          );
      final loaded = ScheduleData.fromJson(data.toJson());
      expect(loaded.lastImportFor('2026-2027-1'), first);
      expect(loaded.lastImportFor('2027-2028-1'), second);
      expect(loaded.summaryFor('2026-2027-1'), 'first');
      expect(loaded.summaryFor('2027-2028-1'), 'second');
      expect(schoolTimestamp(first), '2030-09-01 11:00');
    },
  );
  test(
    'legacy multi-semester timestamp stays unknown rather than assigned to all terms',
    () {
      final legacy =
          ScheduleData(
              courses: [
                sample(),
                sample(id: 'other', term: '2027-2028-1'),
              ],
              importedAt: DateTime.utc(2030, 9, 1),
            ).toJson()
            ..['schema'] = 1
            ..remove('importedAtBySemester')
            ..remove('summaryBySemester');
      final data = ScheduleData.fromJson(legacy);
      expect(data.lastImportFor('2026-2027-1'), isNull);
      final updated = data.mergeImport(
        [sample()],
        'new',
        DateTime.utc(2030, 9, 2),
      );
      expect(updated.lastImportFor('2027-2028-1'), isNull);
      expect(updated.lastImportFor('2026-2027-1'), DateTime.utc(2030, 9, 2));
    },
  );
}
