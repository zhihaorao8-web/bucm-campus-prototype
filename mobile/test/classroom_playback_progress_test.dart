import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/data/classroom_playback_progress.dart';
import 'package:campus_schedule/application/classroom_playback_progress_session.dart';
import 'package:campus_schedule/platform/classroom_player.dart';
import 'package:campus_schedule/platform/school_adapter.dart';
import 'package:campus_schedule/ui/classroom_player_page.dart';
import 'package:campus_schedule/ui/classroom_course_page.dart';
import 'package:campus_schedule/platform/classroom_access.dart';
import 'package:campus_schedule/platform/classroom_session_cache.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'classroom_recovery_page_test.dart' as fake;
import 'classroom_name_merge_test.dart' as sources;
import 'support/memory_classroom_library.dart';
import 'classroom_player_test.dart' show snapshot;

ClassroomPlaybackIdentity identity({
  String semester = '2030-2031-1',
  String course = 'source-a',
}) => ClassroomPlaybackIdentity(
  semester: semester,
  courseId: course,
  recordId: 'same-record',
);
ClassroomPlaybackProgress progress(int position, {int duration = 600000}) =>
    ClassroomPlaybackProgress(
      position: position,
      duration: duration,
      updatedAt: DateTime.utc(2030, 9, 1),
    );

class MemoryProgress extends ClassroomPlaybackProgressStore {
  final values = <String, ClassroomPlaybackProgress>{};
  int epoch = 0, writes = 0, reads = 0;
  bool failRead = false, failSave = false;
  Completer<ClassroomPlaybackProgress?>? readGate;
  Completer<void>? writeGate;
  @override
  int get revision => epoch;
  @override
  Future<ClassroomPlaybackProgress?> lookup(
    ClassroomPlaybackIdentity identity,
  ) async {
    reads++;
    if (failRead) throw const FormatException('synthetic damaged file');
    return readGate?.future ?? values[identity.key];
  }

  @override
  Future<void> save(
    ClassroomPlaybackIdentity identity,
    ClassroomPlaybackProgress progress, {
    required int revision,
  }) async {
    if (failSave) throw FileSystemException('synthetic storage failure');
    if (writeGate != null) await writeGate!.future;
    if (revision != epoch) return;
    writes++;
    values[identity.key] = progress;
  }

  @override
  Future<void> clear() async {
    epoch++;
    values.clear();
    notifyListeners();
  }
}

class ProgressHarness {
  final store = MemoryProgress();
  final id = identity();
  final data = snapshot()
    ..addAll({'position': 0, 'playing': false, 'wanted': false});
  final commands = <String>[];
  static const channel = MethodChannel('synthetic-local-progress');
  late ClassroomPlayerController player;
  ClassroomPlaybackProgressSession? session;
  Completer<void>? seekGate;
  bool foreground = true;

  void setup() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      commands.add(call.method);
      final args = Map<String, Object?>.from(call.arguments as Map);
      if (call.method == 'seek') {
        if (seekGate != null) await seekGate!.future;
        data['position'] = args['position'];
      }
      if (call.method == 'pause') {
        data.addAll({'playing': false, 'wanted': false});
      }
      if (call.method == 'play') data.addAll({'playing': true, 'wanted': true});
      return call.method == 'dispose' ? null : data;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    player = ClassroomPlayerController(
      ClassroomPlayerState(data),
      channel: channel,
    );
  }

  Future<void> start(WidgetTester tester) async {
    setup();
    session = ClassroomPlaybackProgressSession(
      player: player,
      identity: id,
      store: store,
      canPlay: () => foreground,
    )..start();
    await tester.pump();
  }

  Future<void> refresh(WidgetTester tester) async {
    await player.refresh();
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    session?.dispose();
    player.dispose();
    await tester.pump();
  }
}

