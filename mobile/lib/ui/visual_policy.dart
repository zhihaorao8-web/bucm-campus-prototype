import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../application/appearance_controller.dart';

/// Shared system/user accessibility decisions. Background animation still owns
/// foreground/TickerMode checks; reduced motion does not remove static material.
class AppVisualPolicy {
  AppVisualPolicy.of(BuildContext context, this.settings)
    : highContrast =
          MediaQuery.highContrastOf(context) || settings.contrast > 0,
      reducedMotion = MediaQuery.disableAnimationsOf(context);

  final AppearanceSettings settings;
  final bool highContrast, reducedMotion;
  bool get translucent => !highContrast && settings.blur && settings.glass;
  bool get opaque => !translucent;
  bool get liquidGlass => translucent;
  // The existing dock can retain plain blur with glass highlights switched off.
  bool get dockBlur => !highContrast && settings.blur && settings.floating;
}

/// True while [animation] is actively moving or held at an intermediate value.
/// Settled endpoints and zero-duration reduced-motion routes remain inactive.
bool isBackdropAnimationActive(Animation<double>? animation) {
  if (animation == null) return false;
  final status = animation.status;
  if (status == AnimationStatus.forward || status == AnimationStatus.reverse) {
    return true;
  }
  final value = animation.value;
  return value > 0.0 && value < 1.0;
}

/// Monotonically suspends descendant [BackdropFilter] and shader passes
/// inside transient offscreen layers (Hero flight shuttles, opacity fades).
class BackdropSuspensionScope extends InheritedWidget {
  const BackdropSuspensionScope({
    super.key,
    required this.suspended,
    required super.child,
  });

  final bool suspended;

  static bool maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<BackdropSuspensionScope>()
          ?.suspended ??
      false;

  @override
  bool updateShouldNotify(BackdropSuspensionScope oldWidget) =>
      suspended != oldWidget.suspended;
}

mixin _AnimationSuspensionMixin<T extends StatefulWidget> on State<T> {
  final List<Animation<double>> _watched = [];
  bool _animating = false;
  bool _syncScheduled = false;

  bool get isAnimating => _animating;

  void attachAnimations(Iterable<Animation<double>?> animations) {
    final next = [for (final a in animations) ?a];
    var same = _watched.length == next.length;
    if (same) {
      for (var i = 0; i < next.length; i++) {
        if (!identical(_watched[i], next[i])) {
          same = false;
          break;
        }
      }
    }
    if (!same) {
      detachAnimations();
      for (final a in next) {
        a
          ..addListener(_syncAnimating)
          ..addStatusListener(_onStatus);
        _watched.add(a);
      }
    }
    _animating = _computeAnimating();
  }

  void detachAnimations() {
    for (final a in _watched) {
      a
        ..removeListener(_syncAnimating)
        ..removeStatusListener(_onStatus);
    }
    _watched.clear();
  }

  bool _computeAnimating() => _watched.any(isBackdropAnimationActive);

  void _onStatus(AnimationStatus _) => _syncAnimating();

  void _syncAnimating() {
    final next = _computeAnimating();
    if (next == _animating || !mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_syncScheduled) return;
      _syncScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncScheduled = false;
        if (!mounted) return;
        final settled = _computeAnimating();
        if (settled != _animating) {
          setState(() => _animating = settled);
        }
      });
      return;
    }
    setState(() => _animating = next);
  }

  @override
  void dispose() {
    detachAnimations();
    super.dispose();
  }
}

/// Publishes [BackdropSuspensionScope] while [animation] is active without
/// rebuilding descendants on every animation tick.
class BackdropSuspensionAnimation extends StatefulWidget {
  const BackdropSuspensionAnimation({
    super.key,
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  State<BackdropSuspensionAnimation> createState() =>
      _BackdropSuspensionAnimationState();
}

class _BackdropSuspensionAnimationState
    extends State<BackdropSuspensionAnimation>
    with _AnimationSuspensionMixin {
  @override
  void initState() {
    super.initState();
    attachAnimations([widget.animation]);
  }

  @override
  void didUpdateWidget(BackdropSuspensionAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.animation, widget.animation)) {
      attachAnimations([widget.animation]);
    }
  }

  @override
  Widget build(BuildContext context) => BackdropSuspensionScope(
    suspended: isAnimating || BackdropSuspensionScope.maybeOf(context),
    child: widget.child,
  );
}

/// Supplies `suspended == true` while the enclosing route or an ancestor
/// [BackdropSuspensionScope] is actively transitioning, keeping per-frame
/// animation rebuilds out of blur surfaces.
class BackdropTransitionBuilder extends StatefulWidget {
  const BackdropTransitionBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, bool suspended) builder;

  @override
  State<BackdropTransitionBuilder> createState() =>
      _BackdropTransitionBuilderState();
}

class _BackdropTransitionBuilderState extends State<BackdropTransitionBuilder>
    with _AnimationSuspensionMixin {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    attachAnimations([route?.animation, route?.secondaryAnimation]);
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    isAnimating || BackdropSuspensionScope.maybeOf(context),
  );
}
