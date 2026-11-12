import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:campus_schedule/platform/classroom_access.dart';
import 'package:campus_schedule/platform/classroom_session_cache.dart';
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
  for (final outcome in ['success', 'unsupported', 'forbidden']) {
    testWidgets('experimental directory import: $outcome', (tester) async {
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
        expect(library.saves, 1);
        expect(controller.visited, ['a', 'b']);
      } else {
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
