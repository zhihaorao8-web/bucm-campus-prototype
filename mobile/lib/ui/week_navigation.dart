import 'app_controls.dart';
import '../design/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'app_icons.dart';
import 'app_theme.dart';

class ScheduleModeSwitch extends StatelessWidget {
  const ScheduleModeSwitch({
    super.key,
    required this.daily,
    required this.onChanged,
  });
  final bool daily;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 112,
      height: 56,
      padding: const EdgeInsets.all(AppSpace.xs),
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(AppRadius.inset),
      ),
      child: Stack(
        children: [
          AppSegmentIndicator(
            selected: daily ? 1 : 0,
            count: 2,
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.small),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
          Row(
            children: [
              for (final (value, label) in [(false, '周'), (true, '日')])
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: value == daily,
                    label: '$label视图',
                    child: MiuixPressable(
                      onPressed: () => onChanged(value),
                      borderRadius: BorderRadius.circular(AppRadius.small),
                      child: Center(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: value == daily
                                ? colors.onSurface
                                : colors.onSurfaceVariant,
                            fontWeight: value == daily
                                ? FontWeight.w600
                                : FontWeight.w400,
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
    );
  }
}

class WeekNavigation extends StatefulWidget {
  const WeekNavigation({
    super.key,
    required this.week,
    required this.range,
    required this.isCurrent,
    required this.onCurrent,
    this.onPrevious,
    this.onNext,
  });
  final int week;
  final String range;
  final bool isCurrent;
  final VoidCallback? onPrevious, onNext;
  final VoidCallback onCurrent;
  @override
  State<WeekNavigation> createState() => _WeekNavigationState();
}

class _WeekNavigationState extends State<WeekNavigation> {
  double drag = 0;
  @override
  Widget build(BuildContext context) {
    final motion = !MediaQuery.disableAnimationsOf(context);
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      key: const ValueKey('week-navigation'),
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => drag = 0,
      onHorizontalDragUpdate: (details) => drag += details.delta.dx,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (drag.abs() > 40 || velocity.abs() > 450) {
          final direction = drag.abs() > 12 ? drag : velocity;
          (direction < 0 ? widget.onNext : widget.onPrevious)?.call();
        }
      },
      child: Row(
        children: [
          IconButton(
            tooltip: '上一周',
            onPressed: widget.onPrevious,
            icon: const AppIcon(AppIcons.chevronLeft),
          ),
          Expanded(
            child: Column(
              children: [
                AnimatedSwitcher(
                  duration: motion ? AppMotion.segment : Duration.zero,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, .2),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    '第 ${widget.week} 周',
                    key: ValueKey(widget.week),
                    style: Theme.of(context).textTheme.titleMedium!.copyWith(
                      fontFeatures: tabularTime,
                    ),
                  ),
                ),
                Text(
                  widget.range,
                  style: TextStyle(
                    fontSize: AppType.caption,
                    color: colors.onSurfaceVariant,
                    fontFeatures: tabularTime,
                  ),
                ),
              ],
            ),
          ),
          if (!widget.isCurrent)
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: colors.primaryContainer,
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              ),
              onPressed: widget.onCurrent,
              child: const Text('本周'),
            ),
          IconButton(
            tooltip: '下一周',
            onPressed: widget.onNext,
            icon: const AppIcon(AppIcons.chevronRight),
          ),
        ],
      ),
    );
  }
}
