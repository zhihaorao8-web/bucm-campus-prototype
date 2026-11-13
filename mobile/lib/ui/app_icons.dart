import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

part 'app_icons.g.dart';

@immutable
class AppIconData {
  const AppIconData(this.name, {this.matchTextDirection = false});
  final String name;
  final bool matchTextDirection;
  String get asset => 'assets/icons/iconmcp/$name.svg';
}

/// Offline IconMCP SVG, inheriting the same size, tint and opacity as Icon.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.shadows,
    this.textDirection,
  });
  final AppIconData icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final List<Shadow>? shadows;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final dimension = size ?? theme.size ?? 24;
    final tint =
        color ?? theme.color ?? Theme.of(context).colorScheme.onSurface;
    Widget picture(Color value) => SvgPicture.asset(
      icon.asset,
      width: dimension,
      height: dimension,
      colorFilter: ColorFilter.mode(value, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
    Widget result = SizedBox.square(
      dimension: dimension,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          for (final shadow in shadows ?? theme.shadows ?? const <Shadow>[])
            Transform.translate(
              offset: shadow.offset,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: shadow.blurSigma,
                  sigmaY: shadow.blurSigma,
                ),
                child: picture(shadow.color),
              ),
            ),
          picture(tint),
        ],
      ),
    );
    if (icon.matchTextDirection &&
        (textDirection ?? Directionality.of(context)) == TextDirection.rtl) {
      result = Transform.flip(flipX: true, child: result);
    }
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Opacity(opacity: theme.opacity ?? 1, child: result),
      ),
    );
  }
}

bool _licensesRegistered = false;
void registerAppIconLicenses() {
  if (_licensesRegistered) return;
  _licensesRegistered = true;
  LicenseRegistry.addLicense(() async* {
    for (final name in [
      'LICENSE',
      'LICENSE-Phosphor.txt',
      'LICENSE-Tabler.txt',
      'LICENSE-Lucide.txt',
    ]) {
      yield LicenseEntryWithLineBreaks([
        'IconMCP',
      ], await rootBundle.loadString('assets/icons/iconmcp/$name'));
    }
  });
}
