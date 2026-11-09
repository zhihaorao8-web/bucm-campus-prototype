import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import '../domain/schedule.dart';
import 'app_theme.dart';

String courseLocation(Course course) => course.place.isNotEmpty
    ? course.place
    : course.online
    ? '线上课程'
    : '学校未提供地点';

void showCourseDetails(BuildContext context, Course course) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              course.name,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            for (final item in <(String, String)>[
              ('教师', course.teacher.isEmpty ? '未识别教师信息' : course.teacher),
              (
                '数据来源',
                switch (course.dataSource) {
                  'official-xls' => '学校官方 Excel 导出',
                  'dom' => '学校课表页面读取',
                  'synthetic' => '合成示例',
                  _ => '未记录来源',
                },
              ),
              ('地点', courseLocation(course)),
              ('授课周次', '${course.weeks}周，星期${weekdays[course.day - 1]}'),
              ('节次', course.periods.join('、')),
              (
                '北京时间',
                course.segments.map((s) => '${s.start}–${s.end}').join('\n'),
              ),
              ('学期', '${course.semester}\n第1周周一 ${isoDate(course.termStart)}'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 88,
                      child: Text(
                        item.$1,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item.$2,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(),
            Text(
              '时间按你确认的作息规则显示。${course.deliverySource == 'user-weekend-rule' ? '周末线上授课标记来自你的说明；原始地点保持不变。' : ''}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: MiuixButton(
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                onPressed: () => Navigator.pop(context),
                child: const Text('完成'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class CourseRow extends StatelessWidget {
  const CourseRow({
    super.key,
    required this.event,
    this.conflict = false,
    this.now,
  });
  final Occurrence event;
  final bool conflict;
  final DateTime? now;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = now != null && event.activeAt(now!);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MiuixCard(
        cornerRadius: 24,
        insideMargin: const EdgeInsets.all(20),
        onPressed: () => showCourseDetails(context, event.course),
        colors: MiuixCardColors(
          color: AppColors.course(context, event.course.name),
          contentColor: colors.onSurface,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64 * MediaQuery.textScalerOf(context).scale(16) / 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.segment.start,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    event.segment.end,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.course.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(courseLocation(event.course)),
                  if (active || conflict)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        [if (active) '正在上课', if (conflict) '时段重叠'].join('，'),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: conflict ? colors.error : colors.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }
}

class EmptySchedule extends StatelessWidget {
  const EmptySchedule({
    super.key,
    required this.onImport,
    required this.onDemo,
  });
  final VoidCallback onImport, onDemo;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.calendar_month_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text('把课表留在手机里', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        const Text(
          '在学校官方页面登录，导入后就能离线查看。应用不保存你的密码。',
          style: TextStyle(fontSize: 16, height: 1.6),
        ),
        const SizedBox(height: 28),
        MiuixButton(
          colors: MiuixButtonDefaults.buttonColorsPrimary(context),
          onPressed: onImport,
          child: const Text('从学校导入课表'),
        ),
        const SizedBox(height: 12),
        TextButton(onPressed: onDemo, child: const Text('先体验合成示例')),
      ],
    ),
  );
}
