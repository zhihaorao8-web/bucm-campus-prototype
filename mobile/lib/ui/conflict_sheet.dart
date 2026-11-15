import '../design/app_tokens.dart';
import 'package:flutter/material.dart';
import '../domain/schedule.dart';
import 'app_icons.dart';
import 'app_theme.dart';
import 'course_surface.dart';
import 'course_widgets.dart';

/// Returns (course, prefer-in-grid); the caller opens the normal course route.
Future<(Course, bool)?> showConflictCourses(
  BuildContext context,
  List<Occurrence> events,
  Course preferred,
) => showQuietSheet<(Course, bool)>(
  context,
  barrierLabel: '关闭重叠课程',
  constraints: BoxConstraints(
    maxWidth: 640,
    maxHeight: MediaQuery.sizeOf(context).height * .86,
  ),
  builder: (context) => SafeArea(
    top: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xl,
            AppSpace.md,
            AppSpace.sm,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '重叠课程',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '关闭重叠课程',
                onPressed: () => Navigator.pop(context),
                icon: const AppIcon(AppIcons.close),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xl,
            0,
            AppSpace.xl,
            AppSpace.lg,
          ),
          child: Text(
            '此时段有${events.length}门课程。优先显示只调整本次周表外观，以下为各课程的实际授课信息。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: AppType.secondary,
            ),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.comfortable,
              0,
              AppSpace.comfortable,
              AppSpace.xl,
            ),
            child: Column(
              children: [
                for (final event in events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.md),
                    child: QuietCard(
                      key: ValueKey('conflict-details-${event.course.id}'),
                      cornerRadius: 20,
                      insideMargin: const EdgeInsets.all(
                        AppLayout.compactCardInset,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.course.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${event.segment.start}–${event.segment.end} · ${shortDate(event.date)}',
                              style: const TextStyle(fontFeatures: tabularTime),
                            ),
                            const SizedBox(height: 6),
                            Text(courseLocation(event.course)),
                            Text(
                              event.course.teacher.isEmpty
                                  ? '学校未提供教师'
                                  : event.course.teacher,
                            ),
                            Text(
                              '${event.course.weeks}周 · 第${event.course.periods.join('、')}节',
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  key: ValueKey(
                                    'prefer-course-${event.course.id}',
                                  ),
                                  onPressed: event.course.id == preferred.id
                                      ? null
                                      : () => Navigator.pop(context, (
                                          event.course,
                                          true,
                                        )),
                                  child: Text(
                                    event.course.id == preferred.id
                                        ? '当前优先显示'
                                        : '设为优先显示',
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, (
                                    event.course,
                                    false,
                                  )),
                                  child: const Text('查看课程与录播'),
                                ),
                              ],
                            ),
                          ],
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
  ),
);
