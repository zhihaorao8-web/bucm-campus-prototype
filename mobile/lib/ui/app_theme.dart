import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_miuix/miuix.dart';
import '../application/appearance_controller.dart';
import 'app_icons.dart';

/// HyperOS / MIUIX surfaces and typography, shared with Flutter route overlays.
abstract final class AppColors {
  static const blue = Color(0xFF3482FF);
  static const paper = Color(0xFFF7F7F7);
  static const night = Color(0xFF000000);
  static const courseLight = [
    Color(0xFFEDF3FF),
    Color(0xFFF3EFE8),
    Color(0xFFEAF4F0),
    Color(0xFFF8EEEE),
    Color(0xFFF0EDFA),
  ];
  static const courseDark = [
    Color(0xFF1E2B43),
    Color(0xFF322D25),
    Color(0xFF21342C),
    Color(0xFF382828),
    Color(0xFF2E283C),
  ];
  static Color courseAt(BuildContext context, int index) {
    final colors = Theme.of(context).brightness == Brightness.dark
        ? courseDark
        : courseLight;
    if (index < colors.length) return colors[index];
    // Dense conflict graphs can need extra colors; never wrap to a used one.
    return HSLColor.fromAHSL(
      1,
      ((index - colors.length) * 137.508) % 360,
      .45,
      Theme.of(context).brightness == Brightness.dark ? .18 : .94,
    ).toColor();
  }
}

ThemeData appTheme(
  Brightness brightness, {
  AppearanceSettings settings = const AppearanceSettings(),
  int? systemAccent,
}) {
  final dark = brightness == Brightness.dark;
  final miuix = dark ? darkColorScheme() : lightColorScheme();
  final seed = Color(
    settings.monet && systemAccent != null ? systemAccent : settings.accent,
  );
  final generated = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    dynamicSchemeVariant: settings.variant,
    contrastLevel: settings.contrast,
  );
  final customized =
      settings.monet ||
      settings.accent != 0xff3482ff ||
      settings.variant != DynamicSchemeVariant.tonalSpot ||
      settings.contrast != 0;
  final colors = customized
      ? generated
      : ColorScheme.fromSeed(
          seedColor: miuix.primary,
          brightness: brightness,
        ).copyWith(
          primary: miuix.primary,
          onPrimary: miuix.onPrimary,
          surface: miuix.surface,
          onSurface: miuix.onSurface,
          surfaceContainer: miuix.surfaceContainer,
          surfaceContainerHighest: miuix.secondaryVariant,
          onSurfaceVariant: dark
              ? const Color(0xFFABABAB)
              : const Color(0xFF757575),
          outlineVariant: miuix.dividerLine,
          primaryContainer: dark
              ? const Color(0xFF182D4D)
              : const Color(0xFFEAF2FF),
          onPrimaryContainer: miuix.primary,
        );
  final text = Typography.material2021().black
      .apply(bodyColor: colors.onSurface, displayColor: colors.onSurface)
      .copyWith(
        headlineLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: colors.onSurface,
        ),
        headlineMedium: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: colors.onSurface,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          height: 1.5,
          color: colors.onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: colors.onSurface,
        ),
      );
  return ThemeData(
    useMaterial3: true,
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const AppIcon(AppIcons.arrowBack),
      closeButtonIconBuilder: (_) => const AppIcon(AppIcons.close),
    ),
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        TargetPlatform.android: settings.predictiveBack
            ? const PredictiveBackPageTransitionsBuilder()
            : const ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: const CupertinoPageTransitionsBuilder(),
      },
    ),
    brightness: brightness,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    textTheme: text,
    splashFactory: NoSplash.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant,
      thickness: .5,
      space: 32,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surfaceContainer,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

class MiuixThemeBridge extends StatelessWidget {
  const MiuixThemeBridge({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), text = Theme.of(context).textTheme;
    final base = MiuixThemeData.of(theme.brightness);
    return MiuixTheme(
      data: base.copyWith(
        colors: base.colors.copy(
          primary: theme.colorScheme.primary,
          onPrimary: theme.colorScheme.onPrimary,
          primaryVariant: theme.colorScheme.primaryContainer,
          onPrimaryVariant: theme.colorScheme.onPrimaryContainer,
          primaryContainer: theme.colorScheme.primaryContainer,
          onPrimaryContainer: theme.colorScheme.onPrimaryContainer,
          background: theme.colorScheme.surface,
          onBackground: theme.colorScheme.onSurface,
          surface: theme.colorScheme.surface,
          onSurface: theme.colorScheme.onSurface,
          surfaceContainer: theme.colorScheme.surfaceContainer,
          onSurfaceContainer: theme.colorScheme.onSurface,
          secondaryVariant: theme.colorScheme.surfaceContainerHighest,
          onSurfaceVariantSummary: theme.colorScheme.onSurfaceVariant,
          onSurfaceVariantActions: theme.colorScheme.onSurfaceVariant,
          dividerLine: theme.colorScheme.outlineVariant,
          outline: theme.colorScheme.outline,
        ),
        textStyles: base.textStyles.copy(
          main: text.bodyLarge,
          paragraph: text.bodyLarge,
          body1: text.bodyLarge,
          body2: text.bodyMedium,
          button: text.titleMedium,
          footnote1: text.bodyMedium,
          footnote2: text.bodySmall,
          headline1: text.titleMedium,
          headline2: text.bodyLarge,
          subtitle: text.bodyMedium,
          title1: text.headlineLarge,
          title2: text.headlineMedium,
          title3: text.titleLarge,
          title4: text.titleMedium,
        ),
      ),
      child: child,
    );
  }
}
