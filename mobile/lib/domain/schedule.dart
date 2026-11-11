import 'dart:math' as math;

// School wall-clock time, independent of the device timezone.
DateTime schoolNow([DateTime? instant]) {
  final wall = (instant ?? DateTime.now()).toUtc().add(
    const Duration(hours: 8),
  );
  return DateTime(
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
    wall.second,
  );
}

DateTime calendarAdd(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
int calendarDays(DateTime a, DateTime b) => DateTime.utc(
  a.year,
  a.month,
  a.day,
).difference(DateTime.utc(b.year, b.month, b.day)).inDays;
String isoDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String shortDate(DateTime date) => '${date.month}月${date.day}日';
String schoolTimestamp(DateTime instant) {
  final date = schoolNow(instant);
  return '${isoDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
int clockMinutes(String clock) {
  if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(clock)) {
    throw const FormatException('课程时间格式无效');
  }
  final parts = clock.split(':').map(int.parse).toList();
  return parts[0] * 60 + parts[1];
}

Set<int> parseWeeks(String input) {
  var text = input
      .replaceAll(RegExp(r'[第周()（）\s]'), '')
      .replaceAll(RegExp('[，、]'), ',')
      .replaceAll(RegExp('[－～—]'), '-');
  final odd = text.contains('单'), even = text.contains('双');
  if (odd && even) throw const FormatException('单双周不能同时指定');
  text = text.replaceAll(RegExp('[单双]'), '');
  if (!RegExp(r'^\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*$').hasMatch(text)) {
    throw const FormatException('周次格式无效');
  }
  final weeks = <int>{};
  for (final part in text.split(',')) {
    final ends = part.split('-').map(int.parse).toList();
    final start = ends.first, end = ends.last;
    if (start < 1 || end > 30 || start > end) {
      throw const FormatException('周次应在1至30之间');
    }
    for (var n = start; n <= end; n++) {
      if ((!odd || n.isOdd) && (!even || n.isEven)) weeks.add(n);
    }
  }
  if (weeks.isEmpty) throw const FormatException('课程没有实际教学周');
  return weeks;
}

class TeachingSegment {
  const TeachingSegment(this.start, this.end);
  final String start, end;
  factory TeachingSegment.fromJson(Map<String, dynamic> json) {
    final value = TeachingSegment(
      json['start'] as String,
      json['end'] as String,
    );
    if (clockMinutes(value.start) >= clockMinutes(value.end)) {
      throw const FormatException('课程起止时间无效');
    }
    return value;
  }
  Map<String, dynamic> toJson() => {'start': start, 'end': end};
}

class Course {
  Course({
    required this.id,
    required this.name,
    required this.teacher,
    required this.place,
    required this.day,
    required this.weeks,
    required this.periods,
    required this.segments,
    required this.semester,
    required this.termStart,
    this.online = false,
    this.sourceCount = 1,
    this.dataSource = 'unknown',
    this.timeSource = 'user-2026-11-09',
    this.deliverySource = 'school-page',
  });
  final String id,
      name,
      teacher,
      place,
      weeks,
      semester,
      dataSource,
      timeSource,
      deliverySource;
  final int day, sourceCount;
  final List<int> periods;
  final List<TeachingSegment> segments;
  final DateTime termStart;
  final bool online;
  Set<int> get weekSet => parseWeeks(weeks);
  int get maxWeek => weekSet.reduce(math.max);
  int weekAt(DateTime date) => (calendarDays(date, termStart) / 7).floor() + 1;
  bool occursOn(DateTime date) =>
      date.weekday == day && weekSet.contains(weekAt(date));
  factory Course.fromJson(Map<String, dynamic> json) {
    final start = DateTime.parse(json['termStart'] as String);
    if (start.weekday != DateTime.monday ||
        isoDate(start) != json['termStart']) {
      throw const FormatException('学期起点必须是有效的周一日期');
    }
    final course = Course(
      id: json['id'] as String,
      name: json['name'] as String,
      teacher: json['teacher'] as String? ?? '',
      place: json['place'] as String? ?? '',
      day: json['day'] as int,
      weeks: json['weeks'] as String,
      periods: (json['periods'] as List).cast<int>(),
      segments: (json['segments'] as List)
          .map(
            (s) =>
                TeachingSegment.fromJson(Map<String, dynamic>.from(s as Map)),
          )
          .toList(),
      semester: json['semester'] as String,
      termStart: start,
      online: json['online'] as bool? ?? false,
      sourceCount: json['sourceCount'] as int? ?? 1,
      dataSource: json['dataSource'] as String? ?? 'unknown',
      timeSource: json['timeSource'] as String? ?? 'user-2026-11-09',
      deliverySource: json['deliverySource'] as String? ?? 'school-page',
    );
    if (course.name.trim().isEmpty ||
        course.id.isEmpty ||
        course.day < 1 ||
        course.day > 7 ||
        course.segments.isEmpty ||
        course.periods.isEmpty ||
        course.periods.any((p) => p < 1 || p > 12) ||
        !RegExp(r'^20\d{2}-20\d{2}-[12]$').hasMatch(course.semester)) {
      throw const FormatException('课程信息不完整');
    }
    course.weekSet;
    for (var i = 1; i < course.segments.length; i++) {
      if (clockMinutes(course.segments[i - 1].end) >
          clockMinutes(course.segments[i].start)) {
        throw const FormatException('授课分段顺序无效');
      }
    }
    return course;
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'dataSource': dataSource,
    'name': name,
    'teacher': teacher,
    'place': place,
    'day': day,
    'weeks': weeks,
    'periods': periods,
    'segments': segments.map((s) => s.toJson()).toList(),
    'semester': semester,
    'termStart': isoDate(termStart),
    'online': online,
    'sourceCount': sourceCount,
    'timeSource': timeSource,
    'deliverySource': deliverySource,
  };
}

class Occurrence {
  const Occurrence(this.course, this.segment, this.date);
  final Course course;
  final TeachingSegment segment;
  final DateTime date;
  DateTime at(String clock) => DateTime(
    date.year,
    date.month,
    date.day,
    clockMinutes(clock) ~/ 60,
    clockMinutes(clock) % 60,
  );
  DateTime get start => at(segment.start);
  DateTime get end => at(segment.end);
  bool activeAt(DateTime now) => !now.isBefore(start) && now.isBefore(end);
  bool overlaps(Occurrence other) =>
      start.isBefore(other.end) && other.start.isBefore(end);
}

List<Occurrence> occurrencesOn(Iterable<Course> courses, DateTime date) =>
    [
      for (final course in courses)
        if (course.occursOn(date))
          for (final segment in course.segments)
            Occurrence(course, segment, date),
    ]..sort((a, b) {
      final time = a.start.compareTo(b.start);
      return time != 0 ? time : a.course.id.compareTo(b.course.id);
    });

List<Occurrence> nextOccurrences(Iterable<Course> courses, DateTime now) {
  final all = <Occurrence>[];
  for (final course in courses) {
    for (final week in course.weekSet) {
      final date = calendarAdd(
        course.termStart,
        (week - 1) * 7 + course.day - 1,
      );
      for (final segment in course.segments) {
        final event = Occurrence(course, segment, date);
        if (event.end.isAfter(now)) all.add(event);
      }
    }
  }
  all.sort((a, b) => a.start.compareTo(b.start));
  return all;
}

class ScheduleData {
  const ScheduleData({
    this.courses = const [],
    this.importedAt,
    this.summary = '',
    this.importedAtBySemester = const {},
    this.summaryBySemester = const {},
    this.isDemo = false,
  });
  final List<Course> courses;
  final DateTime? importedAt;
  final String summary;
  final bool isDemo;
  final Map<String, DateTime> importedAtBySemester;
  final Map<String, String> summaryBySemester;
  DateTime? lastImportFor(String semester) =>
      importedAtBySemester[semester] ??
      (semesters.length == 1 && semesters.single == semester
          ? importedAt
          : null);
  String summaryFor(String semester) =>
      summaryBySemester[semester] ??
      (semesters.length == 1 && semesters.single == semester ? summary : '');
  List<String> get semesters =>
      courses.map((c) => c.semester).toSet().toList()
        ..sort((a, b) => b.compareTo(a));
  factory ScheduleData.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != 1 && json['schema'] != 2) {
      throw const FormatException('不支持的课表存储版本');
    }
    return ScheduleData(
      courses: (json['courses'] as List)
          .map((c) => Course.fromJson(Map<String, dynamic>.from(c as Map)))
          .toList(),
      importedAt: json['importedAt'] == null
          ? null
          : DateTime.parse(json['importedAt'] as String),
      summary: json['summary'] as String? ?? '',
      importedAtBySemester: Map.unmodifiable(
        (json['importedAtBySemester'] as Map? ?? {}).map(
          (key, value) =>
              MapEntry(key as String, DateTime.parse(value as String)),
        ),
      ),
      summaryBySemester: Map.unmodifiable(
        Map<String, String>.from(json['summaryBySemester'] as Map? ?? {}),
      ),
    );
  }
  Map<String, dynamic> toJson() => {
    'schema': 2,
    'courses': courses.map((c) => c.toJson()).toList(),
    'importedAt': importedAt?.toIso8601String(),
    'summary': summary,
    'importedAtBySemester': importedAtBySemester.map(
      (key, value) => MapEntry(key, value.toIso8601String()),
    ),
    'summaryBySemester': summaryBySemester,
  };
  ScheduleData mergeImport(List<Course> incoming, String note, DateTime now) {
    if (isDemo || incoming.isEmpty) throw const FormatException('请退出示例后导入有效课表');
    final terms = incoming.map((c) => c.semester).toSet();
    if (terms.length != 1 ||
        incoming.map((c) => isoDate(c.termStart)).toSet().length != 1 ||
        incoming.map((c) => c.id).toSet().length != incoming.length) {
      throw const FormatException('本批课表的学期、起点或去重信息有冲突');
    }
    // Keep other semesters; only a complete validated batch replaces its semester.
    return ScheduleData(
      courses: [
        ...courses.where((c) => c.semester != terms.single),
        ...incoming,
      ],
      importedAt: now,
      summary: note,
      importedAtBySemester: Map.unmodifiable({
        for (final semester in semesters)
          if (lastImportFor(semester) != null)
            semester: lastImportFor(semester)!,
        terms.single: now,
      }),
      summaryBySemester: Map.unmodifiable({
        for (final semester in semesters) semester: summaryFor(semester),
        terms.single: note,
      }),
    );
  }
}
