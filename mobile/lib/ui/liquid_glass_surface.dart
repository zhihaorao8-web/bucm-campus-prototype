import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/appearance_controller.dart';
import '../design/app_tokens.dart';
import 'visual_policy.dart';

final liquidGlassSupportedProvider = Provider<bool>(
  (ref) => ui.ImageFilter.isShaderFilterSupported,
);
final liquidGlassProgramProvider = FutureProvider<ui.FragmentProgram>(
  (ref) => ui.FragmentProgram.fromAsset(AppLiquidGlass.shaderAsset),
);

/// Bounded background optics. The foreground is painted after the filter.
/// Loading/failure uses ordinary blur, accessibility uses an opaque surface.
class LiquidGlassSurface extends ConsumerStatefulWidget {
  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.radius = AppLiquidGlass.radius,
    this.blur = AppLiquidGlass.blur,
    this.edgeDepth = AppLiquidGlass.edgeDepth,
    this.refraction = AppLiquidGlass.refraction,
    this.blurKey,
  }) : assert(radius >= 0),
       assert(blur >= 0),
       assert(edgeDepth > 0),
       assert(refraction >= 0);
  final Widget child;
  final double radius, blur, edgeDepth, refraction;
  final Key? blurKey;

  @override
  ConsumerState<LiquidGlassSurface> createState() => _LiquidGlassSurfaceState();
}

class _LiquidGlassSurfaceState extends ConsumerState<LiquidGlassSurface> {
  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  bool _failed = false;

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final policy = AppVisualPolicy.of(
      context,
      ref.watch(currentAppearanceProvider),
    );
    final supported = ref.watch(liquidGlassSupportedProvider);
    final program = policy.liquidGlass && supported
        ? ref.watch(liquidGlassProgramProvider).asData?.value
        : null;
    if (_program != program) {
      _shader?.dispose();
      _program = program;
      _shader = program?.fragmentShader();
      _failed = false;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: LayoutBuilder(
        builder: (context, constraints) {
          ui.ImageFilter filter = ui.ImageFilter.blur(
            sigmaX: widget.blur,
            sigmaY: widget.blur,
          );
          final shader = _shader;
          if (shader != null &&
              !_failed &&
              constraints.hasBoundedWidth &&
              constraints.hasBoundedHeight &&
              constraints.biggest.shortestSide > 0) {
            try {
              shader
                ..setFloat(2, constraints.maxWidth)
                ..setFloat(3, constraints.maxHeight)
                ..setFloat(4, widget.radius)
                ..setFloat(5, widget.edgeDepth)
                ..setFloat(6, widget.refraction);
              filter = ui.ImageFilter.compose(
                outer: ui.ImageFilter.shader(shader),
                inner: filter,
              );
            } on UnsupportedError {
              _failed = true;
            } on StateError {
              _failed = true;
            }
          }
          return BackdropFilter(
            key: widget.blurKey,
            enabled: policy.translucent,
            filter: filter,
            child: ColoredBox(
              color: policy.opaque
                  ? Theme.of(context).colorScheme.surfaceContainer
                  : Colors.transparent,
              child: widget.child,
            ),
          );
        },
      ),
    );
  }
}
