import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/appearance_controller.dart';

/// A clipped, translucent course surface. Text is painted after the blur.
class AcrylicSurface extends ConsumerWidget {
  const AcrylicSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentAppearanceProvider);
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opaque =
        MediaQuery.highContrastOf(context) ||
        settings.contrast > 0 ||
        !settings.blur ||
        !settings.glass;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: opaque
            ? null
            : [
                BoxShadow(
                  color: (dark ? Colors.black : const Color(0xFF75AFC2))
                      .withValues(alpha: dark ? .16 : .045),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          key: const ValueKey('focus-acrylic-blur'),
          enabled: !opaque,
          filter: ui.ImageFilter.blur(
            sigmaX: dark ? 16 : 10,
            sigmaY: dark ? 16 : 10,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: opaque ? colors.surfaceContainer : null,
              gradient: opaque
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        (dark ? const Color(0xFF252F38) : Colors.white)
                            .withValues(alpha: dark ? .86 : .46),
                        (dark ? const Color(0xFF252F38) : Colors.white)
                            .withValues(alpha: dark ? .76 : .26),
                      ],
                    ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                width: .8,
                color: opaque
                    ? colors.outlineVariant
                    : Colors.white.withValues(alpha: dark ? .15 : .80),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
