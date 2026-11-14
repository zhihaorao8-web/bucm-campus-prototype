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
      duration: const Duration(seconds: 9),
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
          color: !dark && !contrast && settings.aurora
              ? const Color(0xFFF9FCFF)
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
  void paint(Canvas canvas, Size size) => _paintDiffusion(canvas, size);

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
              : const [Color(0xFFEAF6FF), Color(0xFFECFCF8), Color(0xFFF6EEFF)],
        ).createShader(bounds),
    );
    const todayDarkHues = [
      Color(0xFF6CCFFF),
      Color(0xFF7FE8CD),
      Color(0xFFFFD1A6),
      Color(0xFFB8BBFF),
    ];
    const todayLightHues = [
      Color(0xFF00B8FF),
      Color(0xFF00E8B5),
      Color(0xFF7B64FF),
      Color(0xFFFF72A8),
    ];
    // Reading pages use the same broad diffusion, with their existing palettes
    // and a fixed phase. Only Today owns continuous ambient motion.
    final hues = dark
        ? switch (tab) {
            1 => const [
              Color(0xFF6096FD),
              Color(0xFF6ED7B4),
              Color(0xFFCADFFF),
              Color(0xFFB8BBFF),
            ],
            2 => const [
              Color(0xFFA882F5),
              Color(0xFFF5C391),
              Color(0xFFE1CEFA),
              Color(0xFF72D0FF),
            ],
            _ => todayDarkHues,
          }
        : switch (tab) {
            1 => const [
              Color(0xFF1F7BFF),
              Color(0xFF00DDA0),
              Color(0xFF4CC3FF),
              Color(0xFF7A6BFF),
            ],
            2 => const [
              Color(0xFF8B54FF),
              Color(0xFFFF7A5C),
              Color(0xFFD678FF),
              Color(0xFF18BAFF),
            ],
            _ => todayLightHues,
          };
    final angle = tab == 0 ? phase.value * math.pi * 2 : 0.0;
    final moving = tab == 0;
    for (var i = 0; i < hues.length; i++) {
      final orbit = angle + i * math.pi / 2;
      final baseX = dark
          ? const [-.06, 1.00, .06, .96][i]
          : (moving
                ? const [.44, .56, .56, .44][i]
                : const [.24, .78, .76, .26][i]);
      final baseY = dark
          ? const [.08, .32, .62, .92][i]
          : (moving
                ? const [.18, .38, .62, .82][i]
                : const [.18, .32, .68, .82][i]);
      final dx = moving
          ? (dark
                ? .26 * math.sin(orbit) + .07 * math.cos(2 * angle + i)
                : .34 * math.sin(orbit) + .10 * math.cos(2 * angle + i * 1.1))
          : 0.0;
      final dy = moving
          ? (dark
                ? .10 * math.cos(orbit) + .035 * math.sin(2 * angle + i)
                : .16 * math.cos(orbit + i * .4) +
                      .05 * math.sin(2 * angle + i * .9))
          : 0.0;
      final center = Offset(
        size.width * (baseX + dx),
        size.height * (baseY + dy),
      );
      final baseAlpha = dark
          ? const [.24, .21, .14, .16][i]
          : const [.68, .64, .58, .60][i];
      final alpha = moving && !dark
          ? baseAlpha * (.82 + .18 * math.sin(2 * angle + i * 1.3))
          : baseAlpha;
      final tilt = moving
          ? (i.isEven ? 1 : -1) *
                (dark ? .18 * math.sin(orbit) : .28 + .32 * math.sin(orbit))
          : 0.0;
      final sx =
          size.width *
          (dark
              ? .96 + (moving ? .12 * math.cos(orbit) : 0.0)
              : (moving
                    ? .70 + .18 * math.cos(orbit + i * .7)
                    : .78));
      final sy =
          size.height *
          (dark
              ? .40 + (moving ? .06 * math.sin(2 * angle + i) : 0.0)
              : (moving
                    ? .30 + .10 * math.sin(2 * angle + i * .9)
                    : .36));
      canvas.save();
      canvas.translate(center.dx, center.dy);
      if (tilt != 0) canvas.rotate(tilt);
      canvas.scale(sx, sy);
      canvas.drawCircle(
        Offset.zero,
        1,
        Paint()
          ..shader = RadialGradient(
            stops: dark ? const [0, .22, .58, 1] : const [0, .20, .58, 1],
            colors: [
              hues[i].withValues(alpha: alpha),
              hues[i].withValues(alpha: alpha * (dark ? .84 : .84)),
              hues[i].withValues(alpha: alpha * (dark ? .30 : .32)),
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
