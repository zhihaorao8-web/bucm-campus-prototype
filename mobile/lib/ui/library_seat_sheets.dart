import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/app_palette.dart';
import '../design/app_tokens.dart';
import '../domain/library_seats.dart';
import '../domain/schedule.dart';
import 'app_icons.dart';
import 'app_theme.dart';
import 'course_surface.dart';
import 'library_seat_map.dart';

typedef LibraryTimeSlotSelection = ({
  TimeOfDay start,
  TimeOfDay end,
  bool selectSeat,
});

Future<LibraryArea?> showLibraryAreaSheet(
  BuildContext context, {
  required List<LibraryArea> areas,
  required LibraryArea? selected,
}) {
  final floors = <String>[];
  for (final area in areas) {
    if (area.floor.isNotEmpty && !floors.contains(area.floor)) {
      floors.add(area.floor);
    }
  }
  String? selectedFloor;

  return showQuietSheet<LibraryArea>(
    context,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final highContrast = MediaQuery.highContrastOf(context);
        final visibleAreas = selectedFloor == null
            ? areas
            : areas.where((area) => area.floor == selectedFloor).toList();
        final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                AppSpace.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '选择座位区域',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭区域选择',
                        icon: const AppIcon(AppIcons.close),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                  if (floors.length > 1) ...[
                    const SizedBox(height: AppSpace.sm),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: AppSpace.xs),
                            child: ChoiceChip(
                              label: const Text('全部楼层'),
                              selected: selectedFloor == null,
                              onSelected: (_) =>
                                  setSheetState(() => selectedFloor = null),
                            ),
                          ),
                          for (final floor in floors)
                            Padding(
                              padding: const EdgeInsets.only(
                                right: AppSpace.xs,
                              ),
                              child: ChoiceChip(
                                label: Text(floor),
                                selected: selectedFloor == floor,
                                onSelected: (_) =>
                                    setSheetState(() => selectedFloor = floor),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpace.md),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: visibleAreas.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpace.sm),
                      itemBuilder: (_, index) {
                        final area = visibleAreas[index];
                        final isSelected = selected?.id == area.id;
                        return Semantics(
                          button: true,
                          selected: isSelected,
                          child: Material(
                            color: isSelected
                                ? colors.primaryContainer.withValues(alpha: .72)
                                : colors.surfaceContainerLow.withValues(
                                    alpha: highContrast ? 1.0 : .75,
                                  ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.input,
                              ),
                              side: BorderSide(
                                width: isSelected || highContrast ? 1.2 : 0.7,
                                color: isSelected
                                    ? colors.primary
                                    : (highContrast
                                          ? colors.outline
                                          : colors.outlineVariant),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => Navigator.of(sheetContext).pop(area),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: AppLayout.minTap,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpace.lg,
                                    vertical: AppSpace.md,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              area.name,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                    color: isSelected
                                                        ? colors.primary
                                                        : colors.onSurface,
                                                  ),
                                            ),
                                            if (area.floor.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                area.floor,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: colors
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      if (isSelected)
                                        AppIcon(
                                          AppIcons.check,
                                          size: AppControl.icon,
                                          color: colors.primary,
                                        ),
                                    ],
                                  ),
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
          ),
        );
      },
    ),
  );
}

int _minutesOnDate(DateTime utcInstant, DateTime date) {
  final dt = schoolNow(utcInstant);
  final diff = DateTime.utc(
    dt.year,
    dt.month,
    dt.day,
  ).difference(DateTime.utc(date.year, date.month, date.day)).inDays;
  return diff * 1440 + dt.hour * 60 + dt.minute;
}

List<LibraryHours> _normalizeWindows(List<LibraryHours> windows) {
  if (windows.isEmpty) return const [(510, 1320)];
  final sorted = windows.where((w) => w.$1 < w.$2).toList()
    ..sort((a, b) => a.$1.compareTo(b.$1));
  if (sorted.isEmpty) return const [(510, 1320)];
  final merged = <LibraryHours>[sorted.first];
  for (final window in sorted.skip(1)) {
    final last = merged.last;
    if (window.$1 <= last.$2) {
      merged[merged.length - 1] = (last.$1, math.max(last.$2, window.$2));
    } else {
      merged.add(window);
    }
  }
  return merged;
}

