import 'course_interaction.dart';
import 'course_surface.dart';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/appearance_controller.dart';
import 'conflict_sheet.dart';
import 'package:flutter/material.dart';
import 'app_icons.dart';
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

// Sweep at actual segment endpoints: a conflict stack only covers time shared
// by the displayed entries. Chain overlaps never imply a longer lesson.
class EventStack {
  const EventStack(this.start, this.end, this.events);
  final DateTime start, end;
  final List<Occurrence> events;
  String get key =>
      '${isoDate(start)}-${start.hour}:${start.minute}-${end.hour}:${end.minute}';
}

List<EventStack> stackEvents(List<Occurrence> events) {
  final points = {
    for (final event in events) ...[event.start, event.end],
  }.toList()..sort();
  final result = <EventStack>[];
  for (var i = 0; i + 1 < points.length; i++) {
    final start = points[i], end = points[i + 1];
    final active =
        events
            .where(
              (event) =>
                  !event.start.isAfter(start) && event.end.isAfter(start),
            )
            .toList()
          ..sort((a, b) => a.course.id.compareTo(b.course.id));
    if (active.isNotEmpty) result.add(EventStack(start, end, active));
  }
  return result;
}

class WeekGrid extends ConsumerStatefulWidget {
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
      48 + 32 + 5 * 56 * MediaQuery.textScalerOf(context).scale(12) / 12;
  static const blocks = [
    (510, 600),
    (630, 720),
    (810, 900),
    (930, 1020),
    (1080, 1225),
  ];
  @override
  ConsumerState<WeekGrid> createState() => _WeekGridState();
}

class _WeekGridState extends ConsumerState<WeekGrid> {
  final preferred = <String, String>{};
  bool opening = false;
  @override
  void didUpdateWidget(WeekGrid old) {
    super.didUpdateWidget(old);
    if (old.monday != widget.monday ||
        old.courses.firstOrNull?.semester !=
            widget.courses.firstOrNull?.semester) {
      preferred.clear();
    }
  }

