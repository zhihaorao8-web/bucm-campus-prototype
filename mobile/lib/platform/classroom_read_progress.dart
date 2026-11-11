enum ClassroomReadStage { authentication, portal, platform, data }

/// A separate budget for each automatic stage. Human authentication has no
/// retry budget; callers only watch the current DOM while the app is active.
class ClassroomReadProgress {
  ClassroomReadStage? stage;
  int attempts = 0;

  bool advance(ClassroomReadStage next) {
    if (stage != next) {
      stage = next;
      attempts = 0;
    }
    if (next == ClassroomReadStage.authentication) return true;
    return ++attempts <= 20;
  }

  void reset() {
    stage = null;
    attempts = 0;
  }

  String get timeoutMessage => switch (stage) {
    ClassroomReadStage.portal => '尚未从 WebVPN 进入教学平台。可在官方页面手动进入，或点击继续导入重试。',
    ClassroomReadStage.platform => '尚未进入课程平台。请检查平台入口或弹窗，再点击继续导入。',
    _ => '课程数据读取超时。可点击继续导入重试，已导入内容保留。',
  };
}
