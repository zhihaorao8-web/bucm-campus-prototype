import '../design/app_tokens.dart';
import 'package:flutter/material.dart';

const navigationDuration = AppMotion.navigation;
const navigationCurve = AppMotion.navigationCurve;

/// Retain scroll/state while keeping non-visible tabs out of hit testing,
/// semantics, and widget visibility checks. Only the viewport drives motion.
class RetainedNavigationPage extends StatefulWidget {
  const RetainedNavigationPage({
    super.key,
    required this.controller,
    required this.index,
    required this.selected,
    required this.child,
  });
  final PageController controller;
  final int index, selected;
  final Widget child;
  @override
  State<RetainedNavigationPage> createState() => _RetainedNavigationPageState();
}

class _RetainedNavigationPageState extends State<RetainedNavigationPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AnimatedBuilder(
      animation: widget.controller,
      child: widget.child,
      builder: (context, child) {
        final position = navigationPosition(widget.controller, widget.selected);
        final selected = widget.index == widget.selected;
        return Offstage(
          offstage: (position - widget.index).abs() >= .99999,
          child: TickerMode(
            enabled: selected,
            child: ExcludeSemantics(
              excluding: !selected,
              child: ExcludeFocus(
                excluding: !selected,
                child: IgnorePointer(ignoring: !selected, child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}

double navigationPosition(PageController controller, int fallback) =>
    controller.hasClients && controller.position.hasContentDimensions
    ? controller.page ?? fallback.toDouble()
    : fallback.toDouble();

/// Both modes have stable elements and independent scroll controllers. The
/// viewport does not resize; the outgoing mode cannot receive taps or focus.
class ScheduleModeTransition extends StatefulWidget {
  const ScheduleModeTransition({
    super.key,
    required this.daily,
    required this.weekly,
    required this.dailyView,
  });
  final bool daily;
  final Widget weekly, dailyView;
  @override
  State<ScheduleModeTransition> createState() => _ScheduleModeTransitionState();
}

class _ScheduleModeTransitionState extends State<ScheduleModeTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController progress = AnimationController(
    vsync: this,
    value: widget.daily ? 1 : 0,
  );
  void synchronize() {
    final target = widget.daily ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      progress.value = target;
    } else if (progress.value != target) {
      progress.animateTo(
        target,
        duration: AppMotion.segment,
        curve: navigationCurve,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    synchronize();
  }

  @override
  void didUpdateWidget(ScheduleModeTransition old) {
    super.didUpdateWidget(old);
    if (old.daily != widget.daily) synchronize();
  }

  @override
  void dispose() {
    progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: progress,
    builder: (context, _) => ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (var index = 0; index < 2; index++)
            Offstage(
              offstage: index == 0 ? progress.value == 1 : progress.value == 0,
              child: TickerMode(
                enabled: (index == 1) == widget.daily,
                child: ExcludeSemantics(
                  excluding: (index == 1) != widget.daily,
                  child: IgnorePointer(
                    ignoring: (index == 1) != widget.daily,
                    child: FractionalTranslation(
                      translation: Offset(
                        index == 0
                            ? -.015 * progress.value
                            : .015 * (1 - progress.value),
                        0,
                      ),
                      child: Opacity(
                        opacity: index == 0
                            ? 1 - progress.value
                            : progress.value,
                        child: index == 0 ? widget.weekly : widget.dailyView,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Only course content changes; headers and scroll viewports stay in place.
class ScheduleContentTransition extends StatefulWidget {
  const ScheduleContentTransition({
    super.key,
    required this.order,
    required this.child,
  });
  final int order;
  final Widget child;
  @override
  State<ScheduleContentTransition> createState() =>
      _ScheduleContentTransitionState();
}

class _ScheduleContentTransitionState extends State<ScheduleContentTransition> {
  double direction = 1;
  @override
  void didUpdateWidget(ScheduleContentTransition old) {
    super.didUpdateWidget(old);
    if (widget.order != old.order) {
      direction = widget.order > old.order ? 1 : -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return ClipRect(
      child: AnimatedSwitcher(
        duration: reduced ? Duration.zero : AppMotion.contentEnter,
        reverseDuration: reduced ? Duration.zero : AppMotion.contentExit,
        transitionBuilder: (child, animation) {
          final entering = child.key == ValueKey(widget.order);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: Offset((entering ? 1 : -1) * direction * .025, 0),
                end: Offset.zero,
              ).chain(CurveTween(curve: navigationCurve)).animate(animation),
              child: child,
            ),
          );
        },
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [
            for (final old in previous)
              ExcludeSemantics(child: IgnorePointer(child: old)),
            ?current,
          ],
        ),
        child: KeyedSubtree(key: ValueKey(widget.order), child: widget.child),
      ),
    );
  }
}
