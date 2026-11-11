import '../domain/classroom.dart';
import '../domain/schedule.dart';
import 'classroom_library.dart';

class ClassroomTimelineEntry {
  const ClassroomTimelineEntry(this.page, this.record);
  final RecordingPage page;
  final ClassroomRecording record;
  ClassroomCourse get course => page.course;
}

/// Display order is independent of the original school pagination. Playback
/// always retains both source identity and the original page.
List<ClassroomTimelineEntry> classroomTimeline(ClassroomArchive archive) {
  final entries = [
    for (final page in archive.pages)
      for (final record in page.records) ClassroomTimelineEntry(page, record),
  ];
  entries.sort((a, b) {
    final date = b.record.date.compareTo(a.record.date);
    if (date != 0) return date;
    final source = a.course.id.compareTo(b.course.id);
    return source != 0 ? source : a.record.id.compareTo(b.record.id);
  });
  return List.unmodifiable(entries);
}

List<ClassroomTimelineEntry> recordingsOnDate(
  List<ClassroomTimelineEntry> entries,
  DateTime date,
) => entries
    .where((entry) => isoDate(entry.record.date) == isoDate(date))
    .toList(growable: false);
