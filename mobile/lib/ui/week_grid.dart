import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/schedule.dart';
import 'app_theme.dart';
import 'course_widgets.dart';
import 'course_colors.dart';

class EventPlacement {
  const EventPlacement(this.event, this.lane, this.lanes);
  final Occurrence event;
  final int lane, lanes;
}

// Connected overlap groups share a lane count; touching endpoints don't overlap.
List<EventPlacement> layoutEvents(List<Occurrence> events) {
  final sorted = [...events]..sort((a, b) => a.start.compareTo(b.start));
  final output = <EventPlacement>[];
  var index = 0;
  while (index < sorted.length) {
    final group = <Occurrence>[sorted[index++]];
    var end = group.first.end;
    while (index < sorted.length && sorted[index].start.isBefore(end)) {
      final event = sorted[index++];
      group.add(event);
      if (event.end.isAfter(end)) end = event.end;
    }
    final laneEnds = <DateTime>[];
    final assigned = <int>[];
    for (final event in group) {
      var lane = laneEnds.indexWhere((end) => !end.isAfter(event.start));
      if (lane < 0) {
        lane = laneEnds.length;
        laneEnds.add(event.end);
      } else {
        laneEnds[lane] = event.end;
      }
      assigned.add(lane);
    }
    for (var i = 0; i < group.length; i++) {
      output.add(EventPlacement(group[i], assigned[i], laneEnds.length));
    }
  }
  return output;
}

