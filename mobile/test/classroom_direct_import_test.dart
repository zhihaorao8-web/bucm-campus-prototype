import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:campus_schedule/platform/classroom_access.dart';
import 'package:campus_schedule/platform/classroom_session_cache.dart';
import 'package:campus_schedule/platform/test_diagnostics.dart';
import 'package:campus_schedule/ui/classroom_course_page.dart';
import 'classroom_name_merge_test.dart' as names;
import 'classroom_recovery_page_test.dart' as fake;

class DirectController extends names.NameImportController {
  DirectController(this.outcome) {
    failSecond = false;
  }
  final String outcome;
  final requests = <String>[];
  @override
  Future<CallAsyncJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    Map<String, dynamic> arguments = const {},
    ContentWorld? contentWorld,
  }) async {
    final cmd =
        jsonDecode(
              RegExp(
                r'const command = (.*);',
              ).firstMatch(functionBody)!.group(1)!,
            )
            as Map;
    requests.add(cmd['action'] as String);
    final Map<String, dynamic> result;
    if (cmd['action'] == 'cancel') {
      result = {'state': 'cancelled'};
    } else if (outcome != 'success') {
      result = {'state': outcome};
    } else if (cmd['action'] == 'catalog') {
      result = {
        'state': 'catalog',
        'semester': names.local.semester,
        'courses': [names.source('a').toJson(), names.source('b').toJson()],
      };
    } else {
      result = {
        'state': 'records',
        ...names.single(cmd['id'] as String).pages.single.toJson(),
      };
    }
    return CallAsyncJavaScriptResult(value: jsonEncode(result));
  }
}

class AuthInterruptController extends DirectController {
  AuthInterruptController() : super('success');
  Completer<CallAsyncJavaScriptResult?>? pending;
  @override
  Future<CallAsyncJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    Map<String, dynamic> arguments = const {},
    ContentWorld? contentWorld,
  }) {
    if (pending == null && functionBody.contains('"action":"catalog"')) {
      pending = Completer<CallAsyncJavaScriptResult?>();
      return pending!.future;
    }
    return super.callAsyncJavaScript(
      functionBody: functionBody,
      arguments: arguments,
      contentWorld: contentWorld,
    );
  }
}

void main() {
  setUpAll(() async {
    for (final file in [
      'classroom.js',
      'classroom-entry.js',
      'recording-api.cjs',
      'recording-api-bridge.js',
    ]) {
      await rootBundle.loadString('assets/$file');
    }
  });
  testWidgets(
    'authentication during pending request survives late timeout and resumes',
    (tester) async {
      TestDiagnostics.shared.clear();
      final controller = AuthInterruptController();
      final library = names.CapturingNameLibrary();
      InAppWebViewPlatform.instance = fake.RecoveryPlatform(controller);
      await tester.pumpWidget(
        MaterialApp(
          home: ClassroomCoursePage(
            course: names.local,
            importCourses: [names.local],
            library: library,
            onDetails: (_) {},
            probe: (_) async => const AccessProbe(ProbeState.available),
          ),
        ),
      );
      Future<void> ticks(int n) async {
        for (var i = 0; i < n; i++) {
          await tester.pump(const Duration(seconds: 2));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
      }

      await ticks(4);
      expect(controller.pending, isNotNull);
      controller.pendingState = 'authentication';
      final params = controller.viewParams!;
      params.onTitleChanged?.call(
        params.controllerFromPlatform!(controller),
        '合成认证',
      );
      await ticks(3);
      controller.pending!.completeError(
        TimeoutException('SYNTHETIC_PRIVATE_ERROR'),
      );
      await ticks(3);
      expect(library.saves, 0);
      expect(find.text('学校录播目录未能完整读取，原目录保留。请重新连接后重试。'), findsNothing);
      expect(
        TestDiagnostics.shared.events.any(
          (e) => e['event'] == 'invalidResponse',
        ),
        isFalse,
      );
      expect(
        TestDiagnostics.shared.events.any((e) => e['event'] == 'cancelled'),
        isTrue,
      );
      controller.pendingState = null;
      await ticks(12);
      expect(library.saves, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      ClassroomSessionCache.shared.clear();
      expect(tester.takeException(), isNull);
    },
    skip: !const bool.fromEnvironment('CAMPUS_DIRECT_CATALOG'),
  );
  for (final outcome in ['success', 'unsupported', 'forbidden']) {
    testWidgets('experimental directory import: $outcome', (tester) async {
      TestDiagnostics.shared.clear();
      final controller = DirectController(outcome);
      final library = names.CapturingNameLibrary();
      InAppWebViewPlatform.instance = fake.RecoveryPlatform(controller);
      await tester.pumpWidget(
        MaterialApp(
          home: ClassroomCoursePage(
            course: names.local,
            importCourses: [names.local],
            library: library,
            onDetails: (_) {},
            probe: (_) async => const AccessProbe(ProbeState.available),
          ),
        ),
      );
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(seconds: 2));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      if (outcome == 'success') {
        expect(
          TestDiagnostics.shared.events.any((e) => e['event'] == 'directReady'),
          isTrue,
        );
        expect(
          TestDiagnostics.shared.events.any((e) => e['event'] == 'importSaved'),
          isTrue,
        );
        expect(library.saves, 1);
        expect(library.value.courses.length, 2);
        expect(controller.visited, isEmpty);
        expect(controller.requests, [
          'catalog',
          'records',
          'records',
          'cancel',
        ]);
      } else if (outcome == 'unsupported') {
        expect(
          TestDiagnostics.shared.events.any(
            (e) => e['event'] == 'fallbackUnsupported',
          ),
          isTrue,
        );
        expect(library.saves, 1);
        expect(controller.visited, ['a', 'b']);
      } else {
        expect(
          TestDiagnostics.shared.events.any(
            (e) => e['event'] == 'permissionDenied',
          ),
          isTrue,
        );
        expect(
          TestDiagnostics.shared.events.any((e) => e['event'] == 'importSaved'),
          isFalse,
        );
        expect(library.saves, 0);
        expect(controller.visited, isEmpty);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      ClassroomSessionCache.shared.clear();
      expect(tester.takeException(), isNull);
    }, skip: !const bool.fromEnvironment('CAMPUS_DIRECT_CATALOG'));
  }
}