  Future<void> open(EventStack stack, Occurrence primary) async {
    if (opening) return;
    opening = true;
    try {
      if (stack.events.length == 1) {
        await showCourseDetails(context, primary.course, date: primary.date);
        return;
      }
      final choice = await showConflictCourses(
        context,
        stack.events,
        primary.course,
      );
      if (!mounted || choice == null) return;
      if (choice.$2) {
        setState(() => preferred[stack.key] = choice.$1.id);
      } else {
        await showCourseDetails(context, choice.$1, date: primary.date);
      }
    } finally {
      opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final settings = ref.watch(currentAppearanceProvider);
    final count = settings.showWeekend ? 7 : 5;
    final scale = MediaQuery.textScalerOf(context);
    final stacks = [
      for (var day = 0; day < count; day++)
        stackEvents(
          occurrencesOn(widget.courses, calendarAdd(widget.monday, day)),
        ),
    ];
    final all = stacks.expand((day) => day).toList();
    final colorIndices = adjacentCourseColors([
      for (final stack in all)
        Rect.fromLTRB(
          stack.start.weekday - 1,
          (stack.start.hour * 60 + stack.start.minute).toDouble(),
          stack.start.weekday.toDouble(),
          (stack.end.hour * 60 + stack.end.minute).toDouble(),
        ),
    ]);
    final colorIndex = {
      for (var i = 0; i < all.length; i++) all[i]: colorIndices[i],
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        const header = 48.0, rest = 16.0;
        final gutter = math.max(40.0, scale.scale(9) * 5 + 4);
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : WeekGrid.minimumHeight(context);
        final row = (height - header - rest * 2) / 5;
        final col = (constraints.maxWidth - gutter) / count;
        double blockTop(int i) =>
            i * row + (i >= 2 ? rest : 0) + (i >= 4 ? rest : 0);
        double position(DateTime time) {
          final minute = time.hour * 60 + time.minute;
          for (var i = 0; i < WeekGrid.blocks.length; i++) {
            final (start, end) = WeekGrid.blocks[i];
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
                        '${widget.monday.month}月',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                          fontFeatures: tabularTime,
                        ),
                      ),
                    ),
                    for (var day = 0; day < count; day++)
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final date = calendarAdd(widget.monday, day);
                            final current =
                                calendarDays(date, widget.today) == 0;
                            return Semantics(
                              label:
                                  '周${weekdays[day]}，${shortDate(date)}，查看日课表',
                              button: widget.onSelectDay != null,
                              child: InkWell(
                                key: ValueKey('week-day-$day'),
                                onTap: widget.onSelectDay == null
                                    ? null
                                    : () => widget.onSelectDay!(day + 1),
                                child: Center(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '周${weekdays[day]}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: current
                                                ? colors.primary
                                                : colors.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Container(
                                          key: current
                                              ? const ValueKey(
                                                  'week-today-date',
                                                )
                                              : null,
                                          width: 22,
                                          height: 22,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: current
                                                ? colors.primary
                                                : Colors.transparent,
                                          ),
                                          child: Text(
                                            '${date.day}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: current
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              color: current
                                                  ? colors.onPrimary
                                                  : colors.onSurfaceVariant,
                                              fontFeatures: tabularTime,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Material(
                  color: Colors.transparent,
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
                                top: BorderSide(color: colors.outlineVariant),
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
                                        fontFeatures: tabularTime,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${clock(WeekGrid.blocks[i].$1)}\n${clock(WeekGrid.blocks[i].$2)}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 9,
                                        height: 1.3,
                                        color: colors.onSurfaceVariant,
                                        fontFeatures: tabularTime,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      for (var day = 0; day <= count; day++)
                        for (final (first, last) in [(0, 2), (2, 4), (4, 5)])
                          Positioned(
                            left: gutter + day * col,
                            top: blockTop(first),
                            height: (last - first) * row,
                            child: VerticalDivider(
                              width: 1,
                              thickness: .5,
                              color: colors.outlineVariant,
                            ),
                          ),
                      for (final (index, label) in [(2, '午休'), (4, '晚休')])
                        Positioned(
                          top: blockTop(index) - rest,
                          left: 0,
                          right: 0,
                          height: rest,
                          child: ColoredBox(
                            color: Colors.transparent,
                            child: Row(
                              children: [
                                Expanded(
                                  child: CustomPaint(
                                    painter: _DashedLine(colors.outlineVariant),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: CustomPaint(
                                    painter: _DashedLine(colors.outlineVariant),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      for (var day = 0; day < count; day++)
                        for (final stack in stacks[day])
                          Builder(
                            builder: (context) {
                              final primary =
                                  stack.events
                                      .where(
                                        (event) =>
                                            event.course.id ==
                                            preferred[stack.key],
                                      )
                                      .firstOrNull ??
                                  stack.events.first;
                              final conflicting = stack.events.length > 1;
                              void target() => open(stack, primary);
                              return Positioned(
                                left: gutter + day * col + 1.5,
                                width: math.max(1, col - 3),
                                top: position(stack.start) + 2,
                                height: math.max(
                                  1,
                                  position(stack.end) -
                                      position(stack.start) -
                                      4,
                                ),
                                child: Semantics(
                                  key: ValueKey(
                                    conflicting
                                        ? 'week-stack-${stack.key}'
                                        : 'week-event-${primary.course.id}-${primary.segment.start}${stack.start != primary.start || stack.end != primary.end ? '-slice-${stack.start.hour}:${stack.start.minute}' : ''}',
                                  ),
                                  button: true,
                                  excludeSemantics: true,
                                  onTap: target,
                                  label: conflicting
                                      ? '时段重叠，${stack.events.length}门课程：${stack.events.map((event) => '${event.course.name}，${event.segment.start}到${event.segment.end}').join('；')}，点击展开全部课程'
                                      : '${primary.course.name}，周${weekdays[day]}，${primary.segment.start}到${primary.segment.end}，${courseLocation(primary.course)}，${primary.course.teacher}${widget.hasRecordings?.call(primary.course) == true ? '，本地目录中有可播放录播' : ''}',
                                  child: Stack(
                                    children: [
                                      if (conflicting)
                                        Positioned.fill(
                                          left: 3,
                                          top: 3,
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: AppColors.courseAt(
                                                context,
                                                colorIndex[stack]!,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(9),
                                              border: Border.all(
                                                color: colors.outlineVariant,
                                              ),
                                            ),
                                          ),
                                        ),
                                      Positioned.fill(
                                        right: conflicting ? 3 : 0,
                                        bottom: conflicting ? 3 : 0,
                                        child: _WeekCourseCard(
                                          event: primary,
                                          additional: stack.events.length - 1,
                                          colorIndex: colorIndex[stack]!,
                                          soft: settings.softCards,
                                          onTap: target,
                                          hasRecordings:
                                              widget.hasRecordings?.call(
                                                primary.course,
                                              ) ==
                                              true,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
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

class _WeekCourseCard extends StatelessWidget {
  const _WeekCourseCard({
    required this.event,
    required this.additional,
    required this.colorIndex,
    required this.soft,
    required this.onTap,
    required this.hasRecordings,
  });
  final Occurrence event;
  final int additional, colorIndex;
  final bool soft, hasRecordings;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ink = AppColors.courseInk(context, colorIndex);
    return CoursePressable(
      radius: 8,
      dense: true,
      onPressed: onTap,
      child: CourseSurface(
        radius: 8,
        dense: true,
        color: soft
            ? AppColors.courseAt(context, colorIndex)
            : colors.surfaceContainer,
        child: Material(
          key: ValueKey('week-primary-${event.course.id}'),
          color: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (!soft)
                Positioned(
                  top: 5,
                  bottom: 5,
                  left: 0,
                  width: 3,
                  child: DecoratedBox(
                    key: const ValueKey('week-color-rail'),
                    decoration: BoxDecoration(
                      color: ink,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(soft ? 4 : 7, 4, 3, 4),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final line =
                          MediaQuery.textScalerOf(context).scale(12) * 1.25;
                      final badge = additional > 0 && box.maxHeight >= 28;
                      final available = box.maxHeight - (badge ? 14 : 0);
                      final showPlace =
                          available >= line * 3 + 3 && box.maxWidth >= 22;
                      final showTeacher =
                          available >= line * 4 + 6 && box.maxWidth >= 44;
                      final lines =
                          ((available -
                                      (showPlace ? line + 3 : 0) -
                                      (showTeacher ? line + 3 : 0)) /
                                  line)
                              .floor()
                              .clamp(1, 4);
                      return ClipRect(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (badge)
                              SizedBox(
                                height: 14,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      '+$additional 冲突',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: colors.error,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Flexible(
                              child: Text(
                                event.course.name,
                                maxLines: lines,
                                overflow: TextOverflow.clip,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.25,
                                  fontWeight: FontWeight.w600,
                                  color: soft ? ink : colors.onSurface,
                                ),
                              ),
                            ),
                            if (showPlace) ...[
                              const SizedBox(height: 3),
                              Text(
                                additional > 0
                                    ? '${event.segment.start}–${event.segment.end}'
                                    : '@${courseLocation(event.course)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  height: 1.25,
                                  color: soft ? ink : colors.onSurfaceVariant,
                                  fontFeatures: tabularTime,
                                ),
                              ),
                            ],
                            if (showTeacher &&
                                event.course.teacher.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      event.course.teacher,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        height: 1.25,
                                        color: soft
                                            ? ink
                                            : colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  if (hasRecordings &&
                                      box.maxWidth >= 44 &&
                                      available >= line * 7 + 24)
                                    AppIcon(
                                      AppIcons.mediaLibrary,
                                      size: 12,
                                      color: ink,
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedLine extends CustomPainter {
  const _DashedLine(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = .6;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(math.min(x + 3, size.width), 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedLine old) => old.color != color;
}
