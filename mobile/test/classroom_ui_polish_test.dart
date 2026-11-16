import 'dart:io';
import 'dart:ui' as ui;
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/application/classroom_connection_status.dart';
import 'package:campus_schedule/data/classroom_library.dart';
import 'package:campus_schedule/domain/classroom.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/ui/classroom_connection_card.dart';
import 'package:campus_schedule/ui/classroom_recording_timeline.dart';
import 'package:campus_schedule/ui/classroom_section_switch.dart';
import 'package:campus_schedule/ui/course_surface.dart';
import 'package:campus_schedule/ui/quiet_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/memory_appearance.dart';

void main() {
  testWidgets(
    'shared actions keep 48dp targets and recovery access while busy',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var busy = true;
      var opened = 0, retried = 0, refreshed = 0, rematched = 0;
      late StateSetter update;
      await tester.pumpWidget(
        appearanceScope(
          MaterialApp(
            theme: appTheme(Brightness.dark),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      update = setState;
                      return ClassroomConnectionCard(
                        status: const ClassroomConnectionStatus(
                          ClassroomConnectionPhase.failed,
                        ),
                        directoryLabel: '合成离线目录',
                        busy: busy,
                        onOpenSchool: () => opened++,
                        onRetry: () => retried++,
                        onRefresh: () => refreshed++,
                        onRematch: () => rematched++,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      Finder button(String label) => find
          .ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          )
          .first;
      for (final label in ['重试连接', '刷新录播', '重新匹配同名课程']) {
        expect(
          tester.widget<ButtonStyleButton>(button(label)).onPressed,
          isNull,
        );
      }
      await tester.ensureVisible(find.text('打开学校页面'));
      await tester.tap(find.text('打开学校页面'));
      expect(opened, 1);
      update(() => busy = false);
      await tester.pumpAndSettle();
      for (final label in ['重试连接', '刷新录播', '重新匹配同名课程']) {
        await tester.ensureVisible(find.text(label));
        expect(tester.getSize(button(label)).height, greaterThanOrEqualTo(48));
        await tester.tap(find.text(label));
      }
      expect([retried, refreshed, rematched], [1, 1, 1]);
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in [
    'blur-off',
    'glass-off',
    'app-contrast',
    'system-contrast',
  ]) {
    testWidgets('classroom section switch retains opaque fallback: $mode', (
      tester,
    ) async {
      final settings = AppearanceSettings(
        blur: mode != 'blur-off',
        glass: mode != 'glass-off',
        contrast: mode == 'app-contrast' ? 1 : 0,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [currentAppearanceProvider.overrideWithValue(settings)],
          child: MaterialApp(
            theme: appTheme(Brightness.dark),
            home: MediaQuery(
              data: MediaQueryData(highContrast: mode == 'system-contrast'),
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ClassroomSectionSwitch(
                    tabs: const ['录播', '直播'],
                    selectedIndex: 0,
                    onSelected: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final filter = tester.widget<BackdropFilter>(
        find.byKey(const ValueKey('classroom-section-blur')),
      );
      expect(filter.enabled, isFalse);
      final box = (filter.child! as DecoratedBox).decoration as BoxDecoration;
      expect(box.color!.a, 1);
      expect(box.gradient, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'classroom section switch blurs backdrop and switches cleanly dark=$dark scale=$scale',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var selected = 0;
          await tester.pumpWidget(
            appearanceScope(
              MaterialApp(
                theme: appTheme(dark ? Brightness.dark : Brightness.light),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: StatefulBuilder(
                    builder: (context, setState) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: ClassroomSectionSwitch(
                        tabs: const ['录播', '直播'],
                        selectedIndex: selected,
                        onSelected: (v) => setState(() => selected = v),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final filter = tester.widget<BackdropFilter>(
            find.byKey(const ValueKey('classroom-section-blur')),
          );
          expect(filter.enabled, isTrue);
          for (final label in ['录播', '直播']) {
            final text = tester.renderObject<RenderParagraph>(find.text(label));
            expect(text.didExceedMaxLines, isFalse);
          }
          await tester.tap(find.text('直播'));
          await tester.pumpAndSettle();
          expect(selected, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'connection card and playback timeline lay out cleanly at width 320 scale=$scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var refreshes = 0;
        var rematches = 0;
        var played = '';
        final archive = ClassroomArchive([
          RecordingPage.fromJson({
            'course': {
              'id': 'c-1',
              'name': '推拿手法学',
              'teacher': '薛卫国',
              'code': '101',
              'group': '针灸推拿学202402班',
              'semester': '2026-2027-1',
            },
            'page': 1,
            'pageSize': 2,
            'total': 3,
            'records': [
              {
                'id': 'r-1',
                'label': '2026-11-09 08:30-11:15',
                'date': '2026-11-09',
                'place': '针推实践教学实训502室',
                'published': true,
              },
              {
                'id': 'r-2',
                'label': '2026-11-02 08:30-11:15',
                'date': '2026-11-02',
                'place': '针推实践教学实训502室',
                'published': false,
              },
            ],
          }),
          RecordingPage.fromJson({
            'course': {
              'id': 'c-1',
              'name': '推拿手法学',
              'teacher': '薛卫国',
              'code': '101',
              'group': '针灸推拿学202402班',
              'semester': '2026-2027-1',
            },
            'page': 2,
            'pageSize': 2,
            'total': 3,
            'records': [
              {
                'id': 'r-3',
                'label': '2026-10-26 08:30-11:15',
                'date': '2026-10-26',
                'place': '针推实践教学实训502室',
                'published': true,
              },
            ],
          }),
        ], DateTime.utc(2026, 11, 12, 4, 4));

        await tester.pumpWidget(
          appearanceScope(
            MaterialApp(
              theme: appTheme(Brightness.light),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClassroomConnectionCard(
                        status: const ClassroomConnectionStatus(
                          ClassroomConnectionPhase.idle,
                          '尚未检查本次连接',
                        ),
                        directoryLabel: '已导入的录播列表 · 更新于 2026-11-12 12:04 · 可刷新',
                        summaryLabel: '已按名称合并 1 门学校课程（按日期汇总）',
                        busy: false,
                        onRefresh: () => refreshes++,
                        onRematch: () => rematches++,
                      ),
                      const SizedBox(height: 12),
                      ClassroomRecordingTimeline(
                        archive: archive,
                        date: DateTime(2026, 11, 16),
                        page: 1,
                        lessonPage: 1,
                        onPage: (_) {},
                        onLessonPage: (_) {},
                        onPlay: (r, c, _) => played = '$c:${r.id}',
                        busy: false,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('尚未检查本次连接'), findsOneWidget);
        expect(find.text('已按名称合并 1 门学校课程（按日期汇总）'), findsOneWidget);
        await tester.ensureVisible(find.text('刷新录播'));
        await tester.tap(find.text('刷新录播'));
        await tester.ensureVisible(find.text('重新匹配同名课程'));
        await tester.tap(find.text('重新匹配同名课程'));
        expect(refreshes, 1);
        expect(rematches, 1);

        await tester.ensureVisible(find.text('回放来源（1）'));
        await tester.tap(find.text('回放来源（1）'));
        await tester.pumpAndSettle();
        expect(find.text('3 条录播'), findsOneWidget);

        expect(find.text('当天暂无录播，可查看其他日期。'), findsOneWidget);
        expect(find.text('已发布'), findsOneWidget);
        expect(find.text('未发布或暂不可观看'), findsOneWidget);

        await tester.ensureVisible(find.text('2026-11-09 08:30-11:15'));
        await tester.tap(find.text('2026-11-09 08:30-11:15'));
        expect(played, 'c-1:r-1');

        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('optional preview render of polished classroom playback view', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
      await (FontLoader(
        'PreviewChinese',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    });
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(780, 2080);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final archive = ClassroomArchive([
      RecordingPage.fromJson({
        'course': {
          'id': 'c-1',
          'name': '推拿手法学',
          'teacher': '薛卫国',
          'code': '101',
          'group': '针灸推拿学202402班',
          'semester': '2026-2027-1',
        },
        'page': 1,
        'pageSize': 2,
        'total': 2,
        'records': [
          {
            'id': 'r-1',
            'label': '2026-11-09 08:30-11:15',
            'date': '2026-11-09',
            'place': '针推实践教学实训502室',
            'published': true,
          },
          {
            'id': 'r-2',
            'label': '2026-11-02 08:30-11:15',
            'date': '2026-11-02',
            'place': '针推实践教学实训502室',
            'published': true,
          },
        ],
      }),
    ], DateTime.utc(2026, 11, 12, 4, 4));
    for (final dark in [false, true]) {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        appearanceScope(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: appTheme(dark ? Brightness.dark : Brightness.light)
                  .copyWith(
                    textTheme: appTheme(
                      dark ? Brightness.dark : Brightness.light,
                    ).textTheme.apply(fontFamily: 'PreviewChinese'),
                  ),
              home: QuietBackdrop(
                tab: 1,
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  appBar: AppBar(
                    backgroundColor: Colors.transparent,
                    title: const Text('课程课堂'),
                  ),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        QuietCard(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '推拿手法学',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text('薛卫国\n2026-2027-1'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ClassroomSectionSwitch(
                          tabs: const ['录播', '直播'],
                          selectedIndex: 0,
                          onSelected: (_) {},
                        ),
                        const SizedBox(height: 16),
                        ClassroomConnectionCard(
                          status: const ClassroomConnectionStatus(
                            ClassroomConnectionPhase.idle,
                            '尚未检查本次连接',
                          ),
                          directoryLabel:
                              '已导入的录播列表 · 更新于 2026-11-12 12:04 · 可刷新',
                          summaryLabel: '已按名称合并 1 门学校课程（按日期汇总）',
                          busy: false,
                          onRefresh: () {},
                          onRematch: () {},
                        ),
                        const SizedBox(height: 12),
                        ClassroomRecordingTimeline(
                          archive: archive,
                          date: DateTime(2026, 11, 16),
                          page: 1,
                          lessonPage: 1,
                          onPage: (_) {},
                          onLessonPage: (_) {},
                          onPlay: (_, _, _) {},
                          busy: false,
                        ),
                      ],
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
                .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          '../dist/flutter-preview/classroom-polish-${dark ? 'dark' : 'light'}.png',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  }, skip: !const bool.fromEnvironment('CAPTURE_PREVIEW'));
}
