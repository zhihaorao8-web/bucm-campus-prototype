import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'app_palette.dart';

/// Selectable background rendering themes for [QuietBackdrop].
enum BackdropTheme {
  diffusion,
  grainGradient,
  aurora,
  horizonGradient;

  String? get shaderAsset => switch (this) {
    BackdropTheme.diffusion => null,
    BackdropTheme.grainGradient => 'shaders/backdrop_grain_gradient.frag',
    BackdropTheme.aurora => 'shaders/backdrop_aurora.frag',
    BackdropTheme.horizonGradient => 'shaders/backdrop_horizon_gradient.frag',
  };

  String get label => switch (this) {
    BackdropTheme.diffusion => '柔和弥散',
    BackdropTheme.grainGradient => '流光丝绸雾',
    BackdropTheme.aurora => '极光柔幕',
    BackdropTheme.horizonGradient => '晨昏地平线',
  };
}

/// Resolved base, palette stops, and shader geometry parameters for a given
/// [BackdropTheme], brightness, and continuous navigation position.
@immutable
class BackdropStyleSpec {
  const BackdropStyleSpec({
    required this.base,
    required this.colors,
    this.p0 = 0,
    this.p1 = 0,
    this.p2 = 0,
    this.p3 = 0,
    this.p4 = 0,
  });

  final Color base;
  final List<Color> colors;
  final double p0, p1, p2, p3, p4;

  static double _toLinear(double c) => c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  static double _cbrt(double v) =>
      v < 0 ? -math.pow(-v, 1 / 3).toDouble() : math.pow(v, 1 / 3).toDouble();

  /// Converts an sRGB [Color] to OKLab `(l, a, b)` for perceptual shader blends.
  static ({double l, double a, double b}) colorToOklab(Color c) {
    final r = _toLinear(c.r);
    final g = _toLinear(c.g);
    final b = _toLinear(c.b);
    final l = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    final m = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    final s = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    return (
      l: 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
      a: 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
      b: 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
    );
  }

  static const _grainLightBases = [
    Color(0xFFFAFBFD),
    Color(0xFFFCFDFF),
    Color(0xFFFDFBF7),
    Color(0xFFFAF9F6),
  ];
  static const _grainDarkBases = [
    Color(0xFF070D14),
    Color(0xFF070D14),
    Color(0xFF091313),
    Color(0xFF0B0C14),
  ];
  static const _grainLightStops = [
    [
      Color(0xFFFAFBFD),
      Color(0xFFDFF1FF),
      Color(0xFFD8F4EB),
      Color(0xFFE8E4FF),
      Color(0xFFFDE4EE),
    ],
    [
      Color(0xFFFCFDFF),
      Color(0xFFDCEBFF),
      Color(0xFFD7F2EB),
      Color(0xFFE3EEFF),
      Color(0xFFE6E3FF),
    ],
    [
      Color(0xFFFDFBF7),
      Color(0xFFD7F2E8),
      Color(0xFFDFEEFF),
      Color(0xFFE4F2EA),
      Color(0xFFF4EBDC),
    ],
    [
      Color(0xFFFAF9F6),
      Color(0xFFEAE1FF),
      Color(0xFFFCE6D6),
      Color(0xFFEFE5FF),
      Color(0xFFE0F1FF),
    ],
  ];
  static const _grainDarkStops = [
    [
      Color(0xFF070D14),
      Color(0xFF0E243B),
      Color(0xFF12313A),
      Color(0xFF1C2542),
      Color(0xFF2B2030),
    ],
    [
      Color(0xFF070D14),
      Color(0xFF0E1F3D),
      Color(0xFF102C2E),
      Color(0xFF182942),
      Color(0xFF1D1E3B),
    ],
    [
      Color(0xFF091313),
      Color(0xFF0D2926),
      Color(0xFF112638),
      Color(0xFF193330),
      Color(0xFF2A251B),
    ],
    [
      Color(0xFF0B0C14),
      Color(0xFF1E1736),
      Color(0xFF2E2019),
      Color(0xFF221C36),
      Color(0xFF0F2436),
    ],
  ];
  static const _grainParams = [
    (1.22, 0.88, 0.38, 35.0, 0.66),
    (1.38, 0.58, 0.24, -20.0, 0.58),
    (1.28, 0.74, 0.32, 60.0, 0.62),
    (1.32, 0.68, 0.30, 115.0, 0.64),
  ];

