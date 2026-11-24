import '../design/app_tokens.dart';
import 'visual_policy.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/schedule.dart';
import '../application/appearance_controller.dart';
import 'acrylic_surface.dart';

/// Size the MIUIX tabs for their actual text, including internal padding.
/// A fixed 56dp tab left only 32dp for two Chinese glyphs and painted blank
/// when the system text size exceeded that space.
class WeekdayTabs extends ConsumerWidget {
  const WeekdayTabs({super.key, required this.day, required this.onSelected});
  final int day;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = MiuixTheme.of(context);
    final settings = ref.watch(currentAppearanceProvider);
    final colors = Theme.of(context).colorScheme;
    final opaque = AppVisualPolicy.of(context, settings).opaque;
    final style = DefaultTextStyle.of(context).style
        .merge(theme.textStyles.main)
        .copyWith(
          fontSize: theme.textStyles.body1.fontSize,
          fontWeight: FontWeight.bold,
        );
    final labels = [for (final name in weekdays) '周$name'];
    var width = MiuixTabRowDefaults.tabRowMinWidth;
    var height = 48.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1,
      )..layout();
      width = math.max(
        width,
        painter.width + 2 * MiuixTabRowDefaults.itemHorizontalPadding + 8,
      );
      height = math.max(height, painter.height + 16);
      painter.dispose();
    }
    return AcrylicSurface(
      radius: AppRadius.section,
      blurKey: const ValueKey('weekday-acrylic-blur'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.section),
        child: MiuixTabRow(
          key: const ValueKey('weekday-tabs'),
          tabs: labels,
          colors: MiuixTabRowColors(
            backgroundColor: Colors.transparent,
            contentColor: colors.onSurfaceVariant,
            selectedBackgroundColor: colors.surfaceContainer.withValues(
              alpha: opaque ? 1 : .62,
            ),
            selectedContentColor: colors.primary,
          ),
          selectedTabIndex: day - 1,
          contentAlignment: Alignment.center,
          minWidth: width.ceilToDouble(),
          maxWidth: width.ceilToDouble(),
          height: height.ceilToDouble(),
          itemSpacing: 6,
          onTabSelected: (index) => onSelected(index + 1),
        ),
      ),
    );
  }
}
