import '../design/app_tokens.dart';
import 'visual_policy.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/appearance_controller.dart';
import 'acrylic_surface.dart';

/// Frosted-acrylic segmented control for switching between classroom sections
/// (e.g. recorded playback and live stream), with sliding capsule indicator and
/// automatic opaque fallback when glass, blur, or contrast settings require it.
class ClassroomSectionSwitch extends ConsumerWidget {
  const ClassroomSectionSwitch({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    this.blurKey = const ValueKey('classroom-section-blur'),
  }) : assert(tabs.length >= 2);

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Key blurKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentAppearanceProvider);
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opaque = AppVisualPolicy.of(context, settings).opaque;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final selected = selectedIndex.clamp(0, tabs.length - 1);
    final baseStyle =
        (Theme.of(context).textTheme.bodyLarge ?? const TextStyle()).copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        );

    var maxTextHeight = 0.0;
    for (final label in tabs) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: baseStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1,
      )..layout();
      maxTextHeight = math.max(maxTextHeight, painter.height);
      painter.dispose();
    }
    final height = math.max(50.0, (maxTextHeight + 24).ceilToDouble());
    final alignX = tabs.length <= 1
        ? 0.0
        : -1.0 + 2.0 * selected / (tabs.length - 1);

    return AcrylicSurface(
      radius: AppRadius.section,
      blurKey: blurKey,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Stack(
            children: [
              AnimatedAlign(
                alignment: Alignment(alignX, 0),
                duration: reduceMotion ? Duration.zero : AppMotion.segment,
                curve: AppMotion.segmentCurve,
                child: FractionallySizedBox(
                  widthFactor: 1 / tabs.length,
                  heightFactor: 1,
                  child: DecoratedBox(
                    key: const ValueKey('classroom-section-indicator'),
                    decoration: BoxDecoration(
                      color: opaque
                          ? colors.surfaceContainerHighest
                          : (dark
                                ? Colors.white.withValues(alpha: .13)
                                : Colors.white.withValues(alpha: .84)),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        width: .6,
                        color: opaque
                            ? colors.outlineVariant
                            : Colors.white.withValues(alpha: dark ? .20 : .94),
                      ),
                      boxShadow: opaque
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: dark ? .18 : .06,
                                ),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == selected,
                        inMutuallyExclusiveGroup: true,
                        label: '${tabs[i]}，标签 ${i + 1} / ${tabs.length}',
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => onSelected(i),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                child: Text(
                                  tabs[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: baseStyle.copyWith(
                                    color: i == selected
                                        ? (opaque
                                              ? colors.onSurface
                                              : colors.primary)
                                        : colors.onSurfaceVariant,
                                    fontWeight: i == selected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
