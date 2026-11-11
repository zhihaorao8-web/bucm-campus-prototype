import 'dart:convert';
import '../domain/classroom.dart';
import '../domain/schedule.dart';

enum ImportTaskStatus {
  pending,
  running,
  completed,
  unmatched,
  failed,
  cancelled,
}

String importTaskStatusLabel(ImportTaskStatus status) => switch (status) {
  ImportTaskStatus.pending => '待处理',
  ImportTaskStatus.running => '进行中',
  ImportTaskStatus.completed => '完成',
  ImportTaskStatus.unmatched => '未匹配',
  ImportTaskStatus.failed => '失败',
  ImportTaskStatus.cancelled => '已取消',
};

class ClassroomImportItem {
  ClassroomImportItem(this.courses);
  final List<Course> courses;
  Course get course => courses.first;
  ImportTaskStatus status = ImportTaskStatus.pending;
  String? reason;
}

class ClassroomImportProgress {
  ClassroomImportProgress(List<Course> courses) {
    final grouped = <String, List<Course>>{};
    for (final course in courses) {
      grouped.putIfAbsent(key(course), () => []).add(course);
    }
    items = List.unmodifiable(
      grouped.values.map(
        (group) => ClassroomImportItem(List.unmodifiable(group)),
      ),
    );
  }
  late final List<ClassroomImportItem> items;
  static String key(Course course) =>
      jsonEncode([course.semester, classroomName(course.name)]);
  List<Course> get courses =>
      items.map((item) => item.course).toList(growable: false);
  int get totalLocalItems =>
      items.fold(0, (total, item) => total + item.courses.length);
  List<int> get failures => [
    for (var i = 0; i < items.length; i++)
      if (items[i].status == ImportTaskStatus.failed) i,
  ];
  void update(int index, ImportTaskStatus status, [String? reason]) {
    items[index].status = status;
    items[index].reason = reason;
  }

  int count(ImportTaskStatus status) =>
      items.where((item) => item.status == status).length;
}
