import 'dart:math' as math;
import '../design/app_tokens.dart';
import '../design/app_palette.dart';
import 'course_interaction.dart';
import 'acrylic_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/schedule.dart';
import 'app_icons.dart';
import 'app_theme.dart';
import 'course_widgets.dart';
import 'quiet_backdrop.dart';

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
    return CourseCardLink(
      radius: 28,
      onOpen: (tag) => showCourseDetails(
        context,
        event.course,
        date: event.date,
        transitionTag: tag,
      ),
      child: AcrylicSurface(
        liquidGlass: true,
        child: MiuixCard(
          key: const ValueKey('today-focus'),
          colors: MiuixCardColors(
            color: Colors.transparent,
            contentColor: colors.onSurface,
          ),
          cornerRadius: 28,
          insideMargin: const EdgeInsets.all(AppLayout.focusInset),
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
                            color: active ? AppPalette.success : colors.primary,
                            boxShadow: MediaQuery.highContrastOf(context)
                                ? null
                                : [
                                    BoxShadow(
                                      color:
                                          (active
                                                  ? AppPalette.success
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
                        horizontal: AppSpace.control,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.section),
                      ),
                      child: Text(
                        active
                            ? '剩 ${remainingMinutes(event.end, now)} 分钟'
                            : event.start.difference(now).inMinutes < 60
                            ? '${remainingMinutes(event.start, now)} 分钟后开始'
                            : '${shortDate(event.date)} 周${weekdays[event.date.weekday - 1]}',
                        style: TextStyle(
                          fontSize: AppType.smallLabel,
                          fontWeight: FontWeight.w600,
                          color: colors.onPrimaryContainer,
                          fontFeatures: tabularTime,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  event.segment.start,
                  style: TextStyle(
                    fontSize: AppType.focusTime,
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
                const SizedBox(height: 16),
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
                    padding: const EdgeInsets.only(top: AppSpace.sm),
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
                    builder: (context, value, _) => WavyProgressIndicator(
                      key: const ValueKey('today-lesson-progress'),
                      value: value,
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
              padding: const EdgeInsets.fromLTRB(28, 2, 0, AppSpace.lg),
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
                        fontSize: AppType.caption,
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

/// Serene Material 3-inspired wavy progress indicator matching the Pen spec.
/// Flows gently while visible in the foreground and freezes under reduced
/// motion, background lifecycle, or inactive [TickerMode].
class WavyProgressIndicator extends ConsumerStatefulWidget {
  const WavyProgressIndicator({
    super.key,
    required this.value,
    this.activeColor,
    this.trackColor,
    this.height = 12.0,
    this.strokeWidth = 2.8,
    this.trackHeight = 3.5,
    this.amplitude = 2.6,
    this.wavelength = 26.0,
    this.gap = 6.0,
    this.semanticsLabel,
    this.semanticsValue,
  });

  final double value;
  final Color? activeColor;
  final Color? trackColor;
  final double height;
  final double strokeWidth;
  final double trackHeight;
  final double amplitude;
  final double wavelength;
  final double gap;
  final String? semanticsLabel;
  final String? semanticsValue;

  @override
  ConsumerState<WavyProgressIndicator> createState() =>
      _WavyProgressIndicatorState();
}

class _WavyProgressIndicatorState extends ConsumerState<WavyProgressIndicator>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _phase;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    _phase = AnimationController(vsync: this, duration: AppMotion.wave);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.value.clamp(0.0, 1.0);
    final animate =
        progress > 0 &&
        !MediaQuery.disableAnimationsOf(context) &&
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        ref.watch(ambientMotionEnabledProvider);
    if (animate && !_phase.isAnimating) {
      _phase.repeat();
    } else if (!animate && _phase.isAnimating) {
      _phase.stop();
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final active = widget.activeColor ?? colors.primary;
    final track =
        widget.trackColor ??
        (highContrast
            ? colors.outline
            : colors.primary.withValues(alpha: dark ? .20 : .13));

    return Semantics(
      label: widget.semanticsLabel,
      value: widget.semanticsValue,
      child: SizedBox(
        width: double.infinity,
        height: widget.height,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _WavyProgressPainter(
              value: progress,
              phase: _phase,
              activeColor: active,
              trackColor: track,
              strokeWidth: widget.strokeWidth,
              trackHeight: widget.trackHeight,
              amplitude: widget.amplitude,
              wavelength: widget.wavelength,
              gap: widget.gap,
            ),
          ),
        ),
      ),
    );
  }
}

class _WavyProgressPainter extends CustomPainter {
  _WavyProgressPainter({
    required this.value,
    required this.phase,
    required this.activeColor,
    required this.trackColor,
    required this.strokeWidth,
    required this.trackHeight,
    required this.amplitude,
    required this.wavelength,
    required this.gap,
  }) : super(repaint: phase);

  final double value;
  final Animation<double> phase;
  final Color activeColor;
  final Color trackColor;
  final double strokeWidth;
  final double trackHeight;
  final double amplitude;
  final double wavelength;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final halfStroke = strokeWidth / 2;
    final usable = size.width - strokeWidth;
    if (usable <= 0 || size.height <= 0) return;

    final centerY = size.height / 2;
    final maxAmp = math.max(0.0, (size.height - strokeWidth) / 2);
    final effectiveAmp = math.min(amplitude, maxAmp);
    final activeWidth = usable * value;

    if (value > 0) {
      final path = Path();
      final endX = halfStroke + activeWidth;
      final phaseShift = phase.value * math.pi * 2;
      double yAt(double x) =>
          centerY -
          effectiveAmp *
              math.sin((2 * math.pi * (x - halfStroke) / wavelength) - phaseShift);
      path.moveTo(halfStroke, yAt(halfStroke));
      for (var x = halfStroke + 1.5; x < endX; x += 1.5) {
        path.lineTo(x, yAt(x));
      }
      path.lineTo(endX, yAt(endX));
      canvas.drawPath(
        path,
        Paint()
          ..color = activeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    if (value < 1) {
      final trackStart = value <= 0 ? 0.0 : halfStroke + activeWidth + gap;
      final trackEnd = size.width;
      if (trackEnd - trackStart > trackHeight) {
        canvas.drawRRect(
          RRect.fromLTRBR(
            trackStart,
            centerY - trackHeight / 2,
            trackEnd,
            centerY + trackHeight / 2,
            Radius.circular(trackHeight / 2),
          ),
          Paint()..color = trackColor,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WavyProgressPainter old) =>
      old.value != value ||
      old.activeColor != activeColor ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth ||
      old.trackHeight != trackHeight ||
      old.amplitude != amplitude ||
      old.wavelength != wavelength ||
      old.gap != gap;
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
                translucent: true,
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
