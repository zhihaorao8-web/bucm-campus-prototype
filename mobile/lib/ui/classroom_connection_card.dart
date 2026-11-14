import 'package:flutter/material.dart';
import '../application/classroom_connection_status.dart';
import 'app_icons.dart';
import 'app_theme.dart';
import 'course_surface.dart';

/// Unified connection status, directory summary, and direct maintenance card
/// for the recorded classroom section.
class ClassroomConnectionCard extends StatelessWidget {
  const ClassroomConnectionCard({
    super.key,
    required this.status,
    required this.directoryLabel,
    required this.busy,
    this.summaryLabel,
    this.dateHintLabel,
    this.onRetry,
    this.onOpenSchool,
    this.onRefresh,
    this.onRematch,
  });

  final ClassroomConnectionStatus status;
  final String directoryLabel;
  final bool busy;
  final String? summaryLabel;
  final String? dateHintLabel;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenSchool;
  final VoidCallback? onRefresh;
  final VoidCallback? onRematch;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasActions = onRefresh != null || onRematch != null;
    final recovery = status.needsRecovery && (onRetry != null || onOpenSchool != null);
    final badgeBg = status.needsRecovery
        ? colors.errorContainer.withValues(alpha: .72)
        : colors.primaryContainer.withValues(alpha: .78);
    final badgeFg = status.needsRecovery ? colors.error : colors.primary;

    return QuietCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: AppIcon(
                    status.needsRecovery ? AppIcons.info : AppIcons.sync,
                    size: 20,
                    color: badgeFg,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status.label,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        directoryLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontFeatures: tabularTime,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (status.detail != null &&
                status.detail!.trim().isNotEmpty &&
                status.detail != status.label) ...[
              const SizedBox(height: 10),
              Text(
                status.detail!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            if (summaryLabel != null || dateHintLabel != null) ...[
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.onSurface.withValues(alpha: .04),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (summaryLabel != null)
                        Text(
                          summaryLabel!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      if (dateHintLabel != null) ...[
                        if (summaryLabel != null) const SizedBox(height: 4),
                        Text(
                          dateHintLabel!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.primary,
                            fontFeatures: tabularTime,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            if (busy) ...[
              const SizedBox(height: 12),
              const ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(4)),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            ],
            if (recovery) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (onRetry != null)
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 46),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: busy ? null : onRetry,
                      icon: const AppIcon(AppIcons.refresh, size: 17),
                      label: const Text('重试连接'),
                    ),
                  if (onOpenSchool != null)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 46),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        side: BorderSide(
                          color: colors.outlineVariant.withValues(alpha: .8),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: onOpenSchool,
                      icon: const AppIcon(AppIcons.chevronRight, size: 17),
                      label: const Text('打开学校页面'),
                    ),
                ],
              ),
            ],
            if (hasActions) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (onRefresh != null)
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 46),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: busy ? null : onRefresh,
                      icon: const AppIcon(AppIcons.refresh, size: 18),
                      label: const Text('刷新录播'),
                    ),
                  if (onRematch != null)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 46),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        side: BorderSide(
                          color: colors.outlineVariant.withValues(alpha: .8),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: busy ? null : onRematch,
                      icon: const AppIcon(AppIcons.swapHorizontal, size: 18),
                      label: const Text('重新匹配同名课程'),
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
