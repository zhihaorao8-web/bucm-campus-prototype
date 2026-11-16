import 'dart:async';
import 'package:flutter/services.dart';
import '../config/playback_policy.dart';
import '../platform/classroom_player.dart';
import '../platform/test_diagnostics.dart';

/// A per-operation preparation lease. Until handoff, this object owns cleanup
/// of an acquired native session. Navigation/visible authentication stay in UI.
class ClassroomPlaybackPreparation {
  ClassroomPlaybackPreparation({
    required this.command,
    required this.active,
    this.channel = classroomPlaybackChannel,
    TestDiagnostics? diagnostics,
  }) : diagnostics = diagnostics ?? TestDiagnostics.shared;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) command;
  final bool Function() active;
  final MethodChannel channel;
  final TestDiagnostics diagnostics;
  ClassroomPlayerState? _prepared;
  bool _handedOff = false;

  Future<ClassroomPlayerState?> prepare(Object view, String recordId) async {
    diagnostics.record(TestEvent.mediaPrepare);
    await channel.invokeMethod<void>('begin', {
      'view': view,
      'record': recordId,
    });
    if (!active()) return null;
    final response = await command({'action': 'play', 'id': recordId});
    if (response['state'] != 'opening') throw const FormatException();
    final data = await channel
        .invokeMapMethod<Object?, Object?>('prepare')
        .timeout(PlaybackPolicy.prepareTimeout);
    _prepared = ClassroomPlayerState(data!);
    diagnostics.record(TestEvent.mediaReady);
    return _prepared;
  }

  void handoff() => _handedOff = true;

  Future<void> release() async {
    if (!_handedOff && _prepared != null) {
      await channel
          .invokeMethod<void>('dispose', {'session': _prepared!.session})
          .catchError((Object _) {});
    }
    await channel.invokeMethod<void>('cancel').catchError((Object _) {});
  }

  static String failureMessage(Object error) => error is TimeoutException
      ? '学校视频加载超时，请稍后重试。'
      : switch (error is PlatformException ? error.code : '') {
          'NO_VIEW' => '未能读取当前学校页面，请重新打开课程页面。',
          'UNTRUSTED_PAGE' => '请先在官方页面进入学校课程平台。',
          'PREPARE' => '学校播放页面尚未就绪，请刷新录播列表后重试。',
          'POLICY' => '学校媒体或水印配置未能完整读取，请检查官方登录状态。',
          'WATERMARK' => '学校水印配置未能完整读取，请稍后重试。',
          'MEDIA_BOUNDARY' => '学校媒体的访问路径尚未匹配，请返回后重试。',
          'MEDIA_NETWORK' => '学校媒体请求失败，请检查网络后重试。',
          'OFFICIAL_STOP' => '学校页面未能停止播放，请关闭后重新连接。',
          'SCRIPT' => '当前学校页面暂不支持读取播放信息，请刷新后重试。',
          'MEDIA' => '学校媒体暂时无法初始化，请返回后重试。',
          _ => '未能准备课堂视频，请检查官方登录状态后重试。',
        };
}
