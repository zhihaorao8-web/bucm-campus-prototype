import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/appearance_controller.dart';

/// Injectable clock policy for deterministic screenshots; production animates.
final ambientMotionEnabledProvider = Provider<bool>((ref) => true);

/// Pinned so reveal and focus traversal treat the bar as obstruction.
class QuietSliverAppBar extends ConsumerWidget {
  const QuietSliverAppBar({
    super.key,
    required this.title,
    required this.scroll,
    this.actions,
  });
  final Widget title;
  final ScrollController scroll;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentAppearanceProvider);
    final opaque =
        !settings.blur ||
        !settings.glass ||
        settings.contrast > 0 ||
        MediaQuery.highContrastOf(context);
    return SliverAppBar(
      pinned: true,
      title: title,
      actions: actions,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: ListenableBuilder(
        listenable: scroll,
        builder: (context, _) => ClipRect(
          child: BackdropFilter(
            enabled: !opaque,
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: ColoredBox(
              key: const ValueKey('quiet-appbar-scrim'),
              color: Theme.of(context).colorScheme.surface.withValues(
                alpha: opaque
                    ? 1
                    : .04 +
                          .76 *
                              (scroll.hasClients
                                  ? (scroll.offset / 80).clamp(0.0, 1.0)
                                  : 0.0),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Only Today uses a continuous ambient clock; reading pages stay still.
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
    if (tab == 0) {
      _paintDiffusion(canvas, size);
      return;
    }
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

  // Broad elliptical fields overlap beyond the viewport: no visible orb edges.
  // Analytic falloff avoids adding a full-screen blur pass on every frame.
  void _paintDiffusion(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF070D14), Color(0xFF091313), Color(0xFF0B0C14)]
              : const [Color(0xFFFAFDFF), Color(0xFFFCFEFC), Color(0xFFFFFCF9)],
        ).createShader(bounds),
    );
    const hues = [
      Color(0xFF6CCFFF),
      Color(0xFF7FE8CD),
      Color(0xFFFFD1A6),
      Color(0xFFB8BBFF),
    ];
    final angle = phase.value * math.pi * 2;
    for (var i = 0; i < hues.length; i++) {
      final orbit = angle + i * math.pi / 2;
      final center = Offset(
        size.width * ([-.10, 1.04, .04, .98][i] + .13 * math.sin(orbit)),
        size.height * ([.08, .32, .62, .92][i] + .045 * math.cos(orbit)),
      );
      final alpha = dark ? [.23, .20, .13, .15][i] : [.29, .25, .18, .15][i];
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(
        size.width * (1.08 + .05 * math.cos(orbit)),
        size.height * (.43 + .025 * math.sin(orbit)),
      );
      canvas.drawCircle(
        Offset.zero,
        1,
        Paint()
          ..shader = RadialGradient(
            stops: const [0, .22, .58, 1],
            colors: [
              hues[i].withValues(alpha: alpha),
              hues[i].withValues(alpha: alpha * .84),
              hues[i].withValues(alpha: alpha * .30),
              hues[i].withValues(alpha: 0),
            ],
          ).createShader(const Rect.fromLTWH(-1, -1, 2, 2)),
      );
      canvas.restore();
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
