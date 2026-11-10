import 'dart:math' as math;
import 'dart:ui';

/// Color visible neighbors, independent of course names and stored data.
/// All equally near cards in each direction count, including conflict lanes.
List<int> adjacentCourseColors(List<Rect> boxes, {int paletteSize = 5}) {
  assert(paletteSize > 0);
  const epsilon = .000001;
  final neighbors = List.generate(boxes.length, (_) => <int>{});
  void link(int a, int b) {
    neighbors[a].add(b);
    neighbors[b].add(a);
  }

  for (var i = 0; i < boxes.length; i++) {
    final a = boxes[i];
    final nearest = List.filled(4, double.infinity);
    final matches = List.generate(4, (_) => <int>[]);
    void consider(int direction, int j, double gap) {
      if (gap < -epsilon) return;
      if (gap < nearest[direction] - epsilon) {
        nearest[direction] = gap;
        matches[direction].clear();
      }
      if ((gap - nearest[direction]).abs() < epsilon) {
        matches[direction].add(j);
      }
    }

    for (var j = 0; j < boxes.length; j++) {
      if (i == j) continue;
      final b = boxes[j];
      if (a.overlaps(b)) link(i, j);
      if (math.min(a.right, b.right) - math.max(a.left, b.left) > epsilon) {
        consider(0, j, b.top - a.bottom);
        consider(1, j, a.top - b.bottom);
      }
      if (math.min(a.bottom, b.bottom) - math.max(a.top, b.top) > epsilon) {
        consider(2, j, b.left - a.right);
        consider(3, j, a.left - b.right);
      }
    }
    for (final group in matches) {
      for (final j in group) {
        link(i, j);
      }
    }
  }
  // A geometry-based order keeps colors stable when the source list is reordered.
  final order = List.generate(boxes.length, (i) => i)
    ..sort((i, j) {
      final a = boxes[i], b = boxes[j];
      for (final pair in [
        (a.top, b.top),
        (a.left, b.left),
        (a.bottom, b.bottom),
        (a.right, b.right),
      ]) {
        final result = pair.$1.compareTo(pair.$2);
        if (result != 0) return result;
      }
      return i.compareTo(j);
    });
  final colors = List.filled(boxes.length, -1);
  for (var rank = 0; rank < order.length; rank++) {
    final i = order[rank];
    final used = {
      for (final j in neighbors[i])
        if (colors[j] >= 0) colors[j],
    };
    var chosen = -1;
    for (var n = 0; n < paletteSize; n++) {
      final candidate = (rank + n) % paletteSize;
      if (!used.contains(candidate)) {
        chosen = candidate;
        break;
      }
    }
    if (chosen < 0) {
      chosen = paletteSize;
      while (used.contains(chosen)) {
        chosen++;
      }
    }
    colors[i] = chosen;
  }
  return colors;
}