void main() {
  test(
    'resume boundaries reject short, completed, unknown or changed duration',
    () {
      expect(progress(9999).resumePosition(600000), isNull);
      expect(progress(10000).resumePosition(600000), 10000);
      expect(progress(570000).resumePosition(600000), 570000);
      expect(progress(570001).resumePosition(600000), isNull);
      expect(progress(600000).resumePosition(600000), isNull);
      expect(progress(120000).resumePosition(0), isNull);
      expect(progress(120000).resumePosition(590000), isNull);
      expect(progress(120000).resumePosition(601000), 120000);
      expect(() => progress(-1), throwsFormatException);
      expect(() => progress(600001), throwsFormatException);
      expect(() => progress(0, duration: 0), throwsFormatException);
    },
  );

  test(
    'persistent store isolates semester and source; corrupt/save-failed files are retained; clear blocks stale writes',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'synthetic-local-progress-',
      );
      final store = ClassroomPlaybackProgressStore(directory: dir);
      final file = File('${dir.path}/classroom-progress-v1.json');
      try {
        final ids = [
          identity(),
          identity(course: 'source-b'),
          identity(semester: '2031-2032-1'),
        ];
        for (var i = 0; i < ids.length; i++) {
          await store.save(
            ids[i],
            progress((i + 1) * 12000),
            revision: store.revision,
          );
        }
        final reopened = ClassroomPlaybackProgressStore(directory: dir);
        for (var i = 0; i < ids.length; i++) {
          expect((await reopened.lookup(ids[i]))!.position, (i + 1) * 12000);
        }
        final json = jsonDecode(await file.readAsString()) as Map;
        final record = (json['records'] as Map).values.first as Map;
        expect(record.keys.toSet(), {'position', 'duration', 'updatedAt'});
        final before = await file.readAsString();
        await Directory('${file.path}.pending').create();
        await expectLater(
          store.save(ids[0], progress(50000), revision: store.revision),
          throwsA(isA<FileSystemException>()),
        );
        expect(await file.readAsString(), before);
        await Directory('${file.path}.pending').delete();
        await file.writeAsString('{damaged-synthetic-progress');
        await expectLater(store.lookup(ids[0]), throwsFormatException);
        await expectLater(
          store.save(ids[0], progress(50000), revision: store.revision),
          throwsFormatException,
        );
        expect(await file.readAsString(), '{damaged-synthetic-progress');
        await store.clear();
        final epoch = store.revision;
        final late = store.save(ids[0], progress(60000), revision: epoch);
        final clear = store.clear();
        await Future.wait([late, clear]);
        await store.save(ids[0], progress(60000), revision: epoch);
        expect(await file.exists(), isFalse);
        expect(await store.lookup(ids[0]), isNull);
      } finally {
        store.dispose();
        await dir.delete(recursive: true);
      }
    },
  );

  testWidgets('continue, periodic updates and final snapshot are local only', (
    tester,
  ) async {
    final h = ProgressHarness();
    h.store.values[h.id.key] = progress(120000);
    await h.start(tester);
    expect(h.session!.choicePosition, 120000);
    expect(h.session!.blocked, isTrue);
    expect(h.store.writes, 0);
    await h.session!.choose(resume: true);
    expect(h.data['position'], 120000);
    expect(h.data['playing'], isTrue);
    h.data['position'] = 125000;
    await h.refresh(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(h.store.values[h.id.key]!.position, 125000);
    h.data['position'] = 128000;
    await h.refresh(tester);
    await h.close(tester);
    expect(h.store.values[h.id.key]!.position, 128000);
    expect(h.commands, isNot(contains('report')));
  });

  testWidgets(
    'unknown duration waits; from-start seeks zero; background decision does not play',
    (tester) async {
      final h = ProgressHarness();
      h.data['duration'] = 0;
      h.store.values[h.id.key] = progress(120000);
      await h.start(tester);
      expect(h.session!.blocked, isTrue);
      expect(h.session!.choicePosition, isNull);
      h.data['duration'] = 600000;
      await h.refresh(tester);
      expect(h.session!.choicePosition, 120000);
      h.foreground = false;
      await h.session!.choose(resume: false);
      expect(h.data['position'], 0);
      expect(h.commands, isNot(contains('play')));
      expect(h.store.values[h.id.key]!.position, 0);
      await h.close(tester);
    },
  );

  testWidgets(
    'read and save failures do not block manual playback or destroy old progress',
    (tester) async {
      final h = ProgressHarness();
      h.store.failRead = true;
      await h.start(tester);
      expect(h.session!.ready, isTrue);
      expect(h.session!.warning, contains('未能读取'));
      await h.player.command('play');
      await tester.pump(const Duration(seconds: 10));
      expect(h.store.writes, 0);
      await h.close(tester);
      final write = ProgressHarness();
      write.store.failSave = true;
      await write.start(tester);
      await write.player.command('play');
      await write.session!.save();
      expect(write.session!.warning, contains('未能保存'));
      expect(write.player.state.playing, isTrue);
      await write.close(tester);
    },
  );

  testWidgets(
    'unknown duration times out to manual start without a late resume prompt',
    (tester) async {
      final h = ProgressHarness();
      h.data['duration'] = 0;
      h.store.values[h.id.key] = progress(120000);
      await h.start(tester);
      await tester.pump(const Duration(seconds: 10));
      expect(h.session!.blocked, isFalse);
      expect(h.session!.warning, contains('从头播放'));
      expect(h.store.values[h.id.key]!.position, 120000);
      h.data['duration'] = 600000;
      await h.refresh(tester);
      expect(h.session!.choicePosition, isNull);
      expect(h.commands, isNot(contains('seek')));
      await h.close(tester);
    },
  );

  testWidgets(
    'clear while reading or seeking blocks late old-account data and playback',
    (tester) async {
      final h = ProgressHarness();
      h.store.readGate = Completer();
      await h.start(tester);
      await h.store.clear();
      h.store.readGate!.complete(progress(120000));
      await tester.pump();
      expect(h.session!.invalidated, isTrue);
      expect(h.session!.choicePosition, isNull);
      await h.close(tester);
      final seek = ProgressHarness();
      seek.store.values[seek.id.key] = progress(120000);
      await seek.start(tester);
      seek.seekGate = Completer();
      final choosing = seek.session!.choose(resume: true);
      await tester.pump();
      await seek.store.clear();
      seek.seekGate!.complete();
      await choosing;
      expect(seek.session!.invalidated, isTrue);
      expect(seek.commands, isNot(contains('play')));
      expect(seek.store.values, isEmpty);
      await seek.close(tester);
    },
  );

  testWidgets('final progress is queued after an in-flight save', (
    tester,
  ) async {
    final h = ProgressHarness();
    await h.start(tester);
    await h.player.command('play');
    h.store.writeGate = Completer();
    h.data['position'] = 30000;
    await h.refresh(tester);
    final writing = h.session!.save();
    h.data['position'] = 40000;
    await h.refresh(tester);
    await h.close(tester);
    h.store.writeGate!.complete();
    await writing;
    await tester.pump();
    expect(h.store.values[h.id.key]!.position, 40000);
  });

  for (final choice in ['继续观看', '从头播放', '返回列表', '清除会话']) {
    testWidgets('resume dialog handles $choice before playback', (
      tester,
    ) async {
      final h = ProgressHarness();
      h.store.values[h.id.key] = progress(120000);
      h.setup();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      const capture = bool.fromEnvironment('CAPTURE_PREVIEW');
      if (capture) {
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
      final boundary = GlobalKey();
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: choice == '从头播放' ? Brightness.dark : Brightness.light,
              fontFamily: capture ? 'PreviewChinese' : null,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('打开合成回放'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ClassroomPlayerPage(
                        title: '合成课堂',
                        controller: h.player,
                        identity: h.id,
                        progressStore: h.store,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开合成回放'));
      await tester.pumpAndSettle();
      expect(find.text('继续观看？'), findsOneWidget);
      expect(find.textContaining('02:00'), findsWidgets);
      expect(h.commands, isNot(contains('play')));
      if (capture && ['继续观看', '从头播放'].contains(choice)) {
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '../dist/flutter-preview/resume-${choice == '从头播放' ? 'dark' : 'light'}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      if (choice == '清除会话') {
        await h.store.clear();
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '继续观看'))
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('返回列表'));
      } else {
        await tester.tap(find.text(choice));
      }
      await tester.pumpAndSettle();
      if (choice == '返回列表' || choice == '清除会话') {
        expect(find.text('打开合成回放'), findsOneWidget);
        if (choice == '清除会话') {
          expect(h.store.values, isEmpty);
        } else {
          expect(h.store.values[h.id.key]!.position, 120000);
        }
        expect(h.commands, isNot(contains('play')));
      } else {
        expect(h.data['position'], choice == '继续观看' ? 120000 : 0);
        expect(h.commands, contains('play'));
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'small landscape keeps progress warning and media error controls reachable',
    (tester) async {
      final h = ProgressHarness();
      h.data['error'] = 'FORBIDDEN';
      h.store.failRead = true;
      h.setup();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (_) async => null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      tester.view.physicalSize = const Size(640, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: ClassroomPlayerPage(
            title: '合成课堂',
            controller: h.player,
            identity: h.id,
            progressStore: h.store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byTooltip('全屏'), 160);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('全屏'));
      await tester.pumpAndSettle();
      expect(find.textContaining('本机进度未能读取'), findsOneWidget);
      expect(find.textContaining('学校暂未允许观看'), findsOneWidget);
      expect(
        tester.getRect(find.byTooltip('退出全屏')).bottom,
        lessThanOrEqualTo(320),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('school session clear synchronously invalidates progress epoch', (
    tester,
  ) async {
    const channel = MethodChannel('cn.bucm.campus/school');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp(
        'synthetic-progress-logout-',
      );
      messenger.setMockMethodCallHandler(paths, (_) async => dir.path);
      try {
        final epoch = ClassroomPlaybackProgressStore.shared.revision;
        final cleared = SchoolAdapter().clearSession();
        expect(ClassroomPlaybackProgressStore.shared.revision, epoch + 1);
        await cleared;
        expect(
          await File('${dir.path}/classroom-progress-v1.json').exists(),
          isFalse,
        );
      } finally {
        messenger.setMockMethodCallHandler(paths, null);
        await dir.delete(recursive: true);
      }
    });
  });

  testWidgets(
    'course playback checks native preparation before loading the exact source progress',
    (tester) async {
      rootBundle.clear();
      ClassroomSessionCache.shared.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final school = sources.NameImportController()..failSecond = false;
      InAppWebViewPlatform.instance = fake.RecoveryPlatform(school);
      final store = MemoryProgress();
      ClassroomPlaybackIdentity key(String id) => ClassroomPlaybackIdentity(
        semester: sources.local.semester,
        courseId: id,
        recordId: 'shared-record-id',
      );
      store.values[key('a').key] = progress(60000);
      store.values[key('b').key] = progress(120000);
      final data = snapshot()..['position'] = 0;
      var prepared = false;
      const channel = MethodChannel('cn.bucm.campus/playback');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'prepare') {
          expect(store.reads, 0);
          prepared = true;
        }
        if (call.method == 'seek') {
          data['position'] = (call.arguments as Map)['position'];
        }
        if (call.method == 'play') {
          data.addAll({'playing': true, 'wanted': true});
        }
        return ['begin', 'cancel', 'dispose'].contains(call.method)
            ? null
            : data;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(
        MaterialApp(
          home: ClassroomCoursePage(
            course: sources.local,
            library: MemoryClassroomLibrary(sources.merged()),
            progressStore: store,
            onDetails: (_) {},
            probe: (_) async => const AccessProbe(ProbeState.available),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('来源b的回放'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('来源b的回放'));
      for (var i = 0; i < 30 && find.text('继续观看？').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(seconds: 2));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(prepared, isTrue);
      expect(
        tester
            .widget<ClassroomPlayerPage>(find.byType(ClassroomPlayerPage))
            .identity!
            .key,
        key('b').key,
      );
      expect(find.textContaining('02:00'), findsWidgets);
      await tester.tap(find.text('继续观看'));
      await tester.pumpAndSettle();
      expect(data['position'], 120000);
      expect(store.values[key('a').key]!.position, 60000);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      ClassroomSessionCache.shared.clear();
      expect(tester.takeException(), isNull);
    },
  );
}
