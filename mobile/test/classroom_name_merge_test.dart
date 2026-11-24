import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:campus_schedule/platform/campus_login_navigation.dart';
import 'package:campus_schedule/platform/classroom_access.dart';
import 'package:campus_schedule/platform/classroom_session_cache.dart';
import 'package:campus_schedule/platform/school_adapter.dart';
import 'package:campus_schedule/data/classroom_library.dart';
import 'package:campus_schedule/domain/classroom.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/ui/classroom_course_page.dart';
import 'schedule_test.dart' show sample;
import 'support/memory_classroom_library.dart';
import 'support/memory_appearance.dart';
import 'support/campus_login_webview.dart';
import 'classroom_recovery_page_test.dart' as fake;

class PlaybackLoginPlatform extends fake.RecoveryPlatform {
  PlaybackLoginPlatform(super.controller);
  final login = CampusLoginTestPlatform();
  InAppWebViewKeepAlive? previous;

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    if (params.keepAlive == null) {
      return login.createPlatformInAppWebViewWidget(params);
    }
    if (previous != params.keepAlive) {
      previous = params.keepAlive;
      controller.created = false;
    }
    return super.createPlatformInAppWebViewWidget(params);
  }
}

class NameImportController extends fake.RecoveryController {
  String phase = 'catalog', selectedId = 'a';
  String? pendingState;
  String? firstPlayState;
  bool vpnLoginShell = false;
  int prematureRoutes = 0;
  bool failSecond = true;
  final visited = <String>[];
  final played = <String>[];
  @override
  dynamic getViewId() => 'synthetic-view';
  @override
  Future<WebUri?> getUrl() async => vpnLoginShell ? WebUri(vpnEntry) : null;
  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    if (source == campusVpnLoginScript) return vpnLoginShell;
    if (pendingState != null) {
      if (source.contains('var command =')) {
        final command =
            jsonDecode(
                  RegExp(r'var command = (.*);').firstMatch(source)!.group(1)!,
                )
                as Map;
        if (command['action'] == 'catalogRoute') prematureRoutes++;
        return jsonEncode({
          'state': pendingState == 'serviceAuthentication'
              ? 'navigate'
              : pendingState,
        });
      }
      return jsonEncode({
        'state': switch (pendingState) {
          'authentication' || 'serviceAuthentication' => pendingState,
          _ => 'waiting',
        },
      });
    }
    if (!source.contains('var command =')) {
      return jsonEncode({'state': 'waiting'});
    }
    final command =
        jsonDecode(RegExp(r'var command = (.*);').firstMatch(source)!.group(1)!)
            as Map;
    switch (command['action']) {
      case 'catalogRoute':
        phase = 'catalog';
        return jsonEncode({'state': 'opening'});
      case 'choose':
        selectedId = command['id'] as String;
        visited.add(selectedId);
        phase = 'records';
        return jsonEncode({'state': 'opening'});
      case 'play':
        if (firstPlayState case final state?) {
          firstPlayState = null;
          return jsonEncode({'state': state});
        }
        played.add(selectedId);
        return jsonEncode({'state': 'opening'});
      case 'returnRecords':
        return jsonEncode({'state': 'opening'});
      default:
        if (phase == 'catalog') {
          return jsonEncode({
            'state': 'catalog',
            'courses': [sourceCourse('a'), sourceCourse('b')],
          });
        }
        if (selectedId == 'b' && failSecond) {
          return jsonEncode({'state': 'error'});
        }
        return jsonEncode({
          'state': 'records',
          ...single(selectedId).pages.single.toJson(),
        });
    }
  }

  Map<String, Object?> sourceCourse(String id) => source(id).toJson();
}

class CapturingNameLibrary extends ClassroomLibrary {
  ClassroomArchive value = single('a');
  int saves = 0;
  @override
  Future<ClassroomArchive?> lookup(Course course) async => value;
  @override
  Future<void> save(
    Course course,
    ClassroomArchive archive, {
    required int revision,
  }) async {
    value = archive;
    saves++;
  }
}

