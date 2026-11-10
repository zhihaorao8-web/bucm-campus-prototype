import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/ui/course_colors.dart';

void main() {
  test(
    'long neighbors, conflict lanes, vertical gaps and split lessons differ',
    () {
      final boxes = [
        const Rect.fromLTRB(0, 0, 1, 4), // long lesson beside two short lessons
        const Rect.fromLTRB(1, 0, 2, 2),
        const Rect.fromLTRB(1, 2, 2, 4),
        const Rect.fromLTRB(2, 0, 2.5, 2), // two conflict lanes
        const Rect.fromLTRB(2.5, 0, 3, 2),
        const Rect.fromLTRB(1, 5, 2, 6), // after a rest gap
      ];
      final colors = adjacentCourseColors(boxes);
      for (final (a, b) in [(0, 1), (0, 2), (1, 2), (1, 3), (3, 4), (2, 5)]) {
        expect(colors[a], isNot(colors[b]), reason: '$a and $b are adjacent');
      }
      final reversed = adjacentCourseColors(
        boxes.reversed.toList(),
      ).reversed.toList();
      expect(reversed, colors);
    },
  );
  test('empty data and dense neighbors do not force a palette collision', () {
    expect(adjacentCourseColors([]), isEmpty);
    final dense = adjacentCourseColors(
      List.filled(8, const Rect.fromLTWH(0, 0, 1, 1)),
    );
    expect(dense.toSet().length, 8);
  });
}
