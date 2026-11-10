import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/platform/classroom_access.dart';
import 'package:campus_schedule/ui/classroom_browser.dart';

void main() {
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
  testWidgets(
    'unavailable paths keep retry and manual choices on small large-text screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: ClassroomBrowser(
            probe: (_) async => const AccessProbe(ProbeState.unavailable),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('重新检测访问路径'), findsOneWidget);
      await tester.tap(find.byTooltip('学校访问方式'));
      await tester.pumpAndSettle();
      expect(find.text('自动选择（重新检测）'), findsOneWidget);
      expect(find.text('数字北中医（直接访问）'), findsOneWidget);
      expect(find.text('校外访问（学校 WebVPN）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'finishing a probe after leaving does not update a disposed route',
    (tester) async {
      final pending = Completer<AccessProbe>();
      await tester.pumpWidget(
        MaterialApp(home: ClassroomBrowser(probe: (_) => pending.future)),
      );
      await tester.pumpWidget(const SizedBox());
      pending.complete(const AccessProbe(ProbeState.unavailable));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
