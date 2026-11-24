import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../domain/library_seats.dart';
import '../domain/schedule.dart';
import 'acrylic_surface.dart';
import 'app_controls.dart';
import 'app_icons.dart';
import 'app_theme.dart';
import 'course_surface.dart';
import 'library_seat_map.dart';

const _focusStatusMask = 2 | 4 | 64 | 256 | 1024 | 2048;
const _endedStatusMask = 16 | 128 | 512 | 4096;

/// Returns whether [row] is an active or upcoming reservation that belongs
/// in the focus ticket section rather than recent history.
bool isFocusLibraryBooking(LibraryBooking row, DateTime now) {
  if (row.canRequestCancellation(now)) return true;
  final status = row.status;
  if (status == null) return false;
  return (status & _focusStatusMask) != 0 && (status & _endedStatusMask) == 0;
}

DateTime _wallUtc(DateTime value) {
  final wall = value.isUtc ? schoolNow(value) : value;
  return DateTime.utc(
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
    wall.second,
  );
}

DateTime? _parseBookingWallUtc(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final parsed = DateTime.tryParse('${trimmed.replaceFirst(' ', 'T')}:00');
  if (parsed == null) return null;
  return _wallUtc(parsed);
}

/// Formats a concise countdown or remaining-time hint for an upcoming or
/// in-progress reservation within 7 days of [now].
String? libraryBookingTimeHint(LibraryBooking row, DateTime now) {
  final start = _parseBookingWallUtc(row.begin);
  final end = _parseBookingWallUtc(row.end);
  final current = _wallUtc(now);
  if (start != null && start.isAfter(current)) {
    final diff = start.difference(current);
    if (diff.inDays > 7) return null;
    if (diff.inMinutes <= 0) return '即将开始';
    return '${formatLibraryDuration(diff.inMinutes)}后开始';
  }
  if (start != null &&
      end != null &&
      !current.isBefore(start) &&
      end.isAfter(current)) {
    final rem = end.difference(current);
    if (rem.inDays > 7) return null;
    if (rem.inMinutes <= 0) return '即将结束';
    return '距结束还剩 ${formatLibraryDuration(rem.inMinutes)}';
  }
  return null;
}

class LibraryBookingsControlsCard extends StatelessWidget {
  const LibraryBookingsControlsCard({
    super.key,
    required this.begin,
    required this.end,
    required this.now,
    required this.page,
    required this.busy,
    required this.loading,
    required this.onSelectRange,
    required this.onChooseCustomRange,
    required this.onRefresh,
    required this.onPageChanged,
  });

  final DateTime begin, end, now;
  final LibraryBookingPage? page;
  final bool busy, loading;
  final void Function(DateTime begin, DateTime end) onSelectRange;
  final VoidCallback onChooseCustomRange, onRefresh;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final disabled = loading || busy;
    final today = dateOnly(now);
    final weekBegin = calendarAdd(today, 1 - today.weekday);
    final weekEnd = calendarAdd(weekBegin, 6);
    final recentBegin = calendarAdd(today, -29);
    final recentEnd = calendarAdd(today, 1);
    final isThisWeek = dateOnly(begin) == weekBegin && dateOnly(end) == weekEnd;
    final isRecent30 =
        dateOnly(begin) == recentBegin && dateOnly(end) == recentEnd;
    final current = page;

