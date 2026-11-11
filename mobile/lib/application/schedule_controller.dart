import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/schedule_repository.dart';
import '../domain/schedule.dart';

final repositoryProvider = Provider<ScheduleRepository>(
  (ref) => FileScheduleRepository(),
);
final scheduleProvider =
    AsyncNotifierProvider<ScheduleController, ScheduleData>(
      ScheduleController.new,
      retry: (_, _) => null,
    );

class ScheduleController extends AsyncNotifier<ScheduleData> {
  bool _writing = false;
  @override
  Future<ScheduleData> build() => ref.watch(repositoryProvider).load();
  ScheduleData importBaseline({bool recoverUnreadable = false}) {
    if (state.hasError && recoverUnreadable) return const ScheduleData();
    if (state.hasError) throw StateError('请从恢复页面重新导入，或先恢复备份');
    return state.requireValue;
  }

  Future<void> importBatch(
    List<Course> courses,
    String summary, {
    bool recoverUnreadable = false,
  }) async {
    if (_writing) throw StateError('已有导入正在保存，请稍后重试');
    _writing = true;
    try {
      final previous = importBaseline(recoverUnreadable: recoverUnreadable);
      final next = previous.mergeImport(
        courses,
        summary,
        DateTime.now().toUtc(),
      );
      await ref.read(repositoryProvider).save(next);
      state = AsyncData(next);
    } finally {
      _writing = false;
    }
  }

  Future<void> restoreBackup() async {
    if (_writing) throw StateError('请等待导入完成');
    _writing = true;
    try {
      final repository = ref.read(repositoryProvider);
      if (repository is! RecoverableScheduleRepository) {
        throw StateError('当前存储不支持恢复备份');
      }
      final restored = await repository.restoreBackup();
      state = AsyncData(restored);
    } finally {
      _writing = false;
    }
  }

  Future<void> clear() async {
    if (_writing) throw StateError('请等待导入完成');
    _writing = true;
    try {
      final repository = ref.read(repositoryProvider);
      if (repository is RecoverableScheduleRepository) {
        await repository.clearStored();
      } else {
        await repository.save(const ScheduleData());
      }
      state = const AsyncData(ScheduleData());
    } finally {
      _writing = false;
    }
  }
}
