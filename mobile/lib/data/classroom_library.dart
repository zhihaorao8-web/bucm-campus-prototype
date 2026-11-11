import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../domain/classroom.dart';
import '../domain/schedule.dart';

/// Complete metadata pages only. Media descriptors and credentials never enter
/// this model or file. Incomplete imports cannot replace a previous archive.
class ClassroomArchive {
  ClassroomArchive._(this.pages, this.importedAt, this.sources);
  final List<ClassroomArchive>? sources;
  ClassroomArchive(List<RecordingPage> values, this.importedAt)
    : sources = null,
      pages = List.unmodifiable(values) {
    if (pages.isEmpty || pages.length > 1000) {
      throw const FormatException('录播分页数量不支持');
    }
    final first = pages.first;
    final expected = (first.total / first.pageSize).ceil().clamp(1, 1000);
    final ids = <String>{};
    if (first.total > 10000 || pages.length != expected) {
      throw const FormatException('录播尚未完整导入');
    }
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      if (page.page != i + 1 ||
          page.course.id != first.course.id ||
          page.course.semester != first.course.semester ||
          page.total != first.total ||
          page.pageSize != first.pageSize ||
          page.records.length !=
              (i == pages.length - 1
                  ? first.total - i * first.pageSize
                  : first.pageSize) ||
          page.records.any((record) => !ids.add(record.id))) {
        throw const FormatException('录播分页已变化，请重新导入');
      }
    }
  }
  final List<RecordingPage> pages;
  final DateTime importedAt;
  bool get nameMatched => sources != null;
  List<ClassroomCourse> get courses =>
      (sources ?? [this]).map((v) => v.course).toList();
  factory ClassroomArchive.merge(
    List<ClassroomArchive> values,
    DateTime importedAt,
  ) {
    if (values.isEmpty ||
        values.length > 1000 ||
        values.any((v) => v.sources != null)) {
      throw const FormatException('同名课程目录不完整');
    }
    final first = values.first.course;
    if (values.map((v) => v.course.id).toSet().length != values.length ||
        values.any(
          (v) =>
              v.course.semester != first.semester ||
              classroomName(v.course.name) != classroomName(first.name),
        ) ||
        values.fold<int>(0, (n, v) => n + v.total) > 10000 ||
        values.fold<int>(0, (n, v) => n + v.pages.length) > 1000) {
      throw const FormatException('同名课程目录不一致');
    }
    final sorted = [...values]
      ..sort((a, b) => a.course.id.compareTo(b.course.id));
    return ClassroomArchive._(
      List.unmodifiable(sorted.expand((v) => v.pages)),
      importedAt,
      List.unmodifiable(sorted),
    );
  }
  ClassroomCourse get course => pages.first.course;
  int get total =>
      sources?.fold<int>(0, (n, v) => n + v.total) ?? pages.first.total;
  int displayPage(RecordingPage page) =>
      pages.indexWhere(
        (v) => v.course.id == page.course.id && v.page == page.page,
      ) +
      1;
  RecordingPage? sourcePage(String courseId, String recordId) => pages
      .where(
        (page) =>
            page.course.id == courseId &&
            page.records.any((r) => r.id == recordId),
      )
      .firstOrNull;
  Map<String, Object?> toJson() => {
    'importedAt': importedAt.toUtc().toIso8601String(),
    if (sources == null)
      'pages': pages.map((page) => page.toJson()).toList()
    else
      'sources': sources!.map((v) => v.toJson()).toList(),
  };
  factory ClassroomArchive.fromJson(Map<String, dynamic> json) {
    if (json['sources'] != null) {
      final sources = json['sources'] as List;
      if (sources.length > 1000 ||
          sources.any((v) => v is! Map || v.containsKey('sources'))) {
        throw const FormatException();
      }
      return ClassroomArchive.merge(
        sources
            .map(
              (v) => ClassroomArchive.fromJson(
                Map<String, dynamic>.from(v as Map),
              ),
            )
            .toList(),
        DateTime.parse(json['importedAt'] as String),
      );
    }
    final values = json['pages'] as List;
    if (values.length > 1000) throw const FormatException();
    return ClassroomArchive(
      List.unmodifiable(
        values.map(
          (value) =>
              RecordingPage.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
      DateTime.parse(json['importedAt'] as String),
    );
  }
}

class ClassroomLibrary {
  ClassroomLibrary({this.directory});
  static final shared = ClassroomLibrary();
  final Directory? directory;
  Future<void> _tail = Future.value();
  int _revision = 0;
  int get revision => _revision;
  static String key(Course course) =>
      jsonEncode([course.semester, course.id, classroomName(course.name)]);
  Future<File> _file() async {
    final folder = directory ?? await getApplicationSupportDirectory();
    await folder.create(recursive: true);
    return File('${folder.path}/classroom-library-v1.json');
  }

  Future<Map<String, dynamic>> _read() async {
    final file = await _file();
    if (!await file.exists()) return {};
    if (await file.length() > 8 * 1024 * 1024) {
      throw const FormatException('录播目录文件过大');
    }
    final data = jsonDecode(await file.readAsString()) as Map;
    if (!const {1, 2}.contains(data['schema']) ||
        data['courses'] is! Map ||
        (data['courses'] as Map).length > 1000) {
      throw const FormatException('录播目录格式不支持');
    }
    return Map<String, dynamic>.from(data['courses'] as Map);
  }

  Future<ClassroomArchive?> lookup(Course course) async {
    final revision = _revision;
    await _tail;
    final values = await _read();
    var value = values[key(course)];
    if (value == null) {
      final sameName =
          values.values
              .map(
                (v) => ClassroomArchive.fromJson(
                  Map<String, dynamic>.from(v as Map),
                ),
              )
              .where((v) => v.nameMatched && v.course.matches(course))
              .toList()
            ..sort((a, b) => b.importedAt.compareTo(a.importedAt));
      value = sameName.firstOrNull?.toJson();
    }
    if (value == null) return null;
    final archive = ClassroomArchive.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return revision == _revision && archive.course.matches(course)
        ? archive
        : null;
  }

  Future<void> save(
    Course course,
    ClassroomArchive archive, {
    required int revision,
  }) {
    final operation = _tail.then((_) async {
      if (revision != _revision) return;
      if ((archive.nameMatched
              ? !archive.course.matches(course)
              : archive.course.semester != course.semester) ||
          course.dataSource == 'synthetic') {
        throw const FormatException();
      }
      final values = await _read();
      final safe = ClassroomArchive.fromJson(archive.toJson());
      for (final key in values.keys.toList()) {
        final previous = ClassroomArchive.fromJson(
          Map<String, dynamic>.from(values[key] as Map),
        );
        if (previous.course.semester == safe.course.semester &&
            (safe.nameMatched
                ? classroomName(previous.course.name) ==
                      classroomName(safe.course.name)
                : previous.course.id == safe.course.id)) {
          values[key] = safe.toJson();
        }
      }
      values[key(course)] = safe.toJson();
      final content = jsonEncode({'schema': 2, 'courses': values});
      if (utf8.encode(content).length > 8 * 1024 * 1024) {
        throw const FormatException('录播目录文件过大');
      }
      final file = await _file();
      final temp = File('${file.path}.pending');
      try {
        await temp.writeAsString(content, flush: true);
        if (revision == _revision) await temp.rename(file.path);
      } finally {
        if (await temp.exists()) await temp.delete();
      }
    });
    _tail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> remove(Course course) {
    final operation = _tail.then((_) async {
      final values = await _read();
      if (values.remove(key(course)) == null) return;
      final file = await _file();
      final temp = File('${file.path}.pending');
      try {
        await temp.writeAsString(
          jsonEncode({'schema': 2, 'courses': values}),
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

  Future<void> clear() {
    _revision++;
    final operation = _tail.then((_) async {
      final file = await _file();
      if (await file.exists()) await file.delete();
    });
    _tail = operation.catchError((Object _) {});
    return operation;
  }
}
