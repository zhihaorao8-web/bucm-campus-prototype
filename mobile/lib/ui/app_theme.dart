import '../design/app_palette.dart';
import '../design/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_miuix/miuix.dart';
import '../application/appearance_controller.dart';
import 'app_icons.dart';

/// HyperOS / MIUIX surfaces and typography, shared with Flutter route overlays.
abstract final class AppColors {
  static const blue = AppPalette.blue;
  static const paper = AppPalette.paper;
  static const night = AppPalette.night;
  static const courseLight = AppPalette.courseLight;
  static const courseDark = AppPalette.courseDark;
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

  static Color courseInk(BuildContext context, int index) {
    if (MediaQuery.highContrastOf(context)) {
      return Theme.of(context).colorScheme.onSurface;
    }
    const inks = AppPalette.courseInk;
    final ink = index < inks.length ? inks[index] : courseAt(context, index);
    return Theme.of(context).brightness == Brightness.dark
        ? HSLColor.fromColor(ink).withLightness(.76).toColor()
        : ink;
  }
}

const tabularTime = <FontFeature>[FontFeature.tabularFigures()];

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
      settings.accent != AppPalette.accentValue ||
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
          surface: dark ? miuix.surface : AppColors.paper,
          onSurface: dark ? miuix.onSurface : AppPalette.textLight,
          surfaceContainer: dark ? miuix.surfaceContainer : Colors.white,
          surfaceContainerHighest: miuix.secondaryVariant,
          onSurfaceVariant: dark
              ? AppPalette.secondaryDark
              : AppPalette.secondaryLight,
          outlineVariant: dark ? miuix.dividerLine : AppPalette.outlineLight,
          primaryContainer: dark
              ? AppPalette.primaryContainerDark
              : AppPalette.primaryContainerLight,
          onPrimaryContainer: miuix.primary,
        );
  final text = Typography.material2021().black
      .apply(bodyColor: colors.onSurface, displayColor: colors.onSurface)
      .copyWith(
        headlineLarge: TextStyle(
          fontSize: AppType.page,
          fontWeight: FontWeight.w700,
          color: colors.onSurface,
        ),
        headlineMedium: TextStyle(
          fontSize: AppType.compactPage,
          fontWeight: FontWeight.w700,
          color: colors.onSurface,
        ),
        titleLarge: TextStyle(
          fontSize: AppType.section,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: AppType.title,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
        bodyLarge: TextStyle(
          fontSize: AppType.body,
          height: 1.5,
          color: colors.onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: AppType.label,
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
      systemOverlayStyle:
          (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(statusBarColor: Colors.transparent),
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(AppLayout.minTap, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(AppLayout.minTap, AppLayout.minTap),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(AppLayout.minTap, AppLayout.minTap),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant,
      thickness: .5,
      space: 32,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sheet),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surfaceContainer,
      showDragHandle: true,
      modalBarrierColor: Colors.black.withValues(alpha: .28),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
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
