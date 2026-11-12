/// Connection results are independent of the availability of a local archive.
enum ClassroomConnectionPhase {
  idle,
  connecting,
  authentication,
  portal,
  platform,
  reading,
  media,
  updated,
  unavailable,
  forbidden,
  failed,
  paused,
}

class ClassroomConnectionStatus {
  const ClassroomConnectionStatus(this.phase, [this.detail]);
  final ClassroomConnectionPhase phase;
  final String? detail;

  String get label => switch (phase) {
    ClassroomConnectionPhase.idle => '尚未检查本次连接',
    ClassroomConnectionPhase.connecting => '正在连接学校',
    ClassroomConnectionPhase.authentication => '需要本人认证',
    ClassroomConnectionPhase.portal => '正在进入学校门户',
    ClassroomConnectionPhase.platform => '正在进入课程平台',
    ClassroomConnectionPhase.reading => '正在读取录播目录',
    ClassroomConnectionPhase.media => '正在准备课堂视频',
    ClassroomConnectionPhase.updated => '目录更新完成',
    ClassroomConnectionPhase.unavailable => '学校服务暂时无法连接',
    ClassroomConnectionPhase.forbidden => '学校提示没有查看权限',
    ClassroomConnectionPhase.failed => '本次请求未完成',
    ClassroomConnectionPhase.paused => '本次连接已暂停',
  };

  bool get needsRecovery => switch (phase) {
    ClassroomConnectionPhase.authentication ||
    ClassroomConnectionPhase.unavailable ||
    ClassroomConnectionPhase.forbidden ||
    ClassroomConnectionPhase.failed ||
    ClassroomConnectionPhase.paused => true,
    _ => false,
  };
}
