import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import '../domain/schedule.dart';
import 'app_icons.dart';
import 'app_theme.dart';
import 'course_widgets.dart';

double lessonProgress(Occurrence event, DateTime now) =>
    (now.difference(event.start).inMilliseconds /
            event.end.difference(event.start).inMilliseconds)
        .clamp(0, 1);

int remainingMinutes(DateTime end, DateTime now) =>
    (end.difference(now).inMilliseconds / 60000).ceil().clamp(0, 100000);

class FocusCourseCard extends StatelessWidget {
  const FocusCourseCard({
    super.key,
    required this.event,
    required this.now,
    this.overlaps = 1,
  });
  final Occurrence event;
  final DateTime now;
  final int overlaps;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = event.activeAt(now);
    final motion = !MediaQuery.disableAnimationsOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .035),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: MiuixCard(
        key: const ValueKey('today-focus'),
        cornerRadius: 28,
        insideMargin: const EdgeInsets.all(24),
        feedbackType: motion
            ? MiuixPressFeedbackType.sink
            : MiuixPressFeedbackType.none,
        onPressed: () =>
            showCourseDetails(context, event.course, date: event.date),
        child: DefaultTextStyle(
          style: Theme.of(
            context,
          ).textTheme.bodyLarge!.copyWith(color: colors.onSurface),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active
                              ? const Color(0xFF257A54)
                              : colors.primary,
                          boxShadow: MediaQuery.highContrastOf(context)
                              ? null
                              : [
                                  BoxShadow(
                                    color:
                                        (active
                                                ? const Color(0xFF257A54)
                                                : colors.primary)
                                            .withValues(alpha: .12),
                                    spreadRadius: 4,
                                  ),
                                ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        active ? '正在上课' : '下一节课',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      active
                          ? '剩 ${remainingMinutes(event.end, now)} 分钟'
                          : event.start.difference(now).inMinutes < 60
                          ? '${remainingMinutes(event.start, now)} 分钟后开始'
                          : '${shortDate(event.date)} 周${weekdays[event.date.weekday - 1]}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.onPrimaryContainer,
                        fontFeatures: tabularTime,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                event.segment.start,
                style: TextStyle(
                  fontSize: 44,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                  fontFeatures: tabularTime,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${event.segment.end} ${active ? '下课' : '结束'}',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontFeatures: tabularTime,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                event.course.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                courseLocation(event.course),
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              if (active && overlaps > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '有$overlaps门课程重叠',
                    style: TextStyle(color: colors.error),
                  ),
                ),
              if (active) ...[
                const SizedBox(height: 20),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: lessonProgress(event, now)),
                  duration: motion
                      ? const Duration(milliseconds: 500)
                      : Duration.zero,
                  builder: (context, value, _) => LinearProgressIndicator(
                    key: const ValueKey('today-lesson-progress'),
                    value: value,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(4),
                    backgroundColor: colors.primary.withValues(alpha: .09),
                    semanticsLabel: '当前授课分段进度',
                    semanticsValue:
                        '${(lessonProgress(event, now) * 100).round()}%',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Only uncovered time is a break, including when earlier classes overlap.
List<(DateTime, DateTime)> lessonGaps(List<Occurrence> events) {
  final sorted = [...events]..sort((a, b) => a.start.compareTo(b.start));
  final gaps = <(DateTime, DateTime)>[];
  DateTime? end;
  for (final event in sorted) {
    if (end != null && event.start.difference(end).inMinutes >= 10) {
      gaps.add((end, event.start));
    }
    if (end == null || event.end.isAfter(end)) end = event.end;
  }
  return gaps;
}

class TodayCourseTimeline extends StatelessWidget {
  const TodayCourseTimeline({
    super.key,
    required this.events,
    required this.now,
    required this.hasRecordings,
  });
  final List<Occurrence> events;
  final DateTime now;
  final bool Function(Course) hasRecordings;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final gaps = lessonGaps(events);
    return Column(
      children: [
        for (final (index, event) in events.indexed) ...[
          for (final gap in gaps.where(
            (gap) =>
                gap.$2 == event.start &&
                (index == 0 || events[index - 1].start != event.start),
          ))
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 2, 0, 16),
              child: Row(
                children: [
                  Expanded(child: Divider(color: colors.outlineVariant)),
                  const SizedBox(width: 8),
                  Flexible(
                    flex: 5,
                    child: Text(
                      '${gap.$1.hour == 12 && gap.$2.hour == 13
                          ? '午休'
                          : gap.$1.hour == 17 && gap.$2.hour == 18
                          ? '晚休'
                          : '课间休息'} · ${clock(gap.$1)}–${clock(gap.$2)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                        fontFeatures: tabularTime,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Divider(color: colors.outlineVariant)),
                ],
              ),
            ),
          _TimelineEvent(
            event: event,
            now: now,
            first: index == 0,
            last: index == events.length - 1,
            colorIndex: index % 5,
            hasRecordings: hasRecordings(event.course),
            conflict: events.any(
              (other) =>
                  other != event &&
                  other.course.id != event.course.id &&
                  event.overlaps(other),
            ),
          ),
        ],
      ],
    );
  }

  static String clock(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

class _TimelineEvent extends StatelessWidget {
  const _TimelineEvent({
    required this.event,
    required this.now,
    required this.first,
    required this.last,
    required this.colorIndex,
    required this.hasRecordings,
    required this.conflict,
  });
  final Occurrence event;
  final DateTime now;
  final bool first, last, hasRecordings, conflict;
  final int colorIndex;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = event.activeAt(now), ended = !event.end.isAfter(now);
    final status = active
        ? '进行中'
        : ended
        ? '已结束'
        : '未开始';
    return Semantics(
      label: status,
      child: Stack(
        children: [
          Positioned(
            left: 9,
            top: first ? 28 : 0,
            bottom: last ? 28 : 0,
            child: SizedBox(
              width: 1.5,
              child: ColoredBox(color: colors.outlineVariant),
            ),
          ),
          Positioned(
            left: 0,
            top: 25,
            child: Container(
              key: ValueKey(
                'timeline-${event.course.id}-${event.segment.start}-$status',
              ),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active || ended ? colors.primary : colors.surface,
                border: Border.all(
                  color: active ? colors.primary : colors.outline,
                  width: 1.5,
                ),
                boxShadow: active && !MediaQuery.highContrastOf(context)
                    ? [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: .12),
                          spreadRadius: 4,
                        ),
                      ]
                    : null,
              ),
              child: ended
                  ? AppIcon(AppIcons.check, size: 12, color: colors.onPrimary)
                  : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Opacity(
              opacity: ended && !MediaQuery.highContrastOf(context) ? .72 : 1,
              child: CourseRow(
                event: event,
                now: now,
                colorIndex: colorIndex,
                conflict: conflict,
                hasRecordings: hasRecordings,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
