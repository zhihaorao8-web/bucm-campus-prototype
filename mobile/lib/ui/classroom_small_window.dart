import 'app_icons.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Per-playback layout only; no media, course identity or persistent storage.
class ClassroomSmallWindowPlacement {
  Offset alignment = const Offset(1, 1);
  double? widthFraction;
  static const ratio = 16 / 9;

  Rect bounds(Size viewport, double reservedTop) => Rect.fromLTRB(
    12,
    math.max(12, reservedTop),
    math.max(12, viewport.width - 12),
    math.max(math.max(12, reservedTop), viewport.height - 12),
  );

  double maximumWidth(Size viewport, double reservedTop) {
    final area = bounds(viewport, reservedTop);
    return math
        .max(
          0,
          math.min(
            420,
            math.min(
              viewport.width * .7,
              math.min(area.width, area.height * ratio),
            ),
          ),
        )
        .toDouble();
  }

  Rect? resolve(Size viewport, double reservedTop) {
    final area = bounds(viewport, reservedTop);
    final maximum = maximumWidth(viewport, reservedTop);
    // A full 48px close target must fit. Keep preferences when space is scarce.
    if (maximum < 48 * ratio) return null;
    final requested = widthFraction == null
        ? math.min(200.0, viewport.width * .34)
        : viewport.width * widthFraction!;
    final width = requested.clamp(math.min(96, maximum), maximum).toDouble();
    return Rect.fromLTWH(
      area.left + (area.width - width) * alignment.dx,
      area.top + (area.height - width / ratio) * alignment.dy,
      width,
      width / ratio,
    );
  }

  void update(
    Size viewport,
    double reservedTop,
    Offset center,
    double width, {
    required bool resize,
  }) {
    final maximum = maximumWidth(viewport, reservedTop);
    if (maximum < 48 * ratio) return;
    width = width.clamp(math.min(96, maximum), maximum).toDouble();
    if (resize) widthFraction = width / viewport.width;
    final area = bounds(viewport, reservedTop);
    final travelX = area.width - width;
    final travelY = area.height - width / ratio;
    alignment = Offset(
      travelX > 0
          ? ((center.dx - width / 2 - area.left) / travelX)
                .clamp(0, 1)
                .toDouble()
          : alignment.dx,
      travelY > 0
          ? ((center.dy - width / ratio / 2 - area.top) / travelY)
                .clamp(0, 1)
                .toDouble()
          : alignment.dy,
    );
  }
}

class ClassroomSmallWindow extends StatefulWidget {
  const ClassroomSmallWindow({
    super.key,
    required this.placement,
    required this.viewport,
    required this.reservedTop,
    required this.label,
    required this.picture,
    required this.onSwap,
    required this.onClose,
    required this.onInteraction,
    this.showControls = true,
  });
  final ClassroomSmallWindowPlacement placement;
  final Size viewport;
  final double reservedTop;
  final String label;
  final Widget picture;
  final VoidCallback onSwap, onClose, onInteraction;
  final bool showControls;

  @override
  State<ClassroomSmallWindow> createState() => _ClassroomSmallWindowState();
}

class _ClassroomSmallWindowState extends State<ClassroomSmallWindow> {
  Rect? startRect;
  Offset startFocal = Offset.zero;
  double startScale = 1;
  int pointerCount = 0;
  Rect? get rect =>
      widget.placement.resolve(widget.viewport, widget.reservedTop);

  void adjust(Offset delta, double scale) {
    final current = rect;
    if (current == null) return;
    widget.onInteraction();
    setState(
      () => widget.placement.update(
        widget.viewport,
        widget.reservedTop,
        current.center + delta,
        current.width * scale,
        resize: scale != 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = rect;
    if (current == null) {
      return Semantics(
        label: '视频区域空间不足，小窗将在空间恢复后显示',
        child: const SizedBox.shrink(),
      );
    }
    return Positioned.fromRect(
      rect: current,
      child: GestureDetector(
        key: const ValueKey('classroom-small-window'),
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: widget.onSwap,
        onScaleStart: (details) {
          startRect = rect;
          startFocal = details.focalPoint;
          startScale = 1;
          pointerCount = details.pointerCount;
          widget.onInteraction();
        },
        onScaleUpdate: (details) {
          if (pointerCount != details.pointerCount) {
            startRect = rect;
            startFocal = details.focalPoint;
            startScale = details.scale;
            pointerCount = details.pointerCount;
          }
          final initial = startRect;
          if (initial == null) return;
          setState(
            () => widget.placement.update(
              widget.viewport,
              widget.reservedTop,
              initial.center + details.focalPoint - startFocal,
              initial.width * details.scale / startScale,
              resize: details.pointerCount > 1,
            ),
          );
        },
        onScaleEnd: (_) => startRect = null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white54, width: 2),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Semantics(
                  button: true,
                  label: '${widget.label}小窗，点击交换主画面',
                  hint: '单指拖动，双指缩放',
                  onTap: widget.onSwap,
                  onIncrease: () => adjust(Offset.zero, 1.15),
                  onDecrease: () => adjust(Offset.zero, 1 / 1.15),
                  customSemanticsActions: {
                    CustomSemanticsAction(label: '向左移动小窗'): () =>
                        adjust(const Offset(-24, 0), 1),
                    CustomSemanticsAction(label: '向右移动小窗'): () =>
                        adjust(const Offset(24, 0), 1),
                    CustomSemanticsAction(label: '向上移动小窗'): () =>
                        adjust(const Offset(0, -24), 1),
                    CustomSemanticsAction(label: '向下移动小窗'): () =>
                        adjust(const Offset(0, 24), 1),
                  },
                  child: widget.picture,
                ),
                if (widget.showControls)
                  Positioned(
                    left: 6,
                    top: 4,
                    child: IgnorePointer(
                      child: Text(
                        widget.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          backgroundColor: Colors.black54,
                        ),
                      ),
                    ),
                  ),
                if (widget.showControls)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: '关闭小窗',
                      onPressed: widget.onClose,
                      color: Colors.white,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                      ),
                      icon: const AppIcon(AppIcons.close, size: 18),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
