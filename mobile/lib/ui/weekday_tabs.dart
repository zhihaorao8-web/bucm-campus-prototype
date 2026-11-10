import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import '../domain/schedule.dart';

/// Size the MIUIX tabs for their actual text, including internal padding.
/// A fixed 56dp tab left only 32dp for two Chinese glyphs and painted blank
/// when the system text size exceeded that space.
class WeekdayTabs extends StatelessWidget {
  const WeekdayTabs({super.key, required this.day, required this.onSelected});
  final int day;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
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
    return MiuixTabRow(
      key: const ValueKey('weekday-tabs'),
      tabs: labels,
      selectedTabIndex: day - 1,
      contentAlignment: Alignment.center,
      minWidth: width.ceilToDouble(),
      maxWidth: width.ceilToDouble(),
      height: height.ceilToDouble(),
      itemSpacing: 6,
      onTabSelected: (index) => onSelected(index + 1),
    );
  }
}
