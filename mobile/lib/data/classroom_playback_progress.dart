import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class ClassroomPlaybackIdentity {
  ClassroomPlaybackIdentity({
    required this.semester,
    required this.courseId,
    required this.recordId,
  }) {
    if ([semester, courseId, recordId].any(
      (v) =>
          v.trim().isEmpty ||
          v.length > 500 ||
          RegExp(r'[\x00-\x1f]').hasMatch(v),
    )) {
      throw const FormatException('无效录播标识');
    }
  }
  final String semester, courseId, recordId;
  String get key => jsonEncode([semester, courseId, recordId]);
  factory ClassroomPlaybackIdentity.fromKey(String key) {
    final fields = List<String>.from(jsonDecode(key) as List);
    if (fields.length != 3) throw const FormatException('无效录播标识');
    return ClassroomPlaybackIdentity(
      semester: fields[0],
      courseId: fields[1],
      recordId: fields[2],
    );
  }
}

class ClassroomPlaybackProgress {
  ClassroomPlaybackProgress({
    required this.position,
    required this.duration,
    required this.updatedAt,
  }) {
    if (position < 0 ||
        duration <= 0 ||
        position > duration ||
        duration > 7 * 24 * 3600000) {
      throw const FormatException('无效本机进度');
    }
  }
  final int position, duration;
  final DateTime updatedAt;
  int? resumePosition(int currentDuration) =>
      currentDuration > 0 &&
          (duration - currentDuration).abs() <= 2000 &&
          position >= 10000 &&
          duration - position >= 30000 &&
          currentDuration - position >= 30000
      ? position
      : null;
  Map<String, Object> toJson() => {
    'position': position,
    'duration': duration,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
  factory ClassroomPlaybackProgress.fromJson(Map value) =>
      ClassroomPlaybackProgress(
        position: value['position'] as int,
        duration: value['duration'] as int,
        updatedAt: DateTime.parse(value['updatedAt'] as String),
      );
}

/// Only local record identifiers, timing and timestamps. Never media URLs or
/// session/credential data. Epochs prevent writes from a cleared account.
class ClassroomPlaybackProgressStore extends ChangeNotifier {
  ClassroomPlaybackProgressStore({this.directory});
  static final shared = ClassroomPlaybackProgressStore();
  final Directory? directory;
  Future<void> _tail = Future.value();
  int _revision = 0;
  int get revision => _revision;

  Future<File> _file() async {
    final folder = directory ?? await getApplicationSupportDirectory();
    await folder.create(recursive: true);
    return File('${folder.path}/classroom-progress-v1.json');
  }

  Future<Map<String, ClassroomPlaybackProgress>> _read() async {
    final file = await _file();
    if (!await file.exists()) return {};
    if (await file.length() > 2 * 1024 * 1024) {
      throw const FormatException('本机进度文件过大');
    }
    final data = jsonDecode(await file.readAsString()) as Map;
    if (data['schema'] != 1 ||
        data['records'] is! Map ||
        (data['records'] as Map).length > 2000) {
      throw const FormatException('本机进度格式不支持');
    }
    final values = <String, ClassroomPlaybackProgress>{};
    for (final item in (data['records'] as Map).entries) {
      final identity = ClassroomPlaybackIdentity.fromKey(item.key as String);
      if (identity.key != item.key) throw const FormatException('本机进度标识不一致');
      values[identity.key] = ClassroomPlaybackProgress.fromJson(
        item.value as Map,
      );
    }
    return values;
  }

  Future<ClassroomPlaybackProgress?> lookup(
    ClassroomPlaybackIdentity identity,
  ) async {
    final revision = _revision;
    await _tail;
    final result = (await _read())[identity.key];
    return revision == _revision ? result : null;
  }

  Future<void> save(
    ClassroomPlaybackIdentity identity,
    ClassroomPlaybackProgress progress, {
    required int revision,
  }) {
    final operation = _tail.then((_) async {
      if (revision != _revision) return;
      final values = await _read();
      if (revision != _revision) return;
      values[identity.key] = progress;
      // Bound metadata growth, retaining the most recently updated records.
      final sorted = values.entries.toList()
        ..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));
      final content = jsonEncode({
        'schema': 1,
        'records': {
          for (final entry in sorted.take(2000))
            entry.key: entry.value.toJson(),
        },
      });
      if (utf8.encode(content).length > 2 * 1024 * 1024) {
        throw const FormatException('本机进度文件过大');
      }
      final file = await _file();
      final pending = File('${file.path}.pending');
      try {
        await pending.writeAsString(content, flush: true);
        if (revision == _revision) await pending.rename(file.path);
      } finally {
        if (await pending.exists()) await pending.delete();
      }
    });
    _tail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> clear() {
    _revision++;
    notifyListeners();
    final operation = _tail.then((_) async {
      final file = await _file();
      if (await file.exists()) await file.delete();
      final pending = File('${file.path}.pending');
      if (await pending.exists()) await pending.delete();
    });
    _tail = operation.catchError((Object _) {});
    return operation;
  }
}
