import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:campus_schedule/application/classroom_connection_status.dart';
import 'package:campus_schedule/data/classroom_library.dart';
import 'package:campus_schedule/domain/classroom.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/platform/classroom_access.dart';
import 'package:campus_schedule/platform/classroom_session_cache.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/ui/classroom_connection_card.dart';
import 'package:campus_schedule/ui/classroom_course_page.dart';
import 'package:campus_schedule/ui/classroom_recording_timeline.dart';
import 'classroom_recovery_page_test.dart' as fake;
import 'classroom_name_merge_test.dart'
    show local, source, NameImportController;

ClassroomArchive fixture() => ClassroomArchive([
  for (var i = 1; i <= 3; i++)
    RecordingPage.fromJson({
      'course': source('a').toJson(),
      'page': i,
      'pageSize': 1,
      'total': 3,
      'records': [
        {
          'id': 'record-$i',
          'label': '合成回放$i',
          'date': i == 3 ? '2026-10-01' : '2026-09-0$i',
          'place': '',
          'published': true,
        },
      ],
    }),
], DateTime.utc(2026, 10, 2));

class RetainedLibrary extends ClassroomLibrary {
  var value = fixture();
  bool fail = false;
  int epoch = 0;
  bool clearOnRead = false;
  @override
  int get revision => epoch;
  @override
  Future<ClassroomArchive?> lookup(Course course) async {
    if (clearOnRead) {
      epoch++;
      return null;
    }
    if (fail) throw StateError('synthetic storage failure');
    return value;
  }

  @override
  Future<void> save(
    Course course,
    ClassroomArchive archive, {
    required int revision,
  }) async {
    value = archive;
  }
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'connection recovery actions wrap at 320 / large text dark=$dark',
      (tester) async {
        const capture = bool.fromEnvironment('CAPTURE_PREVIEW');
        if (capture) {
          await tester.runAsync(() async {
            final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
            await (FontLoader(
              'PreviewChinese',
            )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
          });
        }
        final boundary = GlobalKey();
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var retries = 0, opens = 0;
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              theme: appTheme(dark ? Brightness.dark : Brightness.light)
                  .copyWith(
                    textTheme:
                        appTheme(
                          dark ? Brightness.dark : Brightness.light,
                        ).textTheme.apply(
                          fontFamily: capture ? 'PreviewChinese' : null,
                        ),
                  ),
              builder: (context, child) => MiuixThemeBridge(
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ClassroomConnectionCard(
                    status: const ClassroomConnectionStatus(
                      ClassroomConnectionPhase.unavailable,
                      '更新失败，已导入目录保留。',
                    ),
                    directoryLabel: '本地目录 · 更新于 2026-10-02 08:00',
                    busy: false,
                    onRetry: () => retries++,
                    onOpenSchool: () => opens++,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('重试连接'));
        await tester.tap(find.text('重试连接'));
        await tester.ensureVisible(find.text('打开学校页面'));
        await tester.tap(find.text('打开学校页面'));
        expect(retries, 1);
        expect(opens, 1);
        expect(find.textContaining('更新于 2026-10-02'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (capture) {
          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final picture = await render.toImage();
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '../dist/flutter-preview/connection-${dark ? 'dark' : 'light'}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            picture.dispose();
          });
        }
      },
    );
  }

