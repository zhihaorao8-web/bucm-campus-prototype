import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/platform/classroom_read_progress.dart';

void main() {
  test('等待本人认证不会耗尽读取次数，进入门户后有独立预算', () {
    final progress = ClassroomReadProgress();
    for (var i = 0; i < 300; i++) {
      expect(progress.advance(ClassroomReadStage.authentication), isTrue);
    }
    expect(progress.attempts, 0);
    expect(progress.advance(ClassroomReadStage.portal), isTrue);
    expect(progress.attempts, 1);
  });
  test('门户、平台、数据分别计数，超时提示不再混淆', () {
    final progress = ClassroomReadProgress();
    for (final stage in [
      ClassroomReadStage.portal,
      ClassroomReadStage.platform,
      ClassroomReadStage.data,
    ]) {
      for (var i = 0; i < 20; i++) {
        expect(progress.advance(stage), isTrue);
      }
      expect(progress.advance(stage), isFalse);
      expect(
        progress.timeoutMessage,
        contains(switch (stage) {
          ClassroomReadStage.portal => 'WebVPN',
          ClassroomReadStage.platform => '入口',
          _ => '课程数据',
        }),
      );
    }
    progress.reset();
    expect(progress.advance(ClassroomReadStage.data), isTrue);
    expect(progress.attempts, 1);
  });
}
