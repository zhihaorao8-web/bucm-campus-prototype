import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import '../data/classroom_library.dart';
import '../data/classroom_timeline.dart';
import '../domain/classroom.dart';
import '../domain/schedule.dart';

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
  final void Function(ClassroomRecording, String) onPlay;
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
          MiuixCard(
            child: Material(
              type: MaterialType.transparency,
              child: ListTile(
                selected: lesson,
                title: Text(visible[i].record.label),
                subtitle: Text(
                  '来源：${visible[i].course.teacher.isEmpty ? '学校未提供教师' : visible[i].course.teacher}${visible[i].course.group.isEmpty ? '' : ' · ${visible[i].course.group}'}\n${visible[i].record.place.isEmpty ? '学校未提供地点' : visible[i].record.place} · ${visible[i].record.published ? '已发布' : '未发布或暂不可观看'}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.play_circle_outline),
                onTap: busy || !visible[i].record.published
                    ? null
                    : () => onPlay(visible[i].record, visible[i].course.id),
              ),
            ),
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
        ExpansionTile(
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
