import '../domain/schedule.dart';

// Entirely synthetic; opt-in preview only, never persisted.
ScheduleData demoSchedule(DateTime now) {
  final monday = calendarAdd(dateOnly(now), -(now.weekday - 1 + 9 * 7));
  final day = now.weekday;
  Course make(
    String id,
    String name,
    int weekday,
    String weeks,
    List<int> periods,
    List<TeachingSegment> segments,
    String place,
  ) => Course(
    id: 'synthetic-$id',
    name: name,
    dataSource: 'synthetic',
    teacher: '示例教师',
    place: place,
    day: weekday,
    weeks: weeks,
    periods: periods,
    segments: segments,
    semester: '2026-2027-1',
    termStart: monday,
  );
  return ScheduleData(
    isDemo: true,
    summary: '合成示例，仅用于体验界面',
    courses: [
      make(
        '1',
        '示例课程：中医基础',
        day,
        '1-16',
        [1, 2],
        [const TeachingSegment('08:30', '10:00')],
        '示例教学楼 201',
      ),
      make(
        '2',
        '示例课程：人体结构',
        day,
        '1-16',
        [3, 4],
        [const TeachingSegment('10:30', '12:00')],
        '示例教学楼 304',
      ),
      make(
        '3',
        '示例课程：医学英语',
        day,
        '1-16',
        [5, 6, 7],
        [
          const TeachingSegment('13:30', '15:00'),
          const TeachingSegment('15:30', '16:15'),
        ],
        '示例教学楼 102',
      ),
      make(
        '4',
        '示例课程：通识研讨',
        day,
        '1-16',
        [9, 10, 11],
        [const TeachingSegment('18:00', '20:25')],
        '示例线上课堂',
      ),
      make(
        '5',
        '示例课程：阅读讨论',
        day % 7 + 1,
        '1-16双',
        [3, 4],
        [const TeachingSegment('10:30', '12:00')],
        '示例研讨室',
      ),
      make(
        '6',
        '示例课程：实验讨论',
        day,
        '1-16',
        [3, 4],
        [const TeachingSegment('10:30', '12:00')],
        '示例实验室',
      ),
    ],
  );
}
