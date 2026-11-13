import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_icons.dart';

Rect? playbackButtonRect(GlobalKey? key, NavigatorState navigator) {
  final button = key?.currentContext?.findRenderObject();
  final overlay = navigator.overlay?.context.findRenderObject();
  if (button is! RenderBox ||
      !button.attached ||
      !button.hasSize ||
      overlay is! RenderBox) {
    return null;
  }
  final rect = MatrixUtils.transformRect(
    button.getTransformTo(overlay),
    Offset.zero & button.size,
  );
  if (!(Offset.zero & overlay.size).contains(rect.center)) return null;
  RenderObject child = button;
  while (child != overlay && child.parent != null) {
    final parent = child.parent!;
    final clip = parent.describeApproximatePaintClip(child);
    if (clip != null &&
        !MatrixUtils.transformRect(
          parent.getTransformTo(overlay),
          clip,
        ).contains(rect.center)) {
      return null;
    }
    child = parent;
  }
  return rect;
}

class ClassroomPlayerRoute extends MaterialPageRoute<void> {
  ClassroomPlayerRoute({
    required super.builder,
    required this.origin,
    required this.color,
    required this.iconColor,
    required this.reducedMotion,
  }) : super(allowSnapshotting: false);

  final Rect? origin;
  final Color color, iconColor;
  final bool reducedMotion;
  bool _entered = false;

  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;

  @override
  Duration get transitionDuration =>
      reducedMotion ? Duration.zero : const Duration(milliseconds: 280);

  @override
  Duration get reverseTransitionDuration =>
      reducedMotion ? Duration.zero : const Duration(milliseconds: 220);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reducedMotion || MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        // Offstage route measurement supplies a completed proxy before entry.
        _entered = _entered || controller!.isCompleted;
        if (_entered || origin == null) {
          return super.buildTransitions(
            context,
            animation,
            secondaryAnimation,
            child!,
          );
        }
        return PlaybackButtonExpansion(
          origin: origin!,
          progress: animation.value,
          color: color,
          iconColor: iconColor,
          child: child!,
        );
      },
    );
  }
}

class PlaybackButtonExpansion extends StatelessWidget {
  const PlaybackButtonExpansion({
    super.key,
    required this.origin,
    required this.progress,
    required this.color,
    required this.iconColor,
    required this.child,
  });

  final Rect origin;
  final double progress;
  final Color color, iconColor;
  final Widget child;
  static const curve = Cubic(.23, 1, .32, 1);

  @override
  Widget build(BuildContext context) {
    final expansion = curve.transform((progress / .75).clamp(0.0, 1.0));
    final reveal = curve.transform(((progress - .75) / .25).clamp(0.0, 1.0));
    final glyph = 1 - (progress / .45).clamp(0.0, 1.0);
    return IgnorePointer(
      ignoring: progress < 1,
      child: ExcludeFocus(
        excluding: progress < 1,
        child: ExcludeSemantics(
          excluding: progress < 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                key: const ValueKey('playback-expanding-surface'),
                painter: PlaybackExpansionPainter(
                  origin: origin,
                  expansion: expansion,
                  color: color,
                ),
              ),
              if (glyph > 0)
                Positioned(
                  left: origin.center.dx - 12,
                  top: origin.center.dy - 12,
                  child: Opacity(
                    opacity: glyph,
                    child: Transform.scale(
                      scale: 1 + expansion,
                      child: AppIcon(AppIcons.play, size: 24, color: iconColor),
                    ),
                  ),
                ),
              Opacity(
                key: const ValueKey('playback-page-reveal'),
                opacity: reveal,
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlaybackExpansionPainter extends CustomPainter {
  const PlaybackExpansionPainter({
    required this.origin,
    required this.expansion,
    required this.color,
  });
  final Rect origin;
  final double expansion;
  final Color color;

  double radiusFor(Size size) {
    final center = origin.center;
    final dx = math.max(center.dx.abs(), (size.width - center.dx).abs());
    final dy = math.max(center.dy.abs(), (size.height - center.dy).abs());
    final end = math.sqrt(dx * dx + dy * dy);
    final start = origin.shortestSide / 2;
    return start + (end - start) * expansion;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(origin.center, radiusFor(size), Paint()..color = color);
  }

  @override
  bool shouldRepaint(PlaybackExpansionPainter oldDelegate) =>
      origin != oldDelegate.origin ||
      expansion != oldDelegate.expansion ||
      color != oldDelegate.color;
}
