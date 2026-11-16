import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/data/local_files.dart';

void main() {
  late Directory folder;
  late File file;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('synthetic-atomic-');
    file = await applicationFile('synthetic.json', directory: folder);
  });
  tearDown(() async => folder.delete(recursive: true));

  test('successful replacement preserves text and removes staging', () async {
    await file.writeAsString('synthetic old');
    expect(await writeAtomicText(file, 'synthetic 新内容'), isTrue);
    expect(await file.readAsString(), 'synthetic 新内容');
    expect(await pendingFile(file).exists(), isFalse);
  });

  test(
    'account guard runs after staging and rejects stale replacement',
    () async {
      await file.writeAsString('synthetic old');
      var guarded = false;
      expect(
        await writeAtomicText(
          file,
          'synthetic stale',
          canCommit: () {
            guarded = true;
            expect(pendingFile(file).readAsStringSync(), 'synthetic stale');
            return false;
          },
        ),
        isFalse,
      );
      expect(guarded, isTrue);
      expect(await file.readAsString(), 'synthetic old');
      expect(await pendingFile(file).exists(), isFalse);
    },
  );

  test(
    'failed staging preserves the old target and blocking directory',
    () async {
      await file.writeAsString('synthetic old');
      final blocking = Directory(pendingFile(file).path);
      await blocking.create();
      await expectLater(
        writeAtomicText(file, 'synthetic next'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await file.readAsString(), 'synthetic old');
      expect(await blocking.exists(), isTrue);
    },
  );

  test(
    'failed rename removes staging without removing target directory',
    () async {
      final target = Directory(file.path);
      await target.create();
      final sentinel = File('${target.path}/synthetic.txt');
      await sentinel.writeAsString('synthetic retained');
      await expectLater(
        writeAtomicText(file, 'synthetic next'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await sentinel.readAsString(), 'synthetic retained');
      expect(await pendingFile(file).exists(), isFalse);
    },
  );

  test(
    'guard failure propagates and cleans staging without replacing data',
    () async {
      await file.writeAsString('synthetic old');
      await expectLater(
        writeAtomicText(
          file,
          'synthetic next',
          canCommit: () {
            throw StateError('synthetic guard failure');
          },
        ),
        throwsStateError,
      );
      expect(await file.readAsString(), 'synthetic old');
      expect(await pendingFile(file).exists(), isFalse);
    },
  );
}
