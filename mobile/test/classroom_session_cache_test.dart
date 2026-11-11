import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:campus_schedule/domain/classroom.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/platform/classroom_session_cache.dart';
import 'schedule_test.dart' show sample;

void main() {
  late DateTime now;
  late List<InAppWebViewKeepAlive> released;
  late ClassroomSessionCache cache;
  setUp(() {
    now = DateTime.utc(2032, 1, 1);
    released = [];
    cache = ClassroomSessionCache(
      clock: () => now,
      release: (view) async {
        released.add(view);
      },
    );
  });
  tearDown(() => cache.clear());
  ClassroomSession session({DateTime? fetchedAt}) => ClassroomSession(
    view: InAppWebViewKeepAlive(),
    entry: 'https://qhz.bucm.edu.cn/cc/',
    fetchedAt: fetchedAt ?? now,
    offset: 120,
    records: RecordingPage.fromJson({
      'course': {
        'id': 'school-synthetic',
        'name': '合成课程',
        'teacher': '教师',
        'code': 'S1',
        'group': '示例班',
        'semester': sample().semester,
      },
      'page': 2,
      'pageSize': 10,
      'total': 11,
      'records': [],
    }),
  );
  void save(Course course, ClassroomSession value) =>
      cache.put(course, value, revision: cache.revision);

  test('短时取用保留列表分页位置，只能取得一次且不释放正在使用的上下文', () {
    final value = session();
    save(sample(), value);
    now = now.add(const Duration(minutes: 1));
    expect(cache.take(sample()), same(value));
    expect(value.records.page, 2);
    expect(value.offset, 120);
    expect(cache.take(sample()), isNull);
    cache.clear();
    expect(released, isEmpty);
    cache.release(value.view);
  });
  test('反复退出重进不会延长有效期，五分钟边界释放且重新获取', () {
    final value = session();
    save(sample(), value);
    now = now.add(const Duration(minutes: 4));
    final taken = cache.take(sample())!;
    save(sample(), taken);
    now = now.add(const Duration(minutes: 1));
    expect(cache.take(sample()), isNull);
    expect(released, [value.view]);
  });
  test('仅保留最近两门课程，取用后返回更新淘汰顺序', () {
    final a = sample(id: 'a'), b = sample(id: 'b'), c = sample(id: 'c');
    final av = session(), bv = session(), cv = session();
    save(a, av);
    save(b, bv);
    save(a, cache.take(a)!);
    save(c, cv);
    expect(released, [bv.view]);
    expect(cache.take(b), isNull);
    expect(cache.take(a), same(av));
    cache.release(av.view);
  });
  test('学期、课程ID和名称隔离，名称空白规范化后可复用', () {
    final a = sample(), value = session();
    save(a, value);
    expect(cache.take(sample(id: 'other')), isNull);
    expect(cache.take(sample(term: '2032-2033-1')), isNull);
    expect(cache.take(Course.fromJson(a.toJson()..['name'] = '其他课程')), isNull);
    expect(
      cache.take(Course.fromJson(a.toJson()..['name'] = '　合成课程　')),
      same(value),
    );
    cache.release(value.view);
  });
  test('清除登录或重新导入后释放缓存，旧页面迟到保存也被拒绝', () {
    final revision = cache.revision;
    final idle = session(), active = session();
    save(sample(), idle);
    cache.clear();
    cache.put(sample(), active, revision: revision);
    expect(cache.take(sample()), isNull);
    expect(released, [idle.view, active.view]);
  });
  test('统一导入工作页面仅可独占取用，不冒充任一课程的录播列表', () {
    final value = session();
    cache.putWorkspace(value, revision: cache.revision);
    expect(cache.take(sample()), isNull);
    expect(cache.takeWorkspace(), same(value));
    expect(cache.takeWorkspace(), isNull);
    cache.clear();
    expect(released, isEmpty);
    cache.release(value.view);
  });
  test('时钟倒退和过期写入不复用，上下文仅释放一次', () {
    final value = session();
    save(sample(), value);
    now = now.subtract(const Duration(seconds: 1));
    expect(cache.take(sample()), isNull);
    cache.clear();
    expect(released, [value.view]);
    final expired = session(
      fetchedAt: now.subtract(const Duration(minutes: 6)),
    );
    save(sample(), expired);
    expect(cache.take(sample()), isNull);
    expect(released, [value.view, expired.view]);
  });
  testWidgets('空闲缓存到期自动释放原生资源，无需再次打开课程', (tester) async {
    final value = session();
    save(sample(), value);
    now = now.add(const Duration(minutes: 5));
    await tester.pump(const Duration(minutes: 5));
    expect(released, [value.view]);
    expect(cache.take(sample()), isNull);
  });
}
