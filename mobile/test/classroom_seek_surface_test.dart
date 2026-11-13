import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/ui/classroom_seek_surface.dart';
import 'classroom_controls_test.dart' show ControlsHarness;

void main() {
  Future<ValueNotifier<(int, int, bool)>> open(
    WidgetTester tester,
    List<int> seeks, {
    int position = 300000,
    int duration = 600000,
  }) async {
    final state = ValueNotifier((position, duration, true));
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 220,
            child: ValueListenableBuilder<(int, int, bool)>(
              valueListenable: state,
              builder: (_, value, _) => ClassroomSeekSurface(
                position: value.$1,
                duration: value.$2,
                enabled: value.$3,
                formatTime: (value) => '$value',
                onSeek: seeks.add,
                onInteraction: () {},
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      ),
    );
    return state;
  }

  testWidgets(
    'relative preview stays anchored during native updates; one seek on release',
    (tester) async {
      final seeks = <int>[];
      final state = await open(tester, seeks);
      final rect = tester.getRect(find.byType(ClassroomSeekSurface));
      final gesture = await tester.startGesture(
        rect.centerLeft + const Offset(80, 0),
      );
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      expect(find.text('330000 / 600000'), findsOneWidget);
      expect(seeks, isEmpty);
      state.value = (500000, 600000, true);
      await tester.pump();
      expect(find.text('330000 / 600000'), findsOneWidget);
      await gesture.up();
      await tester.pump();
      expect(seeks, [330000]);
      expect(
        find.byKey(const ValueKey('classroom-seek-preview')),
        findsNothing,
      );
    },
  );

  for (final (position, distance, expected) in [
    (5000, -200.0, 0),
    (599000, 200.0, 600000),
  ]) {
    testWidgets('gesture clamps to $expected', (tester) async {
      final seeks = <int>[];
      await open(tester, seeks, position: position);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ClassroomSeekSurface)),
      );
      await gesture.moveBy(Offset(distance.sign * 20, 0));
      await gesture.moveBy(Offset(distance, 0));
      await gesture.up();
      await tester.pump();
      expect(seeks, [expected]);
    });
  }

  testWidgets(
    'vertical drag, pointer cancellation and multi-touch never commit',
    (tester) async {
      final seeks = <int>[];
      await open(tester, seeks);
      final center = tester.getCenter(find.byType(ClassroomSeekSurface));
      await tester.dragFrom(center, const Offset(0, 80));
      expect(seeks, isEmpty);
      var gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(80, 0));
      await gesture.cancel();
      await tester.pump();
      expect(seeks, isEmpty);
      gesture = await tester.startGesture(center, pointer: 1);
      await gesture.moveBy(const Offset(80, 0));
      final second = await tester.startGesture(
        center + const Offset(0, 30),
        pointer: 2,
      );
      await gesture.moveBy(const Offset(80, 0));
      await second.up();
      await gesture.up();
      await tester.pump();
      expect(seeks, isEmpty);
      expect(
        find.byKey(const ValueKey('classroom-seek-preview')),
        findsNothing,
      );
    },
  );

  for (final change in ['blocked', 'duration', 'unknown']) {
    testWidgets('$change cancels or disables the gesture', (tester) async {
      final seeks = <int>[];
      final state = await open(
        tester,
        seeks,
        duration: change == 'unknown' ? 0 : 600000,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ClassroomSeekSurface)),
      );
      await gesture.moveBy(const Offset(30, 0));
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      if (change != 'unknown') {
        state.value = (
          300000,
          change == 'duration' ? 500000 : 600000,
          change != 'blocked',
        );
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
      expect(seeks, isEmpty);
      expect(
        find.byKey(const ValueKey('classroom-seek-preview')),
        findsNothing,
      );
    });
  }

  for (final fullscreen in [false, true]) {
    testWidgets(
      'page gesture seeks in fullscreen=$fullscreen without changing pause state or small-window gestures',
      (tester) async {
        final h = ControlsHarness();
        await h.open(
          tester,
          size: fullscreen ? const Size(900, 500) : const Size(400, 800),
          fullscreen: fullscreen,
        );
        final initial = h.player.state.position;
        final surface = tester.getRect(find.byType(ClassroomSeekSurface));
        final gesture = await tester.startGesture(
          surface.centerLeft + const Offset(60, 0),
        );
        await gesture.moveBy(const Offset(20, 0));
        await gesture.moveBy(const Offset(80, 0));
        await tester.pump(const Duration(seconds: 4));
        expect(
          find.byKey(const ValueKey('classroom-seek-preview')),
          findsOneWidget,
        );
        expect(find.byTooltip('暂停'), findsOneWidget);
        expect(h.actions.where((a) => a == 'seek'), isEmpty);
        expect(
          tester
              .getRect(find.byKey(const ValueKey('classroom-seek-preview')))
              .overlaps(
                tester.getRect(
                  find.byKey(const ValueKey('classroom-small-window')),
                ),
              ),
          isFalse,
        );
        await h.capture(
          tester,
          fullscreen ? 'seek-landscape' : 'seek-portrait',
        );
        await gesture.up();
        await tester.pump();
        expect(h.actions.where((a) => a == 'seek').length, 1);
        expect(h.player.state.position, greaterThan(initial));
        expect(h.player.state.wanted, isTrue);
        await tester.drag(
          find.byKey(const ValueKey('classroom-small-window')),
          const Offset(-80, 0),
        );
        await tester.pump();
        expect(h.actions.where((a) => a == 'seek').length, 1);
        expect(h.player.state.main, 'ppt');
        h.data.addAll({'playing': false, 'wanted': false});
        await h.refresh(tester);
        final paused = h.player.state.position;
        await tester.dragFrom(
          surface.centerLeft + const Offset(80, 0),
          const Offset(-70, 0),
        );
        await tester.pump();
        expect(h.player.state.position, lessThan(paused));
        expect(h.player.state.wanted, isFalse);
        await h.close(tester);
      },
    );
  }
}
