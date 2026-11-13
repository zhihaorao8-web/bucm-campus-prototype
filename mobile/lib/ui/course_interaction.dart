import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_miuix/miuix.dart';

/// One accessible press primitive, including keyboard and cancellation. The
/// library's spring retargets from its current value; never stack two scales.
class CoursePressable extends StatefulWidget {
  const CoursePressable({
    super.key,
    required this.onPressed,
    required this.child,
    this.radius = 24,
    this.dense = false,
  });
  final VoidCallback onPressed;
  final Widget child;
  final double radius;
  final bool dense;
  @override
  State<CoursePressable> createState() => _CoursePressableState();
}

class _CoursePressableState extends State<CoursePressable> {
  int? pointer;
  Offset origin = Offset.zero;
  bool held = false;
  void release() {
    pointer = null;
    if (held) setState(() => held = false);
  }

  @override
  Widget build(BuildContext context) => Listener(
    // Start visual feedback on contact, without claiming the gesture arena.
    // Scroll/swipe recognizers can still cancel activation normally.
    onPointerDown: (event) {
      if (pointer != null) return;
      pointer = event.pointer;
      origin = event.position;
      setState(() => held = true);
    },
    onPointerMove: (event) {
      if (event.pointer == pointer &&
          (event.position - origin).distance > kTouchSlop) {
        release();
      }
    },
    onPointerUp: (event) {
      if (event.pointer == pointer) release();
    },
    onPointerCancel: (event) {
      if (event.pointer == pointer) release();
    },
    child: MiuixPressable(
      onPressed: widget.onPressed,
      heldDown: held,
      borderRadius: BorderRadius.circular(widget.radius),
      feedbackType: MediaQuery.disableAnimationsOf(context)
          ? MiuixPressFeedbackType.none
          : MiuixPressFeedbackType.sink,
      sinkAmount: widget.dense ? .99 : .98,
      overlayColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.white
          : Theme.of(context).colorScheme.primary,
      child: widget.child,
    ),
  );
}

class CourseCardLink extends StatefulWidget {
  const CourseCardLink({
    super.key,
    required this.onOpen,
    required this.child,
    this.radius = 24,
  });
  final Future<void> Function(Object? tag) onOpen;
  final Widget child;
  final double radius;
  @override
  State<CourseCardLink> createState() => _CourseCardLinkState();
}

class _CourseCardLinkState extends State<CourseCardLink> {
  // Identity is local to this visual occurrence, not the course id. Repeated
  // segments and the focus card may legitimately show the same course.
  final tag = Object();
  bool opening = false;
  @override
  Widget build(BuildContext context) {
    final transitionTag = MediaQuery.disableAnimationsOf(context) ? null : tag;
    return CoursePressable(
      radius: widget.radius,
      onPressed: () async {
        if (opening) return;
        opening = true;
        try {
          await widget.onOpen(transitionTag);
        } finally {
          opening = false;
        }
      },
      child: CourseCardHero(tag: transitionTag, child: widget.child),
    );
  }
}

class CourseCardHero extends StatelessWidget {
  const CourseCardHero({super.key, required this.tag, required this.child});
  final Object? tag;
  final Widget child;
  @override
  Widget build(BuildContext context) => tag == null
      ? child
      : Hero(
          tag: tag!,
          transitionOnUserGestures: true,
          // Text-rich cards have different intrinsic heights. Keep the flying
          // destination vertically unconstrained and clip to the animated rect
          // rather than squeezing a Column into a short list-row rectangle.
          flightShuttleBuilder: (context, animation, direction, from, to) =>
              ClipRect(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: (to.widget as Hero).child,
                ),
              ),
          child: Material(type: MaterialType.transparency, child: child),
        );
}

/// Keep the configured Android predictive-back builder and native route
/// behavior; Hero supplies card continuity. Reduced motion has zero duration.
class CourseDetailsRoute extends MaterialPageRoute<void> {
  CourseDetailsRoute({required super.builder, required this.reducedMotion});
  final bool reducedMotion;
  @override
  Duration get transitionDuration =>
      reducedMotion ? Duration.zero : const Duration(milliseconds: 280);
  @override
  Duration get reverseTransitionDuration =>
      reducedMotion ? Duration.zero : const Duration(milliseconds: 220);
}
