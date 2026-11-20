import 'schedule.dart';

typedef LibraryHours = (int, int);
typedef LibraryInterval = (DateTime, DateTime);

enum LibrarySeatStatus { available, partial, occupied, closed, viewOnly }

const _bookingStatusFlags = <(int, String)>[
  (2, '待生效'),
  (4, '生效中'),
  (256, '待审核'),
  (512, '审核未通过'),
  (1024, '审核通过'),
  (64, '已签到'),
  (2048, '暂离中'),
  (4096, '已签离'),
  (128, '已结束'),
  (16, '违约'),
];

List<String> libraryBookingStatusLabels(int? status) {
  if (status == null) return const [];
  final labels = [
    for (final (flag, label) in _bookingStatusFlags)
      if ((status & flag) != 0) label,
  ];
  return labels.isEmpty ? ['学校状态码 $status'] : List.unmodifiable(labels);
}

String formatClockMinutes(int minutes) {
  final clamped = minutes.clamp(0, 1439);
  final h = (clamped ~/ 60).toString().padLeft(2, '0');
  final m = (clamped % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

String formatLibraryInterval(LibraryInterval interval) {
  final begin = schoolNow(interval.$1);
  final end = schoolNow(interval.$2);
  String hhmm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  return '${hhmm(begin)}–${hhmm(end)}';
}

String formatLibraryDuration(int minutes) {
  if (minutes <= 0) return '0 分钟';
  final days = minutes ~/ 1440;
  final rem = minutes % 1440;
  final hours = rem ~/ 60;
  final mins = rem % 60;
  final parts = <String>[
    if (days > 0) '$days 天',
    if (hours > 0) '$hours 小时',
    if (mins > 0) '$mins 分钟',
  ];
  return parts.join(' ');
}

const _ruleLimitFlags = <(int, String)>[
  (1, '需要审核'),
  (2, '暂时离开超时仍保留'),
  (8, '增删改预约不发送短信'),
  (16, '仅适用活动'),
  (32, '预约结束必须操作才能离开'),
  (64, '开始时间须为当前时间或开馆时间'),
  (128, '结束时间须为闭馆时间'),
];

class LibrarySeatRule {
  const LibrarySeatRule({
    this.minMinutes,
    this.maxMinutes,
    this.earliestMinutes,
    this.latestMinutes,
    this.cancelMinutes,
    this.limit,
  });

  final int? minMinutes,
      maxMinutes,
      earliestMinutes,
      latestMinutes,
      cancelMinutes,
      limit;

  factory LibrarySeatRule.fromJson(Map<String, dynamic> json) =>
      LibrarySeatRule(
        minMinutes: json['minMinutes'] as int?,
        maxMinutes: json['maxMinutes'] as int?,
        earliestMinutes: json['earliestMinutes'] as int?,
        latestMinutes: json['latestMinutes'] as int?,
        cancelMinutes: json['cancelMinutes'] as int?,
        limit: json['limit'] as int?,
      );

  List<String> get limitLabels {
    final value = limit;
    if (value == null || value == 0) return const [];
    return List.unmodifiable([
      for (final (flag, label) in _ruleLimitFlags)
        if ((value & flag) != 0) label,
    ]);
  }

  String? durationViolation(int startMinutes, int endMinutes) {
    if (startMinutes >= endMinutes) return '结束时间须晚于开始时间。';
    final duration = endMinutes - startMinutes;
    final min = minMinutes;
    final max = maxMinutes;
    final range = [
      if (min != null && min > 0) '至少 ${formatLibraryDuration(min)}',
      if (max != null && max > 0) '最长 ${formatLibraryDuration(max)}',
    ].join('，');
    if (min != null && min > 0 && duration < min) {
      return '所选时长短于学校允许的最短时长（$range）。';
    }
    if (max != null && max > 0 && duration > max) {
      return '所选时长超过学校允许的最长时长（$range）。';
    }
    return null;
  }
}

class LibraryArea {
  const LibraryArea(this.id, this.name, this.floor);

  final String id, name, floor;
  String get label => floor.isEmpty ? name : '$floor · $name';

  factory LibraryArea.fromJson(Map<String, dynamic> json) => LibraryArea(
    json['id'] as String,
    json['name'] as String,
    json['floor'] as String,
  );

  @override
  bool operator ==(Object other) => other is LibraryArea && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class LibrarySeat {
  const LibrarySeat({
    required this.id,
    required this.label,
    required this.open,
    required this.viewOnly,
    required this.hours,
    required this.reservations,
    this.rule,
  });

  final String id, label;
  final bool open, viewOnly;
  final List<LibraryHours> hours;
  final List<LibraryInterval> reservations;
  final LibrarySeatRule? rule;

  factory LibrarySeat.fromJson(Map<String, dynamic> json) => LibrarySeat(
    id: json['id'] as String,
    label: json['label'] as String,
    open: json['open'] as bool,
    viewOnly: json['viewOnly'] as bool,
    hours: (json['hours'] as List)
        .map(
          (row) =>
              (clockMinutes(row[0] as String), clockMinutes(row[1] as String)),
        )
        .toList(),
    reservations: (json['reservations'] as List)
        .map(
          (row) => (
            _schoolInstant(row[0] as String),
            _schoolInstant(row[1] as String),
          ),
        )
        .toList(),
    rule: json['rule'] is Map<String, dynamic>
        ? LibrarySeatRule.fromJson(json['rule'] as Map<String, dynamic>)
        : null,
  );

  static (DateTime, DateTime) _window(DateTime date, int start, int end) {
    final midnight = DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).subtract(const Duration(hours: 8));
    return (
      midnight.add(Duration(minutes: start)),
      midnight.add(Duration(minutes: end)),
    );
  }

  List<LibraryInterval> overlappingReservations(
    DateTime date,
    int start,
    int end,
  ) {
    if (start >= end) return const [];
    final (from, until) = _window(date, start, end);
    return reservations
        .where((r) => r.$1.isBefore(until) && r.$2.isAfter(from))
        .toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
  }

  LibrarySeatStatus statusOn(DateTime date, int start, int end) {
    if (viewOnly) return LibrarySeatStatus.viewOnly;
    if (!open ||
        start >= end ||
        !hours.any((h) => h.$1 <= start && h.$2 >= end)) {
      return LibrarySeatStatus.closed;
    }
    final (from, until) = _window(date, start, end);
    final overlaps = overlappingReservations(date, start, end);
    if (overlaps.isEmpty) return LibrarySeatStatus.available;
    var coveredUntil = from;
    for (final (begin, end) in overlaps) {
      if (begin.isAfter(coveredUntil)) return LibrarySeatStatus.partial;
      if (end.isAfter(coveredUntil)) coveredUntil = end;
      if (!coveredUntil.isBefore(until)) return LibrarySeatStatus.occupied;
    }
    return LibrarySeatStatus.partial;
  }
}

DateTime _schoolInstant(String value) {
  final timestamp = value.trim().replaceFirst(' ', 'T');
  return DateTime.parse('$timestamp:00+08:00');
}

class LibraryBooking {
  const LibraryBooking(
    this.id,
    this.room,
    this.seat,
    this.begin,
    this.end,
    this.status,
  );

  final String id, room, seat, begin, end;
  final int? status;

  bool canRequestCancellation(DateTime now) {
    final flags = status;
    final timestamp = begin.replaceFirst(' ', 'T');
    final start = DateTime.tryParse('$timestamp:00+08:00');
    const pending = 2 | 256 | 1024;
    const ineligible = 4 | 16 | 64 | 128 | 512 | 2048 | 4096;
    return flags != null &&
        (flags & pending) != 0 &&
        (flags & ineligible) == 0 &&
        start != null &&
        start.isAfter(now);
  }

  factory LibraryBooking.fromJson(Map<String, dynamic> json) => LibraryBooking(
    json['id'] as String,
    json['room'] as String,
    json['seat'] as String,
    json['begin'] as String,
    json['end'] as String,
    json['status'] as int?,
  );
}

class LibraryBookingPage {
  const LibraryBookingPage(
    this.rows,
    this.hasMore, {
    this.page = 1,
    this.totalCount = 0,
  });

  final List<LibraryBooking> rows;
  final bool hasMore;
  final int page;
  final int totalCount;
}

class LibraryBookingRequest {
  const LibraryBookingRequest({
    required this.areaId,
    required this.areaName,
    required this.areaLabel,
    required this.seatId,
    required this.seatLabel,
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
    this.rule,
  });

  final String areaId, areaName, areaLabel, seatId, seatLabel;
  final DateTime date;
  final int startMinutes, endMinutes;
  final LibrarySeatRule? rule;

  String get beginTimestamp =>
      '${isoDate(date)} ${formatClockMinutes(startMinutes)}';
  String get endTimestamp =>
      '${isoDate(date)} ${formatClockMinutes(endMinutes)}';
  DateTime get weekBegin => calendarAdd(date, 1 - date.weekday);
  DateTime get weekEnd => calendarAdd(weekBegin, 6);

  bool matchesBooking(LibraryBooking booking, {String bookingId = ''}) {
    if (bookingId.isNotEmpty) return booking.id == bookingId;
    return booking.seat == seatLabel &&
        booking.begin == beginTimestamp &&
        booking.end == endTimestamp &&
        (booking.room.isEmpty ||
            areaName.isEmpty ||
            booking.room == areaName);
  }
}
