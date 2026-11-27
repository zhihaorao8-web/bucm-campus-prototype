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
  String name = '合成课程',
  String teacher = '示例教师',
  String place = '示例楼',
  String term = '2026-2027-1',
  String termStart = '2026-09-07',
  int day = DateTime.monday,
  String weeks = '1-16',
  List<TeachingSegment> segments = const [TeachingSegment('08:30', '10:00')],
}) => Course.fromJson({
  'id': id,
  'name': name,
  'teacher': teacher,
  'place': place,
  'day': day,
  'weeks': weeks,
  'periods': [1, 2],
  'segments': segments.map((s) => s.toJson()).toList(),
  'semester': term,
  'termStart': termStart,
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
  group('semester course search', () {
    const semester = '2026-2027-1';

    test('matches only part of the name in the selected semester', () {
      final courses = [
        sample(id: 'match', name: '基础解剖学 Lab', weeks: '1'),
        sample(id: 'teacher', teacher: '解剖教研组', weeks: '1'),
        sample(id: 'room', place: '解剖实验室', weeks: '1'),
        sample(
          id: 'old',
          name: '基础解剖学 Lab',
          term: '2025-2026-1',
          termStart: '2025-09-08',
          weeks: '1',
        ),
      ];
      Map<DateTime, List<Occurrence>> search(
        String query,
        String selectedTerm,
      ) => searchCourseOccurrences(
        courses,
        semester: selectedTerm,
        query: query,
        now: DateTime(2026, 9, 7),
      );

      expect(
        search('  解剖  ', semester).values.single.single.course.id,
        'match',
      );
      expect(search('lab', semester).values.single.single.course.id, 'match');
      expect(search('解剖', '2025-2026-1').values.single.single.course.id, 'old');
      expect(search('解剖', '2026-2027-2'), isEmpty);
      expect(search('解剖教研组', semester), isEmpty);
      expect(search('解剖实验室', semester), isEmpty);
      expect(search('  ', semester), isEmpty);
    });

    test('retains same-name classes and the day view segment order', () {
      final first = sample(
        id: 'a',
        teacher: '示例教师甲',
        place: '示例楼 A',
        weeks: '1',
        segments: const [
          TeachingSegment('08:30', '10:00'),
          TeachingSegment('10:30', '11:15'),
        ],
      );
      final second = sample(
        id: 'b',
        teacher: '示例教师乙',
        place: '示例楼 B',
        weeks: '1',
      );
      final courses = [second, first];
      final date = DateTime(2026, 9, 7);
      final result = searchCourseOccurrences(
        courses,
        semester: semester,
        query: '合成',
        now: date,
      );

      expect(result.keys, [date]);
      final events = result[date]!;
      final dailyEvents = occurrencesOn(courses, date);
      expect(events.map((event) => event.course), [first, second, first]);
      expect(
        events.map((event) => event.start),
        dailyEvents.map((e) => e.start),
      );
      expect(events.map((event) => event.end), dailyEvents.map((e) => e.end));
    });

    test('expands odd and even weekend classes across the calendar year', () {
      final courses = [
        sample(id: 'odd', termStart: '2026-12-21', day: 6, weeks: '1-4单'),
        sample(id: 'even', termStart: '2026-12-21', day: 7, weeks: '1-4双'),
      ];
      final result = searchCourseOccurrences(
        courses,
        semester: semester,
        query: '合成',
        now: DateTime(2026, 12, 20),
      );

      expect(result.keys.map(isoDate), [
        '2026-12-26',
        '2027-01-03',
        '2027-01-09',
        '2027-01-17',
      ]);
      expect(result.values.map((day) => day.single.course.id), [
        'odd',
        'even',
        'odd',
        'even',
      ]);
    });

    test('places dates with remaining classes before completed dates', () {
      final courses = [sample(weeks: '1-4')];
      List<String> datesAt(DateTime now) => searchCourseOccurrences(
        courses,
        semester: semester,
        query: '合成',
        now: now,
      ).keys.map(isoDate).toList();

      expect(datesAt(DateTime(2026, 9, 21, 9)), [
        '2026-09-21',
        '2026-09-28',
        '2026-09-14',
        '2026-09-07',
      ]);
      expect(datesAt(DateTime(2026, 9, 21, 10)), [
        '2026-09-28',
        '2026-09-21',
        '2026-09-14',
        '2026-09-07',
      ]);
      expect(datesAt(DateTime(2026, 10, 1)), [
        '2026-09-28',
        '2026-09-21',
        '2026-09-14',
        '2026-09-07',
      ]);
    });
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
