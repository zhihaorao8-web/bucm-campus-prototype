import '../domain/classroom.dart';
import 'test_diagnostics.dart';

typedef RecordingApiCall =
    Future<Map<String, dynamic>> Function(Map<String, Object> command);

class ClassroomApiFailure implements Exception {
  const ClassroomApiFailure(this.state);
  final String state;
}

/// Opt-in directory transport; no navigation, persistence or playback authority.
class ClassroomApiReader {
  ClassroomApiReader(this.call, {TestDiagnostics? diagnostics})
    : diagnostics = diagnostics ?? TestDiagnostics.shared;
  final RecordingApiCall call;
  final TestDiagnostics diagnostics;

  Future<List<RecordingPage>?> read({
    required String semester,
    required List<ClassroomCourse> courses,
    required bool Function() active,
    Set<String> skipCourseIds = const {},
  }) async {
    void check() {
      if (!active()) throw const ClassroomApiFailure('cancelled');
    }

    Map<String, dynamic> checked(Map<String, dynamic> data, String state) {
      check();
      if (data['state'] != state) {
        throw ClassroomApiFailure(data['state'] as String? ?? 'error');
      }
      return data;
    }

    try {
      check();
      diagnostics.record(TestEvent.directoryStart, count: courses.length);
      diagnostics.record(TestEvent.catalogRequest);
      final catalogClock = Stopwatch()..start();
      final catalog = await call({'action': 'catalog', 'semester': semester});
      check();
      if (catalog['state'] == 'unsupported') {
        diagnostics.record(
          TestEvent.fallbackUnsupported,
          elapsedMs: catalogClock.elapsedMilliseconds,
        );
        return null;
      }
      checked(catalog, 'catalog');
      final fresh = (catalog['courses'] as List)
          .map(
            (v) =>
                ClassroomCourse.fromJson(Map<String, dynamic>.from(v as Map)),
          )
          .toList();
      diagnostics.record(
        TestEvent.catalogReady,
        elapsedMs: catalogClock.elapsedMilliseconds,
        count: fresh.length,
      );
      if (catalog['semester'] != semester ||
          fresh.any((c) => c.semester != semester) ||
          fresh.map((c) => c.id).toSet().length != fresh.length) {
        throw const ClassroomApiFailure('invalid-data');
      }
      final pages = <RecordingPage>[];
      final expectedIds = courses.map((c) => c.id).toSet();
      if (courses.isNotEmpty &&
          fresh
              .where(
                (c) =>
                    classroomName(c.name) == classroomName(courses.first.name),
              )
              .any((c) => !expectedIds.contains(c.id))) {
        throw const ClassroomApiFailure('catalog-changed');
      }
      for (final course in courses) {
        final matched = fresh.where((c) => c.id == course.id).toList();
        if (matched.length != 1 ||
            matched.single.toJson().toString() != course.toJson().toString()) {
          throw const ClassroomApiFailure('catalog-changed');
        }
        if (skipCourseIds.contains(course.id)) continue;
        int? total;
        final seen = <String>{};
        for (var page = 1; page <= 1000; page++) {
          check();
          diagnostics.record(TestEvent.pageRequest);
          final pageClock = Stopwatch()..start();
          final data = checked(
            await call({'action': 'records', 'id': course.id, 'page': page}),
            'records',
          );
          final value = RecordingPage.fromJson(data);
          if (value.course.id != course.id ||
              value.course.semester != semester ||
              value.page != page ||
              value.pageSize != 10 ||
              value.total > 10000 ||
              total != null && value.total != total) {
            throw const ClassroomApiFailure('invalid-data');
          }
          total = value.total;
          final expected = (total - (page - 1) * 10).clamp(0, 10);
          if (value.records.length != expected ||
              value.records.any((r) => !seen.add(r.id))) {
            throw const ClassroomApiFailure('invalid-data');
          }
          pages.add(value);
          diagnostics.record(
            TestEvent.pageReady,
            elapsedMs: pageClock.elapsedMilliseconds,
            count: value.records.length,
          );
          if (!value.hasNext) break;
          if (page == 1000) throw const ClassroomApiFailure('invalid-data');
        }
        if (seen.length != total) {
          throw const ClassroomApiFailure('invalid-data');
        }
      }
      check();
      diagnostics.record(TestEvent.directReady, count: pages.length);
      return pages;
    } on ClassroomApiFailure catch (e) {
      diagnostics.failure(e.state);
      rethrow;
    } catch (_) {
      diagnostics.record(TestEvent.invalidResponse);
      rethrow;
    } finally {
      // Tear down request context on completion and all error/cancellation paths.
      try {
        await call({'action': 'cancel'});
      } catch (_) {
        /* Page may have closed. */
      }
    }
  }
}
