import '../design/app_tokens.dart';
import 'visual_policy.dart';
import 'app_icons.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/appearance_controller.dart';

/// A bounded backdrop blur: content stays sharp, only the floating dock is frosted.
class GlassNavigation extends ConsumerWidget {
  const GlassNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
    this.position,
  });
  final int selected;
  final double? position;
  final ValueChanged<int> onSelect;
  static const labels = ['今日', '课表', '图书馆', '设置'];
  static const icons = [
    AppIcons.sun,
    AppIcons.calendarWeek,
    AppIcons.book,
    AppIcons.sliders,
  ];
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentAppearanceProvider);
    final floating = settings.floating;
    final policy = AppVisualPolicy.of(context, settings);
    final glass = floating && policy.translucent;
    final radius = floating ? 40.0 : 0.0;
    final theme = Theme.of(context), colors = Theme.of(context).colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final opaque = !policy.dockBlur;
    final motion = !MediaQuery.disableAnimationsOf(context);
    final height =
        70.0 + (MediaQuery.textScalerOf(context).scale(13) - 13).clamp(0, 24);
    return SafeArea(
      top: false,
      minimum: EdgeInsets.only(bottom: floating ? AppSpace.comfortable : 0),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          floating ? AppSpace.xl : 0,
          floating ? AppSpace.md : 0,
          floating ? AppSpace.xl : 0,
          0,
        ),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: floating ? 400 : double.infinity,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                boxShadow: floating
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: dark ? .28 : .10,
                          ),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : [],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: BackdropFilter(
                  key: const ValueKey('dock-blur'),
                  enabled: !opaque,
                  filter: ui.ImageFilter.blur(
                    sigmaX: AppSurface.dockBlur,
                    sigmaY: AppSurface.dockBlur,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: (dark ? AppSurface.dockDark : Colors.white)
                          .withValues(
                            alpha: opaque
                                ? 1
                                : glass
                                ? (dark ? .78 : .72)
                                : .95,
                          ),
                      gradient: glass
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withValues(
                                  alpha: dark ? .08 : .24,
                                ),
                                Colors.transparent,
                                Colors.white.withValues(alpha: .04),
                              ],
                            )
                          : null,
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(
                        color: Colors.white.withValues(
                          alpha: glass ? (dark ? .16 : .85) : 0,
                        ),
                        width: .7,
                      ),
                    ),
                    child: SizedBox(
                      height: height,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpace.compact),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: AnimatedAlign(
                                duration: motion && position == null
                                    ? AppMotion.navigation
                                    : Duration.zero,
                                curve: Curves.easeOutCubic,
                                alignment: Alignment(
                                  -1.0 +
                                      2.0 *
                                          (position ?? selected) /
                                          (labels.length - 1),
                                  0,
                                ),
                                child: FractionallySizedBox(
                                  widthFactor: 1 / labels.length,
                                  heightFactor: 1,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: colors.onSurface.withValues(
                                        alpha: dark ? .12 : .065,
                                      ),
                                      borderRadius: BorderRadius.circular(32),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                for (
                                  var index = 0;
                                  index < labels.length;
                                  index++
                                )
                                  Expanded(
                                    child: Semantics(
                                      key: ValueKey('tab-$index'),
                                      button: true,
                                      selected: selected == index,
                                      label: labels[index],
                                      onTap: () => onSelect(index),
                                      child: ExcludeSemantics(
                                        child: MiuixPressable(
                                          onPressed: () => onSelect(index),
                                          borderRadius: BorderRadius.circular(
                                            32,
                                          ),
                                          feedbackType:
                                              MiuixPressFeedbackType.none,
                                          child: SizedBox.expand(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                AppIcon(
                                                  icons[index],
                                                  size: 25,
                                                  color: selected == index
                                                      ? colors.primary
                                                      : colors.onSurfaceVariant,
                                                ),
                                                const SizedBox(height: 3),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 2,
                                                      ),
                                                  child: FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text(
                                                      labels[index],
                                                      maxLines: 1,
                                                      style: theme
                                                          .textTheme
                                                          .bodySmall!
                                                          .copyWith(
                                                            fontSize: AppType
                                                                .smallLabel,
                                                            height: 1.2,
                                                            fontWeight:
                                                                selected ==
                                                                    index
                                                                ? FontWeight
                                                                      .w600
                                                                : FontWeight
                                                                      .w400,
                                                            color:
                                                                selected ==
                                                                    index
                                                                ? colors.primary
                                                                : colors
                                                                      .onSurfaceVariant,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ],
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
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
