import '../config/runtime_config.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppPlatformInfo {
  const AppPlatformInfo({
    this.name = '校园课表',
    this.version = '',
    this.build = '',
    this.sdk = 0,
    this.systemAccent,
    this.source = '',
  });
  final String name, version, build;
  final int sdk;
  final int? systemAccent;
  final String source;
  String get buildType => kReleaseMode
      ? '发布构建'
      : kProfileMode
      ? '性能构建'
      : '调试构建';
  String get sourceLabel {
    if (!RegExp(r'^[0-9a-f]{40}(-modified)?$').hasMatch(source)) return '源码未知';
    return '源码 ${source.substring(0, 8)}${source.endsWith('-modified') ? ' · 含未提交修改' : ''}';
  }
}

const appChannel = MethodChannel(AppChannels.app);
final appInfoProvider = FutureProvider<AppPlatformInfo>((ref) async {
  final map = await appChannel.invokeMapMethod<String, dynamic>('info');
  if (map == null) throw PlatformException(code: 'NO_APP_INFO');
  return AppPlatformInfo(
    name: map['name'] as String,
    version: map['version'] as String,
    build: '${map['build']}',
    sdk: map['sdk'] as int,
    systemAccent: map['accent'] as int?,
    source: map['source'] as String? ?? '',
  );
});
Future<void> openProjectLink(String target) =>
    appChannel.invokeMethod<void>('openProjectLink', target);