  for (final scenario in [
    'serviceUnavailable',
    'authentication',
    'storage',
    'success',
    'cleared',
    'clearedOnRead',
  ]) {
    testWidgets(
      'refresh return retains archive, date and display page: $scenario',
      (tester) async {
        rootBundle.clear();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        ClassroomSessionCache.shared.clear();
        final library = RetainedLibrary();
        final controller =
            (scenario == 'success'
                  ? (NameImportController()..failSecond = false)
                  : fake.RecoveryController())
              ..state = scenario == 'authentication'
                  ? 'authentication'
                  : 'serviceUnavailable';
        if (scenario == 'authentication') {
          controller.snapshotState = 'authentication';
        }
        InAppWebViewPlatform.instance = fake.RecoveryPlatform(controller);
        var probes = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: ClassroomCoursePage(
              course: local,
              date: DateTime(2026, 10, 1),
              library: library,
              onDetails: (_) {},
              probe: (url) async {
                probes++;
                return AccessProbe(
                  url == vpnEntry
                      ? ProbeState.available
                      : ProbeState.unavailable,
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(probes, 0);
        expect(find.text('尚未检查本次连接'), findsOneWidget);
        await tester.ensureVisible(find.text('下一页'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('下一页'));
        await tester.pumpAndSettle();
        final timeline = tester.widget<ClassroomRecordingTimeline>(
          find.byType(ClassroomRecordingTimeline),
        );
        expect(timeline.page, 2);
        await tester.scrollUntilVisible(find.text('刷新录播'), -250);
        await tester.pumpAndSettle();
        await tester.tap(find.text('刷新录播'));
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(seconds: 2));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
          if (scenario == 'success' &&
              find.text('导入完成').evaluate().isNotEmpty) {
            break;
          }
          if (scenario != 'success' &&
              find
                  .textContaining(
                    scenario == 'authentication'
                        ? '请在学校官方页面完成认证'
                        : '学校服务暂时无法连接',
                  )
                  .evaluate()
                  .isNotEmpty) {
            break;
          }
        }
        if (scenario == 'success') {
          expect(find.text('导入完成'), findsOneWidget);
        } else {
          expect(find.text('学校官方页面'), findsOneWidget);
        }
        if (scenario == 'authentication') {
          expect(find.textContaining('请在学校官方页面完成认证'), findsOneWidget);
        }
        if (scenario == 'storage') library.fail = true;
        if (scenario == 'cleared') library.epoch++;
        if (scenario == 'clearedOnRead') library.clearOnRead = true;
        if (scenario != 'success') {
          await tester.tap(find.byTooltip('返回课程'));
          await tester.pumpAndSettle();
        }
        await tester.pageBack();
        await tester.pumpAndSettle();
        if (scenario.startsWith('cleared')) {
          expect(find.byType(ClassroomRecordingTimeline), findsNothing);
          expect(find.textContaining('学校会话或目录已清除'), findsOneWidget);
          expect(find.textContaining('更新于'), findsNothing);
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          ClassroomSessionCache.shared.clear();
          expect(tester.takeException(), isNull);
          return;
        }
        await tester.scrollUntilVisible(
          find.byType(ClassroomRecordingTimeline),
          250,
        );
        await tester.pumpAndSettle();
        final restored = tester.widget<ClassroomRecordingTimeline>(
          find.byType(ClassroomRecordingTimeline),
        );
        expect(restored.page, 2);
        expect(restored.date, DateTime(2026, 10, 1));
        expect(restored.archive, same(library.value));
        await tester.scrollUntilVisible(
          find.byType(ClassroomConnectionCard),
          -250,
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            '更新于 ${schoolTimestamp(library.value.importedAt)}',
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<ClassroomConnectionCard>(
                find.byType(ClassroomConnectionCard),
              )
              .status
              .phase,
          scenario == 'authentication'
              ? ClassroomConnectionPhase.authentication
              : scenario == 'storage'
              ? ClassroomConnectionPhase.failed
              : scenario == 'success'
              ? ClassroomConnectionPhase.updated
              : ClassroomConnectionPhase.unavailable,
        );
        expect(
          find.text(
            scenario == 'authentication'
                ? '需要本人认证'
                : scenario == 'storage'
                ? '本次请求未完成'
                : scenario == 'success'
                ? '目录更新完成'
                : '学校服务暂时无法连接',
          ),
          findsOneWidget,
        );
        expect(
          find.text('重试连接'),
          scenario == 'success' ? findsNothing : findsOneWidget,
        );
        final requests = probes;
        await tester.pump(const Duration(minutes: 2));
        expect(probes, requests);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        ClassroomSessionCache.shared.clear();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
