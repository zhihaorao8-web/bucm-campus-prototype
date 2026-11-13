import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/appearance_controller.dart';

/// Injectable clock policy for deterministic screenshots; production animates.
final ambientMotionEnabledProvider = Provider<bool>((ref) => true);

/// Only the Today sample animates until the other stages are approved.
class QuietBackdrop extends ConsumerStatefulWidget {
  const QuietBackdrop({super.key, required this.tab, required this.child});
  final int tab;
  final Widget child;
  @override
  ConsumerState<QuietBackdrop> createState() => _QuietBackdropState();
}

class _QuietBackdropState extends ConsumerState<QuietBackdrop>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController phase;
  bool foreground = true;

  @override
  void initState() {
    super.initState();
    phase = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentAppearanceProvider);
    final contrast =
        MediaQuery.highContrastOf(context) || settings.contrast > 0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final animate =
        widget.tab == 0 &&
        settings.aurora &&
        !contrast &&
        !MediaQuery.disableAnimationsOf(context) &&
        foreground &&
        TickerMode.valuesOf(context).enabled &&
        ref.watch(ambientMotionEnabledProvider);
    if (animate && !phase.isAnimating) phase.repeat();
    if (!animate && phase.isAnimating) phase.stop();
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: widget.tab == 0 && !dark && !contrast && settings.aurora
              ? const Color(0xFFFCFDFF)
              : Theme.of(context).colorScheme.surface,
        ),
        if (!contrast && settings.aurora)
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: RepaintBoundary(
                  child: AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 900),
                    child: CustomPaint(
                      key: ValueKey('aurora-${widget.tab}'),
                      painter: _AuroraPainter(widget.tab, dark, phase),
                      child: const SizedBox.expand(),
                    ),
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
        widget.child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.tab, this.dark, this.phase) : super(repaint: phase);
  final int tab;
  final bool dark;
  final Animation<double> phase;
  @override
  void paint(Canvas canvas, Size size) {
    const palettes = [
      [Color(0xFF72D0FF), Color(0xFF91EACF), Color(0xFFFFD8AE)],
      [Color(0xFF6096FD), Color(0xFF6ED7B4), Color(0xFFCADFFF)],
      [Color(0xFFA882F5), Color(0xFFF5C391), Color(0xFFE1CEFA)],
    ];
    final sample = tab == 0;
    final angle = phase.value * math.pi * 2;
    for (var i = 0; i < 3; i++) {
      final orbit = angle + i * math.pi * 2 / 3;
      final center = sample
          ? Offset(
              size.width * ([.12, .93, .10][i] + .10 * math.sin(orbit)),
              size.height * ([.13, .36, .57][i] + .045 * math.cos(orbit)),
            )
          : Offset(size.width * [.05, .52, .2][i], [40.0, 60.0, 160.0][i]);
      final radius = size.width.clamp(280.0, 480.0) * (sample ? .88 : .55);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              palettes[tab][i].withValues(
                alpha: sample ? (dark ? .18 : .24) : (dark ? .09 : .20),
              ),
              palettes[tab][i].withValues(alpha: 0),
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
