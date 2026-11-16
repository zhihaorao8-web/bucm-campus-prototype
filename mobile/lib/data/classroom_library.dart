import '../config/classroom_limits.dart';
import '../config/storage_policy.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/classroom.dart';
import '../domain/schedule.dart';

/// Complete metadata pages only. Media descriptors and credentials never enter
/// this model or file. Incomplete imports cannot replace a previous archive.
enum RecordingAvailability { empty, unpublished, available }

class ClassroomArchive {
  ClassroomArchive._(this.pages, this.importedAt, this.sources);
  final List<ClassroomArchive>? sources;
  ClassroomArchive(List<RecordingPage> values, this.importedAt)
    : sources = null,
      pages = List.unmodifiable(values) {
    if (pages.isEmpty || pages.length > ClassroomLimits.pages) {
      throw const FormatException('录播分页数量不支持');
    }
    final first = pages.first;
    final expected = (first.total / first.pageSize).ceil().clamp(
      1,
      ClassroomLimits.pages,
    );
    final ids = <String>{};
    if (first.total > ClassroomLimits.records || pages.length != expected) {
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
        values.length > ClassroomLimits.sources ||
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
        values.fold<int>(0, (n, v) => n + v.total) > ClassroomLimits.records ||
        values.fold<int>(0, (n, v) => n + v.pages.length) >
            ClassroomLimits.pages) {
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
      if (sources.length > ClassroomLimits.sources ||
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
    if (values.length > ClassroomLimits.sources) throw const FormatException();
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
  final changes = ValueNotifier<int>(0);
  void _changed() => changes.value++;
  static String key(Course course) => jsonEncode([
    course.semester,
    course.id,
    classroomStoredName(course.name),
  ]);
  Future<File> _file() async {
    final folder = directory ?? await getApplicationSupportDirectory();
    await folder.create(recursive: true);
    return File('${folder.path}/${StoragePolicy.libraryFile}');
  }

  Future<Map<String, dynamic>> _read() async {
    final file = await _file();
    if (!await file.exists()) return {};
    if (await file.length() > StoragePolicy.libraryBytes) {
      throw const FormatException('录播目录文件过大');
    }
    final data = jsonDecode(await file.readAsString()) as Map;
    if (!const {1, 2}.contains(data['schema']) ||
        data['courses'] is! Map ||
        (data['courses'] as Map).length > ClassroomLimits.localCourses) {
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

  /// One local file read for an entire timetable. Missing entries stay unknown.
  Future<Map<String, RecordingAvailability>> availability(
    List<Course> courses,
  ) async {
    final revision = _revision;
    await _tail;
    final values = await _read();
    final exact = <String, ClassroomArchive>{};
    final names = <String, ClassroomArchive>{};
    String nameKey(Course course) =>
        jsonEncode([course.semester, classroomName(course.name)]);
    for (final entry in values.entries) {
      final archive = ClassroomArchive.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
      exact[entry.key] = archive;
      if (archive.nameMatched) {
        final key = jsonEncode([
          archive.course.semester,
          classroomName(archive.course.name),
        ]);
        if (names[key] == null ||
            names[key]!.importedAt.isBefore(archive.importedAt)) {
          names[key] = archive;
        }
      }
    }
    final output = <String, RecordingAvailability>{};
    for (final course in courses) {
      if (course.dataSource == 'synthetic') continue;
      final archive = exact[key(course)] ?? names[nameKey(course)];
      if (archive == null || !archive.course.matches(course)) continue;
      output[key(course)] = archive.total == 0
          ? RecordingAvailability.empty
          : archive.pages.any(
              (page) => page.records.any((record) => record.published),
            )
          ? RecordingAvailability.available
          : RecordingAvailability.unpublished;
    }
    return revision == _revision ? Map.unmodifiable(output) : const {};
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
      if (utf8.encode(content).length > StoragePolicy.libraryBytes) {
        throw const FormatException('录播目录文件过大');
      }
      final file = await _file();
      final temp = File('${file.path}.pending');
      try {
        await temp.writeAsString(content, flush: true);
        if (revision == _revision) {
          await temp.rename(file.path);
          _changed();
        }
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
        _changed();
      } finally {
        if (await temp.exists()) await temp.delete();
      }
    });
    _tail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> clear() {
    _revision++;
    _changed();
    final operation = _tail.then((_) async {
      final file = await _file();
      if (await file.exists()) await file.delete();
    });
    _tail = operation.catchError((Object _) {});
    return operation;
  }
}
