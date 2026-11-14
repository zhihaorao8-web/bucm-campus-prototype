import 'package:flutter/material.dart';
import '../data/classroom_library.dart';
import '../data/classroom_timeline.dart';
import '../domain/classroom.dart';
import '../domain/schedule.dart';
import 'app_icon_controls.dart';
import 'app_icons.dart';
import 'app_theme.dart';
import 'course_surface.dart';

class ClassroomRecordingTile extends StatefulWidget {
  const ClassroomRecordingTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onPlay,
    this.selected = false,
    this.sourceLabel,
    this.placeLabel,
    this.published,
  });

  final String title;
  final String subtitle;
  final ValueChanged<GlobalKey>? onPlay;
  final bool selected;
  final String? sourceLabel;
  final String? placeLabel;
  final bool? published;

  @override
  State<ClassroomRecordingTile> createState() => _ClassroomRecordingTileState();
}

class _ClassroomRecordingTileState extends State<ClassroomRecordingTile> {
  final button = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final playable = widget.onPlay != null;
    final structured =
        widget.sourceLabel != null ||
        widget.placeLabel != null ||
        widget.published != null;
    final isPublished = widget.published ?? playable;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: QuietCard(
        cornerRadius: 22,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: widget.selected
                ? colors.primaryContainer.withValues(alpha: .16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            border: widget.selected
                ? Border.all(
                    width: .9,
                    color: colors.primary.withValues(alpha: .35),
                  )
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 8, 14, 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              selected: widget.selected,
              title: Text(
                widget.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: tabularTime,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: !structured
                    ? Text(
                        widget.subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.4,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.sourceLabel != null)
                            Text(
                              widget.sourceLabel!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          if (widget.sourceLabel != null)
                            const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (widget.placeLabel != null)
                                Text(
                                  widget.placeLabel!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: isPublished
                                      ? colors.primaryContainer.withValues(
                                          alpha: .65,
                                        )
                                      : colors.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isPublished ? '已发布' : '未发布或暂不可观看',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: isPublished
                                        ? colors.onPrimaryContainer
                                        : colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
              trailing: Semantics(
                button: true,
                enabled: playable,
                label: '播放 ${widget.title}',
                child: Container(
                  key: button,
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: playable
                        ? colors.primary
                        : colors.surfaceContainerHighest,
                    shape: BoxShape.circle,
                    boxShadow: playable
                        ? [
                            BoxShadow(
                              color: colors.primary.withValues(alpha: .24),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: AppIcon(
                      AppIcons.play,
                      size: 22,
                      color: playable
                          ? colors.onPrimary
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              onTap: playable ? () => widget.onPlay!(button) : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact frosted card bar for switching between paginated recording lists.
class ClassroomPaginationBar extends StatelessWidget {
  const ClassroomPaginationBar({
    super.key,
    required this.currentPage,
    required this.totalItems,
    required this.previousLabel,
    required this.nextLabel,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentPage;
  final int totalItems;
  final String previousLabel;
  final String nextLabel;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final buttonStyle = TextButton.styleFrom(
      minimumSize: const Size(48, 44),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: QuietCard(
        cornerRadius: 18,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final compact = constraints.maxWidth < 280 * textScale;
              final prev = TextButton.icon(
                style: buttonStyle,
                onPressed: onPrevious,
                icon: const AppIcon(AppIcons.chevronLeft, size: 16),
                label: Text(previousLabel),
              );
              final next = TextButton(
                style: buttonStyle,
                onPressed: onNext,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(nextLabel),
                    const SizedBox(width: 4),
                    const AppIcon(AppIcons.chevronRight, size: 16),
                  ],
                ),
              );
              final counter = Text(
                '第 $currentPage 页 · 共 $totalItems 条',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontFeatures: tabularTime,
                ),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    counter,
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [prev, next],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  prev,
                  Expanded(child: counter),
                  next,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class ClassroomRecordingTimeline extends StatelessWidget {
  const ClassroomRecordingTimeline({
    super.key,
    required this.archive,
    this.date,
    required this.page,
    required this.lessonPage,
    required this.onPage,
    required this.onLessonPage,
    required this.onPlay,
    required this.busy,
  });

  final ClassroomArchive archive;
  final DateTime? date;
  final int page, lessonPage;
  final ValueChanged<int> onPage, onLessonPage;
  final void Function(ClassroomRecording, String, GlobalKey) onPlay;
  final bool busy;

  Widget _emptyNotice(BuildContext context, String text) {
    final colors = Theme.of(context).colorScheme;
    return QuietCard(
      cornerRadius: 20,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            AppIcon(
              AppIcons.calendar,
              size: 20,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourcesCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sources = archive.sources ?? [archive];
    return QuietCard(
      cornerRadius: 20,
      child: Material(
        type: MaterialType.transparency,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: AppExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            title: Row(
              children: [
                AppIcon(
                  AppIcons.mediaLibrary,
                  size: 18,
                  color: colors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '回放来源（${archive.courses.length}）',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabularTime,
                    ),
                  ),
                ),
              ],
            ),
            children: [
              for (var i = 0; i < sources.length; i++) ...[
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: colors.outlineVariant.withValues(alpha: .55),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sources[i].course.teacher.isEmpty
                                  ? '学校未提供教师'
                                  : sources[i].course.teacher,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w500),
                            ),
                            if (sources[i].course.group.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                sources[i].course.group,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.secondaryContainer.withValues(alpha: .65),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${sources[i].total} 条录播',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: colors.onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                                fontFeatures: tabularTime,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget group(
    BuildContext context,
    List<ClassroomTimelineEntry> entries,
    int requestedPage,
    ValueChanged<int> change, {
    required bool lesson,
  }) {
    final size = archive.pages.first.pageSize;
    final count = ((entries.length + size - 1) ~/ size).clamp(1, 10000);
    final current = requestedPage.clamp(1, count);
    final visible = entries.skip((current - 1) * size).take(size).toList();
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (entries.isEmpty)
          _emptyNotice(
            context,
            lesson ? '当天暂无录播，可查看其他日期。' : '学校当前没有其他可显示的录播记录。',
          ),
        for (var i = 0; i < visible.length; i++) ...[
          if (!lesson &&
              (i == 0 ||
                  isoDate(visible[i - 1].record.date) !=
                      isoDate(visible[i].record.date)))
            Padding(
              padding: EdgeInsets.fromLTRB(4, i == 0 ? 4 : 14, 4, 8),
              child: Text(
                isoDate(visible[i].record.date),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontFeatures: tabularTime,
                ),
              ),
            ),
          ClassroomRecordingTile(
            key: ValueKey((visible[i].course.id, visible[i].record.id)),
            selected: lesson,
            title: visible[i].record.label,
            sourceLabel:
                '来源：${visible[i].course.teacher.isEmpty ? '学校未提供教师' : visible[i].course.teacher}${visible[i].course.group.isEmpty ? '' : ' · ${visible[i].course.group}'}',
            placeLabel: visible[i].record.place.isEmpty
                ? '学校未提供地点'
                : visible[i].record.place,
            published: visible[i].record.published,
            subtitle:
                '来源：${visible[i].course.teacher.isEmpty ? '学校未提供教师' : visible[i].course.teacher}${visible[i].course.group.isEmpty ? '' : ' · ${visible[i].course.group}'}\n${visible[i].record.place.isEmpty ? '学校未提供地点' : visible[i].record.place} · ${visible[i].record.published ? '已发布' : '未发布或暂不可观看'}',
            onPlay: busy || !visible[i].record.published
                ? null
                : (button) =>
                      onPlay(visible[i].record, visible[i].course.id, button),
          ),
        ],
        if (entries.isNotEmpty)
          ClassroomPaginationBar(
            currentPage: current,
            totalItems: entries.length,
            previousLabel: lesson ? '本次上页' : '上一页',
            nextLabel: lesson ? '本次下页' : '下一页',
            onPrevious: busy || current == 1 ? null : () => change(current - 1),
            onNext: busy || current == count ? null : () => change(current + 1),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = classroomTimeline(archive);
    final lesson = date == null
        ? <ClassroomTimelineEntry>[]
        : recordingsOnDate(entries, date!);
    final others = date == null
        ? entries
        : entries
              .where((entry) => isoDate(entry.record.date) != isoDate(date!))
              .toList();
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sourcesCard(context),
        if (date != null) ...[
          const SizedBox(height: 20),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              Text('本次课回放', style: Theme.of(context).textTheme.titleLarge),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isoDate(date!),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabularTime,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          group(context, lesson, lessonPage, onLessonPage, lesson: true),
        ],
        const SizedBox(height: 20),
        Text(
          date == null ? '课程回放' : '其他日期回放',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        group(context, others, page, onPage, lesson: false),
      ],
    );
  }
}
