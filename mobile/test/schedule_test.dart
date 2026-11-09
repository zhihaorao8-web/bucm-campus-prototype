import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:campus_schedule/application/schedule_controller.dart';
import 'package:campus_schedule/data/schedule_repository.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/platform/school_adapter.dart';
import 'package:campus_schedule/ui/week_grid.dart';

Course sample({
  String id = 'synthetic-1',
  String term = '2026-2027-1',
  String weeks = '1-16',
  List<TeachingSegment> segments = const [TeachingSegment('08:30', '10:00')],
}) => Course.fromJson({
  'id': id,
  'name': '合成课程',
  'teacher': '示例教师',
  'place': '示例楼',
  'day': 1,
  'weeks': weeks,
  'periods': [1, 2],
  'segments': segments.map((s) => s.toJson()).toList(),
  'semester': term,
  'termStart': '2026-09-07',
});

class MemoryRepository implements ScheduleRepository {
  MemoryRepository(this.value);
  ScheduleData value;
  bool fail = false;
  @override
  Future<ScheduleData> load() async => value;
  @override
  Future<void> save(ScheduleData next) async {
    if (fail) throw const FileSystemException('Synthetic write failure');
    value = next;
  }
}

void main() {
  test('school clock uses UTC+8 independently of device timezone', () {
    final time = schoolNow(DateTime.utc(2026, 11, 9, 18, 30));
    expect(isoDate(time), '2026-11-10');
    expect(time.hour, 2);
    expect(time.minute, 30);
  });
  test('week parity, semester start and actual teaching segments', () {
    expect(parseWeeks('1-8单,10-12'), {1, 3, 5, 7, 11});
    expect(() => parseWeeks('0-2'), throwsFormatException);
    expect(() => parseWeeks('2-1'), throwsFormatException);
    expect(() => parseWeeks('1-8单双'), throwsFormatException);
    final c = sample(
      weeks: '1-16单',
      segments: const [
        TeachingSegment('08:30', '10:00'),
        TeachingSegment('10:30', '11:15'),
      ],
    );
    expect(occurrencesOn([c], DateTime(2026, 9, 7)).length, 2);
    expect(occurrencesOn([c], DateTime(2026, 9, 14)), isEmpty);
    expect(occurrencesOn([c], DateTime(2026, 8, 31)), isEmpty);
    final next = nextOccurrences([c], DateTime(2026, 9, 7, 10, 15));
    expect(next.first.segment.start, '10:30');
    expect(next.first.activeAt(DateTime(2026, 9, 7, 10, 15)), isFalse);
    expect(next.first.activeAt(DateTime(2026, 9, 7, 10, 30)), isTrue);
    expect(next.first.activeAt(DateTime(2026, 9, 7, 11, 15)), isFalse);
  });
  test(
    'overlap groups show conflicts while adjoining lessons reuse a lane',
    () {
      final events = occurrencesOn([
        sample(),
        sample(id: 'synthetic-2'),
        sample(
          id: 'synthetic-3',
          segments: const [TeachingSegment('10:00', '11:15')],
        ),
      ], DateTime(2026, 9, 7));
      final layout = layoutEvents(events);
      expect(layout.take(2).map((p) => p.lanes), [2, 2]);
      expect(layout.take(2).map((p) => p.lane).toSet().length, 2);
      expect(layout.last.lanes, 1);
    },
  );
  test(
    'full batch replaces one semester, retains other semesters and rejects duplicates',
    () {
      final data = ScheduleData(
        courses: [
          sample(),
          sample(id: 'other', term: '2025-2026-1'),
        ],
      );
      final next = data.mergeImport(
        [sample(id: 'updated')],
        '合成测试',
        DateTime(2026),
      );
      expect(next.courses.map((c) => c.id), ['other', 'updated']);
      expect(
        next
            .mergeImport([sample(id: 'updated')], '', DateTime(2026))
            .courses
            .length,
        2,
      );
      expect(
        () => data.mergeImport([], '', DateTime(2026)),
        throwsFormatException,
      );
      expect(
        () => data.mergeImport([sample(), sample()], '', DateTime(2026)),
        throwsFormatException,
      );
      expect(
        () => const ScheduleData(
          isDemo: true,
        ).mergeImport([sample()], '', DateTime(2026)),
        throwsFormatException,
      );
    },
  );
  test(
    'file cache survives a fresh repository and refuses synthetic preview writes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'campus-synthetic-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repo = FileScheduleRepository(directory: directory);
      await repo.save(ScheduleData(courses: [sample()]));
      expect(
        (await FileScheduleRepository(
          directory: directory,
        ).load()).courses.single.teacher,
        '示例教师',
      );
      await expectLater(
        repo.save(const ScheduleData(isDemo: true)),
        throwsStateError,
      );
      expect((await repo.load()).courses.length, 1);
      await File(
        '${directory.path}/schedule-v1.json',
      ).writeAsString('invalid synthetic JSON');
      await expectLater(repo.load(), throwsFormatException);
    },
  );
  test('failed write retains previously published controller state', () async {
    final repo = MemoryRepository(ScheduleData(courses: [sample()]));
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await container.read(scheduleProvider.future);
    repo.fail = true;
    await expectLater(
      container.read(scheduleProvider.notifier).importBatch([
        sample(id: 'new'),
      ], '合成'),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      container.read(scheduleProvider).requireValue.courses.single.id,
      'synthetic-1',
    );
  });
  test(
    'school allowlist rejects suffix tricks, credentials, HTTP and other ports',
    () {
      expect(schoolUrl('https://webvpn.bucm.edu.cn/export'), isTrue);
      for (final url in [
        'http://bucm.edu.cn/',
        'https://bucm.edu.cn.evil.example/',
        'https://user:pass@bucm.edu.cn/',
        'https://bucm.edu.cn:444/',
        'file:///local',
      ]) {
        expect(schoolUrl(url), isFalse);
      }
      expect(authenticationUrl('https://open.weixin.qq.com/'), isTrue);
      expect(schoolUrl('https://open.weixin.qq.com/'), isFalse);
    },
  );
}