List<LibraryHours> _bookedIntervalsOnDate(
  LibrarySeat? seat,
  DateTime date,
  int windowStart,
  int windowEnd,
) {
  if (seat == null || seat.reservations.isEmpty) return const [];
  final raw = <LibraryHours>[];
  for (final (begin, end) in seat.reservations) {
    final start = math.max(windowStart, _minutesOnDate(begin, date));
    final finish = math.min(windowEnd, _minutesOnDate(end, date));
    if (start < finish) raw.add((start, finish));
  }
  if (raw.isEmpty) return const [];
  raw.sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <LibraryHours>[raw.first];
  for (final interval in raw.skip(1)) {
    final last = merged.last;
    if (interval.$1 <= last.$2) {
      merged[merged.length - 1] = (last.$1, math.max(last.$2, interval.$2));
    } else {
      merged.add(interval);
    }
  }
  return merged;
}

List<LibraryHours> _freeGapsOnDate(
  List<LibraryHours> openWindows,
  List<LibraryHours> booked, {
  required int minDuration,
}) {
  final gaps = <LibraryHours>[];
  for (final (openStart, openEnd) in openWindows) {
    var cursor = openStart;
    for (final (bookedStart, bookedEnd) in booked) {
      if (bookedEnd <= cursor) continue;
      if (bookedStart >= openEnd) break;
      if (bookedStart > cursor) {
        final segmentEnd = math.min(bookedStart, openEnd);
        if (segmentEnd - cursor >= minDuration) {
          gaps.add((cursor, segmentEnd));
        }
      }
      cursor = math.max(cursor, bookedEnd);
      if (cursor >= openEnd) break;
    }
    if (openEnd - cursor >= minDuration) {
      gaps.add((cursor, openEnd));
    }
  }
  return gaps;
}

TimeOfDay _toTimeOfDay(int minutes) {
  final clamped = minutes.clamp(0, 1439);
  return TimeOfDay(hour: clamped ~/ 60, minute: clamped % 60);
}

int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

