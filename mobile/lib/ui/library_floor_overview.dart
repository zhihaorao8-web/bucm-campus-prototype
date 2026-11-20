import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../domain/library_seats.dart';
import 'app_icons.dart';
import 'app_theme.dart';
import 'course_surface.dart';

/// Current depth inside the 3-level library seat selection flow.
enum LibrarySelectionLevel { floors, floorMap, areaSeats }

/// Architectural template classification for a floor schematic.
enum LibraryFloorKind { floor2, standard3to5, generic }

/// Named spatial wing slots on the 2F / 3F-5F architectural schematics.
enum LibraryZoneSlot { westA, westB, westC, north, south }

/// Groups areas sharing the same floor label while preserving server ordering.
@immutable
class LibraryFloorGroup {
  const LibraryFloorGroup({
    required this.floor,
    required this.areas,
    required this.kind,
  });

  final String floor;
  final List<LibraryArea> areas;
  final LibraryFloorKind kind;
}

const libraryCourtyardRect = Rect.fromLTRB(0.27, 0.185, 0.56, 0.815);
const libraryNorthNonSeatStrip = Rect.fromLTRB(0.27, 0.04, 0.56, 0.175);
const libraryCompassRect = Rect.fromLTRB(0.915, 0.04, 0.99, 0.21);
const libraryWestARect = Rect.fromLTRB(0.02, 0.185, 0.135, 0.865);
const libraryWestBRect = Rect.fromLTRB(0.145, 0.185, 0.26, 0.865);
const libraryNorthZoneRect = Rect.fromLTRB(0.69, 0.04, 0.905, 0.21);
const librarySouthZoneRect = Rect.fromLTRB(0.69, 0.785, 0.905, 0.955);
const libraryWestCEastArmRect = Rect.fromLTRB(0.57, 0.185, 0.675, 0.955);
const libraryWestCSouthArmRect = Rect.fromLTRB(0.27, 0.825, 0.57, 0.955);

const _floor2WestWingContour = Rect.fromLTRB(0.02, 0.185, 0.26, 0.865);

const List<Offset> _westCPolygonNormalized = <Offset>[
  Offset(0.57, 0.185),
  Offset(0.675, 0.185),
  Offset(0.675, 0.955),
  Offset(0.27, 0.955),
  Offset(0.27, 0.825),
  Offset(0.57, 0.825),
];

String _normalizeLabel(String raw) => raw
    .trim()
    .toUpperCase()
    .replaceAll('Ａ', 'A')
    .replaceAll('Ｂ', 'B')
    .replaceAll('Ｃ', 'C')
    .replaceAll(RegExp(r'\s+'), '');

/// Matches a server area name onto one of the 5 architectural schematic slots.
LibraryZoneSlot? matchLibraryZoneSlot(LibraryArea area) {
  final normalized = _normalizeLabel(area.name);
  if (normalized.isEmpty) return null;
  if (normalized.contains('西A')) return LibraryZoneSlot.westA;
  if (normalized.contains('西B')) return LibraryZoneSlot.westB;
  if (normalized.contains('西C')) return LibraryZoneSlot.westC;
  if (normalized.contains('北区') || normalized.endsWith('北')) {
    return LibraryZoneSlot.north;
  }
  if (normalized.contains('南区') || normalized.endsWith('南')) {
    return LibraryZoneSlot.south;
  }
  return null;
}

/// Classifies a floor group into dedicated 2F layout, 3F-5F layout, or generic.
LibraryFloorKind classifyLibraryFloor(String floor, List<LibraryArea> areas) {
  final f = _normalizeLabel(floor);
  final combined = '$f ${_normalizeLabel(areas.map((a) => a.name).join(' '))}';
  if (f.contains('二层') ||
      f.contains('2层') ||
      f.contains('2F') ||
      f.contains('二楼')) {
    return LibraryFloorKind.floor2;
  }
  if (f.contains('三层') ||
      f.contains('四层') ||
      f.contains('五层') ||
      f.contains('3层') ||
      f.contains('4层') ||
      f.contains('5层') ||
      f.contains('3F') ||
      f.contains('4F') ||
      f.contains('5F') ||
      f.contains('三楼') ||
      f.contains('四楼') ||
      f.contains('五楼')) {
    return LibraryFloorKind.standard3to5;
  }
  if (areas.any((area) {
    final slot = matchLibraryZoneSlot(area);
    return slot == LibraryZoneSlot.westA ||
        slot == LibraryZoneSlot.westB ||
        slot == LibraryZoneSlot.westC ||
        slot == LibraryZoneSlot.south;
  })) {
    return LibraryFloorKind.standard3to5;
  }
  if (areas.isNotEmpty &&
      areas.every(
        (area) =>
            _normalizeLabel(area.name).contains('二层') ||
            _normalizeLabel(area.name).contains('2层'),
      )) {
    return LibraryFloorKind.floor2;
  }
  if (combined.contains('二层') && !combined.contains('三层')) {
    return LibraryFloorKind.floor2;
  }
  return LibraryFloorKind.generic;
}

/// Groups server seat areas by floor while preserving original ordering.
List<LibraryFloorGroup> groupLibraryFloors(List<LibraryArea> areas) {
  if (areas.isEmpty) return const [];
  final buckets = <String, List<LibraryArea>>{};
  for (final area in areas) {
    final key = area.floor.trim().isEmpty ? '座位区域' : area.floor.trim();
    buckets.putIfAbsent(key, () => <LibraryArea>[]).add(area);
  }
  return [
    for (final entry in buckets.entries)
      LibraryFloorGroup(
        floor: entry.key,
        areas: List.unmodifiable(entry.value),
        kind: classifyLibraryFloor(entry.key, entry.value),
      ),
  ];
}

/// Maps areas in [group] onto architectural schematic slots for its [kind].
({Map<LibraryZoneSlot, LibraryArea> mapped, List<LibraryArea> unmapped})
resolveFloorZones(LibraryFloorGroup group) {
  final mapped = <LibraryZoneSlot, LibraryArea>{};
  final unmapped = <LibraryArea>[];
  if (group.kind == LibraryFloorKind.generic) {
    return (mapped: mapped, unmapped: List.unmodifiable(group.areas));
  }
  final allowedSlots = group.kind == LibraryFloorKind.floor2
      ? const <LibraryZoneSlot>{LibraryZoneSlot.north}
      : const <LibraryZoneSlot>{
          LibraryZoneSlot.westA,
          LibraryZoneSlot.westB,
          LibraryZoneSlot.westC,
          LibraryZoneSlot.north,
          LibraryZoneSlot.south,
        };
  for (final area in group.areas) {
    final slot = matchLibraryZoneSlot(area);
    if (slot != null &&
        allowedSlots.contains(slot) &&
        !mapped.containsKey(slot)) {
      mapped[slot] = area;
    } else {
      unmapped.add(area);
    }
  }
  return (mapped: mapped, unmapped: List.unmodifiable(unmapped));
}

