import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/appearance_controller.dart';

/// Lightweight acrylic for course lists and dense grids. The background is
/// already diffused, so these surfaces need no individual backdrop filters.
class CourseSurface extends ConsumerWidget {
  const CourseSurface({
    super.key,
    required this.child,
    this.color,
    this.radius = 24,
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
        translucent &&
        settings.blur &&
        settings.glass &&
        settings.contrast <= 0 &&
        !MediaQuery.highContrastOf(context);
    final base = color ?? colors.surfaceContainer;
    final alpha = dense ? (dark ? .84 : .90) : (dark ? .64 : .78);
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
                    base.withValues(alpha: alpha + .02),
                    base.withValues(alpha: alpha - .02),
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
