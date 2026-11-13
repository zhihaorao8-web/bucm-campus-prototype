import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/platform/test_diagnostics.dart';
import 'package:campus_schedule/ui/test_diagnostics_page.dart';

void main() {
  test('bounded typed records export no raw error or arbitrary fields', () {
    final log = TestDiagnostics(enabled: true, capacity: 2);
    log.record(TestEvent.directoryStart, count: 3);
    log.failure('secret-token https://private.test');
    log.record(TestEvent.directReady, elapsedMs: -1, count: 999999);
    final data = jsonDecode(log.export()) as Map;
    expect(data['dropped'], 1);
    expect((data['events'] as List).length, 2);
    expect(log.events.first['event'], 'requestFailed');
    expect(log.events.last['elapsedMs'], 0);
    expect(log.events.last['count'], 10000);
    expect(log.export(), isNot(contains('secret-token')));
    expect(log.export(), isNot(contains('private.test')));
    expect(() => log.events.first['event'] = 'changed', throwsUnsupportedError);
    log.clear();
    expect(log.events, isEmpty);
  });
  test('disabled diagnostics do not collect events', () {
    final log = TestDiagnostics(enabled: false);
    log.record(TestEvent.directReady);
    log.failure('forbidden');
    expect(log.events, isEmpty);
  });
  testWidgets('small dark panel with large text remains operable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final log = TestDiagnostics(enabled: true);
    log.record(TestEvent.mediaNetwork);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentAppearanceProvider.overrideWithValue(
            const AppearanceSettings(),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: TestDiagnosticsPage(diagnostics: log),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('复制诊断记录'), findsOneWidget);
    expect(find.text('清空记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    log.dispose();
  });
  testWidgets('panel shows sanitized data, copies and clears', (tester) async {
    final log = TestDiagnostics(enabled: true);
    log.record(TestEvent.directReady, count: 2);
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentAppearanceProvider.overrideWithValue(
            const AppearanceSettings(),
          ),
        ],
        child: MaterialApp(home: TestDiagnosticsPage(diagnostics: log)),
      ),
    );
    expect(find.textContaining('directReady'), findsOneWidget);
    await tester.tap(find.text('复制诊断记录'));
    await tester.pumpAndSettle();
    expect(clipboard, contains('directReady'));
    await tester.tap(find.text('清空记录'));
    await tester.pumpAndSettle();
    expect(log.events, isEmpty);
    expect(find.textContaining('暂无记录'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    log.dispose();
  });
}
