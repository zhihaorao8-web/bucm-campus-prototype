import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/data/classroom_links.dart';
import 'schedule_test.dart' show sample;

void main() {
  test(
    'explicit links survive reopen, serialize writes and keep corrupted file',
    () async {
      final dir = await Directory.systemTemp.createTemp('synthetic-classroom-');
      addTearDown(() => dir.delete(recursive: true));
      final repo = ClassroomLinks(directory: dir);
      await Future.wait([
        repo.bind(sample(id: 'one'), 'school-one'),
        repo.bind(sample(id: 'two'), 'school-two'),
      ]);
      final reopened = ClassroomLinks(directory: dir);
      expect(await reopened.lookup(sample(id: 'one')), 'school-one');
      expect(await reopened.lookup(sample(id: 'two')), 'school-two');
      await expectLater(
        repo.bind(sample(id: 'one'), ''),
        throwsFormatException,
      );
      expect(await repo.lookup(sample(id: 'one')), 'school-one');
      final file = File('${dir.path}/classroom-links-v1.json');
      await file.writeAsString('synthetic corrupt');
      await expectLater(repo.lookup(sample()), throwsFormatException);
      expect(await file.readAsString(), 'synthetic corrupt');
    },
  );
}
