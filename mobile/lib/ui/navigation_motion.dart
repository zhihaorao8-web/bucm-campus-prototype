import 'package:flutter/material.dart';

const navigationDuration = Duration(milliseconds: 260);
const navigationCurve = Cubic(.23, 1, .32, 1);

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
              child: IgnorePointer(ignoring: !selected, child: child),
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
