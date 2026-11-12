import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/application/classroom_import_collection.dart';
import 'package:campus_schedule/domain/classroom.dart';
import 'classroom_name_merge_test.dart' show source, single;

void main() {
  final now = DateTime.utc(2026, 1, 1);
  test('partial group cannot merge; retry reuses only complete sources', () {
    final collection = ClassroomImportCollection();
    collection.prepare([source('a'), source('b')]);
    collection.addPage(single('a').pages.single, now);
    expect(collection.complete, isFalse);
    expect(() => collection.merge(now), throwsFormatException);
    collection.reset();
    collection.prepare([source('a'), source('b')]);
    expect(collection.sourceIndex, 1);
    expect(collection.nextSource.id, 'b');
    collection.addPage(single('b').pages.single, now);
    expect(collection.merge(now).courses.map((c) => c.id), ['a', 'b']);
  });
  test(
    'changed source order rejects reuse; out of order page requests missing page',
    () {
      final collection = ClassroomImportCollection();
      collection.prepare([source('a'), source('b')]);
      expect(
        () => collection.prepare([source('b'), source('a')]),
        throwsFormatException,
      );
      final wrong = RecordingPage.fromJson(
        single('a').pages.single.toJson()..['page'] = 2,
      );
      expect(collection.addPage(wrong, now), 1);
      expect(collection.pages, isEmpty);
      expect(collection.completed, isEmpty);
    },
  );
}
