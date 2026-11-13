import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/platform/classroom_player.dart';
import 'package:campus_schedule/ui/classroom_player_page.dart';

Map<String, Object?> snapshot({bool pptOnly = false}) => {
  'session': 'synthetic-session',
  'main': 'ppt',
  'small': pptOnly ? null : 'teacher',
  'available': pptOnly ? ['ppt'] : ['ppt', 'teacher', 'student'],
  'playing': false,
  'wanted': false,
  'buffering': false,
  'position': 30000,
  'duration': 600000,
  'speed': 1.0,
  'watermark': '合成水印',
  'error': null,
  'textures': [
    {'kind': 'ppt', 'texture': 1, 'ratio': 16 / 9},
    if (!pptOnly) {'kind': 'teacher', 'texture': 2, 'ratio': 16 / 9},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('synthetic-playback');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final brightness in Brightness.values) {
    testWidgets('主小窗交换、学生切换与释放 $brightness', (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = snapshot();
      final actions = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        actions.add(call.method);
        final args = Map<String, Object?>.from(call.arguments as Map);
        if (call.method == 'layout') {
          data['main'] = args['main'];
          data['small'] = args['small'];
          data['textures'] = [
            {'kind': args['main'], 'texture': 1, 'ratio': 16 / 9},
            if (args['small'] != null)
              {'kind': args['small'], 'texture': 2, 'ratio': 16 / 9},
          ];
        } else if (call.method == 'seek') {
          data['position'] = args['position'];
        } else if (call.method == 'play') {
          data['wanted'] = true;
          data['playing'] = true;
        } else if (call.method == 'pause') {
          data['wanted'] = false;
          data['playing'] = false;
        }
        if (call.method == 'dispose') return null;
        return data;
      });
      final controller = ClassroomPlayerController(
        ClassroomPlayerState(data),
        channel: channel,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: ClassroomPlayerPage(title: '合成课堂', controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'PPT主画面',
        ),
        findsOneWidget,
      );
      expect(find.text('合成水印'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('后退10秒'));
      await tester.tap(find.byTooltip('后退10秒'));
      await tester.pump();
      expect(controller.state.position, 20000);
      data['position'] = 5000;
      await controller.refresh();
      await tester.pump();
      await tester.tap(find.byTooltip('后退10秒'));
      await tester.pump();
      expect(controller.state.position, 0);
      data['position'] = 599000;
      await controller.refresh();
      await tester.pump();
      await tester.tap(find.byTooltip('前进10秒'));
      await tester.pump();
      expect(controller.state.position, 600000);

      await tester.tap(find.byTooltip('交换主画面与小窗'));
      await tester.pump();
      expect(controller.state.main, 'teacher');
      expect(controller.state.small, 'ppt');
      await tester.tap(find.byTooltip('选择小窗画面'));
      await tester.pumpAndSettle();
      expect(find.text('关闭小窗'), findsNothing);
      await tester.tap(find.text('学生').last);
      await tester.pumpAndSettle();
      expect(controller.state.small, 'student');
      await tester.ensureVisible(find.byTooltip('关闭小窗'));
      await tester.tap(find.byTooltip('关闭小窗'));
      await tester.pump();
      expect(controller.state.small, isNull);
      await tester.ensureVisible(find.text('显示小窗'));
      await tester.tap(find.text('显示小窗'));
      await tester.pump();
      expect(controller.state.small, 'student');
      await tester.tap(find.byTooltip('播放'));
      await tester.pump();
      expect(controller.state.wanted, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(controller.state.wanted, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(actions, contains('dispose'));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('单画面、窄横屏全屏返回及小窗禁用', (tester) async {
    final systemCalls = <String>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      systemCalls.add(call.method);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = snapshot(pptOnly: true);
    messenger.setMockMethodCallHandler(channel, (_) async => data);
    final controller = ClassroomPlayerController(
      ClassroomPlayerState(data),
      channel: channel,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ClassroomPlayerPage(title: '合成单路', controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byTooltip('全屏'), 120);
    await tester.ensureVisible(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(systemCalls, contains('SystemChrome.setPreferredOrientations'));
    expect(find.byTooltip('退出全屏'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('切换画面'));
    await tester.pumpAndSettle();
    expect(find.text('学生'), findsNothing);
    expect(find.text('关闭小窗'), findsNothing);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '交换主画面与小窗'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('small-view-off')))
          .selected,
      isTrue,
    );
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    await tester.scrollUntilVisible(find.byTooltip('全屏'), 120);
    await tester.ensureVisible(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('全屏'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  test('已释放控制器忽略迟到响应，拒绝无效画面与跨会话状态', () async {
    final completer = Completer<Map<String, Object?>>();
    var disposed = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'dispose') {
        disposed = true;
        return null;
      }
      return completer.future;
    });
    final player = ClassroomPlayerController(
      ClassroomPlayerState(snapshot()),
      channel: channel,
    );
    final reading = player.refresh();
    player.dispose();
    completer.complete({...snapshot(), 'position': 90000});
    await reading;
    await Future<void>.delayed(Duration.zero);
    expect(player.state.position, 30000);
    expect(disposed, isTrue);
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'dispose'
          ? null
          : {...snapshot(), 'session': 'another-session'},
    );
    final current = ClassroomPlayerController(
      ClassroomPlayerState(snapshot()),
      channel: channel,
    );
    await current.refresh();
    expect(current.state.session, 'synthetic-session');
    expect(current.failure, isNotNull);
    current.dispose();
    expect(
      () => ClassroomPlayerState({...snapshot(), 'small': 'ppt'}),
      throwsFormatException,
    );
    expect(
      () => ClassroomPlayerState({
        ...snapshot(),
        'available': ['arbitrary'],
      }),
      throwsFormatException,
    );
  });
}
