import 'package:flutter/material.dart';
import '../application/appearance_controller.dart';

/// Shared system/user accessibility decisions. Background animation still owns
/// foreground/TickerMode checks; reduced motion does not remove static material.
class AppVisualPolicy {
  AppVisualPolicy.of(BuildContext context, this.settings)
    : highContrast =
          MediaQuery.highContrastOf(context) || settings.contrast > 0,
      reducedMotion = MediaQuery.disableAnimationsOf(context);

  final AppearanceSettings settings;
  final bool highContrast, reducedMotion;
  bool get translucent => !highContrast && settings.blur && settings.glass;
  bool get opaque => !translucent;
  bool get liquidGlass => translucent;
  // The existing dock can retain plain blur with glass highlights switched off.
  bool get dockBlur => !highContrast && settings.blur && settings.floating;
}
