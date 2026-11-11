import 'dart:io';
import 'package:flutter/material.dart';
import 'ui_test.dart' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:campus_schedule/data/schedule_repository.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/application/schedule_controller.dart';
import 'schedule_test.dart' show sample, MemoryRepository;

class RecoveryMemory extends MemoryRepository
    implements RecoverableScheduleRepository {
  RecoveryMemory() : super(ScheduleData(courses: [sample()]));
  bool broken = true;
  @override
  Future<ScheduleData> load() async {
    if (broken) throw const FormatException('synthetic damaged primary');
    return value;
  }

  @override
  Future<ScheduleData?> loadBackup() async => value;
  @override
  Future<ScheduleData> restoreBackup() async {
    broken = false;
    return value;
  }

  @override
  Future<void> clearStored() async {
    value = const ScheduleData();
    broken = false;
  }
}

void main() {
  testWidgets(
    'reimport is primary; backup in more actions restores usable app',
    (tester) async {
      final repo = RecoveryMemory();
      await tester.pumpWidget(ui.app(repo));
      await tester.pumpAndSettle();
      expect(find.text('重新导入'), findsOneWidget);
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      expect(find.text('外观设置'), findsOneWidget);
      await tester.tap(find.text('今日').last);
      await tester.pumpAndSettle();
      expect(find.text('恢复备份'), findsNothing);
      await tester.tap(find.text('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复备份'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(find.text('重新导入'), findsNothing);
      expect(repo.broken, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('failed replacement retains primary and valid backup', () async {
    final dir = await Directory.systemTemp.createTemp('synthetic-recovery-');
    addTearDown(() => dir.delete(recursive: true));
    final repo = FileScheduleRepository(directory: dir);
    await repo.save(ScheduleData(courses: [sample()]));
    final file = File('${dir.path}/schedule-v1.json');
    final original = await file.readAsString();
    await Directory('${file.path}.pending').create();
    await expectLater(
      repo.save(ScheduleData(courses: [sample(id: 'new')])),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsString(), original);
    expect((await repo.loadBackup())!.courses.single.id, 'synthetic-1');
  });

  test(
    'damaged primary remains preserved; validated backup restores and explicit clear removes copies',
    () async {
      final dir = await Directory.systemTemp.createTemp('synthetic-recovery-');
      addTearDown(() => dir.delete(recursive: true));
      final repo = FileScheduleRepository(directory: dir);
      await repo.save(ScheduleData(courses: [sample()]));
      await repo.save(ScheduleData(courses: [sample(id: 'second')]));
      expect((await repo.loadBackup())!.courses.single.id, 'synthetic-1');
      final primary = File('${dir.path}/schedule-v1.json');
      await primary.writeAsString('synthetic damaged input');
      await expectLater(repo.load(), throwsFormatException);
      expect((await repo.restoreBackup()).courses.single.id, 'synthetic-1');
      final damaged = (await dir.list().toList())
          .whereType<File>()
          .where((f) => f.path.contains('.damaged-'))
          .single;
      expect(await damaged.readAsString(), 'synthetic damaged input');
      await repo.clearStored();
      expect((await repo.load()).courses, isEmpty);
      expect(await repo.loadBackup(), isNull);
      expect((await dir.list().toList()).length, 1);
    },
  );

  test(
    'invalid backup cannot replace unreadable primary; explicit recovery import can',
    () async {
      final dir = await Directory.systemTemp.createTemp('synthetic-recovery-');
      addTearDown(() => dir.delete(recursive: true));
      final primary = File('${dir.path}/schedule-v1.json');
      await primary.writeAsString('damaged synthetic');
      await File('${primary.path}.backup').writeAsString('invalid backup');
      final repo = FileScheduleRepository(directory: dir);
      await expectLater(repo.restoreBackup(), throwsFormatException);
      expect(await primary.readAsString(), 'damaged synthetic');
      final container = ProviderContainer(
        overrides: [repositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      await expectLater(
        container.read(scheduleProvider.future),
        throwsFormatException,
      );
      expect(
        container
            .read(scheduleProvider.notifier)
            .importBaseline(recoverUnreadable: true)
            .courses,
        isEmpty,
      );
      expect(
        () => container.read(scheduleProvider.notifier).importBaseline(),
        throwsStateError,
      );
      await expectLater(
        container.read(scheduleProvider.notifier).importBatch([
          sample(),
        ], 'synthetic'),
        throwsStateError,
      );
      await container
          .read(scheduleProvider.notifier)
          .importBatch([sample()], 'synthetic', recoverUnreadable: true);
      expect(
        container.read(scheduleProvider).requireValue.courses.single.id,
        'synthetic-1',
      );
      expect((await repo.load()).courses.length, 1);
    },
  );
}
