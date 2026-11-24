import '../design/app_tokens.dart';
import 'visual_policy.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/appearance_controller.dart';
import 'navigation_motion.dart';

Future<T?> showQuietSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? barrierLabel,
  BoxConstraints? constraints,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  showDragHandle: false,
  barrierLabel: barrierLabel,
  constraints: constraints,
  // Keyboard or mouse (traditional highlight) opens at once so focus lands without a wait.
  sheetAnimationStyle:
      MediaQuery.disableAnimationsOf(context) ||
          FocusManager.instance.highlightMode == FocusHighlightMode.traditional
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: AppMotion.routeEnter,
          reverseDuration: AppMotion.routeExit,
          curve: navigationCurve,
          reverseCurve: FlippedCurve(navigationCurve),
        ),
  builder: (context) => QuietSheet(child: builder(context)),
);

class QuietSheet extends ConsumerWidget {
  const QuietSheet({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentAppearanceProvider);
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opaque = AppVisualPolicy.of(context, settings).opaque;
    const radius = BorderRadius.vertical(top: Radius.circular(AppRadius.sheet));
    return BackdropTransitionBuilder(
      builder: (context, suspended) => ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          enabled: !opaque && !suspended,
          filter: ui.ImageFilter.blur(
            sigmaX: AppSurface.sheetBlur,
            sigmaY: AppSurface.sheetBlur,
            tileMode: ui.TileMode.clamp,
          ),
          child: Material(
            color: Colors.transparent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface.withValues(
                  alpha: opaque ? 1 : AppSurface.sheetAlpha(dark),
                ),
                borderRadius: radius,
                border: Border.all(
                  width: .7,
                  color: opaque
                      ? colors.outlineVariant
                      : Colors.white.withValues(alpha: dark ? .12 : .75),
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class QuietCard extends StatelessWidget {
  const QuietCard({
    super.key,
    required this.child,
    this.cornerRadius = AppRadius.card,
    this.insideMargin = EdgeInsets.zero,
  });
  final Widget child;
  final double cornerRadius;
  final EdgeInsetsGeometry insideMargin;

  @override
  Widget build(BuildContext context) => CourseSurface(
    radius: cornerRadius,
    child: MiuixCard(
      cornerRadius: cornerRadius,
      insideMargin: insideMargin,
      colors: MiuixCardColors(
        color: Colors.transparent,
        contentColor: Theme.of(context).colorScheme.onSurface,
      ),
      child: child,
    ),
  );
}

/// Lightweight acrylic for course lists and dense grids. The background is
/// already diffused, so these surfaces need no individual backdrop filters.
class CourseSurface extends ConsumerWidget {
  const CourseSurface({
    super.key,
    required this.child,
    this.color,
    this.radius = AppRadius.card,
    this.dense = false,
    this.translucent = true,
  });
  final Widget child;
  final Color? color;
  final double radius;
  final bool dense, translucent;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentAppearanceProvider);
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final glass =
        translucent && AppVisualPolicy.of(context, settings).translucent;
    final base = color ?? colors.surfaceContainer;
    final alpha = AppSurface.listAlpha(dark, dense: dense);
    final shape = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: shape,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          color: glass ? null : base,
          gradient: glass
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    base.withValues(alpha: alpha + AppSurface.edgeVariation),
                    base.withValues(alpha: alpha - AppSurface.edgeVariation),
                  ],
                )
              : null,
          border: Border.all(
            width: dense ? .5 : .7,
            color: glass
                ? Colors.white.withValues(alpha: dark ? .12 : .75)
                : colors.outlineVariant,
          ),
        ),
        child: child,
      ),
    );
  }
}
