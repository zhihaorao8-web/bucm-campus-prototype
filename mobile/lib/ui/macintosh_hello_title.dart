import 'dart:math' as math;
import 'dart:ui' show PathMetric;
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'macintosh_hello_glyphs.g.dart';
import 'quiet_backdrop.dart';

/// Hand-lettered title inspired by Apple's Macintosh Skeletal Filled script
/// with an entrance stroke-by-stroke write-on animation.
class MacintoshHelloTitle extends ConsumerStatefulWidget {
  const MacintoshHelloTitle({
    super.key,
    required this.text,
    required this.color,
    required this.glyphSize,
    required this.active,
    this.duration = const Duration(milliseconds: 1350),
  });

  final String text;
  final Color color;
  final double glyphSize;
  final bool active;
  final Duration duration;

  @override
  ConsumerState<MacintoshHelloTitle> createState() =>
      _MacintoshHelloTitleState();
}

class _MacintoshHelloTitleState extends ConsumerState<MacintoshHelloTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  bool _hasPlayed = false;
  double? _cachedSize;
  String? _cachedText;
  late _PreparedWord _prepared;

  @override
  void initState() {
    super.initState();
    _syncPrepared();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybePlayOrSnap();
  }

  @override
  void didUpdateWidget(covariant MacintoshHelloTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.glyphSize != widget.glyphSize) {
      _syncPrepared();
    }
    if (oldWidget.text != widget.text) {
      _hasPlayed = false;
    }
    _maybePlayOrSnap();
  }

  void _syncPrepared() {
    if (_cachedText == widget.text && _cachedSize == widget.glyphSize) return;
    _cachedText = widget.text;
    _cachedSize = widget.glyphSize;
    _prepared = _PreparedWord.build(widget.text, widget.glyphSize);
  }

  void _maybePlayOrSnap() {
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        !ref.read(ambientMotionEnabledProvider);
    if (reduceMotion) {
      _hasPlayed = true;
      _controller.value = 1.0;
      return;
    }
    if (!_hasPlayed && widget.active) {
      _hasPlayed = true;
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        !ref.watch(ambientMotionEnabledProvider);
    if (reduceMotion && _controller.value != 1.0) {
      _hasPlayed = true;
      _controller.value = 1.0;
    }

    return SizedBox(
      width: _prepared.width,
      height: _prepared.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          key: ValueKey('hello-title-paint-${widget.text}'),
          size: Size(_prepared.width, _prepared.height),
          painter: _HelloTitlePainter(
            word: _prepared,
            color: widget.color,
            progress: _controller.value,
          ),
        ),
      ),
    );
  }
}

/// Syncs [MacintoshHelloTitle] position and collapse fade-out with a sibling
/// [MiuixTopAppBar] while keeping native semantics and touch routing intact.
class MacintoshHelloHeaderOverlay extends StatelessWidget {
  const MacintoshHelloHeaderOverlay({
    super.key,
    required this.text,
    required this.scrollBehavior,
    required this.active,
    this.glyphSize = 46.0,
    this.titlePadding = MiuixTopAppBarDefaults.titlePadding,
  });

