import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/ui/classroom_small_window.dart';
import 'classroom_controls_test.dart' show ControlsHarness;

const smallKey = ValueKey('classroom-small-window');
const smallLabel = '教师小窗，点击交换主画面';
Rect window(WidgetTester tester) => tester.getRect(find.byKey(smallKey));

void expectInside(WidgetTester tester) {
  final area = tester.getRect(
    find.byKey(const ValueKey('fullscreen-playback-surface')),
  );
  final box = window(tester);
  final watermark = tester.getRect(find.text('合成水印'));
  expect(box.left, greaterThanOrEqualTo(area.left + 11.9));
  expect(box.right, lessThanOrEqualTo(area.right - 11.9));
  expect(box.top, greaterThanOrEqualTo(watermark.bottom + 7.9));
  expect(box.bottom, lessThanOrEqualTo(area.bottom - 11.9));
  expect(box.height, greaterThanOrEqualTo(48));
}

void main() {
  test(
    'geometry preserves preferences while clamping changed viewport and watermark bounds',
    () {
      final placement = ClassroomSmallWindowPlacement();
      const size = Size(900, 600);
      placement.update(size, 80, const Offset(-500, -500), 300, resize: true);
      final preferred = placement.widthFraction;
      final original = placement.resolve(size, 80)!;
      expect(original.left, 12);
      expect(original.top, 80);
      for (final view in [
        const Size(320, 180),
        const Size(640, 106),
        const Size(900, 600),
      ]) {
        final box = placement.resolve(view, 40)!;
        expect(box.left, greaterThanOrEqualTo(12));
        expect(box.top, greaterThanOrEqualTo(40));
        expect(box.right, lessThanOrEqualTo(view.width - 12));
        expect(box.bottom, lessThanOrEqualTo(view.height - 12 + .001));
      }
      expect(placement.resolve(const Size(320, 60), 40), isNull);
      expect(placement.widthFraction, preferred);
      expect(placement.resolve(size, 80), original);
    },
  );

  testWidgets(
    'drag clamps away from watermark, never swaps; close/restore retains layout and tap swaps',
    (tester) async {
      final h = ControlsHarness();
      h.data.addAll({'playing': false, 'wanted': false});
      await h.open(tester);
      final start = window(tester);
      await tester.drag(find.byKey(smallKey), const Offset(-2000, -2000));
      await tester.pumpAndSettle();
      expectInside(tester);
      final moved = window(tester);
      expect(moved.center.dx, lessThan(start.center.dx));
      expect(h.actions.where((v) => v == 'layout'), isEmpty);
      await h.capture(tester, 'small-window-moved');
      await tester.tap(find.byTooltip('关闭小窗'));
      await tester.pumpAndSettle();
      expect(find.byKey(smallKey), findsNothing);
      expect(h.data['small'], isNull);
      await tester.tap(find.text('显示小窗'));
      await tester.pumpAndSettle();
      expect(window(tester), moved);
      await tester.tap(find.byKey(smallKey));
      await tester.pumpAndSettle();
      expect(h.data['main'], 'teacher');
      expect(h.data['small'], 'ppt');
      await h.close(tester);
    },
  );

  testWidgets(
    'two-finger pinch resizes without swapping and stays bounded at both limits',
    (tester) async {
      final h = ControlsHarness();
      h.data.addAll({'playing': false, 'wanted': false});
      await h.open(tester);
      final before = window(tester);
      Future<void> pinch(double endDistance) async {
        final center = window(tester).center + const Offset(0, 8);
        final a = await tester.startGesture(
          center - const Offset(30, 0),
          pointer: 1,
        );
        final b = await tester.startGesture(
          center + const Offset(30, 0),
          pointer: 2,
        );
        await tester.pump();
        // Start recognition before increasing the span further.
        await a.moveTo(center - const Offset(40, 0));
        await b.moveTo(center + const Offset(40, 0));
        await tester.pump();
        await a.moveTo(center - Offset(endDistance, 0));
        await b.moveTo(center + Offset(endDistance, 0));
        await tester.pump();
        await a.up();
        await b.up();
        await tester.pumpAndSettle();
      }

      await pinch(100);
      expect(window(tester).width, greaterThan(before.width));
      expectInside(tester);
      await h.capture(tester, 'small-window-enlarged');
      await pinch(2);
      expect(window(tester).width, closeTo(96, .01));
      expectInside(tester);
      expect(h.actions.where((v) => v == 'layout'), isEmpty);
      await h.close(tester);
    },
  );

  testWidgets(
    'rotation and automatic control layout changes keep dragged window legal',
    (tester) async {
      final h = ControlsHarness();
      await h.open(tester);
      await tester.drag(find.byKey(smallKey), const Offset(-160, -120));
      await tester.pump();
      expectInside(tester);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byTooltip('退出全屏'), findsNothing);
      expectInside(tester);
      tester.view.physicalSize = const Size(640, 320);
      await tester.pump();
      expectInside(tester);
      await tester.tapAt(const Offset(70, 80));
      await tester.pump();
      expect(find.byTooltip('退出全屏'), findsOneWidget);
      expectInside(tester);
      await h.close(tester);
    },
  );

  testWidgets(
    'large watermark reserves its full text area and scarce space does not close native stream',
    (tester) async {
      final h = ControlsHarness();
      h.data.addAll({
        'playing': false,
        'wanted': false,
        'error': 'FORBIDDEN',
        'watermark': '合成水印第一行\n合成水印第二行\n合成水印第三行\n合成水印第四行',
      });
      await h.open(tester, size: const Size(640, 320), textScale: 1.5);
      expect(find.byKey(smallKey), findsNothing);
      expect(h.data['small'], 'teacher');
      h.data.addAll({'playing': true, 'wanted': true, 'error': null});
      await h.refresh(tester);
      await tester.pump(const Duration(seconds: 4));
      final mark = tester.getRect(find.text(h.data['watermark']! as String));
      expect(window(tester).top, greaterThanOrEqualTo(mark.bottom + 7.9));
      expect(h.actions.where((v) => v == 'layout'), isEmpty);
      await h.capture(tester, 'small-window-watermark');
      await h.close(tester);
    },
  );

  testWidgets('accessibility increase/decrease resize the window', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final h = ControlsHarness()..accessible.value = true;
    await h.open(tester);
    final before = window(tester).width;
    final node = tester.getSemantics(find.bySemanticsLabel(smallLabel));
    node.owner!.performAction(node.id, ui.SemanticsAction.increase);
    await tester.pump();
    expect(window(tester).width, greaterThan(before));
    node.owner!.performAction(node.id, ui.SemanticsAction.decrease);
    await tester.pump();
    expect(window(tester).width, closeTo(before, .01));
    expectInside(tester);
    await h.close(tester);
    semantics.dispose();
  });
}
