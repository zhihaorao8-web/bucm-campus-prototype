import '../config/runtime_config.dart';
import '../config/playback_policy.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const classroomPlaybackChannel = MethodChannel(AppChannels.playback);

String classroomViewName(String kind) => switch (kind) {
  'ppt' => 'PPT',
  'teacher' => '教师',
  'student' => '学生',
  _ => '课堂画面',
};

/// Only display/control metadata crosses the channel. No URLs or credentials.
class ClassroomPlayerState {
  ClassroomPlayerState(Map<Object?, Object?> value)
    : session = value['session'] as String,
      main = value['main'] as String,
      small = value['small'] as String?,
      available = List<String>.from(value['available'] as List),
      textures = (value['textures'] as List)
          .map((v) => Map<String, Object?>.from(v as Map))
          .toList(),
      playing = value['playing'] == true,
      wanted = value['wanted'] == true,
      buffering = value['buffering'] == true,
      position = (value['position'] as num).toInt(),
      duration = (value['duration'] as num).toInt(),
      speed = (value['speed'] as num).toDouble(),
      watermark = value['watermark'] as String,
      error = value['error'] as String? {
    const kinds = {'ppt', 'teacher', 'student'};
    if (session.isEmpty ||
        session.length > 100 ||
        available.isEmpty ||
        available.length > 3 ||
        available.toSet().length != available.length ||
        !kinds.containsAll(available) ||
        !available.contains(main) ||
        (small != null && (!available.contains(small) || main == small)) ||
        watermark.length > 500 ||
        position < 0 ||
        duration < 0 ||
        !speed.isFinite ||
        speed < .5 ||
        speed > 3 ||
        textures.length > 2) {
      throw const FormatException('无效播放状态');
    }
    for (final item in textures) {
      final id = item['texture'];
      final ratio = item['ratio'];
      if (!available.contains(item['kind']) ||
          id is! int ||
          id < 0 ||
          ratio is! num ||
          !ratio.isFinite ||
          ratio <= 0 ||
          ratio > 10) {
        throw const FormatException('无效视频画面');
      }
    }
  }
  final String session, main, watermark;
  final String? small, error;
  final List<String> available;
  final List<Map<String, Object?>> textures;
  final bool playing, wanted, buffering;
  final int position, duration;
  final double speed;
  Map<String, Object?>? texture(String kind) {
    for (final item in textures) {
      if (item['kind'] == kind) return item;
    }
    return null;
  }
}

class ClassroomPlayerController extends ChangeNotifier {
  ClassroomPlayerController(
    this.state, {
    this.channel = classroomPlaybackChannel,
  });
  final MethodChannel channel;
  ClassroomPlayerState state;
  String? failure;
  Timer? _timer;
  bool _disposed = false, _reading = false;
  int _generation = 0;
  int _commands = 0;

  void start() {
    _timer ??= Timer.periodic(PlaybackPolicy.statePoll, (_) => refresh());
  }

  Future<void> refresh() async {
    if (_disposed || _reading || _commands > 0) return;
    _reading = true;
    try {
      await command('state');
    } finally {
      _reading = false;
    }
  }

  Future<void> command(
    String action, [
    Map<String, Object?> args = const {},
  ]) async {
    if (_disposed) return;
    final ticket = ++_generation;
    if (action != 'state') _commands++;
    try {
      final data = await channel.invokeMapMethod<Object?, Object?>(action, {
        'session': state.session,
        ...args,
      });
      if (_disposed || ticket != _generation) return;
      final next = ClassroomPlayerState(data!);
      if (next.session != state.session) throw const FormatException();
      state = next;
      failure = null;
    } catch (_) {
      if (_disposed || ticket != _generation) return;
      failure = '播放连接已中断，请返回录播列表重试。';
    } finally {
      if (action != 'state') _commands--;
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    unawaited(
      channel
          .invokeMethod<void>('dispose', {'session': state.session})
          .catchError((Object _) {}),
    );
    super.dispose();
  }
}
