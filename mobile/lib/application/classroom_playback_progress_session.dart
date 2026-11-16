import '../config/playback_policy.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/classroom_playback_progress.dart';
import '../platform/classroom_player.dart';

class ClassroomPlaybackProgressSession extends ChangeNotifier {
  ClassroomPlaybackProgressSession({
    required this.player,
    required this.identity,
    required this.store,
    required this.canPlay,
  }) : revision = store.revision;
  final ClassroomPlayerController player;
  final ClassroomPlaybackIdentity identity;
  final ClassroomPlaybackProgressStore store;
  final bool Function() canPlay;
  final int revision;
  ClassroomPlaybackProgress? saved;
  bool ready = false, invalidated = false;
  bool _loaded = false,
      _active = false,
      _disposed = false,
      _writeFailed = false,
      _saving = false;
  bool _saveAgain = false;
  int? choicePosition;
  String? warning;
  Timer? _timer;
  Timer? _durationTimer;
  bool get blocked => !ready || invalidated;

  void start() {
    store.addListener(_cleared);
    player.addListener(_changed);
    _timer = Timer.periodic(
      PlaybackPolicy.saveInterval,
      (_) => unawaited(save()),
    );
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      saved = await store.lookup(identity);
    } catch (_) {
      warning = '本机进度未能读取，本次可从头播放。';
      _writeFailed = true;
    }
    if (_disposed || revision != store.revision) return;
    _loaded = true;
    if (saved == null ||
        !PlaybackPolicy.resumablePosition(saved!.position, saved!.duration)) {
      ready = true;
    }
    _changed();
    if (!ready && choicePosition == null) {
      _durationTimer = Timer(PlaybackPolicy.durationWait, () {
        if (_disposed || invalidated || ready || choicePosition != null) return;
        ready = true;
        warning = '暂未取得有效视频时长，本次可从头播放。';
        notifyListeners();
      });
    }
  }

  void _cleared() {
    if (_disposed || revision == store.revision) return;
    invalidated = true;
    _durationTimer?.cancel();
    choicePosition = null;
    warning = '学校会话已清除，请返回录播列表重新连接。';
    unawaited(player.command('pause'));
    notifyListeners();
  }

  void _changed() {
    if (_disposed || invalidated) return;
    if (ready && player.state.playing) _active = true;
    if (_loaded &&
        !ready &&
        choicePosition == null &&
        player.state.duration > 0 &&
        player.state.error == null &&
        player.failure == null) {
      choicePosition = saved?.resumePosition(player.state.duration);
      ready = choicePosition == null;
      if (!ready) unawaited(player.command('pause'));
    }
    if (ready || choicePosition != null) _durationTimer?.cancel();
    notifyListeners();
  }

  Future<void> choose({required bool resume}) async {
    final target = choicePosition;
    if (_disposed ||
        invalidated ||
        target == null ||
        revision != store.revision) {
      return;
    }
    await player.command('seek', {'position': resume ? target : 0});
    if (_disposed || invalidated || revision != store.revision) return;
    choicePosition = null;
    ready = true;
    _active = player.failure == null && player.state.error == null;
    notifyListeners();
    if (_active) {
      unawaited(save());
      if (!_disposed && !invalidated && canPlay()) await player.command('play');
    }
  }

  Future<void> save() async {
    if (_saving) {
      _saveAgain = true;
      return;
    }
    if (!_active ||
        blocked ||
        _writeFailed ||
        revision != store.revision ||
        player.failure != null ||
        player.state.error != null ||
        player.state.duration <= 0) {
      return;
    }
    _saving = true;
    try {
      final state = player.state;
      await store.save(
        identity,
        ClassroomPlaybackProgress(
          position: state.position.clamp(0, state.duration),
          duration: state.duration,
          updatedAt: DateTime.now().toUtc(),
        ),
        revision: revision,
      );
    } catch (_) {
      _writeFailed = true;
      warning = '本机进度未能保存，播放不受影响。';
      if (!_disposed) notifyListeners();
    } finally {
      _saving = false;
      if (_saveAgain) {
        _saveAgain = false;
        unawaited(save());
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _durationTimer?.cancel();
    store.removeListener(_cleared);
    player.removeListener(_changed);
    unawaited(save());
    _disposed = true;
    super.dispose();
  }
}