// Five teaching blocks share the available height. Rest time is compressed,
// while each actual teaching segment keeps its own position and detail entry.
class WeekGrid extends StatelessWidget {
  const WeekGrid({
    super.key,
    required this.courses,
    required this.monday,
    required this.today,
    this.onSelectDay,
    this.hasRecordings,
  });
  final List<Course> courses;
  final bool Function(Course)? hasRecordings;
  final DateTime monday, today;
  final ValueChanged<int>? onSelectDay;
  static double minimumHeight(BuildContext context) =>
      40 + 32 + 5 * 56 * MediaQuery.textScalerOf(context).scale(12) / 12;
  static const blocks = [
    (510, 600),
    (630, 720),
    (810, 900),
    (930, 1020),
    (1080, 1225),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scale = MediaQuery.textScalerOf(context);
    final placements = [
      for (var d = 0; d < 5; d++)
        layoutEvents(occurrencesOn(courses, calendarAdd(monday, d))),
    ];
    final all = placements.expand((day) => day).toList();
    final colorIndices = adjacentCourseColors([
      for (final p in all)
        Rect.fromLTRB(
          p.event.date.weekday - 1 + p.lane / p.lanes,
          clockMinutes(p.event.segment.start).toDouble(),
          p.event.date.weekday - 1 + (p.lane + 1) / p.lanes,
          clockMinutes(p.event.segment.end).toDouble(),
        ),
    ]);
    final cardColors = {
      for (var i = 0; i < all.length; i++)
        all[i]: AppColors.courseAt(context, colorIndices[i]),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        const header = 40.0, rest = 16.0;
        final gutter = math.max(40.0, scale.scale(9) * 5 + 4);
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : minimumHeight(context);
        final row = (height - header - rest * 2) / 5;
        final col = (constraints.maxWidth - gutter) / 5;
        double blockTop(int i) =>
            i * row + (i >= 2 ? rest : 0) + (i >= 4 ? rest : 0);
        double position(int minute) {
          for (var i = 0; i < blocks.length; i++) {
            final (start, end) = blocks[i];
            if (minute <= end) {
              return blockTop(i) +
                  ((minute - start) / (end - start)).clamp(0, 1) * row;
            }
          }
          return height - header;
        }

        String clock(int minute) =>
            '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
        return SizedBox(
          key: const ValueKey('week-overview'),
          height: height,
          child: Column(
            children: [
              SizedBox(
                height: header,
                child: Row(
                  children: [
                    SizedBox(
                      width: gutter,
                      child: Text(
                        '${monday.month}月',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (var d = 0; d < 5; d++)
                      Expanded(
                        child: Semantics(
                          label:
                              '周${weekdays[d]}，${shortDate(calendarAdd(monday, d))}，查看日课表',
                          button: onSelectDay != null,
                          child: InkWell(
                            key: ValueKey('week-day-$d'),
                            onTap: onSelectDay == null
                                ? null
                                : () => onSelectDay!(d + 1),
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '周${weekdays[d]}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            calendarDays(
                                                  calendarAdd(monday, d),
                                                  today,
                                                ) ==
                                                0
                                            ? colors.primary
                                            : colors.onSurface,
                                      ),
                                    ),
                                    Text(
                                      col < 40
                                          ? '${calendarAdd(monday, d).day}'
                                          : '${calendarAdd(monday, d).month}/${calendarAdd(monday, d).day}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color:
                                            calendarDays(
                                                  calendarAdd(monday, d),
                                                  today,
                                                ) ==
                                                0
                                            ? colors.primary
                                            : colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Material(
                  color: colors.surface,
                  child: Stack(
                    children: [
                      for (var i = 0; i < 5; i++)
                        Positioned(
                          top: blockTop(i),
                          left: 0,
                          right: 0,
                          height: row,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: colors.outlineVariant.withValues(
                                    alpha: .45,
                                  ),
                                ),
                              ),
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: gutter,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${i + 1}',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${clock(blocks[i].$1)}\n${clock(blocks[i].$2)}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 9,
                                        height: 1.3,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      for (var d = 0; d <= 5; d++)
                        Positioned(
                          left: gutter + d * col,
                          top: 0,
                          bottom: 0,
                          child: VerticalDivider(
                            width: 1,
                            thickness: .5,
                            color: colors.outlineVariant.withValues(alpha: .45),
                          ),
                        ),
                      for (final (index, label) in [(2, '午休'), (4, '晚休')])
                        Positioned(
                          top: blockTop(index) - rest,
                          left: 0,
                          right: 0,
                          height: rest,
                          child: ColoredBox(
                            color: colors.surfaceContainerHighest.withValues(
                              alpha: .4,
                            ),
                            child: Center(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      for (var d = 0; d < 5; d++)
                        for (final p in placements[d])
                          Positioned(
                            left:
                                gutter + d * col + p.lane * col / p.lanes + 1.5,
                            width: math.max(1, col / p.lanes - 3),
                            top:
                                position(clockMinutes(p.event.segment.start)) +
                                2,
                            height: math.max(
                              1,
                              position(clockMinutes(p.event.segment.end)) -
                                  position(
                                    clockMinutes(p.event.segment.start),
                                  ) -
                                  4,
                            ),
                            child: Semantics(
                              key: ValueKey(
                                'week-event-${p.event.course.id}-${p.event.segment.start}',
                              ),
                              button: true,
                              label:
                                  '${p.event.course.name}，周${weekdays[d]}，${p.event.segment.start}到${p.event.segment.end}，${courseLocation(p.event.course)}，${p.event.course.teacher}${p.lanes > 1 ? '，时段重叠' : ''}${hasRecordings?.call(p.event.course) == true ? '，本地目录中有可播放录播' : ''}',
                              excludeSemantics: true,
                              child: Material(
                                color: cardColors[p],
                                borderRadius: BorderRadius.circular(7),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => showCourseDetails(
                                    context,
                                    p.event.course,
                                    date: p.event.date,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                      vertical: 5,
                                    ),
                                    child: LayoutBuilder(
                                      builder: (context, box) {
                                        final line = scale.scale(12) * 1.25;
                                        final showPlace =
                                            box.maxHeight >= line * 3 + 3 &&
                                            box.maxWidth >= 22;
                                        final showTeacher =
                                            box.maxHeight >= line * 4 + 6 &&
                                            box.maxWidth >= 44;
                                        final lines =
                                            ((box.maxHeight -
                                                        (showPlace
                                                            ? line + 3
                                                            : 0) -
                                                        (showTeacher
                                                            ? line + 3
                                                            : 0)) /
                                                    line)
                                                .floor()
                                                .clamp(1, 4);
                                        final ink =
                                            MediaQuery.highContrastOf(context)
                                            ? colors.onSurface
                                            : HSLColor.fromColor(cardColors[p]!)
                                                  .withSaturation(.4)
                                                  .withLightness(
                                                    dark ? .78 : .4,
                                                  )
                                                  .toColor();
                                        return ClipRect(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (hasRecordings?.call(
                                                        p.event.course,
                                                      ) ==
                                                      true &&
                                                  box.maxHeight >=
                                                      line * 7 + 24 &&
                                                  box.maxWidth >= 44)
                                                Align(
                                                  alignment:
                                                      Alignment.centerRight,
                                                  child: Icon(
                                                    Icons
                                                        .video_library_outlined,
                                                    size: 12,
                                                    color: ink,
                                                  ),
                                                ),
                                              Flexible(
                                                child: Text(
                                                  p.event.course.name,
                                                  maxLines: lines,
                                                  overflow: TextOverflow.clip,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    height: 1.25,
                                                    fontWeight: FontWeight.w700,
                                                    color: ink,
                                                  ),
                                                ),
                                              ),
                                              if (showPlace) ...[
                                                const SizedBox(height: 3),
                                                Text(
                                                  '@${courseLocation(p.event.course)}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    height: 1.25,
                                                    color: ink,
                                                  ),
                                                ),
                                              ],
                                              if (showTeacher &&
                                                  p
                                                      .event
                                                      .course
                                                      .teacher
                                                      .isNotEmpty) ...[
                                                const SizedBox(height: 3),
                                                Text(
                                                  p.event.course.teacher,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    height: 1.25,
                                                    color: ink,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