final local = Course.fromJson(sample().toJson()..['dataSource'] = 'school');
ClassroomCourse source(String id, {String? name, String? semester}) =>
    ClassroomCourse(
      id: id,
      name: name ?? local.name,
      semester: semester ?? local.semester,
      teacher: '来源教师$id',
      code: 'S$id',
      group: '合成班$id',
    );
ClassroomArchive single(String id, {String? name, String? semester}) =>
    ClassroomArchive([
      RecordingPage.fromJson({
        'course': source(id, name: name, semester: semester).toJson(),
        'page': 1,
        'pageSize': 10,
        'total': 1,
        'records': [
          {
            'id': 'shared-record-id',
            'label': '来源$id的回放',
            'date': '2026-10-01',
            'place': '合成教室',
            'published': true,
            'mediaUrl': 'NEVER_EXPORT',
          },
        ],
      }),
    ], DateTime.utc(2031, 1, 1));
ClassroomArchive merged() => ClassroomArchive.merge([
  single('a'),
  single('b'),
], DateTime.utc(2031, 1, 2));

void main() {
  setUpAll(() async {
    await rootBundle.loadString('assets/classroom.js');
    await rootBundle.loadString('assets/classroom-entry.js');
  });
  for (final (pending, route, outcome) in [
    ('loading', vpnEntry, 'resume'),
    ('navigate', vpnEntry, 'resume'),
    ('authentication', vpnEntry, 'resume'),
    ('serviceAuthentication', vpnEntry, 'resume'),
    ('serviceAuthentication', vpnEntry, 'cancel'),
    ('authentication', classroomProbe, 'resume'),
    ('authentication', classroomProbe, 'cancel'),
    ('authentication', classroomProbe, 'switch-account'),
    ('authentication', classroomProbe, 'forbidden'),
    ('play-command', classroomProbe, 'resume'),
    ('vpn-root', vpnEntry, 'resume'),
  ]) {
    testWidgets('录播任务恢复 $pending $route $outcome', (tester) async {
      final cache = ClassroomSessionCache.shared;
      cache.clear();
      cache.putWorkspace(
        ClassroomSession(
          view: InAppWebViewKeepAlive(),
          records: single('b').pages.single,
          entry: route,
          fetchedAt: DateTime.now(),
        ),
        revision: cache.revision,
      );
      final duringPreparation = pending == 'play-command' || pending == 'vpn-root';
      final controller = NameImportController()
        ..failSecond = false
        ..pendingState = duringPreparation ? null : pending
        ..firstPlayState = switch (pending) {
          'play-command' => 'authentication',
          'vpn-root' => 'navigate',
          _ => null,
        }
        ..vpnLoginShell = pending == 'vpn-root';
      final platform = PlaybackLoginPlatform(controller);
      InAppWebViewPlatform.instance = platform;
      const channel = MethodChannel('cn.bucm.campus/playback');
      final nativeCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        nativeCalls.add(call.method);
        if (call.method == 'prepare') {
          throw PlatformException(code: 'SYNTHETIC_STOP');
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        appearanceScope(
          MaterialApp(
            home: ClassroomCoursePage(
              course: local,
              library: MemoryClassroomLibrary(merged()),
              onDetails: (_) {},
              probe: (_) async =>
                  throw StateError('retained view must be reused'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('来源a的回放'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('来源a的回放'));
      Future<void> ticks(int count) async {
        for (var i = 0; i < count; i++) {
          await tester.pump(const Duration(seconds: 2));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
      }

      await ticks(3);
      expect(controller.prematureRoutes, 0);
      expect(controller.played, isEmpty);
      expect(find.text('学校数据已变化，请刷新列表后重试。'), findsNothing);
      if (pending == 'serviceAuthentication') {
        expect(platform.login.views, isEmpty);
        expect(find.textContaining('登录后继续观看原回放'), findsOneWidget);
        expect(nativeCalls, isNot(contains('prepare')));
        if (outcome == 'cancel') {
          await tester.tap(find.byTooltip('返回课程'));
          await tester.pump();
        }
      } else if (pending == 'authentication' || duringPreparation) {
        final login = platform.login.views.single;
        final target = route == vpnEntry
            ? CampusLoginTarget.vpn
            : CampusLoginTarget.classroom;
        expect(login.params.initialUrlRequest?.url.toString(), target.loginEntry);
        expect(nativeCalls.where((action) => action == 'begin'),
            hasLength(duringPreparation ? 1 : 0));
        if (outcome == 'switch-account') {
          final messenger = tester.binding.defaultBinaryMessenger;
          final folder = await tester.runAsync(
            () => Directory.systemTemp.createTemp('synthetic-classroom-logout-'),
          );
          const paths = MethodChannel('plugins.flutter.io/path_provider');
          messenger.setMockMethodCallHandler(paths, (_) async => folder!.path);
          messenger.setMockMethodCallHandler(SchoolAdapter.channel, (_) async => null);
          addTearDown(() async {
            messenger.setMockMethodCallHandler(paths, null);
            messenger.setMockMethodCallHandler(SchoolAdapter.channel, null);
            await folder!.delete(recursive: true);
          });
          await tester.runAsync(() => SchoolAdapter().clearSession());
        }
        if (outcome == 'cancel' || outcome == 'switch-account') {
          await tester.pageBack();
        } else {
          if (target == CampusLoginTarget.classroom) {
            login.controller.execute = (_) => jsonEncode({'state': 'loading'});
            login.visit(target.entry);
            await ticks(1);
            expect(find.text('校园账号登录'), findsOneWidget);
            expect(nativeCalls, isNot(contains('prepare')));
          }
          controller.phase = 'catalog';
          controller.vpnLoginShell = false;
          login.controller.execute = (script) => target == CampusLoginTarget.vpn
              ? true
              : jsonEncode({'state': 'catalog'});
          login.visit(target.entry);
        }
      }
      controller.pendingState = outcome == 'forbidden' ? 'forbidden' : null;
      await ticks(10);
      expect(controller.visited, outcome == 'resume'
          ? ['a', if (duringPreparation) 'a']
          : isEmpty);
      expect(controller.played, outcome == 'resume' ? ['a'] : isEmpty);
      expect(nativeCalls.where((action) => action == 'prepare'),
          hasLength(outcome == 'resume' ? 1 : 0));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      cache.clear();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('统一导入逐门汇总，第二来源失败保留旧目录，重试复用第一来源并一次保存完整集合', (tester) async {
    final controller = NameImportController();
    final library = CapturingNameLibrary();
    InAppWebViewPlatform.instance = fake.RecoveryPlatform(controller);
    await tester.pumpWidget(
      appearanceScope(
        MaterialApp(
          home: ClassroomCoursePage(
            course: local,
            importCourses: [
              local,
              Course.fromJson(
                local.toJson()
                  ..['id'] = 'unmatched-local'
                  ..['name'] = '未匹配合成课程',
              ),
            ],
            library: library,
            onDetails: (_) {},
            probe: (_) async => const AccessProbe(ProbeState.available),
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    Future<void> ticks(int count) async {
      for (var i = 0; i < count; i++) {
        await tester.pump(const Duration(seconds: 2));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
    }

    await ticks(12);
    expect(controller.visited, ['a', 'b']);
    expect(library.saves, 0);
    expect(library.value.nameMatched, isFalse);
    expect(find.text('失败（1）'), findsOneWidget);
    await tester.ensureVisible(find.text('保留失败项，继续其他课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留失败项，继续其他课程'));
    await ticks(8);
    expect(find.text('未匹配（1）'), findsOneWidget);
    controller.failSecond = false;
    await tester.ensureVisible(find.text('只重试失败项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('只重试失败项'));
    await tester.pump();
    await ticks(12);
    expect(find.text('导入完成'), findsOneWidget);
    expect(controller.visited, ['a', 'b', 'b']);
    expect(library.saves, 1);
    expect(library.value.courses.length, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    ClassroomSessionCache.shared.clear();
    final playback = NameImportController()..failSecond = false;
    InAppWebViewPlatform.instance = fake.RecoveryPlatform(playback);
    const channel = MethodChannel('cn.bucm.campus/playback');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'prepare') {
        throw PlatformException(code: 'SYNTHETIC_STOP');
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      appearanceScope(
        MaterialApp(
          home: ClassroomCoursePage(
            course: local,
            library: library,
            onDetails: (_) {},
            probe: (_) async => const AccessProbe(ProbeState.available),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('下一页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('来源b的回放'));
    await tester.tap(find.text('来源b的回放'));
    await ticks(10);
    expect(playback.visited, ['b']);
    expect(playback.played, ['b']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    ClassroomSessionCache.shared.clear();
    expect(tester.takeException(), isNull);
  });
  test('仅按同学期名称匹配所有老师和班级，拒绝模糊名和冲突ID', () {
    final matches = matchingClassroomCourses(local, [
      source('b'),
      source('a'),
      source('old', semester: '2033-2034-1'),
      source('different', name: '${local.name}（选修）'),
    ]);
    expect(matches.map((c) => c.id), ['a', 'b']);
    expect(
      () => matchingClassroomCourses(local, [
        source('a'),
        source('a', name: '其他课程'),
      ]),
      throwsFormatException,
    );
  });
  test('合并完整来源、保留复合播放身份，拒绝跨名/跨学期/嵌套目录', () {
    final archive = merged();
    expect(archive.total, 2);
    expect(archive.courses.length, 2);
    expect(
      archive.sourcePage('a', 'shared-record-id')!.course.teacher,
      '来源教师a',
    );
    expect(
      archive.sourcePage('b', 'shared-record-id')!.course.teacher,
      '来源教师b',
    );
    expect(archive.displayPage(archive.pages[1]), 2);
    expect(ClassroomArchive.fromJson(archive.toJson()).sources!.length, 2);
    expect(jsonEncode(archive.toJson()), isNot(contains('NEVER_EXPORT')));
    for (final bad in [
      single('b', name: '其他课程'),
      single('b', semester: '2033-2034-1'),
      single('a'),
      archive,
    ]) {
      expect(
        () => ClassroomArchive.merge([single('a'), bad], DateTime.now()),
        throwsFormatException,
      );
    }
  });
  test('旧单来源兼容，新汇总同步同名排课项并供新教师课表项复用', () async {
    final dir = await Directory.systemTemp.createTemp('synthetic-name-merge-');
    try {
      final library = ClassroomLibrary(directory: dir);
      final other = Course.fromJson(
        local.toJson()
          ..['id'] = 'other-slot'
          ..['teacher'] = '其他老师',
      );
      await library.save(local, single('a'), revision: library.revision);
      final file = File('${dir.path}/classroom-library-v1.json');
      final old = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      old['schema'] = 1;
      await file.writeAsString(jsonEncode(old));
      expect((await library.lookup(local))!.nameMatched, isFalse);
      await library.save(other, single('b'), revision: library.revision);
      await library.save(local, merged(), revision: library.revision);
      expect((jsonDecode(await file.readAsString()) as Map)['schema'], 2);
      expect((await library.lookup(other))!.courses.length, 2);
      final changed = Course.fromJson(
        other.toJson()..['id'] = 'new-teacher-slot',
      );
      expect((await library.lookup(changed))!.courses.length, 2);
      expect(
        await library.lookup(
          Course.fromJson(changed.toJson()..['semester'] = '2033-2034-1'),
        ),
        isNull,
      );
      await library.save(
        local,
        ClassroomArchive.merge([single('b')], DateTime.now()),
        revision: library.revision,
      );
      expect((await library.lookup(other))!.courses.single.id, 'b');
      final epoch = library.revision;
      await library.clear();
      await library.save(local, merged(), revision: epoch);
      expect(await library.lookup(local), isNull);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  testWidgets('离线目录按日期汇总不同来源，同名不同老师均可见且不执行网络检测', (tester) async {
    var probes = 0;
    await tester.pumpWidget(
      appearanceScope(
        MaterialApp(
          home: ClassroomCoursePage(
            course: local,
            library: MemoryClassroomLibrary(merged()),
            onDetails: (_) {},
            probe: (_) async {
              probes++;
              throw StateError('no network');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('已按名称合并 2 门'), findsOneWidget);
    expect(find.text('来源a的回放'), findsOneWidget);
    expect(find.text('来源b的回放'), findsOneWidget);
    expect(find.text('第 1 页 · 共 2 条'), findsOneWidget);
    expect(probes, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
