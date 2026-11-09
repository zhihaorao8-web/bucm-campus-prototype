import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// A bounded backdrop blur: content stays sharp, only the floating dock is frosted.
class GlassNavigation extends StatelessWidget {
  const GlassNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
  });
  final int selected;
  final ValueChanged<int> onSelect;
  static const labels = ['今日', '课表', '设置'];
  static const icons = [
    Icons.wb_sunny_outlined,
    Icons.calendar_view_week_outlined,
    Icons.tune_outlined,
  ];
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = Theme.of(context).colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final opaque = MediaQuery.highContrastOf(context);
    final motion = !MediaQuery.disableAnimationsOf(context);
    final height =
        70.0 + (MediaQuery.textScalerOf(context).scale(13) - 13).clamp(0, 24);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? .28 : .10),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: BackdropFilter(
                  key: const ValueKey('dock-blur'),
                  enabled: !opaque,
                  filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: (dark ? const Color(0xFF282828) : Colors.white)
                          .withValues(
                            alpha: opaque
                                ? 1
                                : dark
                                ? .78
                                : .72,
                          ),
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: dark ? .16 : .85),
                        width: .7,
                      ),
                    ),
                    child: SizedBox(
                      height: height,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: AnimatedAlign(
                                duration: motion
                                    ? const Duration(milliseconds: 240)
                                    : Duration.zero,
                                curve: Curves.easeOutCubic,
                                alignment: Alignment(-1.0 + selected, 0),
                                child: FractionallySizedBox(
                                  widthFactor: 1 / 3,
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
                                                Icon(
                                                  icons[index],
                                                  size: 25,
                                                  color: selected == index
                                                      ? colors.primary
                                                      : colors.onSurfaceVariant,
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  labels[index],
                                                  maxLines: 1,
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall!
                                                      .copyWith(
                                                        fontSize: 12,
                                                        height: 1.2,
                                                        fontWeight:
                                                            selected == index
                                                            ? FontWeight.w600
                                                            : FontWeight.w400,
                                                        color: selected == index
                                                            ? colors.primary
                                                            : colors
                                                                  .onSurfaceVariant,
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
