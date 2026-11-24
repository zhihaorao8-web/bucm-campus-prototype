import 'app_controls.dart';
import '../design/app_tokens.dart';
import 'visual_policy.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/appearance_controller.dart';
import 'acrylic_surface.dart';

/// Frosted-acrylic segmented control for switching between classroom and library
/// sections with a shared liquid glass selection lens and automatic opaque
/// fallback when glass, blur, or contrast settings require it.
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
    final policy = AppVisualPolicy.of(context, settings);
    final colors = Theme.of(context).colorScheme;
    final opaque = policy.opaque;
    final selected = selectedIndex.clamp(0, tabs.length - 1);
    final baseStyle =
        (Theme.of(context).textTheme.bodyLarge ?? const TextStyle()).copyWith(
          fontSize: AppType.control,
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

    return AcrylicSurface(
      radius: AppRadius.section,
      blurKey: blurKey,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xs),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AppSegmentIndicator(
                selected: selected,
                count: tabs.length,
                indicatorKey: const ValueKey('classroom-section-indicator'),
                liquidGlass: true,
                radius: AppRadius.inset,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.inset),
                  border: Border.all(
                    width: policy.highContrast ? 1 : .6,
                    color: policy.highContrast
                        ? colors.outline
                        : colors.outlineVariant,
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
                            borderRadius: BorderRadius.circular(
                              AppRadius.inset,
                            ),
                            onTap: () => onSelected(i),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpace.control,
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
