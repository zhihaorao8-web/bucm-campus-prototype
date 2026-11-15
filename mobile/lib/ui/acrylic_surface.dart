import '../design/app_tokens.dart';
import 'visual_policy.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/appearance_controller.dart';

/// A clipped, translucent course surface. Text is painted after the blur.
class AcrylicSurface extends ConsumerWidget {
  const AcrylicSurface({
    super.key,
    required this.child,
    this.radius = AppRadius.focus,
    this.blurKey = const ValueKey('focus-acrylic-blur'),
  });
  final Widget child;
  final double radius;
  final Key blurKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentAppearanceProvider);
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opaque = AppVisualPolicy.of(context, settings).opaque;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: opaque
            ? null
            : [
                BoxShadow(
                  color: (dark ? Colors.black : AppSurface.focusShadowLight)
                      .withValues(alpha: dark ? .04 : .045),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          key: blurKey,
          enabled: !opaque,
          filter: ui.ImageFilter.blur(
            sigmaX: AppSurface.focusBlur,
            sigmaY: AppSurface.focusBlur,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: opaque ? colors.surfaceContainer : null,
              gradient: opaque
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: AppSurface.focusFill(dark),
                    ),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                width: .8,
                color: opaque
                    ? colors.outlineVariant
                    : Colors.white.withValues(alpha: dark ? .15 : .80),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