  final String text;
  final MiuixScrollBehavior scrollBehavior;
  final bool active;
  final double glyphSize;
  final double titlePadding;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final leftInset = MediaQuery.paddingOf(context).left;
    final color = MiuixTheme.of(context).colors.onSurface;
    final bandTop = topInset + MiuixTopAppBarDefaults.collapsedHeight;
    final bandHeight = glyphSize + 8.0;

    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: scrollBehavior.state,
          builder: (context, child) {
            final fraction = scrollBehavior.state.collapsedFraction;
            final rawOffset = scrollBehavior.state.heightOffset;
            final effectiveOffset = rawOffset.isFinite ? rawOffset : 0.0;
            final opacity =
                (1.0 - fraction * MiuixTopAppBarDefaults.largeTitleFadeRate)
                    .clamp(0.0, 1.0);
            if (opacity <= 0.001) return const SizedBox.shrink();
            return Padding(
              padding: EdgeInsets.only(top: bandTop),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: double.infinity,
                  height: bandHeight,
                  child: ClipRect(
                    child: Stack(
                      children: [
                        Positioned(
                          left: leftInset + titlePadding - 4.0,
                          top: effectiveOffset + 1.0,
                          child: Opacity(opacity: opacity, child: child),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
          child: MacintoshHelloTitle(
            key: ValueKey('hello-title-$text'),
            text: text,
            color: color,
            glyphSize: glyphSize,
            active: active,
          ),
        ),
      ),
    );
  }
}

class _TimedStroke {
  const _TimedStroke(this.path, this.metric, this.start, this.end);
  final Path path;
  final PathMetric metric;
  final double start;
  final double end;
}

class _PreparedWord {
  const _PreparedWord({
    required this.outlinePath,
    required this.strokes,
    required this.scale,
    required this.width,
    required this.height,
  });

  final Path outlinePath;
  final List<_TimedStroke> strokes;
  final double scale;
  final double width;
  final double height;

  static _PreparedWord build(String text, double glyphSize) {
    const pitchUnits = 94.0;
    final scale = glyphSize / 100.0;
    final chars = text.split('');
    final outlinePath = Path()..fillType = PathFillType.evenOdd;
    final rawEntries = <({Path path, PathMetric metric, int charIndex})>[];

    for (var ci = 0; ci < chars.length; ci++) {
      final glyph = macintoshHelloB1Glyphs[chars[ci]];
      if (glyph == null) continue;
      final offsetX = pitchUnits * ci;
      outlinePath.addPath(
        glyph.buildOutlinePath(offsetX: offsetX, scale: scale),
        Offset.zero,
      );
      for (final coords in glyph.strokes) {
        if (coords.length < 4) continue;
        final p = Path()
          ..moveTo((coords[0] + offsetX) * scale, coords[1] * scale);
        for (var i = 2; i + 1 < coords.length; i += 2) {
          p.lineTo((coords[i] + offsetX) * scale, coords[i + 1] * scale);
        }
        final metrics = p.computeMetrics().toList();
        if (metrics.isNotEmpty && metrics.first.length > 0.5) {
          rawEntries.add((path: p, metric: metrics.first, charIndex: ci));
        }
      }
    }

    // Build overlapping stroke schedule with brief breath pause between glyphs.
    final durations = <double>[];
    final starts = <double>[];
    var cursor = 0.0;
    for (var i = 0; i < rawEntries.length; i++) {
      final len = rawEntries[i].metric.length / scale;
      final dur = math.pow(len, 0.72).toDouble().clamp(16.0, 220.0);
      if (i > 0) {
        final sameChar =
            rawEntries[i].charIndex == rawEntries[i - 1].charIndex;
        if (sameChar) {
          cursor -= durations.last * 0.18;
        } else {
          cursor += 8.0;
        }
      }
      starts.add(cursor);
      durations.add(dur);
      cursor += dur;
    }

    final total = math.max(1.0, cursor);
    final timed = <_TimedStroke>[
      for (var i = 0; i < rawEntries.length; i++)
        _TimedStroke(
          rawEntries[i].path,
          rawEntries[i].metric,
          (starts[i] / total).clamp(0.0, 1.0),
          ((starts[i] + durations[i]) / total).clamp(0.0, 1.0),
        ),
    ];

    final widthUnits = chars.isEmpty
        ? 100.0
        : pitchUnits * (chars.length - 1) + 100.0;
    return _PreparedWord(
      outlinePath: outlinePath,
      strokes: timed,
      scale: scale,
      width: widthUnits * scale,
      height: glyphSize,
    );
  }
}

class _HelloTitlePainter extends CustomPainter {
  const _HelloTitlePainter({
    required this.word,
    required this.color,
    required this.progress,
  });

  final _PreparedWord word;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.001) return;
    if (progress >= 0.999 || word.strokes.isEmpty) {
      canvas.drawPath(word.outlinePath, Paint()..color = color);
      return;
    }

    // Mask progressive rounded skeletal strokes against the exact soft-blended
    // B1 outline so every frame stays faithful to the final silhouette.
    canvas.saveLayer(Offset.zero & size, Paint());
    final maskPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 10.8 * word.scale;

    for (final stroke in word.strokes) {
      if (progress <= stroke.start) continue;
      if (progress >= stroke.end) {
        canvas.drawPath(stroke.path, maskPaint);
      } else {
        final span = math.max(1e-4, stroke.end - stroke.start);
        final local = ((progress - stroke.start) / span).clamp(0.0, 1.0);
        final eased = Curves.easeInOutSine.transform(local);
        final partial = stroke.metric.extractPath(
          0.0,
          stroke.metric.length * eased,
        );
        canvas.drawPath(partial, maskPaint);
      }
    }

    canvas.drawPath(
      word.outlinePath,
      Paint()
        ..color = color
        ..blendMode = BlendMode.srcIn,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HelloTitlePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.word != word;
}