/// Returns the bounding schematic rect for [slot] on a floor of [kind].
/// Note: 2F north wing intentionally shares [libraryNorthZoneRect] with 3F-5F.
Rect? libraryZoneRect(
  LibraryZoneSlot slot, {
  LibraryFloorKind kind = LibraryFloorKind.standard3to5,
}) {
  if (kind == LibraryFloorKind.generic) return null;
  if (kind == LibraryFloorKind.floor2) {
    return slot == LibraryZoneSlot.north ? libraryNorthZoneRect : null;
  }
  return switch (slot) {
    LibraryZoneSlot.westA => libraryWestARect,
    LibraryZoneSlot.westB => libraryWestBRect,
    LibraryZoneSlot.westC => const Rect.fromLTRB(0.27, 0.185, 0.675, 0.955),
    LibraryZoneSlot.north => libraryNorthZoneRect,
    LibraryZoneSlot.south => librarySouthZoneRect,
  };
}

/// Normalized alignment focal anchor used for camera zoom-in/pull-out across Level 2 <-> 3.
Alignment libraryZoneAnchor(
  LibraryZoneSlot? slot, {
  bool westCSouthArm = false,
}) => switch (slot) {
  LibraryZoneSlot.westA => const Alignment(-0.84, 0.04),
  LibraryZoneSlot.westB => const Alignment(-0.58, 0.04),
  LibraryZoneSlot.westC =>
    westCSouthArm ? const Alignment(-0.08, 0.77) : const Alignment(0.24, 0.08),
  LibraryZoneSlot.north => const Alignment(0.60, -0.75),
  LibraryZoneSlot.south => const Alignment(0.60, 0.73),
  null => Alignment.center,
};

String libraryZoneShortLabel(LibraryZoneSlot slot) => switch (slot) {
  LibraryZoneSlot.westA => '西A',
  LibraryZoneSlot.westB => '西B',
  LibraryZoneSlot.westC => '西C',
  LibraryZoneSlot.north => '北区',
  LibraryZoneSlot.south => '南区',
};

String libraryZoneDirectionLabel(LibraryZoneSlot? slot) => switch (slot) {
  LibraryZoneSlot.north => '东北翼',
  LibraryZoneSlot.south => '东南翼',
  LibraryZoneSlot.westA => '西外翼',
  LibraryZoneSlot.westB => '西内翼',
  LibraryZoneSlot.westC => '中庭东南翼',
  null => '本层区域',
};

Rect _scaleRect(Rect norm, Size size) => Rect.fromLTRB(
  norm.left * size.width,
  norm.top * size.height,
  norm.right * size.width,
  norm.bottom * size.height,
);

Path _roundedPolygonPath(List<Offset> points, double radius) {
  final path = Path();
  final count = points.length;
  for (var i = 0; i < count; i++) {
    final prev = points[(i - 1 + count) % count];
    final curr = points[i];
    final next = points[(i + 1) % count];
    final v1 = prev - curr;
    final v2 = next - curr;
    final d1 = v1.distance;
    final d2 = v2.distance;
    final r = math.min(radius, math.min(d1, d2) * 0.44);
    final start = d1 <= 0 ? curr : curr + v1 * (r / d1);
    final end = d2 <= 0 ? curr : curr + v2 * (r / d2);
    if (i == 0) {
      path.moveTo(start.dx, start.dy);
    } else {
      path.lineTo(start.dx, start.dy);
    }
    path.quadraticBezierTo(curr.dx, curr.dy, end.dx, end.dy);
  }
  path.close();
  return path;
}

Path _westCPath(Size size, double cornerRadius) => _roundedPolygonPath([
  for (final pt in _westCPolygonNormalized)
    Offset(pt.dx * size.width, pt.dy * size.height),
], cornerRadius);

void _drawDashedRRect(Canvas canvas, RRect rrect, Paint paint) {
  final metricPath = Path()..addRRect(rrect);
  const dash = 4.0;
  const gap = 3.5;
  for (final metric in metricPath.computeMetrics()) {
    var dist = 0.0;
    while (dist < metric.length) {
      final len = math.min(dash, metric.length - dist);
      canvas.drawPath(metric.extractPath(dist, dist + len), paint);
      dist += dash + gap;
    }
  }
}

enum _SpatialTransitionKind {
  floorEnter,
  floorExit,
  zoneDrillIn,
  zonePullOut,
  lateral,
}

/// GPU-composited spatial depth transition across Level 1 (floors), Level 2
/// (floor schematic), and Level 3 (zone seat map). Keeps active height unbound-safe
/// inside scrolling slivers and blocks all hit testing/focus/semantics on exit.
class LibrarySpatialLevelTransition extends StatefulWidget {
  const LibrarySpatialLevelTransition({
    super.key,
    required this.level,
    required this.contentKey,
    required this.focusAnchor,
    required this.child,
  });

  final int level;
  final Object contentKey;
  final Alignment focusAnchor;
  final Widget child;

  @override
  State<LibrarySpatialLevelTransition> createState() =>
      _LibrarySpatialLevelTransitionState();
}

