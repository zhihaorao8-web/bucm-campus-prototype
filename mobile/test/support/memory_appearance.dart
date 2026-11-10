import 'package:campus_schedule/application/appearance_controller.dart';

class MemoryAppearanceRepository implements AppearanceRepository {
  MemoryAppearanceRepository([this.value = const AppearanceSettings()]);
  AppearanceSettings value;
  bool fail = false;
  @override
  Future<AppearanceSettings> load() async => value;
  @override
  Future<void> save(AppearanceSettings next) async {
    if (fail) throw StateError('Synthetic settings write failure');
    value = next;
  }
}