  static const _horizonLightStops = [
    [
      Color(0xFFAED6FF),
      Color(0xFFCBE5FF),
      Color(0xFFE2F2FF),
      Color(0xFFF2F8FF),
      Color(0xFFFAFBFD),
    ],
    [
      Color(0xFFB4D0FF),
      Color(0xFFCEE0FF),
      Color(0xFFE3EEFF),
      Color(0xFFF2F7FF),
      Color(0xFFFCFDFF),
    ],
    [
      Color(0xFFB2EBD9),
      Color(0xFFC9F1E4),
      Color(0xFFE2F6EF),
      Color(0xFFF2F9F6),
      Color(0xFFFDFBF7),
    ],
    [
      Color(0xFFD0C0FF),
      Color(0xFFE1D6FF),
      Color(0xFFEFE9FF),
      Color(0xFFF6F2FB),
      Color(0xFFFAF9F6),
    ],
  ];
  static const _horizonDarkStops = [
    [
      Color(0xFF04080F),
      Color(0xFF0C213B),
      Color(0xFF173D66),
      Color(0xFF1D3550),
      Color(0xFF070D14),
    ],
    [
      Color(0xFF04070E),
      Color(0xFF0D1E3D),
      Color(0xFF183868),
      Color(0xFF1A2F4B),
      Color(0xFF070D14),
    ],
    [
      Color(0xFF050B0B),
      Color(0xFF0C2624),
      Color(0xFF15443F),
      Color(0xFF163230),
      Color(0xFF091313),
    ],
    [
      Color(0xFF06070D),
      Color(0xFF181433),
      Color(0xFF2E2454),
      Color(0xFF221D3A),
      Color(0xFF0B0C14),
    ],
  ];
  static const _horizonParams = [
    (0.92, 0.92, 1.35),
    (0.65, 0.78, 1.45),
    (0.82, 0.86, 1.38),
    (0.85, 0.88, 1.40),
  ];

  /// Returns the sub-style palette and shader parameters for [tab] (0..3).
  static BackdropStyleSpec forTab(BackdropTheme theme, bool dark, int tab) {
    final index = tab.clamp(0, 3);
    switch (theme) {
      case BackdropTheme.diffusion:
        return BackdropStyleSpec(
          base: dark
              ? AppPalette.ambientBaseDark.first
              : AppPalette.ambientBaseLight.first,
          colors: AppPalette.ambientHues(dark, index),
        );
      case BackdropTheme.grainGradient:
        final params = _grainParams[index];
        return BackdropStyleSpec(
          base: (dark ? _grainDarkBases : _grainLightBases)[index],
          colors: (dark ? _grainDarkStops : _grainLightStops)[index],
          p0: params.$1,
          p1: params.$2,
          p2: params.$3,
          p3: params.$4,
          p4: params.$5,
        );
      case BackdropTheme.aurora:
        final intensity = switch (index) {
          0 => dark ? 0.38 : 0.44,
          1 => dark ? 0.30 : 0.34,
          2 => dark ? 0.34 : 0.38,
          _ => dark ? 0.34 : 0.36,
        };
        final geometry = const [
          (0.56, 0.36, 0.88, 1.32),
          (0.68, 0.28, 0.55, 1.55),
          (0.52, 0.34, 0.70, 1.42),
          (0.62, 0.30, 0.64, 1.45),
        ][index];
        return BackdropStyleSpec(
          base: (dark ? _grainDarkBases : _grainLightBases)[index],
          colors: AppPalette.ambientHues(dark, index),
          p0: intensity,
          p1: geometry.$1,
          p2: geometry.$2,
          p3: geometry.$3,
          p4: geometry.$4,
        );
      case BackdropTheme.horizonGradient:
        final params = _horizonParams[index];
        return BackdropStyleSpec(
          base: (dark ? _grainDarkBases : _grainLightBases)[index],
          colors: (dark ? _horizonDarkStops : _horizonLightStops)[index],
          p0: params.$1,
          p1: params.$2,
          p2: params.$3,
        );
    }
  }

  /// Smoothly interpolates between adjacent page sub-styles along [position]
  /// (`0.0..3.0`) for real-time cross-page backdrop transitions.
  static BackdropStyleSpec forPosition(
    BackdropTheme theme,
    bool dark,
    double position,
  ) {
    final clamped = position.clamp(0.0, 3.0);
    final i0 = clamped.floor();
    final i1 = clamped.ceil();
    final a = forTab(theme, dark, i0);
    if (i0 == i1) return a;
    final b = forTab(theme, dark, i1);
    final t = clamped - i0;
    return BackdropStyleSpec(
      base: Color.lerp(a.base, b.base, t)!,
      colors: [
        for (var k = 0; k < a.colors.length; k++)
          Color.lerp(a.colors[k], b.colors[k], t)!,
      ],
      p0: ui.lerpDouble(a.p0, b.p0, t)!,
      p1: ui.lerpDouble(a.p1, b.p1, t)!,
      p2: ui.lerpDouble(a.p2, b.p2, t)!,
      p3: ui.lerpDouble(a.p3, b.p3, t)!,
      p4: ui.lerpDouble(a.p4, b.p4, t)!,
    );
  }
}
