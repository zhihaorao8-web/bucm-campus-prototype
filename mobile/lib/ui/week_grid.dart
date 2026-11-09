import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/schedule.dart';
import 'app_theme.dart';
import 'course_widgets.dart';

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

class WeekGrid extends StatelessWidget {
  const WeekGrid({
    super.key,
    required this.courses,
    required this.monday,
    required this.today,
  });
  final List<Course> courses;
  final DateTime monday, today;
  static const minuteHeight = 1.15;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placements = [
      for (var d = 0; d < 7; d++)
        layoutEvents(occurrencesOn(courses, calendarAdd(monday, d))),
    ];
    final all = placements.expand((p) => p).toList();
    final lanes = all.fold<int>(1, (n, p) => math.max(n, p.lanes));
    final startMinute =
        all.fold<int>(
          480,
          (n, p) => math.min(n, clockMinutes(p.event.segment.start)),
        ) ~/
        60 *
        60;
    final endMinute =
        ((all.fold<int>(
                  1260,
                  (n, p) => math.max(n, clockMinutes(p.event.segment.end)),
                ) +
                59) ~/
            60) *
        60;
    return LayoutBuilder(
      builder: (context, constraints) {
        final minimumColumn = math.max(116.0, lanes * 56.0 + 4);
        final width = math.max(constraints.maxWidth, 7 * minimumColumn + 52);
        final col = (width - 52) / 7;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 52),
                    for (var d = 0; d < 7; d++)
                      SizedBox(
                        width: col,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Column(
                            children: [
                              Text('周${weekdays[d]}'),
                              const SizedBox(height: 4),
                              Text(
                                shortDate(calendarAdd(monday, d)),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
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
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(
                  height: (endMinute - startMinute) * minuteHeight,
                  child: Stack(
                    children: [
                      for (
                        var hour = startMinute ~/ 60;
                        hour < endMinute ~/ 60;
                        hour++
                      )
                        Positioned(
                          top: (hour * 60 - startMinute) * minuteHeight,
                          left: 0,
                          right: 0,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 52,
                                child: Text(
                                  '${hour.toString().padLeft(2, '0')}:00',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  height: 1,
                                  color: colors.outlineVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      for (var day = 0; day < 7; day++)
                        for (final p in placements[day])
                          Positioned(
                            left: 52 + day * col + p.lane * (col - 4) / p.lanes,
                            width: (col - 4) / p.lanes - 3,
                            top:
                                (clockMinutes(p.event.segment.start) -
                                    startMinute) *
                                minuteHeight,
                            height:
                                (clockMinutes(p.event.segment.end) -
                                        clockMinutes(p.event.segment.start)) *
                                    minuteHeight -
                                3,
                            child: Semantics(
                              button: true,
                              label:
                                  '${p.event.course.name}，${p.event.segment.start}到${p.event.segment.end}，${courseLocation(p.event.course)}${p.lanes > 1 ? '，时段重叠' : ''}',
                              child: Material(
                                color: AppColors.course(
                                  context,
                                  p.event.course.name,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => showCourseDetails(
                                    context,
                                    p.event.course,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: LayoutBuilder(
                                      builder: (context, box) {
                                        final scale = MediaQuery.textScalerOf(
                                          context,
                                        );
                                        final titleHeight =
                                            scale.scale(13) * 1.4;
                                        final locationHeight =
                                            scale.scale(12) * 1.5;
                                        final showLocation =
                                            box.maxHeight >=
                                            titleHeight * 2 +
                                                locationHeight +
                                                4;
                                        final lines = math.min(
                                          3,
                                          math.max(
                                            1,
                                            ((box.maxHeight -
                                                        (showLocation
                                                            ? locationHeight + 4
                                                            : 0)) /
                                                    titleHeight)
                                                .floor(),
                                          ),
                                        );
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              p.event.course.name,
                                              maxLines: lines,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                height: 1.4,
                                              ),
                                            ),
                                            if (showLocation) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                courseLocation(p.event.course),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  height: 1.5,
                                                ),
                                              ),
                                            ],
                                          ],
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
              ],
            ),
          ),
        );
      },
    );
  }
}