class _LibrarySpatialLevelTransitionState
    extends State<LibrarySpatialLevelTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1.0,
  );
  Widget? _outgoing;
  late Object _currentKey = widget.contentKey;
  late int _currentLevel = widget.level;
  _SpatialTransitionKind _kind = _SpatialTransitionKind.lateral;
  Alignment _anchor = Alignment.center;
  int _outgoingToken = 0;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && _outgoing != null && mounted) {
        setState(() => _outgoing = null);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) &&
        (_outgoing != null || _controller.value < 1.0)) {
      _outgoing = null;
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant LibrarySpatialLevelTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.contentKey == _currentKey) {
      _currentLevel = widget.level;
      return;
    }

    final prevLevel = _currentLevel;
    final nextLevel = widget.level;
    _kind = switch ((prevLevel, nextLevel)) {
      (0, 1) => _SpatialTransitionKind.floorEnter,
      (1, 0) || (2, 0) => _SpatialTransitionKind.floorExit,
      (1, 2) || (0, 2) => _SpatialTransitionKind.zoneDrillIn,
      (2, 1) => _SpatialTransitionKind.zonePullOut,
      _ => _SpatialTransitionKind.lateral,
    };
    _anchor = widget.focusAnchor;
    _currentKey = widget.contentKey;
    _currentLevel = nextLevel;

    if (MediaQuery.disableAnimationsOf(context)) {
      _outgoing = null;
      _controller.value = 1.0;
      return;
    }

    _outgoingToken++;
    _outgoing = KeyedSubtree(
      key: ValueKey('library-spatial-outgoing-$_outgoingToken'),
      child: oldWidget.child,
    );
    final duration = switch (_kind) {
      _SpatialTransitionKind.floorEnter ||
      _SpatialTransitionKind.zoneDrillIn => AppMotion.routeEnter,
      _SpatialTransitionKind.floorExit ||
      _SpatialTransitionKind.zonePullOut => AppMotion.routeExit,
      _SpatialTransitionKind.lateral => AppMotion.segment,
    };
    _controller.duration = duration;
    _controller.forward(from: 0.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final activeChild = KeyedSubtree(
      key: ValueKey('library-spatial-child-$_currentKey'),
      child: widget.child,
    );

    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        child: activeChild,
        builder: (context, incomingChild) {
          final raw = _controller.value;
          final animating = !reduced && _outgoing != null && raw < 1.0;
          final t = animating ? AppMotion.navigationCurve.transform(raw) : 1.0;

          final (
            double inScale,
            Offset inOffset,
            double inOpacity,
            Alignment inAlign,
            double outScale,
            Offset outOffset,
            double outOpacity,
            Alignment outAlign,
            bool outgoingOnTop,
          ) = switch (_kind) {
            _SpatialTransitionKind.floorEnter => (
              0.93 + 0.07 * t,
              Offset(0, 20.0 * (1 - t)),
              t.clamp(0.0, 1.0),
              Alignment.topCenter,
              1.0 - 0.06 * t,
              Offset(0, 12.0 * t),
              (1.0 - t * 1.18).clamp(0.0, 1.0),
              Alignment.topCenter,
              false,
            ),
            _SpatialTransitionKind.floorExit => (
              0.94 + 0.06 * t,
              Offset(0, -10.0 * (1 - t)),
              t.clamp(0.0, 1.0),
              Alignment.topCenter,
              1.0 - 0.06 * t,
              Offset(0, 16.0 * t),
              (1.0 - t * 1.22).clamp(0.0, 1.0),
              Alignment.topCenter,
              true,
            ),
            _SpatialTransitionKind.zoneDrillIn => (
              0.90 + 0.10 * t,
              Offset(_anchor.x * 16.0 * (1 - t), _anchor.y * 12.0 * (1 - t)),
              t.clamp(0.0, 1.0),
              _anchor,
              1.0 + 0.18 * t,
              Offset.zero,
              (1.0 - t * 1.25).clamp(0.0, 1.0),
              _anchor,
              false,
            ),
            _SpatialTransitionKind.zonePullOut => (
              1.14 - 0.14 * t,
              Offset.zero,
              t.clamp(0.0, 1.0),
              _anchor,
              1.0 - 0.09 * t,
              Offset(_anchor.x * 14.0 * t, _anchor.y * 10.0 * t),
              (1.0 - t * 1.25).clamp(0.0, 1.0),
              _anchor,
              true,
            ),
            _SpatialTransitionKind.lateral => (
              0.96 + 0.04 * t,
              Offset.zero,
              t.clamp(0.0, 1.0),
              Alignment.center,
              1.0 - 0.04 * t,
              Offset.zero,
              (1.0 - t * 1.15).clamp(0.0, 1.0),
              Alignment.center,
              false,
            ),
          };

          final incomingLayer = Opacity(
            key: ValueKey('library-spatial-active-$_currentKey'),
            opacity: animating ? inOpacity : 1.0,
            child: Transform.translate(
              offset: animating ? inOffset : Offset.zero,
              child: Transform.scale(
                scale: animating ? inScale : 1.0,
                alignment: animating ? inAlign : Alignment.center,
                child: incomingChild,
              ),
            ),
          );

          if (!animating) {
            return Stack(
              alignment: Alignment.topCenter,
              clipBehavior: Clip.none,
              children: [incomingLayer],
            );
          }

          final outgoingLayer = Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: TickerMode(
              enabled: false,
              child: ExcludeSemantics(
                child: ExcludeFocus(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: outOpacity,
                      child: Transform.translate(
                        offset: outOffset,
                        child: Transform.scale(
                          scale: outScale,
                          alignment: outAlign,
                          child: _outgoing,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          return Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: outgoingOnTop
                ? [incomingLayer, outgoingLayer]
                : [outgoingLayer, incomingLayer],
          );
        },
      ),
    );
  }
}

/// Shared-axis planar-to-list depth transition for Level 3 (`平面选座图 <-> 紧凑网格`).
class LibrarySeatViewModeTransition extends StatefulWidget {
  const LibrarySeatViewModeTransition({
    super.key,
    required this.usingMap,
    required this.mapChild,
    required this.gridChild,
  });

  final bool usingMap;
  final Widget mapChild;
  final Widget gridChild;

  @override
  State<LibrarySeatViewModeTransition> createState() =>
      _LibrarySeatViewModeTransitionState();
}

class _LibrarySeatViewModeTransitionState
    extends State<LibrarySeatViewModeTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1.0,
    duration: AppMotion.segment,
  );
  Widget? _outgoing;
  late bool _toGrid = !widget.usingMap;
  int _outgoingToken = 0;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && _outgoing != null && mounted) {
        setState(() => _outgoing = null);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) &&
        (_outgoing != null || _controller.value < 1.0)) {
      _outgoing = null;
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant LibrarySeatViewModeTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.usingMap == oldWidget.usingMap) return;
    _toGrid = !widget.usingMap;
    if (MediaQuery.disableAnimationsOf(context)) {
      _outgoing = null;
      _controller.value = 1.0;
      return;
    }
    _outgoingToken++;
    _outgoing = KeyedSubtree(
      key: ValueKey('library-mode-outgoing-$_outgoingToken'),
      child: oldWidget.usingMap ? oldWidget.mapChild : oldWidget.gridChild,
    );
    _controller.forward(from: 0.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final activeMode = KeyedSubtree(
      key: ValueKey('library-mode-${widget.usingMap ? 'map' : 'grid'}'),
      child: widget.usingMap ? widget.mapChild : widget.gridChild,
    );

    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        child: activeMode,
        builder: (context, incomingChild) {
          final raw = _controller.value;
          final animating = !reduced && _outgoing != null && raw < 1.0;
          final t = animating ? AppMotion.segmentCurve.transform(raw) : 1.0;
          final dir = _toGrid ? 1.0 : -1.0;

          final incomingLayer = Opacity(
            key: ValueKey(
              'library-mode-active-${widget.usingMap ? 'map' : 'grid'}',
            ),
            opacity: animating ? t.clamp(0.0, 1.0) : 1.0,
            child: Transform.translate(
              offset: animating ? Offset(dir * 14.0 * (1 - t), 0) : Offset.zero,
              child: Transform.scale(
                scale: animating ? (0.97 + 0.03 * t) : 1.0,
                alignment: Alignment.center,
                child: incomingChild,
              ),
            ),
          );

          if (!animating) {
            return Stack(
              alignment: Alignment.topCenter,
              clipBehavior: Clip.none,
              children: [incomingLayer],
            );
          }

          final outgoingLayer = Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: TickerMode(
              enabled: false,
              child: ExcludeSemantics(
                child: ExcludeFocus(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (1.0 - t * 1.2).clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(-dir * 14.0 * t, 0),
                        child: Transform.scale(
                          scale: 1.0 - 0.04 * t,
                          alignment: Alignment.center,
                          child: _outgoing,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          return Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [outgoingLayer, incomingLayer],
          );
        },
      ),
    );
  }
}