    return QuietCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('本周'),
                  selected: isThisWeek,
                  onSelected: busy
                      ? null
                      : (_) => onSelectRange(weekBegin, weekEnd),
                ),
                ChoiceChip(
                  label: const Text('近 30 天'),
                  selected: isRecent30,
                  onSelected: busy
                      ? null
                      : (_) => onSelectRange(recentBegin, recentEnd),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(
                      AppLayout.minTap,
                      AppLayout.minTap,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.md,
                      vertical: AppSpace.sm,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppControl.radius),
                    ),
                  ),
                  onPressed: busy ? null : onChooseCustomRange,
                  icon: const AppIcon(AppIcons.calendar, size: AppControl.icon),
                  label: Text(
                    '${isoDate(begin)} 至 ${isoDate(end)}',
                    style: const TextStyle(fontFeatures: tabularTime),
                  ),
                ),
                AppActionButton(
                  label: '刷新预约',
                  icon: AppIcons.refresh,
                  outlined: true,
                  onPressed: disabled ? null : onRefresh,
                ),
              ],
            ),
            if (current != null) ...[
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '第 ${current.page} 页 · 共 ${current.totalCount} 条',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontFeatures: tabularTime,
                    ),
                  ),
                  if (current.page > 1)
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          AppLayout.minTap,
                          AppLayout.minTap,
                        ),
                      ),
                      onPressed: disabled
                          ? null
                          : () => onPageChanged(current.page - 1),
                      child: const Text('上一页'),
                    ),
                  if (current.hasMore)
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          AppLayout.minTap,
                          AppLayout.minTap,
                        ),
                      ),
                      onPressed: disabled
                          ? null
                          : () => onPageChanged(current.page + 1),
                      child: const Text('下一页'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LibraryBookingsLoadingSkeleton extends StatelessWidget {
  const LibraryBookingsLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tint = colors.surfaceContainerHighest.withValues(alpha: 0.45);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 2; i++) ...[
          if (i > 0) const SizedBox(height: AppSpace.sm),
          QuietCard(
            child: Padding(
              padding: const EdgeInsets.all(AppLayout.focusInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 112,
                    height: 22,
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Container(
                    width: 180,
                    height: 30,
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Container(
                    width: 144,
                    height: 16,
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class LibraryBookingsEmptyCard extends StatelessWidget {
  const LibraryBookingsEmptyCard({
    super.key,
    required this.page,
    required this.begin,
    required this.end,
    required this.now,
    required this.busy,
    required this.onGoToSelectSeat,
    required this.onViewRecent30Days,
  });

  final LibraryBookingPage page;
  final DateTime begin, end, now;
  final bool busy;
  final VoidCallback onGoToSelectSeat, onViewRecent30Days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final today = dateOnly(now);
    final weekBegin = calendarAdd(today, 1 - today.weekday);
    final weekEnd = calendarAdd(weekBegin, 6);
    final isThisWeek = dateOnly(begin) == weekBegin && dateOnly(end) == weekEnd;
    final title = page.page == 1 && !page.hasMore ? '暂无座位预约' : '本页无座位预约';

    return QuietCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: highContrast
                        ? colors.surface
                        : colors.primaryContainer.withValues(
                            alpha: dark ? 0.50 : 0.85,
                          ),
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    border: highContrast
                        ? Border.all(color: colors.outline)
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.sm),
                    child: AppIcon(
                      AppIcons.book,
                      size: AppControl.icon,
                      color: colors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              page.page == 1 && !page.hasMore
                  ? '当前查询范围内没有预约记录，可以回到选座页挑选合适时段。'
                  : '该页暂无更多记录，可以切回上一页或扩大查询范围。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                AppActionButton(
                  label: '去选座',
                  icon: AppIcons.chevronLeft,
                  onPressed: busy ? null : onGoToSelectSeat,
                ),
                if (isThisWeek)
                  AppActionButton(
                    label: '查看近 30 天',
                    icon: AppIcons.calendar,
                    outlined: true,
                    onPressed: busy ? null : onViewRecent30Days,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class LibraryBookingFocusTicket extends StatelessWidget {
  const LibraryBookingFocusTicket({
    super.key,
    required this.row,
    required this.now,
    required this.canCancel,
    required this.busy,
    required this.onCancel,
    required this.onOpenOfficial,
  });

  final LibraryBooking row;
  final DateTime now;
  final bool canCancel, busy;
  final VoidCallback onCancel, onOpenOfficial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final labels = libraryBookingStatusLabels(row.status);
    final chipLabels = labels.isEmpty ? const ['已登记'] : labels;
    final timeHint = libraryBookingTimeHint(row, now);
    final place = row.room.isEmpty ? row.seat : '${row.room} · ${row.seat}';
    final metadata = labels.isEmpty
        ? '预约编号 ${row.id}'
        : '${labels.join(' · ')} · 预约编号 ${row.id}';

    final beginParts = row.begin.trim().split(RegExp(r'\s+'));
    final endParts = row.end.trim().split(RegExp(r'\s+'));
    final sameDay =
        beginParts.length >= 2 &&
        endParts.length >= 2 &&
        beginParts[0] == endParts[0];

    String? dayTag;
    if (sameDay) {
      final today = dateOnly(now);
      final tomorrow = calendarAdd(today, 1);
      final day = beginParts[0];
      if (day == isoDate(today)) {
        dayTag = '$day · 今天';
      } else if (day == isoDate(tomorrow)) {
        dayTag = '$day · 明天';
      } else {
        dayTag = day;
      }
    }

    return Padding(
      key: ValueKey('library-booking-focus-${row.id}'),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        AppSpace.lg,
        AppSpace.md,
      ),
      child: AcrylicSurface(
        radius: AppRadius.focus,
        blurKey: ValueKey('library-booking-blur-${row.id}'),
        liquidGlass: true,
        child: Padding(
          padding: const EdgeInsets.all(AppLayout.focusInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final label in chipLabels)
                    _BookingStatusChip(label: label),
                  if (timeHint != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.sm,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: highContrast
                            ? colors.surface
                            : colors.primaryContainer.withValues(
                                alpha: dark ? 0.55 : 0.90,
                              ),
                        borderRadius: BorderRadius.circular(AppRadius.small),
                        border: Border.all(
                          width: highContrast ? 1.1 : 0.7,
                          color: highContrast
                              ? colors.outline
                              : colors.primary.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(
                            AppIcons.clock,
                            size: 13,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            timeHint,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w600,
                              fontFeatures: tabularTime,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                children: [
                  if (sameDay)
                    Text(
                      '${beginParts[1]}–${endParts[1]}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                        fontFeatures: tabularTime,
                      ),
                    )
                  else
                    Text(
                      '${row.begin} 至 ${row.end}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                        fontFeatures: tabularTime,
                      ),
                    ),
                  Text(
                    row.seat,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabularTime,
                    ),
                  ),
                ],
              ),
              if (dayTag != null) ...[
                const SizedBox(height: 2),
                Text(
                  dayTag,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFeatures: tabularTime,
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.sm),
              Text(place, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpace.xs),
              Text(
                metadata,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontFeatures: tabularTime,
                ),
              ),
              if (!busy) ...[
                const SizedBox(height: AppSpace.md),
                Divider(
                  height: 1,
                  thickness: 0.7,
                  color: highContrast
                      ? colors.outline
                      : colors.outlineVariant.withValues(alpha: 0.65),
                ),
                const SizedBox(height: AppSpace.sm),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: [
                    if (canCancel)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(
                            AppLayout.minTap,
                            AppLayout.minTap,
                          ),
                          foregroundColor: colors.error,
                          side: BorderSide(
                            color: highContrast
                                ? colors.outline
                                : colors.error.withValues(alpha: 0.55),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppControl.radius,
                            ),
                          ),
                        ),
                        onPressed: onCancel,
                        child: const Text('取消预约'),
                      ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          AppLayout.minTap,
                          AppLayout.minTap,
                        ),
                      ),
                      onPressed: onOpenOfficial,
                      icon: const AppIcon(
                        AppIcons.globe,
                        size: AppControl.icon,
                      ),
                      label: const Text('官方预约页'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class LibraryBookingHistoryRow extends StatelessWidget {
  const LibraryBookingHistoryRow({
    super.key,
    required this.row,
    required this.canCancel,
    required this.busy,
    required this.onCancel,
  });

  final LibraryBooking row;
  final bool canCancel, busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final labels = libraryBookingStatusLabels(row.status);
    final place = row.room.isEmpty ? row.seat : '${row.room} · ${row.seat}';
    final metadata = labels.isEmpty
        ? '预约编号 ${row.id}'
        : '${labels.join(' · ')} · 预约编号 ${row.id}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        AppSpace.lg,
        AppSpace.sm,
      ),
      child: QuietCard(
        key: ValueKey('library-booking-history-${row.id}'),
        cornerRadius: AppRadius.input,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(place, style: theme.textTheme.titleMedium)),
                  const SizedBox(width: AppSpace.sm),
                  _BookingStatusChip(
                    label: labels.isEmpty ? '已登记' : labels.first,
                    muted: true,
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                '${row.begin} 至 ${row.end}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFeatures: tabularTime,
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                metadata,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontFeatures: tabularTime,
                ),
              ),
              if (canCancel && !busy) ...[
                const SizedBox(height: AppSpace.xs),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(
                      AppLayout.minTap,
                      AppLayout.minTap,
                    ),
                  ),
                  onPressed: onCancel,
                  child: const Text('取消预约'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BookingStatusChip extends StatelessWidget {
  const _BookingStatusChip({required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);

    final isError = label == '违约' || label == '审核未通过';
    final isAmber = label == '待审核' || label == '暂离中';
    final isPositive =
        label == '待生效' || label == '生效中' || label == '已签到' || label == '审核通过';

    final Color bg;
    final Color fg;
    final Color border;
    if (isError) {
      fg = colors.error;
      bg = highContrast
          ? colors.surface
          : colors.errorContainer.withValues(alpha: dark ? 0.45 : 0.70);
      border = highContrast
          ? colors.outline
          : colors.error.withValues(alpha: 0.35);
    } else if (isAmber && !muted) {
      final tone = LibrarySeatPalette.toneOf(
        context,
        LibrarySeatStatus.partial,
      );
      fg = tone.foreground;
      bg = tone.background;
      border = tone.border;
    } else if (isPositive && !muted) {
      final tone = LibrarySeatPalette.toneOf(
        context,
        LibrarySeatStatus.available,
      );
      fg = tone.foreground;
      bg = tone.background;
      border = tone.border;
    } else {
      fg = colors.onSurfaceVariant;
      bg = highContrast
          ? colors.surface
          : colors.surfaceContainerHighest.withValues(alpha: dark ? 0.65 : 0.75);
      border = highContrast ? colors.outline : colors.outlineVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(width: highContrast ? 1.1 : 0.7, color: border),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
