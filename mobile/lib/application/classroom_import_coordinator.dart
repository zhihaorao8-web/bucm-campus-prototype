import '../data/classroom_library.dart';
import '../domain/classroom.dart';
import '../domain/schedule.dart';
import '../platform/classroom_api_reader.dart';
import '../platform/test_diagnostics.dart';
import 'classroom_import_collection.dart';

enum DirectoryCollectionResult { ready, unsupported, cancelled }

/// Owns one name group's verified pages and guarded commit. The page decides
/// when to show authentication, navigate a source, or advance the bulk queue.
class ClassroomImportCoordinator {
  ClassroomImportCoordinator({
    required this.library,
    DateTime Function()? clock,
    TestDiagnostics? diagnostics,
  }) : revision = library.revision,
       clock = clock ?? DateTime.now,
       diagnostics = diagnostics ?? TestDiagnostics.shared;
  final ClassroomLibrary library;
  final int revision;
  final DateTime Function() clock;
  final TestDiagnostics diagnostics;
  final collection = ClassroomImportCollection();

  Future<DirectoryCollectionResult> readDirect({
    required String semester,
    required List<ClassroomCourse> courses,
    required RecordingApiCall call,
    required bool Function() active,
  }) async {
    final pages = await ClassroomApiReader(call, diagnostics: diagnostics).read(
      semester: semester,
      courses: courses,
      skipCourseIds: collection.completed.keys.toSet(),
      active: active,
    );
    if (!active()) return DirectoryCollectionResult.cancelled;
    if (pages == null) return DirectoryCollectionResult.unsupported;
    for (final page in pages) {
      collection.addPage(page, clock());
    }
    return DirectoryCollectionResult.ready;
  }

  Future<ClassroomArchive?> commit(
    Course course, {
    bool Function()? active,
  }) async {
    final saved = collection.merge(clock());
    try {
      await library.save(course, saved, revision: revision);
    } catch (_) {
      diagnostics.record(TestEvent.importSaveFailed);
      rethrow;
    }
    if (active != null && !active()) return null;
    if (revision != library.revision) throw const FormatException();
    diagnostics.record(TestEvent.importSaved);
    return saved;
  }
}
