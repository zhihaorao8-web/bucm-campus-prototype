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
  });

  final String id, label;
  final bool open, viewOnly;
  final List<LibraryHours> hours;
  final List<LibraryInterval> reservations;

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
