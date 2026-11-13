import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/ui/classroom_seek_surface.dart';
import 'classroom_controls_test.dart' show ControlsHarness;

void main() {
  testWidgets(
    'one upper-right view button opens all view controls and hides with the seek bar',
    (tester) async {
      final h = ControlsHarness();
      await h.open(tester, size: const Size(900, 500));
      expect(find.byTooltip('选择主画面'), findsNothing);
      expect(find.byTooltip('选择小窗画面'), findsNothing);
      expect(find.byTooltip('交换主画面与小窗'), findsNothing);
      expect(find.byTooltip('前进10秒'), findsNothing);
      final button = tester.getRect(find.byTooltip('切换画面'));
      expect(button.top, lessThan(64));
      expect(button.right, greaterThan(800));
      await tester.tap(find.byTooltip('切换画面'));
      await tester.pumpAndSettle();
      expect(find.text('切换课堂画面'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.byKey(const ValueKey('main-view-teacher')));
      await tester.pump();
      expect(h.player.state.main, 'teacher');
      expect(h.player.state.small, 'ppt');
      await tester.tap(find.byKey(const ValueKey('small-view-off')));
      await tester.pump();
      expect(h.player.state.small, isNull);
      await tester.tap(find.byKey(const ValueKey('small-view-student')));
      await tester.pump();
      expect(h.player.state.small, 'student');
      await tester.tap(find.text('交换主画面与小窗'));
      await tester.pump();
      expect(h.player.state.main, 'student');
      expect(h.player.state.small, 'teacher');
      expect(h.player.state.wanted, isTrue);
      await tester.pumpAndSettle();
      await h.capture(tester, 'landscape-view-sheet');
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await h.capture(tester, 'landscape-minimal');
      await tester.pump(const Duration(seconds: 4));
      expect(find.byTooltip('切换画面'), findsNothing);
      expect(find.byTooltip('关闭小窗'), findsNothing);
      expect(find.byType(Slider), findsNothing);
      await h.capture(tester, 'landscape-minimal-hidden');
      await tester.tapAt(const Offset(150, 100));
      await tester.pump();
      expect(find.byTooltip('切换画面'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      await h.close(tester);
    },
  );
  testWidgets(
    'visible landscape entry keeps the same player and position; back restores portrait then system policy',
    (tester) async {
      final h = ControlsHarness();
      h.data['position'] = 123000;
      await h.open(tester, size: const Size(400, 800), fullscreen: false);
      await tester.tap(find.text('横屏'));
      tester.view.physicalSize = const Size(900, 500);
      await tester.pumpAndSettle();
      expect(
        h.systemCalls.any(
          (c) =>
              c.method == 'SystemChrome.setPreferredOrientations' &&
              c.arguments.toString() ==
                  '[DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]',
        ),
        isTrue,
      );
      final surface = tester.getRect(find.byType(ClassroomSeekSurface));
      expect(
        tester
            .widget<Material>(
              find.byKey(const ValueKey('fullscreen-transparent-controls')),
            )
            .type,
        MaterialType.transparency,
      );
      expect(surface.size, const Size(900, 500));
      final panel = tester.getRect(
        find.byKey(const ValueKey('fullscreen-controls-panel')),
      );
      expect(panel.bottom, surface.bottom);
      final small = tester.getRect(
        find.byKey(const ValueKey('classroom-small-window')),
      );
      expect(small.bottom, lessThanOrEqualTo(panel.top));
      expect(h.player.state.position, 123000);
      expect(h.actions, isNot(contains('dispose')));
      await h.capture(tester, 'landscape-overlay');
      await tester.pump(const Duration(seconds: 4));
      expect(
        find.byKey(const ValueKey('fullscreen-controls-panel')),
        findsNothing,
      );
      expect(find.byType(Slider), findsNothing);
      expect(tester.getRect(find.byType(ClassroomSeekSurface)), surface);
      final gesture = await tester.startGesture(
        surface.centerLeft + const Offset(90, -40),
      );
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(90, 0));
      await tester.pump();
      final preview = tester.getRect(
        find.byKey(const ValueKey('classroom-seek-preview')),
      );
      final visiblePanel = tester.getRect(
        find.byKey(const ValueKey('fullscreen-controls-panel')),
      );
      expect(preview.bottom, lessThanOrEqualTo(visiblePanel.top));
      await gesture.up();
      await tester.pump();
      final position = h.player.state.position;
      expect(position, greaterThan(123000));
      await tester.binding.handlePopRoute();
      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpAndSettle();
      expect(find.text('横屏'), findsOneWidget);
      expect(h.player.state.position, position);
      expect(h.actions, isNot(contains('dispose')));
      expect(
        h.systemCalls
            .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
            .last
            .arguments,
        ['DeviceOrientation.portraitUp'],
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('打开合成课堂'), findsOneWidget);
      expect(h.actions.where((a) => a == 'dispose').length, 1);
      expect(
        h.systemCalls
            .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
            .last
            .arguments,
        isEmpty,
      );
      expect(
        h.systemCalls
            .where((c) => c.method == 'SystemChrome.setEnabledSystemUIMode')
            .last
            .arguments,
        'SystemUiMode.edgeToEdge',
      );
      await h.close(tester);
    },
  );

  testWidgets(
    'dark small landscape with large text keeps watermark, exit and scrollable controls apart',
    (tester) async {
      final h = ControlsHarness();
      h.data['error'] = 'FORBIDDEN';
      await h.open(
        tester,
        size: const Size(640, 320),
        textScale: 2,
        brightness: Brightness.dark,
      );
      final back = tester.getRect(find.byTooltip('返回竖屏'));
      final watermark = tester.getRect(find.text('合成水印'));
      expect(back.overlaps(watermark), isFalse);
      final exit = tester.getRect(find.byTooltip('退出全屏'));
      expect(exit.bottom, lessThanOrEqualTo(320));
      expect(find.byType(ClassroomSeekSurface), findsOneWidget);
      expect(tester.getRect(find.byType(ClassroomSeekSurface)).height, 320);
      await h.capture(tester, 'landscape-dark-large');
      await tester.tap(find.byTooltip('返回竖屏'));
      await tester.pumpAndSettle();
      expect(find.text('横屏'), findsOneWidget);
      await h.close(tester);
    },
  );
}