String _hhmm(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

Future<LibraryTimeSlotSelection?> showLibraryTimeSlotSheet(
  BuildContext context, {
  required DateTime date,
  required DateTime currentSchoolNow,
  required TimeOfDay? initialStart,
  required TimeOfDay? initialEnd,
  required List<LibraryHours> openHours,
  LibrarySeat? focusSeat,
  LibrarySeatRule? rule,
}) {
  final normalizedHours = _normalizeWindows(
    focusSeat != null && focusSeat.hours.isNotEmpty
        ? focusSeat.hours
        : openHours,
  );
  final windowStart = normalizedHours.first.$1;
  final windowEnd = normalizedHours.last.$2;
  final effectiveRule = focusSeat?.rule ?? rule;
  final minDuration = math.max(10, effectiveRule?.minMinutes ?? 30);

  final booked = _bookedIntervalsOnDate(
    focusSeat,
    date,
    windowStart,
    windowEnd,
  );
  final freeGaps = focusSeat == null
      ? const <LibraryHours>[]
      : _freeGapsOnDate(normalizedHours, booked, minDuration: minDuration);

  final isToday = dateOnly(date) == dateOnly(currentSchoolNow);
  final nowMinutes = currentSchoolNow.hour * 60 + currentSchoolNow.minute;

  var startMinutes = initialStart != null ? _toMinutes(initialStart) : windowStart;
  var endMinutes = initialEnd != null ? _toMinutes(initialEnd) : windowEnd;

  // When opening from a partial seat and current window overlaps booked time,
  // default to the first practical available gap on that seat.
  if (focusSeat != null && freeGaps.isNotEmpty) {
    final overlapsCurrent = booked.any(
      (b) => startMinutes < b.$2 && endMinutes > b.$1,
    );
    if (overlapsCurrent) {
      final candidate = freeGaps.firstWhere(
        (g) => !isToday || g.$2 - math.max(g.$1, nowMinutes) >= minDuration,
        orElse: () => freeGaps.first,
      );
      startMinutes = isToday
          ? math.max(candidate.$1, ((nowMinutes + 9) ~/ 10) * 10)
          : candidate.$1;
      endMinutes = candidate.$2;
      if (startMinutes >= endMinutes) {
        startMinutes = candidate.$1;
      }
    }
  }

  final quickPresets = <({String label, int start, int end})>[];
  if (focusSeat != null) {
    for (final gap in freeGaps) {
      final effectiveStart = isToday ? math.max(gap.$1, nowMinutes) : gap.$1;
      if (gap.$2 - effectiveStart >= minDuration) {
        quickPresets.add((
          label:
              '${formatClockMinutes(effectiveStart)}–${formatClockMinutes(gap.$2)}',
          start: effectiveStart,
          end: gap.$2,
        ));
      } else if (!isToday && gap.$2 - gap.$1 >= minDuration) {
        quickPresets.add((
          label: '${formatClockMinutes(gap.$1)}–${formatClockMinutes(gap.$2)}',
          start: gap.$1,
          end: gap.$2,
        ));
      }
    }
  } else {
    void addPreset(String label, int s, int e) {
      final clampedS = math.max(windowStart, s);
      final clampedE = math.min(windowEnd, e);
      if (clampedE - clampedS < minDuration) return;
      if (isToday && clampedS < nowMinutes) return;
      if (!normalizedHours.any((h) => h.$1 <= clampedS && h.$2 >= clampedE)) {
        return;
      }
      if (quickPresets.any((p) => p.start == clampedS && p.end == clampedE)) {
        return;
      }
      quickPresets.add((label: label, start: clampedS, end: clampedE));
    }

    if (isToday) {
      final roundedNow = math.max(windowStart, ((nowMinutes + 9) ~/ 10) * 10);
      addPreset('现在起 2 小时', roundedNow, roundedNow + 120);
      addPreset('现在起 4 小时', roundedNow, roundedNow + 240);
    }
    addPreset('上午 08:30–12:00', 510, 720);
    addPreset('下午 13:30–17:30', 810, 1050);
    addPreset('晚间 18:00–22:00', 1080, 1320);
    addPreset(
      '全天 ${formatClockMinutes(windowStart)}–${formatClockMinutes(windowEnd)}',
      windowStart,
      windowEnd,
    );
  }

  return showQuietSheet<LibraryTimeSlotSelection>(
    context,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final availableTone = LibrarySeatPalette.toneOf(
          context,
          LibrarySeatStatus.available,
        );
        final partialTone = LibrarySeatPalette.toneOf(
          context,
          LibrarySeatStatus.partial,
        );
        final occupiedTone = LibrarySeatPalette.toneOf(
          context,
          LibrarySeatStatus.occupied,
        );
        final closedTone = LibrarySeatPalette.toneOf(
          context,
          LibrarySeatStatus.closed,
        );

        final overlapsSeat = booked.any(
          (b) => startMinutes < b.$2 && endMinutes > b.$1,
        );
        final outsideOpen =
            startMinutes < endMinutes &&
            !normalizedHours.any(
              (h) => h.$1 <= startMinutes && h.$2 >= endMinutes,
            );
        final pastToday = isToday && startMinutes < nowMinutes;
        final ruleError = effectiveRule?.durationViolation(
          startMinutes,
          endMinutes,
        );

        String? validationError;
        if (startMinutes >= endMinutes) {
          validationError = '结束时间须晚于开始时间。';
        } else if (pastToday) {
          validationError = '开始时间早于当前时间，请先调整。';
        } else if (outsideOpen) {
          validationError = '所选时段不在当日开放时间内。';
        } else if (overlapsSeat) {
          validationError = '所选时段与该座位已有预约重叠。';
        } else if (ruleError != null) {
          validationError = ruleError;
        }

        final startTod = _toTimeOfDay(startMinutes);
        final endTod = _toTimeOfDay(endMinutes);
        final durationText = startMinutes < endMinutes
            ? formatLibraryDuration(endMinutes - startMinutes)
            : '0 分钟';

        Future<void> pickClock(bool pickStart) async {
          final picked = await showTimePicker(
            context: sheetContext,
            initialTime: pickStart ? startTod : endTod,
            helpText: pickStart ? '选择开始时间' : '选择结束时间',
          );
          if (picked == null || !sheetContext.mounted) return;
          setSheetState(() {
            if (pickStart) {
              startMinutes = _toMinutes(picked);
            } else {
              endMinutes = _toMinutes(picked);
            }
          });
        }

        final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                AppSpace.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              focusSeat == null ? '选择预约时段' : '查看可约空档',
                              style: theme.textTheme.titleLarge,
                            ),
                            if (focusSeat != null) ...[
                              const SizedBox(height: AppSpace.xs),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpace.control,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: partialTone.background,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.small,
                                  ),
                                  border: Border.all(
                                    width: 0.7,
                                    color: partialTone.border,
                                  ),
                                ),
                                child: Text(
                                  '${focusSeat.label} · 半空闲',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: partialTone.foreground,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: tabularTime,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭时段选择',
                        icon: const AppIcon(AppIcons.close),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.md),
                  CourseSurface(
                    dense: true,
                    radius: AppRadius.input,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: AppSpace.sm,
                            runSpacing: AppSpace.xs,
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '开放 ${formatClockMinutes(windowStart)}–${formatClockMinutes(windowEnd)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontFeatures: tabularTime,
                                ),
                              ),
                              Text(
                                durationText,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: tabularTime,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpace.sm),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final totalSpan = math.max(
                                1,
                                windowEnd - windowStart,
                              );
                              final trackWidth = constraints.maxWidth;
                              double xFor(int minute) =>
                                  ((minute - windowStart).clamp(0, totalSpan) /
                                      totalSpan) *
                                  trackWidth;

                              final selStart = startMinutes.clamp(
                                windowStart,
                                windowEnd,
                              );
                              final selEnd = endMinutes.clamp(
                                windowStart,
                                windowEnd,
                              );
                              final selLeft = xFor(selStart);
                              final selRight = xFor(selEnd);

                              final closedSegments = <LibraryHours>[];
                              for (
                                var i = 0;
                                i < normalizedHours.length - 1;
                                i++
                              ) {
                                closedSegments.add((
                                  normalizedHours[i].$2,
                                  normalizedHours[i + 1].$1,
                                ));
                              }

                              return ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  key: const ValueKey('library-timeline-track'),
                                  height: 22,
                                  width: trackWidth,
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: availableTone.background,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              width: 0.7,
                                              color: availableTone.border,
                                            ),
                                          ),
                                        ),
                                      ),
                                      for (final gap in closedSegments)
                                        Positioned(
                                          left: xFor(gap.$1),
                                          width: math.max(
                                            2,
                                            xFor(gap.$2) - xFor(gap.$1),
                                          ),
                                          top: 0,
                                          bottom: 0,
                                          child: ColoredBox(
                                            color: closedTone.background,
                                          ),
                                        ),
                                      for (final block in booked)
                                        Positioned(
                                          left: xFor(block.$1),
                                          width: math.max(
                                            3,
                                            xFor(block.$2) - xFor(block.$1),
                                          ),
                                          top: 0,
                                          bottom: 0,
                                          child: ColoredBox(
                                            color: occupiedTone.dot.withValues(
                                              alpha: .72,
                                            ),
                                          ),
                                        ),
                                      if (selRight > selLeft)
                                        Positioned(
                                          left: selLeft,
                                          width: math.max(4, selRight - selLeft),
                                          top: 0,
                                          bottom: 0,
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color:
                                                  (validationError == null
                                                          ? colors.primary
                                                          : colors.error)
                                                      .withValues(alpha: .82),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: AppSpace.xs),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              for (final (alignment, tick) in [
                                (Alignment.centerLeft, windowStart),
                                (
                                  Alignment.center,
                                  (windowStart + windowEnd) ~/ 2,
                                ),
                                (Alignment.centerRight, windowEnd),
                              ])
                                Flexible(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: alignment,
                                      child: Text(
                                        formatClockMinutes(tick),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              fontSize: AppType.caption,
                                              color: colors.onSurfaceVariant,
                                              fontFeatures: tabularTime,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (booked.isNotEmpty) ...[
                            const SizedBox(height: AppSpace.xs),
                            Text(
                              '已约 ${booked.map((b) => '${formatClockMinutes(b.$1)}–${formatClockMinutes(b.$2)}').join('、')}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontFeatures: tabularTime,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (quickPresets.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.md),
                    Text(
                      focusSeat == null ? '快捷时段' : '可用空档',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        for (final preset in quickPresets)
                          ChoiceChip(
                            label: Text(
                              preset.label,
                              style: const TextStyle(fontFeatures: tabularTime),
                            ),
                            selected:
                                startMinutes == preset.start &&
                                endMinutes == preset.end,
                            onSelected: (_) => setSheetState(() {
                              startMinutes = preset.start;
                              endMinutes = preset.end;
                            }),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpace.md),
                  Row(
                    children: [
                      Expanded(
                        child: _ClockPickerTile(
                          label: '开始时间',
                          value: _hhmm(startTod),
                          onTap: () => pickClock(true),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: AppSpace.sm),
                        child: Text('至'),
                      ),
                      Expanded(
                        child: _ClockPickerTile(
                          label: '结束时间',
                          value: _hhmm(endTod),
                          onTap: () => pickClock(false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
                      for (final hours in [1, 2, 4])
                        ActionChip(
                          label: Text('+$hours 小时'),
                          onPressed: () {
                            final nextEnd = math.min(
                              windowEnd,
                              startMinutes + hours * 60,
                            );
                            if (nextEnd > startMinutes) {
                              setSheetState(() => endMinutes = nextEnd);
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (validationError == null) ...[
                        AppIcon(
                          AppIcons.check,
                          size: AppControl.icon,
                          color: AppPalette.success,
                        ),
                        const SizedBox(width: AppSpace.xs),
                      ],
                      Expanded(
                        child: Text(
                          validationError ?? '时段可用 · 共 $durationText',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: validationError == null
                                ? (theme.brightness == Brightness.dark
                                      ? const Color(0xFF5EE0A8)
                                      : AppPalette.success)
                                : colors.error,
                            fontWeight: FontWeight.w500,
                            fontFeatures: tabularTime,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.md),
                  FilledButton(
                    onPressed: validationError != null
                        ? null
                        : () => Navigator.of(sheetContext).pop((
                            start: startTod,
                            end: endTod,
                            selectSeat: focusSeat != null,
                          )),
                    child: Text(
                      focusSeat == null
                          ? '应用此时段'
                          : '采用此时段并选中 ${focusSeat.label}',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _ClockPickerTile extends StatelessWidget {
  const _ClockPickerTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label, value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFeatures: tabularTime,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool?> showLibraryConfirmReservationSheet(
  BuildContext context, {
  required LibrarySeat seat,
  required String areaLabel,
  required DateTime date,
  required TimeOfDay start,
  required TimeOfDay end,
  required List<String> ruleLines,
  required String? blockingReason,
}) {
  final startMin = start.hour * 60 + start.minute;
  final endMin = end.hour * 60 + end.minute;
  final durationText = formatLibraryDuration(endMin - startMin);
  var confirmed = false;

  return showQuietSheet<bool>(
    context,
    barrierLabel: '确认预约座位',
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final colors = theme.colorScheme;
      final dark = theme.brightness == Brightness.dark;
      final highContrast = MediaQuery.highContrastOf(sheetContext);
      final partialTone = LibrarySeatPalette.toneOf(
        sheetContext,
        LibrarySeatStatus.partial,
      );
      final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.86;

      return SafeArea(
        key: const ValueKey('library-confirm-reservation-sheet'),
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.md,
              AppSpace.lg,
              AppSpace.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SheetHeader(
                  title: '确认预约座位',
                  closeTooltip: '关闭预约确认',
                  onClose: () => Navigator.of(sheetContext).pop(false),
                ),
                const SizedBox(height: AppSpace.sm),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CourseSurface(
                          dense: true,
                          radius: AppRadius.inset,
                          color: highContrast
                              ? colors.surface
                              : colors.primaryContainer.withValues(
                                  alpha: dark ? 0.45 : 0.72,
                                ),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpace.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LayoutBuilder(
                                  builder: (context, heroConstraints) {
                                    final compactHero =
                                        MediaQuery.textScalerOf(
                                              context,
                                            ).scale(14) >
                                            20 ||
                                        heroConstraints.maxWidth < 280;
                                    final durationPill = endMin > startMin
                                        ? Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: AppSpace.sm,
                                              vertical: AppSpace.xs,
                                            ),
                                            decoration: BoxDecoration(
                                              color: highContrast
                                                  ? colors.surface
                                                  : colors.surface.withValues(
                                                      alpha: dark ? 0.65 : 0.85,
                                                    ),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    AppRadius.small,
                                                  ),
                                              border: Border.all(
                                                color: highContrast
                                                    ? colors.outline
                                                    : colors.primary.withValues(
                                                        alpha: 0.28,
                                                      ),
                                              ),
                                            ),
                                            child: Text(
                                              durationText,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: colors.primary,
                                                    fontWeight: FontWeight.w600,
                                                    fontFeatures: tabularTime,
                                                  ),
                                            ),
                                          )
                                        : null;
                                    final titleRow = Row(
                                      children: [
                                        DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: highContrast
                                                ? colors.surface
                                                : colors.primary.withValues(
                                                    alpha: dark ? 0.25 : 0.14,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              AppRadius.small,
                                            ),
                                            border: highContrast
                                                ? Border.all(
                                                    color: colors.outline,
                                                  )
                                                : null,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(
                                              AppSpace.sm,
                                            ),
                                            child: AppIcon(
                                              AppIcons.book,
                                              size: AppControl.icon,
                                              color: colors.primary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: AppSpace.sm),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                seat.label,
                                                style: theme
                                                    .textTheme
                                                    .titleLarge
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontFeatures: tabularTime,
                                                    ),
                                              ),
                                              if (areaLabel.isNotEmpty)
                                                Text(
                                                  areaLabel,
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: colors
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (!compactHero &&
                                            durationPill != null) ...[
                                          const SizedBox(width: AppSpace.sm),
                                          durationPill,
                                        ],
                                      ],
                                    );
                                    if (!compactHero || durationPill == null) {
                                      return titleRow;
                                    }
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        titleRow,
                                        const SizedBox(height: AppSpace.xs),
                                        durationPill,
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: AppSpace.sm),
                                Text(
                                  '日期：${isoDate(date)}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontFeatures: tabularTime,
                                  ),
                                ),
                                const SizedBox(height: AppSpace.xs),
                                Text(
                                  '时段：${formatClockMinutes(startMin)}–${formatClockMinutes(endMin)}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontFeatures: tabularTime,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpace.md),
                        CourseSurface(
                          dense: true,
                          radius: AppRadius.inset,
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpace.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('适用规则', style: theme.textTheme.titleSmall),
                                const SizedBox(height: AppSpace.sm),
                                for (final line in ruleLines)
                                  if (line.startsWith('签到提示：'))
                                    Container(
                                      margin: const EdgeInsets.only(
                                        bottom: AppSpace.xs,
                                      ),
                                      padding: const EdgeInsets.all(
                                        AppSpace.sm,
                                      ),
                                      decoration: BoxDecoration(
                                        color: partialTone.background,
                                        borderRadius: BorderRadius.circular(
                                          AppRadius.small,
                                        ),
                                        border: Border.all(
                                          color: partialTone.border,
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 1,
                                            ),
                                            child: AppIcon(
                                              AppIcons.info,
                                              size: 16,
                                              color: partialTone.foreground,
                                            ),
                                          ),
                                          const SizedBox(width: AppSpace.xs),
                                          Expanded(
                                            child: Text(
                                              line,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color:
                                                        partialTone.foreground,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: AppSpace.xs,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 2,
                                            ),
                                            child: AppIcon(
                                              line.startsWith('当日开放：') ||
                                                      line.startsWith('允许时长：')
                                                  ? AppIcons.clock
                                                  : AppIcons.info,
                                              size: 15,
                                              color: colors.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(width: AppSpace.xs),
                                          Expanded(
                                            child: Text(
                                              line,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color:
                                                        colors.onSurfaceVariant,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                              ],
                            ),
                          ),
                        ),
                        if (blockingReason != null) ...[
                          const SizedBox(height: AppSpace.sm),
                          Container(
                            padding: const EdgeInsets.all(AppSpace.sm),
                            decoration: BoxDecoration(
                              color: highContrast
                                  ? colors.surface
                                  : colors.errorContainer.withValues(
                                      alpha: dark ? 0.45 : 0.70,
                                    ),
                              borderRadius: BorderRadius.circular(
                                AppRadius.small,
                              ),
                              border: Border.all(
                                color: highContrast
                                    ? colors.outline
                                    : colors.error.withValues(alpha: 0.40),
                              ),
                            ),
                            child: Text(
                              blockingReason,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpace.sm),
                        Text(
                          '确认后将向学校平台发送一次预约申请，并在“我的预约”中回查结果。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                _ResponsiveSheetActions(
                  secondaryLabel: '取消',
                  onSecondary: () => Navigator.of(sheetContext).pop(false),
                  primaryLabel: '确认提交预约',
                  onPrimary: blockingReason != null
                      ? null
                      : () {
                          if (confirmed) return;
                          confirmed = true;
                          Navigator.of(sheetContext).pop(true);
                        },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<bool?> showLibraryConfirmCancelSheet(
  BuildContext context, {
  required LibraryBooking booking,
}) {
  final place = booking.room.isEmpty
      ? booking.seat
      : '${booking.room} · ${booking.seat}';
  var confirmed = false;

  return showQuietSheet<bool>(
    context,
    barrierLabel: '确认取消预约',
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final colors = theme.colorScheme;
      final dark = theme.brightness == Brightness.dark;
      final highContrast = MediaQuery.highContrastOf(sheetContext);
      final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.82;

      return SafeArea(
        key: const ValueKey('library-confirm-cancel-sheet'),
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.md,
              AppSpace.lg,
              AppSpace.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SheetHeader(
                  title: '确认取消预约',
                  closeTooltip: '关闭取消确认',
                  onClose: () => Navigator.of(sheetContext).pop(false),
                ),
                const SizedBox(height: AppSpace.sm),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CourseSurface(
                          dense: true,
                          radius: AppRadius.inset,
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpace.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(place, style: theme.textTheme.titleMedium),
                                const SizedBox(height: AppSpace.xs),
                                Text(
                                  '${booking.begin} 至 ${booking.end}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontFeatures: tabularTime,
                                  ),
                                ),
                                const SizedBox(height: AppSpace.xs),
                                Text(
                                  '预约编号 ${booking.id}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    fontFeatures: tabularTime,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpace.md),
                        Container(
                          padding: const EdgeInsets.all(AppSpace.md),
                          decoration: BoxDecoration(
                            color: highContrast
                                ? colors.surface
                                : colors.errorContainer.withValues(
                                    alpha: dark ? 0.40 : 0.60,
                                  ),
                            borderRadius: BorderRadius.circular(
                              AppRadius.inset,
                            ),
                            border: Border.all(
                              color: highContrast
                                  ? colors.outline
                                  : colors.error.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: AppIcon(
                                  AppIcons.info,
                                  size: AppControl.icon,
                                  color: colors.error,
                                ),
                              ),
                              const SizedBox(width: AppSpace.sm),
                              Expanded(
                                child: Text(
                                  '学校接受取消后，这笔预约将释放。取消资格由学校平台确认。',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                _ResponsiveSheetActions(
                  secondaryLabel: '保留预约',
                  onSecondary: () => Navigator.of(sheetContext).pop(false),
                  primaryLabel: '确认取消',
                  destructive: true,
                  onPrimary: () {
                    if (confirmed) return;
                    confirmed = true;
                    Navigator.of(sheetContext).pop(true);
                  },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.title,
    required this.closeTooltip,
    required this.onClose,
  });

  final String title, closeTooltip;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: colors.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Row(
          children: [
            Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
            IconButton(
              tooltip: closeTooltip,
              icon: const AppIcon(AppIcons.close),
              onPressed: onClose,
            ),
          ],
        ),
      ],
    );
  }
}

class _ResponsiveSheetActions extends StatelessWidget {
  const _ResponsiveSheetActions({
    required this.secondaryLabel,
    required this.onSecondary,
    required this.primaryLabel,
    required this.onPrimary,
    this.destructive = false,
  });

  final String secondaryLabel, primaryLabel;
  final VoidCallback onSecondary;
  final VoidCallback? onPrimary;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scaled = MediaQuery.textScalerOf(context).scale(14);
    return LayoutBuilder(
      builder: (context, constraints) {
        final primaryButton = FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(AppLayout.minTap, AppLayout.minTap),
            backgroundColor: destructive ? colors.error : null,
            foregroundColor: destructive ? colors.onError : null,
          ),
          onPressed: onPrimary,
          child: Text(primaryLabel),
        );
        final secondaryButton = OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(AppLayout.minTap, AppLayout.minTap),
          ),
          onPressed: onSecondary,
          child: Text(secondaryLabel),
        );

        if (scaled > 22 || constraints.maxWidth < 300) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primaryButton,
              const SizedBox(height: AppSpace.sm),
              secondaryButton,
            ],
          );
        }

        return Row(
          children: [
            secondaryButton,
            const SizedBox(width: AppSpace.sm),
            Expanded(child: primaryButton),
          ],
        );
      },
    );
  }
}
