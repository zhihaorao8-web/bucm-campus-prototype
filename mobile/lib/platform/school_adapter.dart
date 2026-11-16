import '../config/runtime_config.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../domain/schedule.dart';
import 'classroom_session_cache.dart';
import 'test_diagnostics.dart';
import '../data/classroom_library.dart';
import '../data/classroom_playback_progress.dart';

bool schoolUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      (uri.host == 'bucm.edu.cn' || uri.host.endsWith('.bucm.edu.cn'));
}

bool authenticationUrl(String value) {
  if (schoolUrl(value)) return true;
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      const {
        'open.weixin.qq.com',
        'work.weixin.qq.com',
        'login.work.weixin.qq.com',
        'open.work.weixin.qq.com',
      }.contains(uri.host);
}

class ParsedBatch {
  ParsedBatch(this.payload);
  final Map<String, dynamic> payload;
  String get semester => payload['semester'] as String? ?? '';
  bool get hasUnscheduled => payload['hasUnscheduled'] == true;
  int get count => (payload['candidates'] as List).length;
}

/// Transitional Android HSSF adapter. No credentials cross the Dart channel.
/// UI, persistence and calendar logic are Dart; iOS/Windows XLS adapters are pending.
class SchoolAdapter {
  static const channel = MethodChannel(AppChannels.school);
  Future<ParsedBatch> download(
    String url,
    String userAgent,
    String semester,
  ) async {
    if (!schoolUrl(url)) throw const FormatException('只允许学校 HTTPS 导出');
    final value = await channel.invokeMethod<String>('download', {
      'url': url,
      'userAgent': userAgent,
      'semester': semester,
    });
    return ParsedBatch(jsonDecode(value!) as Map<String, dynamic>);
  }

  Future<List<Course>> validate(
    ParsedBatch batch,
    String semester,
    DateTime monday,
  ) async {
    final value = await channel.invokeMethod<String>('validate', {
      'payload': jsonEncode(batch.payload),
      'semester': semester,
      'monday': isoDate(monday),
    });
    return (jsonDecode(value!) as List)
        .map((c) => Course.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<ParsedBatch> parseDom(
    Map<String, dynamic> table,
    String semester,
  ) async {
    final value = await channel.invokeMethod<String>('parseDom', {
      'table': jsonEncode(table),
      'semester': semester,
    });
    return ParsedBatch(jsonDecode(value!) as Map<String, dynamic>);
  }

  Future<void> clearSession() async {
    TestDiagnostics.shared.clear();
    ClassroomSessionCache.shared.clear();
    await Future.wait<void>([
      ClassroomLibrary.shared.clear(),
      ClassroomPlaybackProgressStore.shared.clear(),
      channel.invokeMethod<void>('clearSession'),
    ]);
  }
}
