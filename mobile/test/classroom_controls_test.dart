import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/platform/classroom_player.dart';
import 'package:campus_schedule/ui/classroom_player_page.dart';
import 'classroom_player_test.dart' show snapshot;

class ControlsHarness {
  final boundary = GlobalKey();
  final data = snapshot()..addAll({'playing': true, 'wanted': true});
  final actions = <String>[];
  final accessible = ValueNotifier(false);
  late ClassroomPlayerController player;
  static const channel = MethodChannel('synthetic-idle-controls');

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(900, 600),
    double textScale = 1,
  }) async {
    if (const bool.fromEnvironment('CAPTURE_PREVIEW')) {
      await tester.runAsync(() async {
        final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
        await (FontLoader(
          'PreviewChinese',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        final icons = await File(
          '../build/toolchain/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
        ).readAsBytes();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons)))).load();
      });
    }
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      actions.add(call.method);
      final args = Map<String, Object?>.from(call.arguments as Map);
      switch (call.method) {
        case 'pause':
          data.addAll({'playing': false, 'wanted': false});
        case 'play':
          data.addAll({'playing': true, 'wanted': true});
        case 'seek':
          data['position'] = args['position'];
        case 'layout':
          data.addAll({'main': args['main'], 'small': args['small']});
        case 'speed':
          data['speed'] = args['speed'];
        case 'dispose':
          return null;
      }
      return data;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    addTearDown(accessible.dispose);
    player = ClassroomPlayerController(
      ClassroomPlayerState(data),
      channel: channel,
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            fontFamily: const bool.fromEnvironment('CAPTURE_PREVIEW')
                ? 'PreviewChinese'
                : null,
          ),
          builder: (context, child) => ValueListenableBuilder<bool>(
            valueListenable: accessible,
            builder: (_, value, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                accessibleNavigation: value,
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ClassroomPlayerPage(title: '合成课堂', controller: player),
                  ),
                ),
                child: const Text('打开合成课堂'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开合成课堂'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byTooltip('全屏'), 160);
    await tester.ensureVisible(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
  }

  Future<void> refresh(WidgetTester tester) async {
    await player.refresh();
    await tester.pump();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_PREVIEW')) return;
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await render.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('../dist/flutter-preview/controls-$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }
}

void main() {
  testWidgets('small landscape large text keeps error and exit reachable', (
    tester,
  ) async {
    final h = ControlsHarness();
    h.data.addAll({'playing': false, 'wanted': false, 'error': 'FORBIDDEN'});
    await h.open(tester, size: const Size(640, 320), textScale: 1.5);
    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining('学校暂未允许观看'), findsOneWidget);
    final exit = tester.getRect(find.byTooltip('退出全屏'));
    expect(exit.bottom, lessThanOrEqualTo(320));
    final surface = tester.getRect(
      find.byKey(const ValueKey('fullscreen-playback-surface')),
    );
    final small = tester.getRect(find.bySemanticsLabel('教师小窗，点击交换主画面'));
    expect(small.top, greaterThanOrEqualTo(surface.top));
    expect(small.bottom, lessThanOrEqualTo(surface.bottom));
    await h.capture(tester, 'small-error');
    await tester.tap(find.byTooltip('退出全屏'));
    await tester.pumpAndSettle();
    expect(find.text('合成课堂'), findsOneWidget);
    await h.close(tester);
  });
  testWidgets(
    'full-screen idle hides despite periodic state updates; tap reveals; back exits first',
    (tester) async {
      final h = ControlsHarness();
      await h.open(tester);
      await h.capture(tester, 'visible');
      await tester.pump(const Duration(seconds: 2));
      expect(find.byTooltip('暂停'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.byTooltip('暂停'), findsNothing);
      await h.capture(tester, 'hidden');
      expect(find.bySemanticsLabel('轻点显示播放控制'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('fullscreen-playback-surface')),
      );
      await tester.pump();
      expect(find.byTooltip('退出全屏'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byTooltip('退出全屏'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('合成课堂'), findsOneWidget);
      expect(find.byTooltip('全屏'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byTooltip('暂停'), findsOneWidget);
      await h.close(tester);
    },
  );

  testWidgets(
    'pause, buffering and errors reveal and retain controls; background pauses',
    (tester) async {
      final h = ControlsHarness();
      await h.open(tester);
      await tester.pump(const Duration(seconds: 4));
      h.data['buffering'] = true;
      await h.refresh(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byTooltip('暂停'), findsOneWidget);
      h.data.addAll({'buffering': false, 'playing': false, 'wanted': false});
      await h.refresh(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byTooltip('播放'), findsOneWidget);
      h.data.addAll({'playing': true, 'wanted': true});
      await h.refresh(tester);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byTooltip('暂停'), findsNothing);
      h.data['error'] = 'AUTHENTICATION';
      await h.refresh(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(find.textContaining('学校会话已失效'), findsOneWidget);
      expect(find.byTooltip('退出全屏'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(h.actions, contains('pause'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await h.close(tester);
    },
  );

  testWidgets(
    'menus keep controls visible and start a fresh idle window on dismissal',
    (tester) async {
      final h = ControlsHarness();
      await h.open(tester);
      await tester.tap(find.byTooltip('播放速度'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6));
      expect(find.byTooltip('退出全屏'), findsOneWidget);
      await tester.tap(find.text('1.5×'));
      await tester.pumpAndSettle();
      expect(h.data['speed'], 1.5);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byTooltip('退出全屏'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.byTooltip('退出全屏'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('fullscreen-playback-surface')),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('选择主画面'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6));
      expect(find.byTooltip('退出全屏'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      expect(find.byTooltip('退出全屏'), findsNothing);
      await h.close(tester);
    },
  );

  testWidgets(
    'accessibility navigation disables hiding and reveals hidden controls immediately',
    (tester) async {
      final h = ControlsHarness()..accessible.value = true;
      await h.open(tester);
      await tester.pump(const Duration(seconds: 10));
      expect(find.byTooltip('退出全屏'), findsOneWidget);
      h.accessible.value = false;
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(find.byTooltip('退出全屏'), findsNothing);
      h.accessible.value = true;
      await tester.pump();
      expect(find.byTooltip('退出全屏'), findsOneWidget);
      await h.close(tester);
    },
  );

  testWidgets(
    'holding and seeking never hide controls; release restarts idle timeout',
    (tester) async {
      final h = ControlsHarness();
      await h.open(tester);
      final slider = tester.getRect(find.byType(Slider));
      final gesture = await tester.startGesture(slider.center);
      await gesture.moveTo(slider.center + const Offset(100, 0));
      await tester.pump(const Duration(seconds: 6));
      expect(find.byTooltip('退出全屏'), findsOneWidget);
      await gesture.up();
      await tester.pump();
      expect(h.actions, contains('seek'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byTooltip('退出全屏'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.byTooltip('退出全屏'), findsNothing);
      await h.close(tester);
    },
  );
}
