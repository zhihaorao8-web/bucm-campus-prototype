import '../design/app_tokens.dart';
import 'package:flutter/material.dart';
import 'course_surface.dart';
import '../domain/schedule.dart';
import 'app_icons.dart';
import 'app_theme.dart';

class ScheduleSyncCard extends StatelessWidget {
  const ScheduleSyncCard({
    super.key,
    this.semester,
    this.updated,
    required this.demo,
    this.onImport,
    this.footer,
  });
  final String? semester;
  final DateTime? updated;
  final bool demo;
  final VoidCallback? onImport;
  final Widget? footer;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return QuietCard(
      key: const ValueKey('schedule-sync-card'),
      cornerRadius: AppRadius.card,
      insideMargin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpace.comfortable),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: AppIcon(AppIcons.sync, color: colors.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '教务课表',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            semester == null ? '尚未导入课表' : '$semester 学期',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontFeatures: tabularTime,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  demo
                      ? '正在体验合成示例，不代表本人同步状态'
                      : semester == null
                      ? '登录学校官方页面后，课表可保存在本机离线查看'
                      : updated == null
                      ? '本学期更新时间未知，已保存的课表可离线查看'
                      : '本学期更新于 ${schoolTimestamp(updated!)}',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: AppType.secondary,
                    fontFeatures: tabularTime,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  key: const ValueKey('settings-import-schedule'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(AppLayout.minTap, AppLayout.minTap),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg,
                      vertical: AppSpace.md,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  onPressed: demo ? null : onImport,
                  icon: const AppIcon(AppIcons.sync, size: AppControl.icon),
                  label: Text(
                    demo
                        ? '退出示例后导入本人课表'
                        : semester == null
                        ? '从学校导入课表'
                        : '导入或刷新课表',
                  ),
                ),
              ],
            ),
          ),
          if (footer != null) ...[
            Divider(
              height: 1,
              thickness: 0.5,
              indent: AppSpace.comfortable,
              endIndent: AppSpace.comfortable,
              color: colors.outlineVariant,
            ),
            footer!,
          ],
        ],
      ),
    );
  }
}
