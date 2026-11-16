import 'local_files.dart';
import '../config/storage_policy.dart';
import 'dart:convert';
import 'dart:io';
import '../domain/schedule.dart';

abstract interface class ScheduleRepository {
  Future<ScheduleData> load();
  Future<void> save(ScheduleData data);
}

abstract interface class RecoverableScheduleRepository
    implements ScheduleRepository {
  Future<ScheduleData?> loadBackup();
  Future<ScheduleData> restoreBackup();
  Future<void> clearStored();
}

class FileScheduleRepository implements RecoverableScheduleRepository {
  FileScheduleRepository({this.directory});
  final Directory? directory;
  Future<File> _file() =>
      applicationFile(StoragePolicy.scheduleFile, directory: directory);

  @override
  Future<ScheduleData> load() async {
    final file = await _file();
    if (!await file.exists()) return const ScheduleData();
    return _read(file);
  }

  Future<ScheduleData> _read(File file) async {
    if (await file.length() > StoragePolicy.scheduleBytes) {
      throw const FormatException('课表缓存超出限制');
    }
    return ScheduleData.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
  }

  @override
  Future<ScheduleData?> loadBackup() async {
    final backup = File('${(await _file()).path}.backup');
    return await backup.exists() ? _read(backup) : null;
  }

  @override
  Future<ScheduleData> restoreBackup() async {
    final backup = await loadBackup();
    if (backup == null) throw const FormatException('没有可恢复的有效备份');
    await save(backup);
    return backup;
  }

  @override
  Future<void> clearStored() async {
    final file = await _file();
    final base = file.uri.pathSegments.last;
    for (final entry in await file.parent.list(followLinks: false).toList()) {
      final name = entry.uri.pathSegments.last;
      if (entry is File &&
          (name == '$base.backup' ||
              name == '$base.backup.pending' ||
              name.startsWith('$base.damaged-'))) {
        await entry.delete();
      }
    }
    await writeAtomicText(file, jsonEncode(const ScheduleData().toJson()));
  }

  @override
  Future<void> save(ScheduleData data) async {
    if (data.isDemo) throw StateError('示例不能写入本人课表');
    final file = await _file();
    if (await file.exists()) {
      try {
        await _read(file);
        await writeAtomicText(
          File('${file.path}.backup'),
          await file.readAsString(),
        );
      } on FormatException {
        await file.copy(
          '${file.path}.damaged-${DateTime.now().microsecondsSinceEpoch}',
        );
      } on TypeError {
        await file.copy(
          '${file.path}.damaged-${DateTime.now().microsecondsSinceEpoch}',
        );
      }
    }
    await writeAtomicText(file, jsonEncode(data.toJson()));
  }
}
