import 'package:flutter/material.dart';
import '../design/app_tokens.dart';
import 'app_icons.dart';

void showAppNotice(
  BuildContext context,
  String text, {
  bool success = false,
  double bottomInset = 0,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  final foreground =
      success ? colors.onPrimaryContainer : colors.onInverseSurface;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: success ? 4 : 3),
        backgroundColor:
            success ? colors.primaryContainer : colors.inverseSurface,
        elevation: 0,
        margin: EdgeInsets.fromLTRB(
          AppSpace.lg,
          0,
          AppSpace.lg,
          AppSpace.md + bottomInset,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          side: success
              ? BorderSide(color: colors.primary.withValues(alpha: .28))
              : BorderSide.none,
        ),
        content: Row(
          children: [
            if (success) ...[
              AppIcon(AppIcons.check, size: AppControl.icon, color: foreground),
              const SizedBox(width: AppSpace.sm),
            ],
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  fontWeight: success ? FontWeight.w600 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
}

/// Shared maintenance/recovery action. Busy/permission decisions stay with the
/// caller, so "open school page" can remain available while a task waits.
class AppActionButton extends StatelessWidget {
  const AppActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.outlined = false,
    this.horizontalInset,
    this.iconSize = AppControl.icon,
  });
  final String label;
  final AppIconData icon;
  final VoidCallback? onPressed;
  final bool outlined;
  final double? horizontalInset;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.symmetric(
      horizontal:
          horizontalInset ??
          (outlined ? AppControl.secondaryInset : AppControl.inset),
      vertical: AppControl.verticalInset,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppControl.radius),
    );
    const minimum = Size(AppLayout.minTap, AppLayout.minTap);
    return outlined
        ? OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: minimum,
              padding: padding,
              shape: shape,
              side: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: .8),
              ),
            ),
            onPressed: onPressed,
            icon: AppIcon(icon, size: iconSize),
            label: Text(label),
          )
        : FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: minimum,
              padding: padding,
              shape: shape,
            ),
            onPressed: onPressed,
            icon: AppIcon(icon, size: iconSize),
            label: Text(label),
          );
  }
}

/// Shared sliding selection geometry. The parent owns layout, labels, focus,
/// semantics and material so a dense week switch need not mimic a large tab row.
class AppSegmentIndicator extends StatelessWidget {
  const AppSegmentIndicator({
    super.key,
    required this.selected,
    required this.count,
    required this.decoration,
    this.indicatorKey,
  }) : assert(count >= 2),
       assert(selected >= 0 && selected < count);
  final int selected, count;
  final Decoration decoration;
  final Key? indicatorKey;

  @override
  Widget build(BuildContext context) => AnimatedAlign(
    alignment: Alignment(-1 + 2 * selected / (count - 1), 0),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.segment,
    curve: AppMotion.segmentCurve,
    child: FractionallySizedBox(
      widthFactor: 1 / count,
      heightFactor: 1,
      child: DecoratedBox(key: indicatorKey, decoration: decoration),
    ),
  );
}
