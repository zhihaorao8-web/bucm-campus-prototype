import 'package:flutter/material.dart';

/// Fixed identity and fallback colors. Widgets use ColorScheme for semantic
/// text/status colors; ambient and course palettes preserve the approved look.
abstract final class AppPalette {
  static const accentValue = 0xff3482ff;
  static const indigoValue = 0xff3f51b5, violetValue = 0xff7e57c2;
  static const tealValue = 0xff00897b,
      roseValue = 0xffc05072,
      amberValue = 0xffb57500;
  static const blue = Color(accentValue);
  static const paper = Color(0xFFFAF9F6), night = Color(0xFF000000);
  static const textLight = Color(0xFF1E2022);
  static const secondaryDark = Color(0xFFABABAB),
      secondaryLight = Color(0xFF5C6168);
  static const outlineLight = Color(0x151C1E21);
  static const primaryContainerDark = Color(0xFF182D4D),
      primaryContainerLight = Color(0xFFEAF2FF);
  static const success = Color(0xFF257A54);
  static const ambientSurface = Color(0xFFF9FCFF);
  static const ambientBaseDark = [
    Color(0xFF070D14),
    Color(0xFF091313),
    Color(0xFF0B0C14),
  ];
  static const ambientBaseLight = [
    Color(0xFFFAFBFD),
    Color(0xFFFCFDFF),
    Color(0xFFFDFBF7),
  ];
  static const courseLight = [
    Color(0xFFF2F6FF),
    Color(0xFFFAF5EE),
    Color(0xFFEFF8F3),
    Color(0xFFFDF1F1),
    Color(0xFFF5F0FC),
  ];
  static const courseDark = [
    Color(0xFF1E2B43),
    Color(0xFF322D25),
    Color(0xFF21342C),
    Color(0xFF382828),
    Color(0xFF2E283C),
  ];
  static const courseInk = [
    Color(0xFF3B6EF6),
    Color(0xFF9A6B2F),
    Color(0xFF257A54),
    Color(0xFFC23B3B),
    Color(0xFF6E44B8),
  ];
  static List<Color> ambientHues(bool dark, int tab) {
    const todayDarkHues = [
      Color(0xFF6CCFFF),
      Color(0xFF7FE8CD),
      Color(0xFFFFD1A6),
      Color(0xFFB8BBFF),
    ];
    const todayLightHues = [
      Color(0xFF6ECBFF),
      Color(0xFF7BE3C9),
      Color(0xFFA79FFF),
      Color(0xFFFFBED1),
    ];
    // Reading pages use the same broad diffusion, with their existing palettes
    // and a fixed phase. Only Today owns continuous ambient motion.
    return dark
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
              Color(0xFF78B0FF),
              Color(0xFF7AE0C7),
              Color(0xFFB5D6FF),
              Color(0xFFB7B3FF),
            ],
            2 => const [
              Color(0xFFB398FF),
              Color(0xFFFFC59F),
              Color(0xFFE0CCFF),
              Color(0xFF82D1FF),
            ],
            _ => todayLightHues,
          };
  }
}
