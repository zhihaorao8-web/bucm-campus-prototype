import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/platform/classroom_access.dart';

void main() {
  test('白屏恢复只接受已验证的cc入口，不转移查询参数或接受其他隧道', () {
    final target = dedicatedClassroomEntry(
      'https://qhz.bucm.edu.cn/cc/?synthetic=NEVER_EXPORT',
    );
    expect(
      target,
      'https://qhz.bucm.edu.cn/coursePlatform/#/courseCenter/index?firstMenuId=11',
    );
    expect(target, isNot(contains('NEVER_EXPORT')));
    expect(
      dedicatedClassroomEntry(
        'https://webvpn.bucm.edu.cn/https/77726476706e69737468656265737421e1ff5bd225256b5d300d8db9d6562d/cc/',
      ),
      startsWith(vpnEntry),
    );
    for (final invalid in [
      'http://qhz.bucm.edu.cn/cc/',
      'https://qhz.bucm.edu.cn.evil.test/cc/',
      'https://user@qhz.bucm.edu.cn/cc/',
      'https://webvpn.bucm.edu.cn/https/other/cc/',
      'https://webvpn.bucm.edu.cn/',
      'https://qhz.bucm.edu.cn/coursePlatform/',
    ]) {
      expect(dedicatedClassroomEntry(invalid), isNull);
    }
  });
  test('requires platform branding and script, not just status 200', () {
    expect(
      classifyProbe(
        classroomProbe,
        200,
        '<title>智慧教学平台</title><script src="app.js"></script>',
        null,
      ).reachable,
      isTrue,
    );
    expect(
      classifyProbe(
        vpnEntry,
        200,
        '<title>WebVPN</title><script></script>',
        null,
      ).reachable,
      isTrue,
    );
    for (final body in [
      '<title>酒店上网认证</title><script></script>',
      '<title>岐黄智</title>',
      '<h1>OK</h1>',
    ]) {
      expect(classifyProbe(classroomProbe, 200, body, null).reachable, isFalse);
    }
    expect(
      classifyProbe(
        classroomProbe,
        503,
        '<title>岐黄智</title><script></script>',
        null,
      ).reachable,
      isFalse,
    );
  });
  test(
    'CAS authentication redirect is reachable but not an authenticated session',
    () {
      expect(
        classifyProbe(
          classroomProbe,
          302,
          '',
          'https://cas.bucm.edu.cn/login',
        ).state,
        ProbeState.authentication,
      );
      for (final location in [
        'http://cas.bucm.edu.cn/',
        'https://cas.bucm.edu.cn.evil.test/',
        'https://user@cas.bucm.edu.cn/',
        'https://cas.bucm.edu.cn:8880/',
        '/unknown',
        null,
      ]) {
        expect(
          classifyProbe(classroomProbe, 302, '', location).reachable,
          isFalse,
        );
      }
    },
  );
  test(
    'direct succeeds without requesting VPN; fallback requires verified VPN',
    () async {
      final requested = <String>[];
      var result = await chooseClassroomAccess((url) async {
        requested.add(url);
        return const AccessProbe(ProbeState.available);
      });
      expect(result.url, directEntry);
      expect(requested, [classroomProbe]);
      requested.clear();
      result = await chooseClassroomAccess((url) async {
        requested.add(url);
        return AccessProbe(
          url == vpnEntry ? ProbeState.authentication : ProbeState.unavailable,
        );
      });
      expect(result.url, vpnEntry);
      expect(requested, [classroomProbe, vpnEntry]);
      result = await chooseClassroomAccess(
        (_) async => const AccessProbe(ProbeState.unexpected),
      );
      expect(result.url, isNull);
      expect(result.message, contains('暂未确认'));
      result = await chooseClassroomAccess(
        (_) async => const AccessProbe(ProbeState.certificateError),
      );
      expect(result.url, isNull);
      expect(result.message, contains('证书'));
    },
  );
  test('probe refuses arbitrary destinations before networking', () async {
    expect(
      (await probeClassroomEndpoint('https://example.com/')).state,
      ProbeState.unexpected,
    );
  });
}
