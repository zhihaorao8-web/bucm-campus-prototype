import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/data/classroom_library.dart';
import 'package:campus_schedule/data/classroom_timeline.dart';
import 'package:campus_schedule/domain/classroom.dart';
import 'package:campus_schedule/ui/classroom_recording_timeline.dart';

ClassroomArchive source(String id) => ClassroomArchive([
  for (var page = 1; page <= 2; page++)
    RecordingPage.fromJson({
      'course': {
        'id': id,
        'name': '合成课程',
        'teacher': '教师$id',
        'code': '',
        'group': '合成班',
        'semester': '2030-2031-1',
      },
      'page': page,
      'pageSize': 1,
      'total': 2,
      'records': [
        {
          'id': page == 2 ? 'same-id' : 'older-$id',
          'label': '$id-$page',
          'date': page == 2 ? '2030-09-09' : '2030-09-02',
          'place': '',
          'published': true,
        },
      ],
    }),
], DateTime.utc(2030, 9, 10));
void main() {
  final archive = ClassroomArchive.merge([
    source('b'),
    source('a'),
  ], DateTime.utc(2030, 9, 10));
  testWidgets('optional synthetic timeline previews', (tester) async {
    await tester.runAsync(() async {
      final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
      final icons = await File(
        '../build/toolchain/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(icons)))).load();
      await (FontLoader(
        'PreviewChinese',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final dark in [false, true]) {
      tester.view.physicalSize = Size(dark ? 320 : 390, 844);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme(dark ? Brightness.dark : Brightness.light).copyWith(
              textTheme: appTheme(
                dark ? Brightness.dark : Brightness.light,
              ).textTheme.apply(fontFamily: 'PreviewChinese'),
            ),
            builder: (context, child) => MiuixThemeBridge(child: child!),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(dark ? 1.5 : 1)),
                child: Scaffold(
                  appBar: AppBar(title: const Text('合成录播预览')),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: ClassroomRecordingTimeline(
                      archive: archive,
                      date: DateTime(2030, 9, 9),
                      busy: false,
                      page: 1,
                      lessonPage: 1,
                      onPage: (_) {},
                      onLessonPage: (_) {},
                      onPlay: (_, _, _) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          '../build/timeline-preview-${dark ? 'dark' : 'light'}.png',
        );
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  }, skip: !const bool.fromEnvironment('CAPTURE_TIMELINE'));

  test(
    'date order spans source pages and keeps compound playback identities',
    () {
      final entries = classroomTimeline(archive);
      expect(entries.map((entry) => '${entry.course.id}:${entry.record.id}'), [
        'a:same-id',
        'b:same-id',
        'a:older-a',
        'b:older-b',
      ]);
      final lesson = recordingsOnDate(entries, DateTime(2030, 9, 9));
      expect(lesson.length, 2);
      expect(lesson.map((entry) => entry.page.page), everyElement(2));
      expect(recordingsOnDate(entries, DateTime(2030, 9, 10)), isEmpty);
    },
  );
  testWidgets(
    'selected date finds records across original pages and plays exact source',
    (tester) async {
      var lessonPage = 1;
      String? played;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: ClassroomRecordingTimeline(
                  archive: archive,
                  date: DateTime(2030, 9, 9),
                  busy: false,
                  page: 1,
                  lessonPage: lessonPage,
                  onPage: (_) {},
                  onLessonPage: (value) => setState(() => lessonPage = value),
                  onPlay: (record, id, _) => played = '$id:${record.id}',
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('a-2'), findsOneWidget);
      expect(find.text('b-2'), findsNothing);
      await tester.ensureVisible(find.text('本次下页'));
      await tester.tap(find.text('本次下页'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('b-2'));
      await tester.tap(find.text('b-2'));
      expect(played, 'b:same-id');
      expect(find.textContaining('本次课回放'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
