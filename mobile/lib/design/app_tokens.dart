import 'package:flutter/material.dart';

/// Primitive scale. Use semantic/component aliases below where the role is known.
abstract final class AppSpace {
  static const xs = 4.0, sm = 8.0, md = 12.0, lg = 16.0, xl = 24.0, xxl = 32.0;
  static const control = 10.0, comfortable = 20.0, compact = 6.0;
}

abstract final class AppLayout {
  static const minTap = 48.0;
  static const pageInset = AppSpace.xl;
  static const settingsInset = AppSpace.lg;
  static const pageTop = AppSpace.md;
  static const pageBottom = AppSpace.xxl;
  static const compactCardInset = 18.0, focusInset = 22.0;
}

abstract final class AppRadius {
  static const input = 16.0, button = 18.0, section = 20.0;
  static const card = 24.0, focus = 28.0, sheet = 28.0;
  static const small = 12.0, inset = 16.0;
}

abstract final class AppType {
  static const label = 14.0, body = 16.0, title = 17.0;
  static const section = 22.0, page = 34.0, compactPage = 30.0;
  static const focusTime = 38.0;
  static const control = 15.0, smallLabel = 12.0, caption = 11.0;
  static const secondary = 13.0, micro = 10.0, dense = 9.0;
  static const previewTime = 20.0, artisticHeader = 40.0;
}

abstract final class AppControl {
  static const radius = 14.0;
  static const icon = 18.0;
  static const inset = AppSpace.lg;
  static const secondaryInset = 14.0;
  static const verticalInset = AppSpace.control;
}

abstract final class AppMotion {
  static const navigation = Duration(milliseconds: 260);
  static const segment = Duration(milliseconds: 220);
  static const contentEnter = Duration(milliseconds: 180);
  static const contentExit = Duration(milliseconds: 120);
  static const routeEnter = Duration(milliseconds: 280);
  static const routeExit = Duration(milliseconds: 220);
  static const ambient = Duration(seconds: 10);
  static const ambientChange = Duration(milliseconds: 900);
  static const title = Duration(milliseconds: 1350);
  static const navigationCurve = Cubic(.23, 1, .32, 1);
  static const segmentCurve = Curves.easeOutCubic;
}

abstract final class AppHeader {
  static const blur = 20.0;
  static const fadeDistance = 80.0;
  static const initialTint = .04;
  static const tintRange = .76;

  static double tint(double offset, {bool opaque = false}) => opaque
      ? 1
      : initialTint + tintRange * (offset / fadeDistance).clamp(0.0, 1.0);
}

/// Surface variants retain distinct density; they do not add per-grid blur.
abstract final class AppSurface {
  static const focusBlur = 10.0, sheetBlur = 12.0, dockBlur = 24.0;
  static const focusDark = Color(0xFF252F38);
  static const focusShadowLight = Color(0xFF75AFC2);
  static const dockDark = Color(0xFF282828);
  static const edgeVariation = .02;
  static double listAlpha(bool dark, {bool dense = false}) =>
      dense ? (dark ? .84 : .90) : (dark ? .64 : .78);
  static double sheetAlpha(bool dark) => dark ? .92 : .90;
  static List<Color> focusFill(bool dark) => [
    (dark ? focusDark : Colors.white).withValues(alpha: dark ? .30 : .46),
    (dark ? focusDark : Colors.white).withValues(alpha: dark ? .16 : .26),
  ];
}
