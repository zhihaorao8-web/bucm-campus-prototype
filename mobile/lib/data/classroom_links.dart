import '../config/classroom_limits.dart';
import '../config/storage_policy.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../domain/schedule.dart';

/// Only explicit local-course -> platform-course IDs are persisted. Every use
/// must first revalidate against the current authenticated official catalog.
class ClassroomLinks {
  ClassroomLinks({this.directory});
  final Directory? directory;
  Future<void> _tail = Future.value();
  static final shared = ClassroomLinks();
  static String key(Course course) => jsonEncode([course.semester, course.id]);
  Future<File> _file() async {
    final folder = directory ?? await getApplicationSupportDirectory();
    await folder.create(recursive: true);
    return File('${folder.path}/${StoragePolicy.linksFile}');
  }

  Future<Map<String, String>> _read() async {
    final file = await _file();
    if (!await file.exists()) return {};
    if (await file.length() > StoragePolicy.linksBytes) {
      throw const FormatException('课程关联文件过大');
    }
    final json = jsonDecode(await file.readAsString()) as Map;
    if (json['schema'] != 1 || json['links'] is! Map) {
      throw const FormatException('课程关联文件格式不支持');
    }
    return Map<String, String>.from(json['links'] as Map);
  }

  Future<String?> lookup(Course course) async {
    await _tail;
    return (await _read())[key(course)];
  }

  Future<void> bind(Course course, String id) {
    final operation = _tail.then((_) async {
      if (id.isEmpty || id.length > ClassroomLimits.fieldLength) {
        throw const FormatException('学校课程标识无效');
      }
      final values = await _read();
      values[key(course)] = id;
      final file = await _file();
      final temp = File('${file.path}.pending');
      try {
        await temp.writeAsString(
          jsonEncode({'schema': 1, 'links': values}),
          flush: true,
        );
        await temp.rename(file.path);
      } finally {
        if (await temp.exists()) await temp.delete();
      }
    });
    _tail = operation.catchError((Object _) {});
    return operation;
  }
}
