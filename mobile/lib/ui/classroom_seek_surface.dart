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
    this.previewBottomInset = 0,
    this.previewTopInset = 0,
    this.previewExclusion,
  });
  final int position, duration;
  final bool enabled;
  final String Function(int) formatTime;
  final ValueChanged<int> onSeek;
  final VoidCallback onInteraction;
  final Widget child;
  final double previewBottomInset, previewTopInset;
  final Rect? previewExclusion;

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

  Rect previewArea(Size size) {
    final top = widget.previewTopInset.clamp(0.0, size.height);
    final bottom = (size.height - widget.previewBottomInset).clamp(
      top,
      size.height,
    );
    final area = Rect.fromLTRB(0, top, size.width, bottom);
    final exclusion = widget.previewExclusion?.inflate(8).intersect(area);
    if (exclusion == null || !area.overlaps(exclusion)) return area;
    final choices = [
      Rect.fromLTRB(area.left, area.top, exclusion.left, area.bottom),
      Rect.fromLTRB(exclusion.right, area.top, area.right, area.bottom),
      Rect.fromLTRB(area.left, area.top, area.right, exclusion.top),
      Rect.fromLTRB(area.left, exclusion.bottom, area.right, area.bottom),
    ]..sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
    return choices.first;
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
              Positioned.fromRect(
                rect: previewArea(constraints.biggest),
                child: IgnorePointer(
                  child: Center(
                    child: ClassroomSeekPreview(
                      key: const ValueKey('classroom-seek-preview'),
                      target: target!,
                      duration: duration,
                      origin: origin,
                      formatTime: widget.formatTime,
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

/// Shared, non-interactive time display for picture swipes and slider drags.
class ClassroomSeekPreview extends StatelessWidget {
  const ClassroomSeekPreview({
    super.key,
    required this.target,
    required this.duration,
    required this.formatTime,
    this.origin,
  });
  final int target, duration;
  final int? origin;
  final String Function(int) formatTime;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${formatTime(target)} / ${formatTime(duration)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                origin == null
                    ? '松手跳转'
                    : '${target >= origin! ? '前进' : '后退'} ${formatTime((target - origin!).abs())} · 松手跳转',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
