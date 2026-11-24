import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/appearance_controller.dart';
import '../design/app_tokens.dart';
import 'liquid_glass_surface.dart';
import 'visual_policy.dart';

/// A clipped, translucent course surface. Text is painted after the blur.
class AcrylicSurface extends ConsumerWidget {
  const AcrylicSurface({
    super.key,
    required this.child,
    this.radius = AppRadius.focus,
    this.blurKey = const ValueKey('focus-acrylic-blur'),
    this.liquidGlass = false,
    this.edgeDepth = AppLiquidGlass.focusEdgeDepth,
    this.refraction = AppLiquidGlass.focusRefraction,
  }) : assert(radius >= 0),
       assert(edgeDepth > 0),
       assert(refraction >= 0);

  final Widget child;
  final double radius;
  final Key blurKey;
  final bool liquidGlass;
  final double edgeDepth, refraction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentAppearanceProvider);
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final policy = AppVisualPolicy.of(context, settings);
    final opaque = policy.opaque;
    final useLiquidGlass = liquidGlass && policy.liquidGlass;
    final borderRadius = BorderRadius.circular(radius);
    final foreground = DecoratedBox(
      decoration: BoxDecoration(
        color: opaque ? colors.surfaceContainer : null,
        gradient: opaque
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: AppSurface.focusFill(dark),
              ),
        borderRadius: borderRadius,
        border: Border.all(
          width: .8,
          color: opaque
              ? colors.outlineVariant
              : Colors.white.withValues(alpha: dark ? .15 : .80),
        ),
      ),
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
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
        borderRadius: borderRadius,
        child: useLiquidGlass
            ? Stack(
                fit: StackFit.passthrough,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: LiquidGlassSurface(
                          radius: radius,
                          blur: AppSurface.focusBlur,
                          edgeDepth: edgeDepth,
                          refraction: refraction,
                          blurKey: blurKey,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                  foreground,
                ],
              )
            : BackdropFilter(
                key: blurKey,
                enabled: !opaque,
                filter: ui.ImageFilter.blur(
                  sigmaX: AppSurface.focusBlur,
                  sigmaY: AppSurface.focusBlur,
                ),
                child: foreground,
              ),
      ),
    );
  }
}
