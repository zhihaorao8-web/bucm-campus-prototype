import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/appearance_controller.dart';

/// Non-interactive, bounded decoration. No repeating ticker or expensive blur.
class QuietBackdrop extends ConsumerWidget {
  const QuietBackdrop({super.key, required this.tab, required this.child});
  final int tab;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentAppearanceProvider);
    final contrast =
        MediaQuery.highContrastOf(context) || settings.contrast > 0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Theme.of(context).colorScheme.surface),
        if (!contrast && settings.aurora)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 300,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 900),
                  child: CustomPaint(
                    key: ValueKey('aurora-$tab'),
                    painter: _AuroraPainter(tab, dark),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        if (!contrast && settings.paperTexture)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  key: const ValueKey('paper-grain'),
                  painter: _PaperPainter(dark),
                ),
              ),
            ),
          ),
        child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  const _AuroraPainter(this.tab, this.dark);
  final int tab;
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    const palettes = [
      [Color(0xFFFFC682), Color(0xFF78B9FF), Color(0xFFFFDCC2)],
      [Color(0xFF6096FD), Color(0xFF6ED7B4), Color(0xFFCADFFF)],
      [Color(0xFFA882F5), Color(0xFFF5C391), Color(0xFFE1CEFA)],
    ];
    for (var i = 0; i < 3; i++) {
      final center = Offset(
        size.width * [.05, .52, .2][i],
        [40.0, 60.0, 160.0][i],
      );
      final radius = size.width.clamp(280.0, 480.0) * .55;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              palettes[tab][i].withValues(alpha: dark ? .09 : .20),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.tab != tab || old.dark != dark;
}

class _PaperPainter extends CustomPainter {
  const _PaperPainter(this.dark);
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(17);
    final paint = Paint()
      ..color = (dark ? Colors.white : Colors.black).withValues(alpha: .015);
    for (var i = 0; i < (size.width * size.height / 130).round(); i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        .45,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PaperPainter old) => old.dark != dark;
}
