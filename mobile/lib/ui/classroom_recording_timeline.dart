import 'app_icon_controls.dart';
import 'app_icons.dart';
import 'package:flutter/material.dart';
import 'course_surface.dart';
import '../data/classroom_library.dart';
import '../data/classroom_timeline.dart';
import '../domain/classroom.dart';
import '../domain/schedule.dart';

class ClassroomRecordingTile extends StatefulWidget {
  const ClassroomRecordingTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onPlay,
    this.selected = false,
  });
  final String title, subtitle;
  final ValueChanged<GlobalKey>? onPlay;
  final bool selected;

  @override
  State<ClassroomRecordingTile> createState() => _ClassroomRecordingTileState();
}

class _ClassroomRecordingTileState extends State<ClassroomRecordingTile> {
  final button = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return QuietCard(
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          selected: widget.selected,
          title: Text(widget.title),
          subtitle: Text(widget.subtitle),
          isThreeLine: true,
          trailing: Container(
            key: button,
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: AppIcon(AppIcons.play, size: 24, color: colors.onPrimary),
            ),
          ),
          onTap: widget.onPlay == null ? null : () => widget.onPlay!(button),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(lesson ? '当天暂无录播，可查看其他日期。' : '学校当前没有其他可显示的录播记录。'),
          ),
        for (var i = 0; i < visible.length; i++) ...[
          if (!lesson &&
              (i == 0 ||
                  isoDate(visible[i - 1].record.date) !=
                      isoDate(visible[i].record.date)))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                isoDate(visible[i].record.date),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ClassroomRecordingTile(
            key: ValueKey((visible[i].course.id, visible[i].record.id)),
            selected: lesson,
            title: visible[i].record.label,
            subtitle:
                '来源：${visible[i].course.teacher.isEmpty ? '学校未提供教师' : visible[i].course.teacher}${visible[i].course.group.isEmpty ? '' : ' · ${visible[i].course.group}'}\n${visible[i].record.place.isEmpty ? '学校未提供地点' : visible[i].record.place} · ${visible[i].record.published ? '已发布' : '未发布或暂不可观看'}',
            onPlay: busy || !visible[i].record.published
                ? null
                : (button) =>
                      onPlay(visible[i].record, visible[i].course.id, button),
          ),
        ],
        if (entries.isNotEmpty) ...[
          const SizedBox(height: 8),
          Center(child: Text('第 $current 页 · 共 ${entries.length} 条')),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            children: [
              TextButton(
                onPressed: busy || current == 1
                    ? null
                    : () => change(current - 1),
                child: Text(lesson ? '本次上页' : '上一页'),
              ),
              TextButton(
                onPressed: busy || current == count
                    ? null
                    : () => change(current + 1),
                child: Text(lesson ? '本次下页' : '下一页'),
              ),
            ],
          ),
        ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppExpansionTile(
          title: Text('回放来源（${archive.courses.length}）'),
          children: [
            for (final source in archive.sources ?? [archive])
              ListTile(
                title: Text(
                  source.course.teacher.isEmpty
                      ? '学校未提供教师'
                      : source.course.teacher,
                ),
                subtitle: Text('${source.course.group} · ${source.total}条录播'),
              ),
          ],
        ),
        if (date != null) ...[
          Text('本次课回放', style: Theme.of(context).textTheme.titleLarge),
          Text(isoDate(date!)),
          group(context, lesson, lessonPage, onLessonPage, lesson: true),
          const SizedBox(height: 16),
        ],
        Text(
          date == null ? '课程回放' : '其他日期回放',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        group(context, others, page, onPage, lesson: false),
      ],
    );
  }
}
