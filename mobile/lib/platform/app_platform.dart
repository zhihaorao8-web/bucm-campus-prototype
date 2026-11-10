import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppPlatformInfo {
  const AppPlatformInfo({
    this.name = '校园课表',
    this.version = '',
    this.build = '',
    this.sdk = 0,
    this.systemAccent,
  });
  final String name, version, build;
  final int sdk;
  final int? systemAccent;
}

const appChannel = MethodChannel('cn.bucm.campus/app');
final appInfoProvider = FutureProvider<AppPlatformInfo>((ref) async {
  final map = await appChannel.invokeMapMethod<String, dynamic>('info');
  if (map == null) throw PlatformException(code: 'NO_APP_INFO');
  return AppPlatformInfo(
    name: map['name'] as String,
    version: map['version'] as String,
    build: '${map['build']}',
    sdk: map['sdk'] as int,
    systemAccent: map['accent'] as int?,
  );
});
Future<void> openProjectLink(String target) =>
    appChannel.invokeMethod<void>('openProjectLink', target);
