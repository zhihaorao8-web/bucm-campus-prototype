import 'package:flutter/material.dart';
import '../data/classroom_library.dart';
import '../domain/schedule.dart';
import 'classroom_course_page.dart';

Future<void> openClassroomImport(
  BuildContext context,
  List<Course> courses,
) async {
  final unique = <String, Course>{
    for (final course in courses)
      if (course.dataSource != 'synthetic')
        ClassroomLibrary.key(course): course,
  }.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  if (unique.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('请先导入当前学期的本人课表。')));
    return;
  }
  await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => ClassroomCoursePage(
        course: unique.first,
        importCourses: List.unmodifiable(unique),
        onDetails: (_) {},
      ),
    ),
  );
}
