import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/schedule_repository.dart';
import '../domain/schedule.dart';

final repositoryProvider = Provider<ScheduleRepository>(
  (ref) => FileScheduleRepository(),
);
final scheduleProvider =
    AsyncNotifierProvider<ScheduleController, ScheduleData>(
      ScheduleController.new,
    );

class ScheduleController extends AsyncNotifier<ScheduleData> {
  bool _writing = false;
  @override
  Future<ScheduleData> build() => ref.watch(repositoryProvider).load();
  Future<void> importBatch(List<Course> courses, String summary) async {
    if (_writing) throw StateError('已有导入正在保存，请稍后重试');
    _writing = true;
    try {
      final previous = state.requireValue;
      final next = previous.mergeImport(courses, summary, schoolNow());
      await ref.read(repositoryProvider).save(next);
      state = AsyncData(next);
    } finally {
      _writing = false;
    }
  }

  Future<void> clear() async {
    if (_writing) throw StateError('请等待导入完成');
    _writing = true;
    try {
      await ref.read(repositoryProvider).save(const ScheduleData());
      state = const AsyncData(ScheduleData());
    } finally {
      _writing = false;
    }
  }
}
