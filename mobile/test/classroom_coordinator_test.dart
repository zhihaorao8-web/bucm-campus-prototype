import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/application/classroom_connection_coordinator.dart';
import 'package:campus_schedule/application/classroom_import_coordinator.dart';
import 'package:campus_schedule/config/classroom_limits.dart';
import 'package:campus_schedule/data/classroom_library.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/platform/classroom_access.dart';
import 'package:campus_schedule/platform/classroom_api_reader.dart';
import 'package:campus_schedule/platform/classroom_read_progress.dart';
import 'classroom_name_merge_test.dart' show source, single, local;

class GuardedLibrary extends ClassroomLibrary {
  ClassroomArchive value = single('old');
  int epoch = 0, saves = 0;
  bool fail = false;
  Completer<void>? pending;
  @override
  int get revision => epoch;
  @override
  Future<void> save(
    Course course,
    ClassroomArchive archive, {
    required int revision,
  }) async {
    if (pending != null) await pending!.future;
    if (fail) throw StateError('synthetic write failure');
    if (revision != epoch) return;
    value = archive;
    saves++;
  }
}

void main() {
  test(
    'late automatic route cannot replace a newer explicit selection',
    () async {
      final reply = Completer<AccessProbe>();
      final connection = ClassroomConnectionCoordinator(
        probe: (_) => reply.future,
      );
      addTearDown(connection.dispose);
      final old = connection.select(
        ClassroomAccess.automatic,
        ticket: connection.advance(),
      );
      final current = await connection.select(
        ClassroomAccess.vpn,
        ticket: connection.advance(),
      );
      reply.complete(const AccessProbe(ProbeState.available));
      expect(await old, isNull);
      expect(current!.mode, ClassroomAccess.vpn);
    },
  );

  test('reachable official authentication keeps direct access', () async {
    final probes = <String>[];
    final connection = ClassroomConnectionCoordinator(
      probe: (url) async {
        probes.add(url);
        return const AccessProbe(ProbeState.authentication);
      },
    );
    addTearDown(connection.dispose);
    final decision = await connection.select(
      ClassroomAccess.automatic,
      ticket: connection.advance(),
    );
    expect(decision!.mode, ClassroomAccess.direct);
    expect(probes, [classroomProbe]);
  });

  testWidgets('replacing and disposing polls cancels stale callbacks', (
    tester,
  ) async {
    final connection = ClassroomConnectionCoordinator();
    var reads = 0;
    connection.schedulePoll(
      ClassroomReadStage.authentication,
      () => reads += 10,
    );
    connection.schedulePoll(null, () => reads++);
    await tester.pump(ClassroomLimits.dataPoll);
    expect(reads, 1);
    connection.schedulePoll(ClassroomReadStage.authentication, () => reads++);
    connection.dispose();
    await tester.pump(ClassroomLimits.authenticationPoll);
    expect(reads, 1);
    expect(connection.current(connection.generation), isFalse);
  });

  test('partial source group and failed save keep previous archive', () async {
    final library = GuardedLibrary();
    final coordinator = ClassroomImportCoordinator(library: library);
    coordinator.collection.prepare([source('a'), source('b')]);
    coordinator.collection.addPage(
      single('a').pages.single,
      DateTime.utc(2026),
    );
    await expectLater(coordinator.commit(local), throwsFormatException);
    expect(library.saves, 0);
    coordinator.collection.addPage(
      single('b').pages.single,
      DateTime.utc(2026),
    );
    library.fail = true;
    await expectLater(coordinator.commit(local), throwsStateError);
    expect(library.value.course.id, 'old');
    library.fail = false;
    final saved = await coordinator.commit(local);
    expect(saved!.courses.map((course) => course.id), ['a', 'b']);
    expect(library.saves, 1);
  });

  test('account revision invalidates a pending group commit', () async {
    final library = GuardedLibrary()..pending = Completer<void>();
    final coordinator = ClassroomImportCoordinator(library: library);
    coordinator.collection.prepare([source('a')]);
    coordinator.collection.addPage(
      single('a').pages.single,
      DateTime.utc(2026),
    );
    final result = coordinator.commit(local);
    library.epoch++;
    library.pending!.complete();
    await expectLater(result, throwsFormatException);
    expect(library.saves, 0);
    expect(library.value.course.id, 'old');
  });

  test(
    'direct transport unsupported or cancelled leaves collection untouched',
    () async {
      final coordinator = ClassroomImportCoordinator(library: GuardedLibrary());
      coordinator.collection.prepare([source('a')]);
      final commands = <String>[];
      final result = await coordinator.readDirect(
        semester: local.semester,
        courses: [source('a')],
        active: () => true,
        call: (command) async {
          commands.add(command['action'] as String);
          return {'state': 'unsupported'};
        },
      );
      expect(result, DirectoryCollectionResult.unsupported);
      expect(commands, ['catalog', 'cancel']);
      await expectLater(
        coordinator.readDirect(
          semester: local.semester,
          courses: [source('a')],
          active: () => false,
          call: (_) async => {},
        ),
        throwsA(
          isA<ClassroomApiFailure>().having(
            (e) => e.state,
            'state',
            'cancelled',
          ),
        ),
      );
      expect(coordinator.collection.completed, isEmpty);
    },
  );
}