/// Compact architectural footprint thumbnail used on Level 1 floor cards and
/// inside Level 3 directional locator pill.
class LibraryFloorMiniPreview extends StatelessWidget {
  const LibraryFloorMiniPreview({
    super.key,
    required this.kind,
    this.activeSlots = const {},
    this.highlightedSlot,
    this.size = const Size(54, 38),
  });

  final LibraryFloorKind kind;
  final Set<LibraryZoneSlot> activeSlots;
  final LibraryZoneSlot? highlightedSlot;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    return ExcludeSemantics(
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: CustomPaint(
          painter: _MiniFloorPainter(
            kind: kind,
            activeSlots: activeSlots,
            highlightedSlot: highlightedSlot,
            colors: colors,
            dark: dark,
            highContrast: highContrast,
          ),
        ),
      ),
    );
  }
}

class _MiniFloorPainter extends CustomPainter {
  const _MiniFloorPainter({
    required this.kind,
    required this.activeSlots,
    required this.highlightedSlot,
    required this.colors,
    required this.dark,
    required this.highContrast,
  });

  final LibraryFloorKind kind;
  final Set<LibraryZoneSlot> activeSlots;
  final LibraryZoneSlot? highlightedSlot;
  final ColorScheme colors;
  final bool dark, highContrast;

  Paint _fillFor(LibraryZoneSlot slot) {
    final isFocused = highlightedSlot == slot;
    final hasFocusMode = highlightedSlot != null;
    final active = activeSlots.contains(slot);
    if (isFocused) {
      return Paint()..color = colors.primary;
    }
    if (!active || hasFocusMode) {
      return Paint()
        ..color = colors.outlineVariant.withValues(
          alpha: highContrast ? 0.55 : (dark ? 0.35 : 0.45),
        );
    }
    return Paint()
      ..color = colors.primary.withValues(alpha: highContrast ? 0.85 : 0.62);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final mutePaint = Paint()
      ..color = colors.outlineVariant.withValues(
        alpha: highContrast ? 0.48 : (dark ? 0.28 : 0.38),
      );
    final courtyardPaint = Paint()
      ..color = colors.surfaceContainerHighest.withValues(
        alpha: dark ? 0.48 : 0.55,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    void rect(Rect norm, Paint paint, [double radius = 1.6]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(_scaleRect(norm, size), Radius.circular(radius)),
        paint,
      );
    }

    rect(libraryCourtyardRect, courtyardPaint, 1.5);
    rect(libraryNorthNonSeatStrip, mutePaint, 1.4);

    if (kind == LibraryFloorKind.generic) {
      rect(_floor2WestWingContour, mutePaint, 2.0);
      rect(libraryNorthZoneRect, mutePaint, 1.6);
      rect(librarySouthZoneRect, mutePaint, 1.6);
      return;
    }

    if (kind == LibraryFloorKind.floor2) {
      rect(_floor2WestWingContour, mutePaint, 2.0);
      canvas.drawPath(_westCPath(size, 2.0), mutePaint);
      rect(librarySouthZoneRect, mutePaint, 1.6);
      rect(libraryNorthZoneRect, _fillFor(LibraryZoneSlot.north), 1.8);
      return;
    }

    rect(libraryWestARect, _fillFor(LibraryZoneSlot.westA), 1.4);
    rect(libraryWestBRect, _fillFor(LibraryZoneSlot.westB), 1.4);
    canvas.drawPath(_westCPath(size, 2.0), _fillFor(LibraryZoneSlot.westC));
    rect(libraryNorthZoneRect, _fillFor(LibraryZoneSlot.north), 1.6);
    rect(librarySouthZoneRect, _fillFor(LibraryZoneSlot.south), 1.6);
  }

  @override
  bool shouldRepaint(covariant _MiniFloorPainter old) =>
      old.kind != kind ||
      old.highlightedSlot != highlightedSlot ||
      old.dark != dark ||
      old.highContrast != highContrast ||
      old.colors != colors ||
      old.activeSlots.length != activeSlots.length ||
      !old.activeSlots.containsAll(activeSlots);
}

/// Top path breadcrumb showing `全部楼层 › 图书馆三层 › 三层南区`.
class LibrarySpatialBreadcrumbBar extends StatelessWidget {
  const LibrarySpatialBreadcrumbBar({
    super.key,
    required this.level,
    required this.floorName,
    required this.areaName,
    required this.busy,
    required this.onSelectFloors,
    required this.onSelectFloorMap,
  });

  final LibrarySelectionLevel level;
  final String? floorName;
  final String? areaName;
  final bool busy;
  final VoidCallback onSelectFloors;
  final VoidCallback onSelectFloorMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final canStepFloors = level != LibrarySelectionLevel.floors && !busy;
    final canStepFloorMap = level == LibrarySelectionLevel.areaSeats && !busy;

