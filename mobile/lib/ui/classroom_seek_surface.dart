import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Relative preview on the main picture; one seek is sent only on release.
class ClassroomSeekSurface extends StatefulWidget {
  const ClassroomSeekSurface({
    super.key,
    required this.position,
    required this.duration,
    required this.enabled,
    required this.formatTime,
    required this.onSeek,
    required this.onInteraction,
    required this.child,
  });
  final int position, duration;
  final bool enabled;
  final String Function(int) formatTime;
  final ValueChanged<int> onSeek;
  final VoidCallback onInteraction;
  final Widget child;

  @override
  State<ClassroomSeekSurface> createState() => _ClassroomSeekSurfaceState();
}

class _ClassroomSeekSurfaceState extends State<ClassroomSeekSurface> {
  int pointers = 0, origin = 0, duration = 0;
  int? target;
  double startX = 0, startWidth = 0;

  @override
  void didUpdateWidget(ClassroomSeekSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || widget.duration != duration) target = null;
  }

  void cancel() {
    if (target != null) setState(() => target = null);
  }

  void start(DragStartDetails details, double width) {
    if (!widget.enabled ||
        widget.duration <= 0 ||
        pointers != 1 ||
        width <= 0) {
      return;
    }
    widget.onInteraction();
    setState(() {
      origin = widget.position.clamp(0, widget.duration);
      duration = widget.duration;
      startX = details.localPosition.dx;
      startWidth = width;
      target = origin;
    });
  }

  void update(DragUpdateDetails details, double width) {
    if (target == null) return;
    if (!widget.enabled || pointers != 1 || width != startWidth) {
      cancel();
      return;
    }
    // A picture-width swipe covers up to two minutes, including long lectures.
    final offset =
        (details.localPosition.dx - startX) /
        startWidth *
        math.min(duration, 120000);
    setState(() => target = (origin + offset.round()).clamp(0, duration));
  }

  void finish(double width) {
    final value = target;
    cancel();
    widget.onInteraction();
    if (value != null &&
        value != origin &&
        widget.enabled &&
        widget.duration == duration &&
        width == startWidth) {
      widget.onSeek(value);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Listener(
      onPointerDown: (_) {
        pointers++;
        if (pointers > 1) cancel();
      },
      onPointerUp: (_) => pointers = math.max(0, pointers - 1),
      onPointerCancel: (_) {
        pointers = math.max(0, pointers - 1);
        cancel();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: widget.onInteraction,
        onHorizontalDragStart: widget.enabled
            ? (details) => start(details, constraints.maxWidth)
            : null,
        onHorizontalDragUpdate: widget.enabled
            ? (details) => update(details, constraints.maxWidth)
            : null,
        onHorizontalDragEnd: widget.enabled
            ? (_) => finish(constraints.maxWidth)
            : null,
        onHorizontalDragCancel: cancel,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (target != null)
              IgnorePointer(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: DecoratedBox(
                        key: const ValueKey('classroom-seek-preview'),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${widget.formatTime(target!)} / ${widget.formatTime(duration)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${target! >= origin ? '前进' : '后退'} ${widget.formatTime((target! - origin).abs())} · 松手跳转',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
