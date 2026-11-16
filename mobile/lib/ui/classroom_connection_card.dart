import '../design/app_tokens.dart';
import 'app_controls.dart';
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
    final recovery =
        status.needsRecovery && (onRetry != null || onOpenSchool != null);
    final badgeBg = status.needsRecovery
        ? colors.errorContainer.withValues(alpha: .72)
        : colors.primaryContainer.withValues(alpha: .78);
    final badgeFg = status.needsRecovery ? colors.error : colors.primary;

    return QuietCard(
      child: Padding(
        padding: const EdgeInsets.all(AppLayout.compactCardInset),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                    vertical: AppSpace.control,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (summaryLabel != null)
                        Text(
                          summaryLabel!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      if (dateHintLabel != null) ...[
                        if (summaryLabel != null) const SizedBox(height: 4),
                        Text(
                          dateHintLabel!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
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
                    AppActionButton(
                      label: '重试连接',
                      icon: AppIcons.refresh,
                      onPressed: busy ? null : onRetry,
                      outlined: false,
                      horizontalInset: AppControl.secondaryInset,
                      iconSize: 17,
                    ),
                  if (onOpenSchool != null)
                    AppActionButton(
                      label: '打开学校页面',
                      icon: AppIcons.chevronRight,
                      onPressed: onOpenSchool,
                      outlined: true,
                      iconSize: 17,
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
                    AppActionButton(
                      label: '刷新录播',
                      icon: AppIcons.refresh,
                      onPressed: busy ? null : onRefresh,
                      outlined: false,
                    ),
                  if (onRematch != null)
                    AppActionButton(
                      label: '重新匹配同名课程',
                      icon: AppIcons.swapHorizontal,
                      onPressed: busy ? null : onRematch,
                      outlined: true,
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
