import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../domain/schedule.dart';

abstract interface class ScheduleRepository {
  Future<ScheduleData> load();
  Future<void> save(ScheduleData data);
}

class FileScheduleRepository implements ScheduleRepository {
  FileScheduleRepository({this.directory});
  final Directory? directory;
  Future<File> _file() async {
    final folder = directory ?? await getApplicationSupportDirectory();
    await folder.create(recursive: true);
    return File('${folder.path}/schedule-v1.json');
  }

  @override
  Future<ScheduleData> load() async {
    final file = await _file();
    if (!await file.exists()) return const ScheduleData();
    if (await file.length() > 8 * 1024 * 1024) {
      throw const FormatException('课表缓存超出限制');
    }
    return ScheduleData.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> save(ScheduleData data) async {
    if (data.isDemo) throw StateError('示例不能写入本人课表');
    final file = await _file();
    final temporary = File('${file.path}.pending');
    try {
      await temporary.writeAsString(jsonEncode(data.toJson()), flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
