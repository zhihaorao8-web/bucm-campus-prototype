import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/platform/classroom_policy.dart';

void main() {
  test('classroom separates media ports from authentication navigation', () {
    expect(classroomNavigation('https://qhz.bucm.edu.cn/cc/'), isTrue);
    expect(classroomNavigation('https://cas.bucm.edu.cn/'), isTrue);
    expect(classroomNavigation('https://qxkt4.bucm.edu.cn:8880/vod/'), isFalse);
    expect(classroomMedia('https://qxkt4.bucm.edu.cn:8880/vod/'), isTrue);
    for (final url in [
      'http://qxkt4.bucm.edu.cn:8880/vod/',
      'https://qxkt4.bucm.edu.cn.evil.test:8880/',
      'https://user@qxkt4.bucm.edu.cn:8880/',
      'https://qxkt4.bucm.edu.cn:8881/',
    ]) {
      expect(classroomMedia(url), isFalse);
    }
  });
}
