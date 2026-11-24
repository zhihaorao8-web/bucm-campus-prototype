import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/appearance_controller.dart';
import '../design/app_tokens.dart';
import 'app_icons.dart';
import 'liquid_glass_surface.dart';
import 'visual_policy.dart';

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
  final foreground = success
      ? colors.onPrimaryContainer
      : colors.onInverseSurface;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: success ? 4 : 3),
        backgroundColor: success
            ? colors.primaryContainer
            : colors.inverseSurface,
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

/// Shared sliding selection geometry and optional liquid glass capsule. The
/// parent owns layout, labels, focus, semantics and container surface so a
/// dense week switch need not mimic a large tab row.
class AppSegmentIndicator extends StatelessWidget {
  const AppSegmentIndicator({
    super.key,
    required this.selected,
    required this.count,
    required this.decoration,
    this.indicatorKey,
    this.liquidGlass = false,
    this.radius,
    this.blur = AppLiquidGlass.segmentLensBlur,
    this.edgeDepth = AppLiquidGlass.segmentLensEdgeDepth,
    this.refraction = AppLiquidGlass.segmentLensRefraction,
  }) : assert(count >= 2),
       assert(selected >= 0 && selected < count),
       assert(radius == null || radius >= 0),
       assert(blur >= 0),
       assert(edgeDepth > 0),
       assert(refraction >= 0);

  final int selected, count;
  final Decoration decoration;
  final Key? indicatorKey;
  final bool liquidGlass;
  final double? radius;
  final double blur, edgeDepth, refraction;

  double _resolveRadius() {
    if (radius != null) return radius!;
    final current = decoration;
    if (current is BoxDecoration) {
      final borderRadius = current.borderRadius;
      if (borderRadius is BorderRadius && borderRadius.topLeft.x >= 0) {
        return borderRadius.topLeft.x;
      }
    }
    return AppRadius.inset;
  }

  Widget _buildSlide({required bool reducedMotion, required Widget child}) =>
      IgnorePointer(
        child: ExcludeSemantics(
          child: AnimatedAlign(
            alignment: Alignment(-1 + 2 * selected / (count - 1), 0),
            duration: reducedMotion ? Duration.zero : AppMotion.segment,
            curve: AppMotion.segmentCurve,
            child: FractionallySizedBox(
              widthFactor: 1 / count,
              heightFactor: 1,
              child: child,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!liquidGlass) {
      return _buildSlide(
        reducedMotion: MediaQuery.disableAnimationsOf(context),
        child: DecoratedBox(key: indicatorKey, decoration: decoration),
      );
    }
    return Consumer(
      builder: (context, ref, _) {
        final policy = AppVisualPolicy.of(
          context,
          ref.watch(currentAppearanceProvider),
        );
        final Widget pill;
        if (policy.liquidGlass) {
          final theme = Theme.of(context);
          final colors = theme.colorScheme;
          final dark = theme.brightness == Brightness.dark;
          final effectiveRadius = _resolveRadius();
          final lensRadius = BorderRadius.circular(effectiveRadius);
          pill = DecoratedBox(
            key: indicatorKey,
            decoration: BoxDecoration(
              borderRadius: lensRadius,
              boxShadow: AppLiquidGlass.lensShadows(
                dark,
                colors.primary,
                colors.onSurface,
              ),
            ),
            child: LiquidGlassSurface(
              radius: effectiveRadius,
              blur: blur,
              edgeDepth: edgeDepth,
              refraction: refraction,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    stops: const [0, .48, 1],
                    colors: AppLiquidGlass.lensFill(dark, colors.primary),
                  ),
                  borderRadius: lensRadius,
                  border: Border.all(
                    color: AppLiquidGlass.lensBorder(dark),
                    width: AppLiquidGlass.lensBorderWidth,
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          );
        } else {
          pill = DecoratedBox(key: indicatorKey, decoration: decoration);
        }
        return _buildSlide(reducedMotion: policy.reducedMotion, child: pill);
      },
    );
  }
}
