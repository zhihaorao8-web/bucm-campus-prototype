import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/ui/classroom_player_page.dart';
import 'package:campus_schedule/platform/classroom_player.dart';
import 'classroom_player_test.dart' show snapshot;
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/ui/classroom_player_route.dart';
import 'package:campus_schedule/ui/classroom_recording_timeline.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('play button expands before page reveal; reduced=$reduced', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final navigator = GlobalKey<NavigatorState>();
      ClassroomPlayerRoute? route;
      Rect? origin;
      var activations = 0;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ClassroomRecordingTile(
                title: '合成回放',
                subtitle: '合成教师\n合成教室',
                onPlay: (button) {
                  origin = playbackButtonRect(button, navigator.currentState!);
                  route = ClassroomPlayerRoute(
                    origin: origin,
                    color: Colors.blue,
                    iconColor: Colors.white,
                    reducedMotion: reduced,
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('合成播放页')),
                      body: TextButton(
                        focusNode: focus,
                        onPressed: () => activations++,
                        child: const Text('播放控制'),
                      ),
                    ),
                  );
                  navigator.currentState!.push(route!);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('合成回放'));
      await tester.pump();
      await tester.pump();
      expect(origin!.size, const Size(48, 48));
      expect(
        route!.transitionDuration,
        reduced ? Duration.zero : const Duration(milliseconds: 280),
      );
      if (!reduced) {
        PlaybackExpansionPainter painter() =>
            tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('playback-expanding-surface')),
                    )
                    .painter!
                as PlaybackExpansionPainter;
        double opacity() => tester
            .widget<Opacity>(find.byKey(const ValueKey('playback-page-reveal')))
            .opacity;
        final size = tester.getSize(
          find.byKey(const ValueKey('playback-expanding-surface')),
        );
        expect(painter().origin, origin);
        expect(painter().radiusFor(size), 24);
        expect(opacity(), 0);
        await tester.pump(const Duration(milliseconds: 100));
        expect(painter().radiusFor(size), greaterThan(24));
        expect(opacity(), 0);
        await tester.tap(find.text('播放控制'), warnIfMissed: false);
        expect(activations, 0);
        focus.requestFocus();
        await tester.pump();
        expect(focus.hasFocus, isFalse);
        await tester.pump(const Duration(milliseconds: 110));
        expect(painter().expansion, closeTo(1, 1e-8));
        for (final corner in [
          Offset.zero,
          size.topRight(Offset.zero),
          size.bottomLeft(Offset.zero),
          size.bottomRight(Offset.zero),
        ]) {
          expect(
            painter().radiusFor(size),
            greaterThanOrEqualTo((origin!.center - corner).distance - 1e-6),
          );
        }
        expect(opacity(), 0);
        await tester.pump(const Duration(milliseconds: 35));
        expect(opacity(), greaterThan(0));
        expect(opacity(), lessThan(1));
      }
      await tester.pumpAndSettle();
      expect(find.byType(PlaybackButtonExpansion), findsNothing);
      await tester.tap(find.text('播放控制'));
      expect(activations, 1);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('合成回放'), findsOneWidget);
      expect(find.text('合成播放页'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'expansion can reverse before completion without stranding overlay',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('列表')),
        ),
      );
      navigator.currentState!.push(
        ClassroomPlayerRoute(
          builder: (_) => const Scaffold(body: Text('播放器')),
          origin: const Rect.fromLTWH(300, 400, 48, 48),
          color: Colors.blue,
          iconColor: Colors.white,
          reducedMotion: false,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final before = tester
          .widget<PlaybackButtonExpansion>(find.byType(PlaybackButtonExpansion))
          .progress;
      navigator.currentState!.pop();
      await tester.pump();
      expect(
        tester
            .widget<PlaybackButtonExpansion>(
              find.byType(PlaybackButtonExpansion),
            )
            .progress,
        before,
      );
      await tester.pumpAndSettle();
      expect(find.text('列表'), findsOneWidget);
      expect(find.byType(PlaybackButtonExpansion), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'detached or offscreen button uses native route, not a stale origin',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final button = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            body: Transform.translate(
              offset: const Offset(0, 2000),
              child: SizedBox(key: button, width: 48, height: 48),
            ),
          ),
        ),
      );
      expect(playbackButtonRect(button, navigator.currentState!), isNull);
      expect(playbackButtonRect(GlobalKey(), navigator.currentState!), isNull);
      navigator.currentState!.push(
        ClassroomPlayerRoute(
          builder: (_) => const Scaffold(body: Text('播放器')),
          origin: null,
          color: Colors.blue,
          iconColor: Colors.white,
          reducedMotion: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('播放器'), findsOneWidget);
      expect(find.byType(PlaybackButtonExpansion), findsNothing);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('clipped scroll button cannot become an invisible origin', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final button = GlobalKey();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.only(top: 100),
            child: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  SizedBox(key: button, height: 48, width: 48),
                  const SizedBox(height: 1600),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(playbackButtonRect(button, navigator.currentState!), isNotNull);
    scroll.jumpTo(60);
    await tester.pump();
    expect(tester.getCenter(find.byKey(button)).dy, greaterThan(0));
    expect(playbackButtonRect(button, navigator.currentState!), isNull);
  });

  testWidgets('capture playback entry frames', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.runAsync(() async {
      final loader = FontLoader('PreviewChinese')
        ..addFont(
          File(
            'C:/Windows/Fonts/msyh.ttc',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await loader.load();
      await Directory(
        '../dist/playback-stage3-preview',
      ).create(recursive: true);
    });
    const channel = MethodChannel('synthetic-capture');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async =>
          call.method == 'dispose' ? null : (snapshot()..['textures'] = []),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    for (final mode in ['light', 'dark', 'large']) {
      tester.view.physicalSize = Size(mode == 'large' ? 320 : 390, 844);
      final boundary = GlobalKey();
      Future<void> capture(String name) async {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '../dist/playback-stage3-preview/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      final theme = appTheme(
        mode == 'dark' ? Brightness.dark : Brightness.light,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'PreviewChinese'),
          ),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MiuixThemeBridge(
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(mode == 'large' ? 1.5 : 1),
              ),
              child: RepaintBoundary(key: boundary, child: child!),
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('课程课堂')),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    '中医基础理论',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const Text('合成教师\n2030–2031学年第一学期'),
                  const SizedBox(height: 32),
                  const Text('10月1日 · 合成录播'),
                  const SizedBox(height: 12),
                  ClassroomRecordingTile(
                    title: '第一讲 · 阴阳学说',
                    subtitle: '合成教师 · 合成班\n合成教室 · 已发布',
                    onPlay: (button) {
                      final navigator = Navigator.of(context);
                      final player = ClassroomPlayerController(
                        ClassroomPlayerState(snapshot()..['textures'] = []),
                        channel: channel,
                      );
                      navigator.push(
                        ClassroomPlayerRoute(
                          origin: playbackButtonRect(button, navigator),
                          color: theme.colorScheme.primary,
                          iconColor: theme.colorScheme.onPrimary,
                          reducedMotion: false,
                          builder: (_) => ClassroomPlayerPage(
                            title: '第一讲 · 阴阳学说',
                            controller: player,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture('$mode-list');
      await tester.tap(find.text('第一讲 · 阴阳学说'));
      await tester.pump();
      await tester.pump();
      for (var i = 0; i <= 15; i++) {
        if (i > 0) await tester.pump(const Duration(milliseconds: 20));
        await capture('$mode-${i.toString().padLeft(2, '0')}');
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await capture('$mode-return');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
  }, skip: !const bool.fromEnvironment('CAPTURE_PLAYBACK'));

  testWidgets('disabled recording cannot launch; geometry survives resize', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ClassroomRecordingTile(
            title: '未发布',
            subtitle: '暂无权限\n合成记录',
            onPlay: null,
          ),
        ),
      ),
    );
    expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNull);
    final painter = PlaybackExpansionPainter(
      origin: const Rect.fromLTWH(280, 700, 48, 48),
      expansion: 1,
      color: Colors.blue,
    );
    for (final size in [const Size(320, 844), const Size(844, 320)]) {
      final center = painter.origin.center;
      expect(painter.radiusFor(size), greaterThanOrEqualTo(center.distance));
      expect(
        painter.radiusFor(size),
        greaterThanOrEqualTo((center - size.bottomRight(Offset.zero)).distance),
      );
    }
  });
}
