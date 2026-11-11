import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/platform/classroom_policy.dart';

void main() {
  test('school VPN documents retain strict HTTPS navigation boundary', () {
    expect(
      classroomNavigation('https://webvpn.bucm.edu.cn/https/synthetic/cc/'),
      isTrue,
    );
    for (final url in [
      'http://webvpn.bucm.edu.cn/',
      'https://webvpn.bucm.edu.cn.evil.test/',
      'https://user@webvpn.bucm.edu.cn/',
      'https://webvpn.bucm.edu.cn:8880/',
    ]) {
      expect(classroomNavigation(url), isFalse);
    }
  });
  test('classroom separates media ports from authentication navigation', () {
    expect(classroomNavigation('https://qhz.bucm.edu.cn/cc/'), isTrue);
    expect(classroomNavigation('https://cas.bucm.edu.cn/'), isTrue);
    expect(classroomNavigation('https://qxkt4.bucm.edu.cn:8880/vod/'), isFalse);
    expect(classroomMedia('https://qxkt4.bucm.edu.cn:8880/vod/'), isTrue);
    expect(classroomMedia('https://qxkt2.bucm.edu.cn:8880/vod/'), isTrue);
    expect(classroomMedia('https://qxkt3.bucm.edu.cn:8880/vod/'), isTrue);
    for (final url in [
      'http://qxkt4.bucm.edu.cn:8880/vod/',
      'https://qxkt4.bucm.edu.cn.evil.test:8880/',
      'https://user@qxkt4.bucm.edu.cn:8880/',
      'https://qxkt4.bucm.edu.cn:8881/',
      'https://qxkt1.bucm.edu.cn:8880/vod/',
    ]) {
      expect(classroomMedia(url), isFalse);
    }
  });
}
