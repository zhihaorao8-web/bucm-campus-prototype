import '../design/app_palette.dart';
import '../design/app_tokens.dart';
import 'visual_policy.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/appearance_controller.dart';

/// Injectable clock policy for deterministic screenshots; production animates.
final ambientMotionEnabledProvider = Provider<bool>((ref) => true);

/// Allows tests to simulate environments where custom backdrop shaders are disabled.
final backdropShadersEnabledProvider = Provider<bool>((ref) => true);

/// Loads and caches the compiled [ui.FragmentProgram] for each shader-backed [BackdropTheme].
final backdropProgramProvider =
    FutureProvider.family<ui.FragmentProgram, BackdropTheme>((ref, theme) {
      final asset = theme.shaderAsset;
      if (asset == null) {
        return Future<ui.FragmentProgram>.error(
          StateError('Diffusion theme does not use a fragment shader'),
        );
      }
      return ui.FragmentProgram.fromAsset(asset);
    });

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
    final opaque = AppVisualPolicy.of(context, settings).opaque;
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
        builder: (context, _) => BackdropTransitionBuilder(
          builder: (context, suspended) => ClipRect(
            child: BackdropFilter(
              enabled: !opaque && !suspended,
              filter: ui.ImageFilter.blur(
                sigmaX: AppHeader.blur,
                sigmaY: AppHeader.blur,
                tileMode: ui.TileMode.clamp,
              ),
              child: ColoredBox(
                key: const ValueKey('quiet-appbar-scrim'),
                color: Theme.of(context).colorScheme.surface.withValues(
                  alpha: AppHeader.tint(
                    scroll.hasClients ? scroll.offset : 0,
                    opaque: opaque,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Only Today uses a continuous ambient clock; reading pages stay still.
/// When [positionListenable] and [positionResolver] are supplied, background
/// colors and parameters interpolate continuously across page transitions.
class QuietBackdrop extends ConsumerStatefulWidget {
  const QuietBackdrop({
    super.key,
    required this.tab,
    required this.child,
    this.positionListenable,
    this.positionResolver,
    this.theme,
  });
  final int tab;
  final Widget child;
  final Listenable? positionListenable;
  final double Function()? positionResolver;
  final BackdropTheme? theme;
  @override
  ConsumerState<QuietBackdrop> createState() => _QuietBackdropState();
}

class _QuietBackdropState extends ConsumerState<QuietBackdrop>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController phase;
  double _lastPhaseValue = 0;
  double _elapsedSeconds = 0;
  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  bool _shaderFailed = false;
  bool foreground = true;

  @override
  void initState() {
    super.initState();
    phase = AnimationController(vsync: this, duration: AppMotion.ambient)
      ..addListener(_advanceClock);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  void _advanceClock() {
    final current = phase.value;
    var delta = current - _lastPhaseValue;
    if (delta < 0) delta += 1.0;
    _lastPhaseValue = current;
    _elapsedSeconds += delta * AppMotion.ambient.inMilliseconds / 1000.0;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _shader?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    phase.dispose();
    super.dispose();
  }

  double _resolvePosition() =>
      (widget.positionResolver?.call() ?? widget.tab.toDouble()).clamp(0.0, 3.0);

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentAppearanceProvider);
    final policy = AppVisualPolicy.of(context, settings);
    final contrast = policy.highContrast;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final activeTheme = widget.theme ?? BackdropTheme.diffusion;
    final animate =
        widget.tab == 0 &&
        settings.aurora &&
        !contrast &&
        !policy.reducedMotion &&
        foreground &&
        TickerMode.valuesOf(context).enabled &&
        ref.watch(ambientMotionEnabledProvider);
    if (animate && !phase.isAnimating) {
      _lastPhaseValue = phase.value;
      phase.repeat();
    }
    if (!animate && phase.isAnimating) phase.stop();

    final shadersEnabled = ref.watch(backdropShadersEnabledProvider);
    final programAsync =
        activeTheme != BackdropTheme.diffusion &&
            !contrast &&
            settings.aurora &&
            shadersEnabled
        ? ref.watch(backdropProgramProvider(activeTheme))
        : null;
    final program = programAsync?.asData?.value;
    if (!identical(_program, program)) {
      _shader?.dispose();
      _program = program;
      _shader = program?.fragmentShader();
      _shaderFailed = false;
    }

    final useShader = _shader != null && !_shaderFailed;
    final repaint = widget.positionListenable == null
        ? phase
        : Listenable.merge([phase, widget.positionListenable!]);

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: !dark && !contrast && settings.aurora
              ? (activeTheme == BackdropTheme.diffusion
                    ? AppPalette.ambientSurface
                    : BackdropStyleSpec.forTab(
                        activeTheme,
                        dark,
                        widget.tab,
                      ).base)
              : Theme.of(context).colorScheme.surface,
        ),
        if (!contrast && settings.aurora)
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: RepaintBoundary(
                  child: CustomPaint(
                    key: ValueKey('aurora-${widget.tab}'),
                    painter: useShader
                        ? _ShaderBackdropPainter(
                            theme: activeTheme,
                            shader: _shader!,
                            dark: dark,
                            grainEnabled: settings.paperTexture,
                            positionResolver: _resolvePosition,
                            timeResolver: () =>
                                widget.tab == 0 ? _elapsedSeconds : 0.0,
                            onShaderError: () {
                              if (!_shaderFailed && mounted) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) setState(() => _shaderFailed = true);
                                });
                              }
                            },
                            repaint: repaint,
                          )
                        : _DiffusionBackdropPainter(
                            theme: activeTheme,
                            tab: widget.tab,
                            dark: dark,
                            phase: phase,
                            positionResolver: _resolvePosition,
                            repaint: repaint,
                          ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        if (!contrast && settings.paperTexture && !useShader)
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

class _ShaderBackdropPainter extends CustomPainter {
  _ShaderBackdropPainter({
    required this.theme,
    required this.shader,
    required this.dark,
    required this.grainEnabled,
    required this.positionResolver,
    required this.timeResolver,
    required this.onShaderError,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final BackdropTheme theme;
  final ui.FragmentShader shader;
  final bool dark;
  final bool grainEnabled;
  final double Function() positionResolver;
  final double Function() timeResolver;
  final VoidCallback onShaderError;

  static void _setColor(ui.FragmentShader s, int start, Color c) {
    final lab = BackdropStyleSpec.colorToOklab(c);
    s
      ..setFloat(start, lab.l)
      ..setFloat(start + 1, lab.a)
      ..setFloat(start + 2, lab.b);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final pos = positionResolver();
    final spec = BackdropStyleSpec.forPosition(theme, dark, pos);
    final time = timeResolver();
    try {
      switch (theme) {
        case BackdropTheme.grainGradient:
          shader
            ..setFloat(0, size.width)
            ..setFloat(1, size.height)
            ..setFloat(2, time)
            ..setFloat(3, spec.p0)
            ..setFloat(4, spec.p1)
            ..setFloat(5, spec.p2)
            ..setFloat(6, spec.p3)
            ..setFloat(7, spec.p4)
            ..setFloat(8, dark ? 0.30 : 0.12)
            ..setFloat(9, grainEnabled ? 0.024 : 0.0);
          for (var i = 0; i < 5; i++) {
            _setColor(shader, 10 + i * 3, spec.colors[i]);
          }
        case BackdropTheme.aurora:
          shader
            ..setFloat(0, size.width)
            ..setFloat(1, size.height)
            ..setFloat(2, time)
            ..setFloat(3, dark ? 1.0 : 0.0)
            ..setFloat(4, spec.p0)
            ..setFloat(5, spec.p1)
            ..setFloat(6, spec.p2)
            ..setFloat(7, spec.p3)
            ..setFloat(8, spec.p4)
            ..setFloat(9, grainEnabled ? 0.018 : 0.0);
          _setColor(shader, 10, spec.base);
          for (var i = 0; i < 4; i++) {
            _setColor(shader, 13 + i * 3, spec.colors[i]);
          }
        case BackdropTheme.horizonGradient:
          shader
            ..setFloat(0, size.width)
            ..setFloat(1, size.height)
            ..setFloat(2, time)
            ..setFloat(3, spec.p0)
            ..setFloat(4, spec.p1)
            ..setFloat(5, spec.p2)
            ..setFloat(6, grainEnabled ? 0.019 : 0.0);
          for (var i = 0; i < 5; i++) {
            _setColor(shader, 7 + i * 3, spec.colors[i]);
          }
        case BackdropTheme.diffusion:
          return;
      }
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    } on UnsupportedError {
      onShaderError();
      _paintGradientFallback(canvas, size, spec);
    } on StateError {
      onShaderError();
      _paintGradientFallback(canvas, size, spec);
    }
  }

  static void _paintGradientFallback(
    Canvas canvas,
    Size size,
    BackdropStyleSpec spec,
  ) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = spec.base);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: spec.colors,
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_ShaderBackdropPainter old) =>
      old.theme != theme ||
      old.shader != shader ||
      old.dark != dark ||
      old.grainEnabled != grainEnabled;
}

class _DiffusionBackdropPainter extends CustomPainter {
  _DiffusionBackdropPainter({
    required this.theme,
    required this.tab,
    required this.dark,
    required this.phase,
    required this.positionResolver,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final BackdropTheme theme;
  final int tab;
  final bool dark;
  final Animation<double> phase;
  final double Function() positionResolver;

  @override
  void paint(Canvas canvas, Size size) {
    final pos = positionResolver();
    if (theme != BackdropTheme.diffusion) {
      _ShaderBackdropPainter._paintGradientFallback(
        canvas,
        size,
        BackdropStyleSpec.forPosition(theme, dark, pos),
      );
      return;
    }
    _paintDiffusion(canvas, size, pos);
  }

  // Broad elliptical fields overlap beyond the viewport: no visible orb edges.
  // Analytic falloff avoids adding a full-screen blur pass on every frame.
  void _paintDiffusion(Canvas canvas, Size size, double pos) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? AppPalette.ambientBaseDark
              : AppPalette.ambientBaseLight,
        ).createShader(bounds),
    );
    final hues = AppPalette.ambientHuesAt(dark, pos);
    final motionWeight = (1.0 - pos).clamp(0.0, 1.0);
    final angle = motionWeight > 0 ? phase.value * math.pi * 2 : 0.0;
    for (var i = 0; i < hues.length; i++) {
      final orbit = angle + i * math.pi / 2;
      final nimble = !dark && i.isOdd;
      final baseX = dark
          ? const [-.06, 1.00, .06, .96][i]
          : ui.lerpDouble(
              const [.20, .82, .78, .22][i],
              const [.42, .56, .58, .44][i],
              motionWeight,
            )!;
      final baseY = dark
          ? const [.08, .32, .62, .92][i]
          : ui.lerpDouble(
              const [.16, .34, .74, .84][i],
              const [.18, .36, .64, .82][i],
              motionWeight,
            )!;
      final dx =
          motionWeight *
          (dark
              ? .26 * math.sin(orbit) + .07 * math.cos(2 * angle + i)
              : nimble
              ? .34 * math.sin(orbit) + .14 * math.sin(2 * angle + i)
              : .28 * math.sin(orbit) + .07 * math.cos(2 * angle + i));
      final dy =
          motionWeight *
          (dark
              ? .10 * math.cos(orbit) + .035 * math.sin(2 * angle + i)
              : nimble
              ? .16 * math.cos(2 * angle + i * .8) + .06 * math.sin(orbit)
              : .13 * math.cos(orbit + i * .4) + .04 * math.sin(2 * angle + i));
      final center = Offset(
        size.width * (baseX + dx),
        size.height * (baseY + dy),
      );
      final baseAlpha = dark
          ? const [.24, .21, .14, .16][i]
          : const [.34, .32, .30, .28][i];
      final alpha = !dark
          ? baseAlpha *
                ui.lerpDouble(
                  1.0,
                  .86 + .14 * math.sin(2 * angle + i * 1.2),
                  motionWeight,
                )!
          : baseAlpha;
      final tilt =
          motionWeight *
          (i.isEven ? 1 : -1) *
          (dark ? .18 * math.sin(orbit) : .22 + .34 * math.sin(orbit));
      final sx =
          size.width *
          (dark
              ? .96 + motionWeight * .12 * math.cos(orbit)
              : ui.lerpDouble(
                  .80,
                  nimble
                      ? .58 + .16 * math.cos(2 * angle + i)
                      : .78 + .12 * math.cos(orbit + i * .6),
                  motionWeight,
                )!);
      final sy =
          size.height *
          (dark
              ? .40 + motionWeight * .06 * math.sin(2 * angle + i)
              : ui.lerpDouble(
                  .36,
                  nimble
                      ? .25 + .07 * math.sin(orbit)
                      : .33 + .06 * math.sin(2 * angle + i * .8),
                  motionWeight,
                )!);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      if (tilt != 0) canvas.rotate(tilt);
      canvas.scale(sx, sy);
      canvas.drawCircle(
        Offset.zero,
        1,
        Paint()
          ..shader = RadialGradient(
            stops: dark ? const [0, .22, .58, 1] : const [0, .24, .62, 1],
            colors: [
              hues[i].withValues(alpha: alpha),
              hues[i].withValues(alpha: alpha * (dark ? .84 : .82)),
              hues[i].withValues(alpha: alpha * (dark ? .30 : .32)),
              hues[i].withValues(alpha: 0),
            ],
          ).createShader(const Rect.fromLTWH(-1, -1, 2, 2)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_DiffusionBackdropPainter old) =>
      old.theme != theme || old.tab != tab || old.dark != dark;
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
