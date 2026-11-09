import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:campus_schedule/platform/school_adapter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'Android parses and validates a synthetic batch without a school session',
      (tester) async {
    final adapter = SchoolAdapter();
    const raw = '合成课程\n示例教师\n1-16(周)[01-02-03节]\n示例楼101室';
    final batch = await adapter.parseDom({
      'candidates': [
        {'text': raw, 'day': 1, 'rowLabel': ''},
        {'text': raw, 'day': 1, 'rowLabel': ''},
      ]
    }, '2026-2027-1');
    final courses =
        await adapter.validate(batch, '2026-2027-1', DateTime(2026, 9, 7));
    expect(batch.count, 2);
    expect(courses.length, 1);
    expect(courses.single.sourceCount, 2);
    expect(courses.single.teacher, '示例教师');
    expect(courses.single.segments.length, 2);
    expect(courses.single.segments.last.start, '10:30');
    await expectLater(
        adapter.validate(batch, '2026-2027-2', DateTime(2026, 9, 7)),
        throwsA(isA<PlatformException>()));
    await expectLater(
        adapter.validate(batch, '2026-2027-1', DateTime(2026, 9, 8)),
        throwsA(isA<PlatformException>()));
    // Check the native allowlist too; this fails before making any request.
    await expectLater(
        SchoolAdapter.channel.invokeMethod('download', {
          'url': 'https://bucm.edu.cn.evil.example/export',
          'userAgent': '',
          'semester': '',
        }),
        throwsA(isA<PlatformException>()));
  });
}