    Widget crumb({
      required Key key,
      required String label,
      required bool active,
      VoidCallback? onTap,
    }) {
      return Semantics(
        button: onTap != null,
        selected: active,
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(AppRadius.small),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 38),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.sm,
                vertical: AppSpace.compact,
              ),
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: active
                      ? colors.onSurface
                      : (onTap != null
                            ? colors.primary
                            : colors.onSurfaceVariant),
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return CourseSurface(
      dense: true,
      radius: AppRadius.input,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: AppSpace.xs,
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2,
          runSpacing: 2,
          children: [
            crumb(
              key: const ValueKey('library-breadcrumb-floors'),
              label: '全部楼层',
              active: level == LibrarySelectionLevel.floors,
              onTap: canStepFloors ? onSelectFloors : null,
            ),
            if (level != LibrarySelectionLevel.floors && floorName != null) ...[
              AppIcon(
                AppIcons.chevronRight,
                size: 14,
                color: colors.onSurfaceVariant,
              ),
              crumb(
                key: const ValueKey('library-breadcrumb-floor'),
                label: floorName!,
                active: level == LibrarySelectionLevel.floorMap,
                onTap: canStepFloorMap ? onSelectFloorMap : null,
              ),
            ],
            if (level == LibrarySelectionLevel.areaSeats && areaName != null) ...[
              AppIcon(
                AppIcons.chevronRight,
                size: 14,
                color: colors.onSurfaceVariant,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.sm,
                  vertical: AppSpace.compact,
                ),
                child: Text(
                  areaName!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Level 3 directional pill showing which architectural wing of the floor is open.
class LibrarySpatialLocatorPill extends StatelessWidget {
  const LibrarySpatialLocatorPill({
    super.key,
    required this.floorKind,
    required this.activeSlots,
    required this.activeSlot,
    required this.busy,
    required this.onBackToFloorMap,
  });

  final LibraryFloorKind floorKind;
  final Set<LibraryZoneSlot> activeSlots;
  final LibraryZoneSlot? activeSlot;
  final bool busy;
  final VoidCallback onBackToFloorMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    return Semantics(
      button: true,
      label: '返回楼层平面图，当前方位 ${libraryZoneDirectionLabel(activeSlot)}',
      child: Material(
        color: colors.primaryContainer.withValues(
          alpha: highContrast ? 0.95 : 0.65,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
          side: BorderSide(
            width: highContrast ? 1.1 : 0.7,
            color: colors.primary.withValues(alpha: highContrast ? 0.9 : 0.35),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('library-level3-locator'),
          onTap: busy ? null : onBackToFloorMap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.sm,
                vertical: AppSpace.compact,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    AppIcons.chevronLeft,
                    size: 16,
                    color: colors.primary,
                  ),
                  const SizedBox(width: AppSpace.xs),
                  LibraryFloorMiniPreview(
                    size: const Size(26, 18),
                    kind: floorKind,
                    activeSlots: activeSlots,
                    highlightedSlot: activeSlot,
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Flexible(
                    child: Text(
                      '${libraryZoneDirectionLabel(activeSlot)} · ↑ 北',
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Level 1 skeleton shown while initial `/ic-web/seatMenu` floors load.
class LibraryFloorListSkeleton extends StatelessWidget {
  const LibraryFloorListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tint = colors.surfaceContainerHighest.withValues(alpha: .42);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(height: AppSpace.sm),
          QuietCard(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 38,
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 16,
                          width: 110,
                          decoration: BoxDecoration(
                            color: tint,
                            borderRadius: BorderRadius.circular(AppSpace.sm),
                          ),
                        ),
                        const SizedBox(height: AppSpace.xs),
                        Container(
                          height: 12,
                          width: 170,
                          decoration: BoxDecoration(
                            color: tint,
                            borderRadius: BorderRadius.circular(AppSpace.sm),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Level 1 view: displays only floors with architectural mini previews.
class LibraryFloorListView extends StatelessWidget {
  const LibraryFloorListView({
    super.key,
    required this.floors,
    required this.recentFloor,
    required this.busy,
    required this.onSelectFloor,
  });

  final List<LibraryFloorGroup> floors;
  final String? recentFloor;
  final bool busy;
  final ValueChanged<LibraryFloorGroup> onSelectFloor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final totalAreas = floors.fold<int>(
      0,
      (sum, floor) => sum + floor.areas.length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.xs,
            vertical: AppSpace.xs,
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            children: [
              Text('选择楼层', style: theme.textTheme.titleMedium),
              Text(
                '共 ${floors.length} 层 · $totalAreas 个区域',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontFeatures: tabularTime,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        for (var i = 0; i < floors.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpace.sm),
          _LibraryFloorCard(
            group: floors[i],
            recent: recentFloor == floors[i].floor,
            busy: busy,
            onTap: () => onSelectFloor(floors[i]),
          ),
        ],
      ],
    );
  }
}

class _LibraryFloorCard extends StatefulWidget {
  const _LibraryFloorCard({
    required this.group,
    required this.recent,
    required this.busy,
    required this.onTap,
  });

  final LibraryFloorGroup group;
  final bool recent;
  final bool busy;
  final VoidCallback onTap;

  @override
  State<_LibraryFloorCard> createState() => _LibraryFloorCardState();
}

class _LibraryFloorCardState extends State<_LibraryFloorCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final resolved = resolveFloorZones(widget.group);
    final activeSlots = resolved.mapped.keys.toSet();
    final areaSummary = widget.group.areas.map((a) => a.name).join(' · ');

    return AnimatedScale(
      scale: _pressed && !reduced ? 0.98 : 1.0,
      duration: reduced ? Duration.zero : const Duration(milliseconds: 110),
      curve: AppMotion.navigationCurve,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: widget.recent
              ? Border.all(
                  width: highContrast ? 1.5 : 1.1,
                  color: colors.primary.withValues(
                    alpha: highContrast ? 1.0 : 0.48,
                  ),
                )
              : null,
        ),
        child: QuietCard(
          child: Semantics(
            button: true,
            label: '${widget.group.floor}，${widget.group.areas.length} 个选座区域',
            child: InkWell(
              key: ValueKey('library-floor-card-${widget.group.floor}'),
              borderRadius: BorderRadius.circular(AppRadius.card),
              onTap: widget.busy ? null : widget.onTap,
              onHighlightChanged: (active) {
                if (_pressed != active) setState(() => _pressed = active);
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 72),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.lg,
                    vertical: AppSpace.md,
                  ),
                  child: Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLow.withValues(
                            alpha: highContrast ? 1.0 : 0.72,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.small),
                          border: Border.all(
                            width: highContrast ? 1.0 : 0.7,
                            color: highContrast
                                ? colors.outline
                                : colors.outlineVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpace.sm),
                          child: LibraryFloorMiniPreview(
                            kind: widget.group.kind,
                            activeSlots: activeSlots,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Wrap(
                              spacing: AppSpace.sm,
                              runSpacing: 2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  widget.group.floor,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (widget.recent)
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: colors.primaryContainer
                                          .withValues(alpha: 0.78),
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.small,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpace.sm,
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        '刚才查看',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              fontSize: AppType.caption,
                                              color: colors.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              areaSummary.isEmpty
                                  ? '${widget.group.areas.length} 个区域'
                                  : '${widget.group.areas.length} 个区域 · $areaSummary',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontFeatures: tabularTime,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      AppIcon(
                        AppIcons.chevronRight,
                        size: AppControl.icon,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
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

/// Level 2 architectural zone schematic for the chosen floor (`2F` dedicated or
/// `3F-5F` hand-drawn wing map including unified L-shaped `西C`).
class LibraryFloorSchematicView extends StatefulWidget {
  const LibraryFloorSchematicView({
    super.key,
    required this.group,
    required this.recentZoneSlot,
    required this.busy,
    required this.onSelectZone,
    required this.onBackToFloors,
  });

  final LibraryFloorGroup group;
  final LibraryZoneSlot? recentZoneSlot;
  final bool busy;
  final void Function(LibraryArea area, LibraryZoneSlot? slot, Alignment anchor)
  onSelectZone;
  final VoidCallback onBackToFloors;

  @override
  State<LibraryFloorSchematicView> createState() =>
      _LibraryFloorSchematicViewState();
}

class _LibraryFloorSchematicViewState extends State<LibraryFloorSchematicView>
    with SingleTickerProviderStateMixin {
  LibraryZoneSlot? _pressedSlot;
  late final AnimationController _highlightController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
    value: 0.0,
  );
  bool _didInit = false;

  void _triggerRecentHighlight() {
    if (widget.recentZoneSlot == null) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _highlightController.value = 0.0;
    } else {
      _highlightController.reverse(from: 1.0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      _triggerRecentHighlight();
    } else if (MediaQuery.disableAnimationsOf(context)) {
      _highlightController.value = 0.0;
    }
  }

  @override
  void didUpdateWidget(covariant LibraryFloorSchematicView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.recentZoneSlot != oldWidget.recentZoneSlot ||
        widget.group.floor != oldWidget.group.floor) {
      _pressedSlot = null;
      _triggerRecentHighlight();
    }
  }

  @override
  void dispose() {
    _highlightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final resolved = resolveFloorZones(widget.group);
    final mapped = resolved.mapped;
    final unmapped = resolved.unmapped;
    final kind = widget.group.kind;

    return QuietCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.group.floor,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      kind == LibraryFloorKind.generic
                          ? '选择下方分区查看具体座位分布'
                          : '点击楼层平面分区查看具体座位分布',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  key: const ValueKey('library-back-to-floors'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(AppLayout.minTap, AppLayout.minTap),
                  ),
                  onPressed: widget.busy ? null : widget.onBackToFloors,
                  icon: const AppIcon(AppIcons.chevronLeft, size: 16),
                  label: const Text('返回楼层'),
                ),
              ],
            ),
            if (kind != LibraryFloorKind.generic) ...[
              const SizedBox(height: AppSpace.sm),
              LayoutBuilder(
                builder: (context, constraints) {
                  final canvasWidth = constraints.maxWidth;
                  final canvasHeight = (canvasWidth / 1.44).clamp(236.0, 310.0);
                  final canvasSize = Size(canvasWidth, canvasHeight);
                  final courtyardPx = _scaleRect(
                    libraryCourtyardRect,
                    canvasSize,
                  );
                  final compassPx = _scaleRect(libraryCompassRect, canvasSize);
                  final westCEastPx = _scaleRect(
                    libraryWestCEastArmRect,
                    canvasSize,
                  );
                  final westCSouthPx = _scaleRect(
                    libraryWestCSouthArmRect,
                    canvasSize,
                  );

                  final westCArea = mapped[LibraryZoneSlot.westC];

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.inset),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow.withValues(
                          alpha: highContrast ? 1.0 : 0.72,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.inset),
                        border: Border.all(
                          width: highContrast ? 1.2 : 0.7,
                          color: highContrast
                              ? colors.outline
                              : colors.outlineVariant.withValues(alpha: .75),
                        ),
                      ),
                      child: SizedBox(
                        key: const ValueKey('library-floor-schematic-canvas'),
                        width: canvasWidth,
                        height: canvasHeight,
                        child: AnimatedBuilder(
                          animation: _highlightController,
                          builder: (context, _) {
                            final highlightStrength =
                                _highlightController.value;
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _SchematicBackgroundPainter(
                                      kind: kind,
                                      colors: colors,
                                      dark: dark,
                                      highContrast: highContrast,
                                    ),
                                  ),
                                ),
                                // Central architectural atrium landmark (non-clickable).
                                Positioned.fromRect(
                                  rect: courtyardPx,
                                  child: ExcludeSemantics(
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            '中庭',
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                                  color: colors.onSurfaceVariant
                                                      .withValues(alpha: .72),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Top-right ↑ 北 compass indicator.
                                Positioned.fromRect(
                                  rect: compassPx,
                                  child: Semantics(
                                    label: '方向 上北下南',
                                    child: Center(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          '↑ 北',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: colors.onSurfaceVariant,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Northeast wing `北区` (shared coordinates on 2F & 3F-5F).
                                _buildRectZone(
                                  context,
                                  slot: LibraryZoneSlot.north,
                                  area: mapped[LibraryZoneSlot.north],
                                  rect: _scaleRect(
                                    libraryNorthZoneRect,
                                    canvasSize,
                                  ),
                                  label: '北区',
                                  highlightStrength:
                                      widget.recentZoneSlot ==
                                              LibraryZoneSlot.north
                                          ? highlightStrength
                                          : 0.0,
                                  reduced: reduced,
                                ),
                                if (kind == LibraryFloorKind.standard3to5) ...[
                                  _buildRectZone(
                                    context,
                                    slot: LibraryZoneSlot.westA,
                                    area: mapped[LibraryZoneSlot.westA],
                                    rect: _scaleRect(
                                      libraryWestARect,
                                      canvasSize,
                                    ),
                                    label: '西\nA',
                                    highlightStrength:
                                        widget.recentZoneSlot ==
                                                LibraryZoneSlot.westA
                                            ? highlightStrength
                                            : 0.0,
                                    reduced: reduced,
                                  ),
                                  _buildRectZone(
                                    context,
                                    slot: LibraryZoneSlot.westB,
                                    area: mapped[LibraryZoneSlot.westB],
                                    rect: _scaleRect(
                                      libraryWestBRect,
                                      canvasSize,
                                    ),
                                    label: '西\nB',
                                    highlightStrength:
                                        widget.recentZoneSlot ==
                                                LibraryZoneSlot.westB
                                            ? highlightStrength
                                            : 0.0,
                                    reduced: reduced,
                                  ),
                                  _buildRectZone(
                                    context,
                                    slot: LibraryZoneSlot.south,
                                    area: mapped[LibraryZoneSlot.south],
                                    rect: _scaleRect(
                                      librarySouthZoneRect,
                                      canvasSize,
                                    ),
                                    label: '南区',
                                    highlightStrength:
                                        widget.recentZoneSlot ==
                                                LibraryZoneSlot.south
                                            ? highlightStrength
                                            : 0.0,
                                    reduced: reduced,
                                  ),
                                  // Continuous L-shaped 西C rendered & scaled as one wing.
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: AnimatedScale(
                                        scale:
                                            _pressedSlot ==
                                                        LibraryZoneSlot.westC &&
                                                    !reduced
                                                ? 0.985
                                                : 1.0,
                                        alignment: const Alignment(0.05, 0.25),
                                        duration: reduced
                                            ? Duration.zero
                                            : const Duration(milliseconds: 110),
                                        curve: AppMotion.navigationCurve,
                                        child: CustomPaint(
                                          painter: _WestCZonePainter(
                                            active: westCArea != null,
                                            pressed:
                                                _pressedSlot ==
                                                LibraryZoneSlot.westC,
                                            recent:
                                                widget.recentZoneSlot ==
                                                LibraryZoneSlot.westC,
                                            highlightStrength:
                                                widget.recentZoneSlot ==
                                                        LibraryZoneSlot.westC
                                                    ? highlightStrength
                                                    : 0.0,
                                            colors: colors,
                                            dark: dark,
                                            highContrast: highContrast,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  _buildWestCHitArm(
                                    context,
                                    key: const ValueKey(
                                      'library-zone-westC-east',
                                    ),
                                    rect: westCEastPx,
                                    label: '西\nC',
                                    area: westCArea,
                                    southArm: false,
                                    labelRectBottomInset:
                                        westCSouthPx.height * 0.65,
                                    reduced: reduced,
                                  ),
                                  _buildWestCHitArm(
                                    context,
                                    key: const ValueKey(
                                      'library-zone-westC-south',
                                    ),
                                    rect: westCSouthPx,
                                    label: '西C',
                                    area: westCArea,
                                    southArm: true,
                                    labelRectBottomInset: 0,
                                    reduced: reduced,
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpace.sm),
              _schematicLegend(context),
            ],
            if (unmapped.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Text(
                kind == LibraryFloorKind.generic ? '开放区域' : '本层其他选座区域',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final area in unmapped)
                    OutlinedButton.icon(
                      key: ValueKey('library-zone-extra-${area.id}'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, AppLayout.minTap),
                      ),
                      onPressed: widget.busy
                          ? null
                          : () => widget.onSelectZone(
                              area,
                              matchLibraryZoneSlot(area),
                              Alignment.center,
                            ),
                      icon: const AppIcon(AppIcons.map, size: 16),
                      label: Text(area.name),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRectZone(
    BuildContext context, {
    required LibraryZoneSlot slot,
    required LibraryArea? area,
    required Rect rect,
    required String label,
    required double highlightStrength,
    required bool reduced,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final active = area != null;
    final pressed = _pressedSlot == slot;
    final recent = widget.recentZoneSlot == slot;

    final fill = !active
        ? colors.surfaceContainerHighest.withValues(alpha: dark ? 0.25 : 0.38)
        : (pressed
              ? colors.primaryContainer.withValues(
                  alpha: highContrast ? 0.96 : 0.92,
                )
              : colors.primaryContainer.withValues(
                  alpha:
                      (dark ? 0.56 : 0.68) +
                      (recent ? 0.22 * highlightStrength : 0.0),
                ));
    final borderColor = !active
        ? colors.outlineVariant.withValues(alpha: 0.45)
        : (pressed || recent
              ? colors.primary
              : colors.primary.withValues(alpha: highContrast ? 0.95 : 0.48));
    final borderWidth = pressed
        ? 1.8
        : (recent
              ? 1.5 + 0.5 * highlightStrength
              : (highContrast ? 1.2 : 0.95));

    return Positioned.fromRect(
      rect: rect,
      child: AnimatedScale(
        scale: pressed && active && !reduced ? 0.985 : 1.0,
        duration: reduced ? Duration.zero : const Duration(milliseconds: 110),
        curve: AppMotion.navigationCurve,
        child: Semantics(
          button: active,
          enabled: active && !widget.busy,
          label: active
              ? '${area.name}，${libraryZoneDirectionLabel(slot)}'
              : '$label 暂未开放',
          child: Material(
            color: fill,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(width: borderWidth, color: borderColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('library-zone-${slot.name}'),
              onTap: !active || widget.busy
                  ? null
                  : () => widget.onSelectZone(
                      area,
                      slot,
                      libraryZoneAnchor(slot),
                    ),
              onHighlightChanged: active
                  ? (down) => setState(() {
                      if (down) {
                        _pressedSlot = slot;
                      } else if (_pressedSlot == slot) {
                        _pressedSlot = null;
                      }
                    })
                  : null,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 3,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: active
                            ? (highContrast
                                  ? colors.onSurface
                                  : colors.onPrimaryContainer)
                            : colors.onSurfaceVariant.withValues(alpha: 0.6),
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

  Widget _buildWestCHitArm(
    BuildContext context, {
    required Key key,
    required Rect rect,
    required String label,
    required LibraryArea? area,
    required bool southArm,
    required double labelRectBottomInset,
    required bool reduced,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final active = area != null;
    final pressed = _pressedSlot == LibraryZoneSlot.westC;

    return Positioned.fromRect(
      rect: rect,
      child: AnimatedScale(
        scale: pressed && active && !reduced ? 0.985 : 1.0,
        duration: reduced ? Duration.zero : const Duration(milliseconds: 110),
        curve: AppMotion.navigationCurve,
        child: Semantics(
          button: active,
          enabled: active && !widget.busy,
          label: active
              ? '${area.name}，中庭${southArm ? '南翼' : '东翼'}'
              : '西C 暂未开放',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(10),
              onTap: !active || widget.busy
                  ? null
                  : () => widget.onSelectZone(
                      area,
                      LibraryZoneSlot.westC,
                      libraryZoneAnchor(
                        LibraryZoneSlot.westC,
                        westCSouthArm: southArm,
                      ),
                    ),
              onHighlightChanged: active
                  ? (down) => setState(() {
                      if (down) {
                        _pressedSlot = LibraryZoneSlot.westC;
                      } else if (_pressedSlot == LibraryZoneSlot.westC) {
                        _pressedSlot = null;
                      }
                    })
                  : null,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  3,
                  3,
                  3,
                  3 + labelRectBottomInset,
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: active
                            ? (highContrast
                                  ? colors.onSurface
                                  : colors.onPrimaryContainer)
                            : colors.onSurfaceVariant.withValues(alpha: 0.6),
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

  Widget _schematicLegend(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);

    Widget swatch({
      required Color fill,
      required Color border,
      required String text,
    }) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(width: 0.9, color: border),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );

    return Wrap(
      spacing: AppSpace.md,
      runSpacing: AppSpace.xs,
      children: [
        swatch(
          fill: colors.primaryContainer.withValues(alpha: dark ? 0.6 : 0.72),
          border: colors.primary.withValues(alpha: highContrast ? 0.95 : 0.55),
          text: '可选座位区',
        ),
        swatch(
          fill: colors.surfaceContainerHighest.withValues(alpha: 0.28),
          border: colors.outlineVariant,
          text: '非选座区域',
        ),
        swatch(
          fill: colors.surfaceContainerHighest.withValues(alpha: 0.5),
          border: colors.outlineVariant.withValues(alpha: 0.75),
          text: '中庭',
        ),
      ],
    );
  }
}

class _SchematicBackgroundPainter extends CustomPainter {
  const _SchematicBackgroundPainter({
    required this.kind,
    required this.colors,
    required this.dark,
    required this.highContrast,
  });

  final LibraryFloorKind kind;
  final ColorScheme colors;
  final bool dark, highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Subtle architectural blueprint grid (disabled in high-contrast mode).
    if (!highContrast) {
      final dotPaint = Paint()
        ..color = colors.outlineVariant.withValues(alpha: dark ? 0.22 : 0.35);
      const step = 16.0;
      for (var y = 10.0; y < size.height; y += step) {
        for (var x = 10.0; x < size.width; x += step) {
          canvas.drawCircle(Offset(x, y), 0.75, dotPaint);
        }
      }
    }

    // 2. Central courtyard (中庭) recessed landmark.
    final courtyard = RRect.fromRectAndRadius(
      _scaleRect(libraryCourtyardRect, size),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      courtyard,
      Paint()
        ..color = colors.surfaceContainerHighest.withValues(
          alpha: dark ? 0.32 : 0.45,
        ),
    );
    canvas.drawRRect(
      courtyard,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = highContrast ? 1.1 : 0.85
        ..color = colors.outlineVariant.withValues(
          alpha: highContrast ? 0.9 : 0.7,
        ),
    );

    final nonSeatFill = Paint()
      ..color = colors.surfaceContainerHighest.withValues(
        alpha: dark ? 0.16 : 0.25,
      );
    final nonSeatStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.85
      ..color = colors.outlineVariant.withValues(
        alpha: highContrast ? 0.72 : 0.48,
      );

    void drawNonSeatRect(Rect norm, [double radius = 9.0]) {
      final rrect = RRect.fromRectAndRadius(
        _scaleRect(norm, size),
        Radius.circular(radius),
      );
      canvas.drawRRect(rrect, nonSeatFill);
      _drawDashedRRect(canvas, rrect, nonSeatStroke);
    }

    // Unlabeled non-seat strip directly north of 中庭 (all schematic floors).
    drawNonSeatRect(libraryNorthNonSeatStrip);

    // 3. Dedicated 2F architectural non-seat wing contours (no fake 3F-5F labels).
    if (kind == LibraryFloorKind.floor2) {
      drawNonSeatRect(_floor2WestWingContour, 10.0);
      drawNonSeatRect(librarySouthZoneRect, 10.0);
      final westCPath = _westCPath(size, 10.0);
      canvas.drawPath(westCPath, nonSeatFill);
      for (final metric in westCPath.computeMetrics()) {
        var d = 0.0;
        while (d < metric.length) {
          final len = math.min(4.0, metric.length - d);
          canvas.drawPath(metric.extractPath(d, d + len), nonSeatStroke);
          d += 7.5;
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SchematicBackgroundPainter old) =>
      old.kind != kind ||
      old.dark != dark ||
      old.highContrast != highContrast ||
      old.colors != colors;
}

class _WestCZonePainter extends CustomPainter {
  const _WestCZonePainter({
    required this.active,
    required this.pressed,
    required this.recent,
    required this.highlightStrength,
    required this.colors,
    required this.dark,
    required this.highContrast,
  });

  final bool active, pressed, recent, dark, highContrast;
  final double highlightStrength;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _westCPath(size, 10.0);
    final fill = !active
        ? colors.surfaceContainerHighest.withValues(alpha: dark ? 0.25 : 0.38)
        : (pressed
              ? colors.primaryContainer.withValues(
                  alpha: highContrast ? 0.96 : 0.92,
                )
              : colors.primaryContainer.withValues(
                  alpha:
                      (dark ? 0.56 : 0.68) +
                      (recent ? 0.22 * highlightStrength : 0.0),
                ));
    final stroke = !active
        ? colors.outlineVariant.withValues(alpha: 0.45)
        : (pressed || recent
              ? colors.primary
              : colors.primary.withValues(alpha: highContrast ? 0.95 : 0.48));
    final strokeWidth = pressed
        ? 1.8
        : (recent
              ? 1.5 + 0.5 * highlightStrength
              : (highContrast ? 1.2 : 0.95));

    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..color = stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _WestCZonePainter old) =>
      old.active != active ||
      old.pressed != pressed ||
      old.recent != recent ||
      old.highlightStrength != highlightStrength ||
      old.dark != dark ||
      old.highContrast != highContrast ||
      old.colors != colors;
}
