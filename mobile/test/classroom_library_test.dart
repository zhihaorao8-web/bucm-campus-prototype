import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/data/classroom_library.dart';
import 'package:campus_schedule/domain/classroom.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/ui/classroom_course_page.dart';
import 'schedule_test.dart' show sample;
import 'support/memory_classroom_library.dart';
import 'support/memory_appearance.dart';

void main() {
  late Directory directory;
  late ClassroomLibrary library;
  final local = Course.fromJson(sample().toJson()..['dataSource'] = 'school');
  RecordingPage page(
    int index, {
    int total = 3,
    String course = 'school-synthetic',
    List<int>? ids,
  }) => RecordingPage.fromJson({
    'course': {
      'id': course,
      'name': local.name,
      'teacher': '示例教师',
      'code': 'S1',
      'group': '合成班',
      'semester': local.semester,
      'token': 'NEVER_EXPORT',
    },
    'page': index,
    'pageSize': 2,
    'total': total,
    'records': (ids ?? (index == 1 ? [1, 2] : [3]))
        .map(
          (id) => {
            'id': 'synthetic-$id',
            'label': '示例录播$id',
            'date': '2026-10-01',
            'place': '示例教室',
            'published': true,
            'mediaUrl': 'NEVER_EXPORT',
          },
        )
        .toList(),
  });
  ClassroomArchive archive() =>
      ClassroomArchive([page(1), page(2)], DateTime.utc(2031, 1, 1));
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'synthetic-classroom-library-',
    );
    library = ClassroomLibrary(directory: directory);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  test(
    'retired associations are ignored and removed only on explicit clear',
    () async {
      final obsolete = File('${directory.path}/classroom-links-v1.json');
      final pending = File('${obsolete.path}.pending');
      final schedule = File('${directory.path}/schedule-v1.json');
      final appearance = File('${directory.path}/appearance-v1.json');
      await obsolete.writeAsString('synthetic unreadable legacy association');
      await pending.writeAsString('synthetic obsolete pending');
      await schedule.writeAsString('synthetic schedule preserved');
      await appearance.writeAsString('synthetic preferences preserved');
      expect(await library.lookup(local), isNull);
      expect(await obsolete.exists(), isTrue);
      await library.clear();
      expect(await obsolete.exists(), isFalse);
      expect(await pending.exists(), isFalse);
      expect(await schedule.readAsString(), 'synthetic schedule preserved');
      expect(
        await appearance.readAsString(),
        'synthetic preferences preserved',
      );
      await library.clear();
    },
  );
  test(
    'legacy full-width keys remain readable and display original school titles',
    () async {
      final oldLocal = Course.fromJson(local.toJson()..['name'] = '合成课程Ⅱ（方向甲）');
      final data = page(1, total: 1, ids: [1]).toJson();
      (data['course'] as Map)['name'] = oldLocal.name;
      final oldArchive = ClassroomArchive([
        RecordingPage.fromJson(data),
      ], DateTime.utc(2031));
      final oldKey = jsonEncode([
        oldLocal.semester,
        oldLocal.id,
        oldLocal.name,
      ]);
      await File('${directory.path}/classroom-library-v1.json').writeAsString(
        jsonEncode({
          'schema': 1,
          'courses': {oldKey: oldArchive.toJson()},
        }),
      );
      expect(ClassroomLibrary.key(oldLocal), oldKey);
      expect((await library.lookup(oldLocal))?.course.name, oldLocal.name);
      final halfLocal = Course.fromJson(
        oldLocal.toJson()..['name'] = '合成课程Ⅱ(方向甲)',
      );
      await library.save(
        halfLocal,
        ClassroomArchive.merge([oldArchive], DateTime.utc(2031)),
        revision: library.revision,
      );
      expect((await library.lookup(halfLocal))?.course.name, oldLocal.name);
      expect((await library.availability([oldLocal, halfLocal])).length, 2);
    },
  );
  test(
    'local availability distinguishes unknown, empty, unpublished and playable, clearing invalidates badges',
    () async {
      expect(await library.availability([local]), isEmpty);
      var notifications = 0;
      library.changes.addListener(() => notifications++);
      await library.save(
        local,
        ClassroomArchive.merge([archive()], DateTime.utc(2031)),
        revision: library.revision,
      );
      final renamedId = Course.fromJson(
        local.toJson()..['id'] = 'new-local-id',
      );
      final unrelated = Course.fromJson(
        local.toJson()
          ..['id'] = 'other'
          ..['name'] = '其他课程',
      );
      final available = await library.availability([
        local,
        renamedId,
        unrelated,
      ]);
      expect(
        available[ClassroomLibrary.key(local)],
        RecordingAvailability.available,
      );
      expect(
        available[ClassroomLibrary.key(renamedId)],
        RecordingAvailability.available,
      );
      expect(available.containsKey(ClassroomLibrary.key(unrelated)), isFalse);
      final privatePage = page(1, total: 1, ids: [1]).toJson();
      for (final record in privatePage['records'] as List) {
        (record as Map)['published'] = false;
      }
      await library.save(
        local,
        ClassroomArchive([
          RecordingPage.fromJson(privatePage),
        ], DateTime.utc(2031)),
        revision: library.revision,
      );
      expect(
        (await library.availability([local]))[ClassroomLibrary.key(local)],
        RecordingAvailability.unpublished,
      );
      await library.save(
        local,
        ClassroomArchive([page(1, total: 0, ids: [])], DateTime.utc(2031)),
        revision: library.revision,
      );
      expect(
        (await library.availability([local]))[ClassroomLibrary.key(local)],
        RecordingAvailability.empty,
      );
      await library.clear();
      expect(await library.availability([local]), isEmpty);
      expect(notifications, 4);
    },
  );

  test('完整分页可跨实例读取，页码与录播ID映射保留，只持久化白名单字段', () async {
    await library.save(local, archive(), revision: library.revision);
    final restored = await ClassroomLibrary(directory: directory).lookup(local);
    expect(restored!.total, 3);
    expect(restored.pages.length, 2);
    expect(restored.sourcePage('school-synthetic', 'synthetic-3')?.page, 2);
    expect(restored.sourcePage('school-synthetic', 'missing'), isNull);
    final raw = await File(
      '${directory.path}/classroom-library-v1.json',
    ).readAsString();
    expect(raw, isNot(contains('NEVER_EXPORT')));
    expect(raw, isNot(contains('mediaUrl')));
  });
  test('不完整、重复、课程改变或分页总数变化时不接受，已有目录不被改写', () async {
    await library.save(local, archive(), revision: library.revision);
    for (final pages in [
      [page(1)],
      [
        page(1),
        page(2, ids: [2]),
      ],
      [page(1), page(2, course: 'another')],
      [
        page(1),
        page(2, total: 4, ids: [3, 4]),
      ],
    ]) {
      expect(
        () => ClassroomArchive(pages, DateTime.now()),
        throwsFormatException,
      );
    }
    expect((await library.lookup(local))!.total, 3);
  });
  test('空课程可完整导入，单门移除保留其他课程，学期ID名称隔离', () async {
    final other = Course.fromJson(local.toJson()..['id'] = 'another');
    await library.save(local, archive(), revision: library.revision);
    final empty = ClassroomArchive([
      page(1, total: 0, ids: [], course: 'other-school'),
    ], DateTime.now());
    await library.save(other, empty, revision: library.revision);
    expect((await library.lookup(other))!.total, 0);
    expect(
      await library.lookup(
        Course.fromJson(local.toJson()..['semester'] = '2032-2033-1'),
      ),
      isNull,
    );
    expect(
      await library.lookup(Course.fromJson(local.toJson()..['name'] = '其他合成课')),
      isNull,
    );
    await library.remove(local);
    expect(await library.lookup(local), isNull);
    expect((await library.lookup(other))!.total, 0);
  });
  test('退出登录清理目录并拒绝旧导入迟到写回，新代次仍可导入', () async {
    final revision = library.revision;
    await library.save(local, archive(), revision: revision);
    await library.clear();
    await library.save(local, archive(), revision: revision);
    expect(await library.lookup(local), isNull);
    await library.save(local, archive(), revision: library.revision);
    expect((await library.lookup(local))!.total, 3);
  });
  test('损坏文件不会默默删除，合成示例和跨学期写入被拒绝', () async {
    await expectLater(
      library.save(
        Course.fromJson(local.toJson()..['dataSource'] = 'synthetic'),
        archive(),
        revision: library.revision,
      ),
      throwsFormatException,
    );
    await expectLater(
      library.save(
        Course.fromJson(local.toJson()..['semester'] = '2032-2033-1'),
        archive(),
        revision: library.revision,
      ),
      throwsFormatException,
    );
    final file = File('${directory.path}/classroom-library-v1.json');
    await file.writeAsString(jsonEncode({'schema': 99, 'courses': {}}));
    await expectLater(library.lookup(local), throwsFormatException);
    expect(await file.exists(), isTrue);
  });
  test('同一学校课程的多个课表项在单课刷新后共享新目录', () async {
    final other = Course.fromJson(local.toJson()..['id'] = 'second-slot');
    await library.save(local, archive(), revision: library.revision);
    await library.save(other, archive(), revision: library.revision);
    final refreshed = ClassroomArchive([
      page(1, total: 1, ids: [9]),
    ], DateTime.now());
    await library.save(local, refreshed, revision: library.revision);
    expect((await library.lookup(other))!.total, 1);
    expect(
      (await library.lookup(other))!.pages.first.records.single.id,
      'synthetic-9',
    );
  });
  test('队列中的导入在清除登录后不得重新写回旧目录', () async {
    final write = library.save(local, archive(), revision: library.revision);
    final clear = library.clear();
    await Future.wait([write, clear]);
    expect(await library.lookup(local), isNull);
  });
  testWidgets('已导入课程直接显示列表和本地分页，不执行学校访问检测', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await library.save(local, archive(), revision: library.revision);
    });
    final restored = await tester.runAsync(() => library.lookup(local));
    var probes = 0;
    await tester.pumpWidget(
      appearanceScope(
        MaterialApp(
          home: ClassroomCoursePage(
            course: local,
            library: MemoryClassroomLibrary(restored),
            onDetails: (_) {},
            probe: (_) async {
              probes++;
              throw StateError('Must not connect');
            },
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    expect(
      find.text(
        '已导入的录播列表 · 更新于 ${schoolTimestamp(restored!.importedAt)} · 可刷新',
      ),
      findsOneWidget,
    );
    expect(find.text('示例录播1'), findsOneWidget);
    await tester.ensureVisible(find.text('下一页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('示例录播3'), findsOneWidget);
    expect(probes, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
