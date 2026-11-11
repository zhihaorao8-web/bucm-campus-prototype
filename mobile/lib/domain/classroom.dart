import 'schedule.dart';

String classroomName(String value) =>
    value.trim().replaceAll(RegExp(r'[\s\u00a0\u3000]+'), ' ');

/// Exact name within the timetable semester; no teacher/fuzzy/substring match.
/// A previously confirmed ID only disambiguates equally named courses.
ClassroomCourse? matchClassroomCourse(
  Course local,
  List<ClassroomCourse> catalog, {
  String? confirmedId,
}) {
  final matches = catalog.where((course) => course.matches(local)).toList();
  final remembered = matches
      .where((course) => course.id == confirmedId)
      .toList();
  final selected = remembered.length == 1
      ? remembered.single
      : matches.length == 1
      ? matches.single
      : null;
  if (selected == null ||
      catalog
              .where(
                (course) =>
                    course.semester == local.semester &&
                    course.id == selected.id,
              )
              .length !=
          1) {
    return null;
  }
  return selected;
}

String classroomText(dynamic value) {
  if (value is! String || value.length > 500) {
    throw const FormatException('学校字段格式不支持');
  }
  return value;
}

class ClassroomCourse {
  const ClassroomCourse({
    required this.id,
    required this.name,
    required this.teacher,
    required this.code,
    required this.group,
    required this.semester,
  });
  final String id, name, teacher, code, group, semester;
  factory ClassroomCourse.fromJson(Map<String, dynamic> json) {
    final result = ClassroomCourse(
      id: classroomText(json['id']),
      name: classroomText(json['name']),
      teacher: classroomText(json['teacher']),
      code: classroomText(json['code']),
      group: classroomText(json['group']),
      semester: classroomText(json['semester']),
    );
    if (result.id.isEmpty ||
        result.name.isEmpty ||
        !RegExp(r'^20\d{2}-20\d{2}-[12]$').hasMatch(result.semester)) {
      throw const FormatException('学校课程信息不完整');
    }
    return result;
  }
  bool matches(Course local) =>
      semester == local.semester &&
      classroomName(name) == classroomName(local.name);
}

class ClassroomRecording {
  const ClassroomRecording({
    required this.id,
    required this.label,
    required this.date,
    required this.place,
    required this.published,
  });
  final String id, label, place;
  final DateTime date;
  final bool published;
  factory ClassroomRecording.fromJson(Map<String, dynamic> json) {
    final id = classroomText(json['id']);
    final rawDate = classroomText(json['date']);
    final date = DateTime.tryParse(rawDate);
    if (id.isEmpty ||
        date == null ||
        isoDate(date) != rawDate ||
        json['published'] is! bool) {
      throw const FormatException('学校录播信息不完整');
    }
    return ClassroomRecording(
      id: id,
      label: classroomText(json['label']),
      date: date,
      place: classroomText(json['place']),
      published: json['published'] as bool,
    );
  }
}

class RecordingPage {
  RecordingPage.fromJson(Map<String, dynamic> json)
    : course = ClassroomCourse.fromJson(
        Map<String, dynamic>.from(json['course'] as Map),
      ),
      page = json['page'] as int,
      pageSize = json['pageSize'] as int,
      total = json['total'] as int,
      records = (json['records'] as List)
          .map(
            (v) => ClassroomRecording.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          )
          .toList() {
    if (page < 1 ||
        pageSize < 1 ||
        pageSize > 100 ||
        total < 0 ||
        records.length > pageSize ||
        records.map((v) => v.id).toSet().length != records.length) {
      throw const FormatException('录播分页信息不支持');
    }
    records.sort((a, b) => b.date.compareTo(a.date));
  }
  final ClassroomCourse course;
  final int page, pageSize, total;
  final List<ClassroomRecording> records;
  bool get hasNext => page * pageSize < total;
}
