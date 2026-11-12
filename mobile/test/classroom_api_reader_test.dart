import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/platform/classroom_api_reader.dart';
import 'package:campus_schedule/domain/classroom.dart';

const c = ClassroomCourse(
  id: 'a',
  name: '合成课程',
  teacher: '合成教师',
  code: 'S1',
  group: 'G1',
  semester: '2030-2031-1',
);
Map<String, dynamic> recordPage(int page, {int total = 11}) => {
  'state': 'records',
  'course': c.toJson(),
  'page': page,
  'pageSize': 10,
  'total': total,
  'records': List.generate(
    page == 1 ? 10 : 1,
    (i) => {
      'id': '${(page - 1) * 10 + i}',
      'label': '合成录播',
      'date': '2030-09-02',
      'place': '合成教室',
      'published': true,
    },
  ),
};
void main() {
  test(
    'new same-name source rejects stale grouping before reading pages',
    () async {
      final calls = <String>[];
      final reader = ClassroomApiReader((cmd) async {
        calls.add(cmd['action'] as String);
        return {
          'state': 'catalog',
          'semester': c.semester,
          'courses': [
            c.toJson(),
            {...c.toJson(), 'id': 'new'},
          ],
        };
      });
      await expectLater(
        reader.read(semester: c.semester, courses: [c], active: () => true),
        throwsA(isA<ClassroomApiFailure>()),
      );
      expect(calls, ['catalog', 'cancel']);
    },
  );
  test(
    'retry validates cached source but does not request its completed pages',
    () async {
      final calls = <String>[];
      final reader = ClassroomApiReader((cmd) async {
        calls.add(cmd['action'] as String);
        return {
          'state': 'catalog',
          'semester': c.semester,
          'courses': [c.toJson()],
        };
      });
      expect(
        await reader.read(
          semester: c.semester,
          courses: [c],
          skipCourseIds: {c.id},
          active: () => true,
        ),
        isEmpty,
      );
      expect(calls, ['catalog', 'cancel']);
    },
  );
  test(
    'two pages are collected without navigation and context is released',
    () async {
      final calls = <Map<String, Object>>[];
      final reader = ClassroomApiReader((cmd) async {
        calls.add(cmd);
        return switch (cmd['action']) {
          'catalog' => {
            'state': 'catalog',
            'semester': c.semester,
            'courses': [c.toJson()],
          },
          'records' => recordPage(cmd['page'] as int),
          _ => {'state': 'cancelled'},
        };
      });
      final pages = await reader.read(
        semester: c.semester,
        courses: [c],
        active: () => true,
      );
      expect(pages!.length, 2);
      expect(calls.map((c) => c['action']), [
        'catalog',
        'records',
        'records',
        'cancel',
      ]);
    },
  );
  test('unsupported capability alone permits fallback', () async {
    final reader = ClassroomApiReader(
      (cmd) async => {
        'state': cmd['action'] == 'catalog' ? 'unsupported' : 'cancelled',
      },
    );
    expect(
      await reader.read(semester: c.semester, courses: [c], active: () => true),
      isNull,
    );
  });
  for (final state in ['authentication', 'forbidden', 'error', 'timeout']) {
    test('$state stops without fallback', () async {
      final reader = ClassroomApiReader((cmd) async => {'state': state});
      await expectLater(
        reader.read(semester: c.semester, courses: [c], active: () => true),
        throwsA(isA<ClassroomApiFailure>()),
      );
    });
  }
  for (final corruption in ['total', 'duplicate', 'source']) {
    test(
      'reject $corruption on final page without returning partial data',
      () async {
        final reader = ClassroomApiReader((cmd) async {
          if (cmd['action'] == 'catalog') {
            return {
              'state': 'catalog',
              'semester': c.semester,
              'courses': [c.toJson()],
            };
          }
          if (cmd['action'] == 'cancel') return {'state': 'cancelled'};
          final p = recordPage(cmd['page'] as int);
          if (cmd['page'] == 2) {
            if (corruption == 'total') p['total'] = 12;
            if (corruption == 'duplicate') {
              (p['records'] as List).first['id'] = '0';
            }
            if (corruption == 'source') {
              p['course'] = {...c.toJson(), 'id': 'other'};
            }
          }
          return p;
        });
        await expectLater(
          reader.read(semester: c.semester, courses: [c], active: () => true),
          throwsA(isA<ClassroomApiFailure>()),
        );
      },
    );
  }
  test(
    'cancel after response prevents next request and releases context',
    () async {
      var active = true;
      final calls = <String>[];
      final reader = ClassroomApiReader((cmd) async {
        calls.add(cmd['action'] as String);
        if (cmd['action'] == 'catalog') {
          active = false;
          return {
            'state': 'catalog',
            'semester': c.semester,
            'courses': [c.toJson()],
          };
        }
        return {'state': 'cancelled'};
      });
      await expectLater(
        reader.read(semester: c.semester, courses: [c], active: () => active),
        throwsA(isA<ClassroomApiFailure>()),
      );
      expect(calls, ['catalog', 'cancel']);
    },
  );
}
