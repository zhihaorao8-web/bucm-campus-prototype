import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Widget appearanceScope(Widget child) => ProviderScope(
  overrides: [
    currentAppearanceProvider.overrideWithValue(const AppearanceSettings()),
  ],
  child: child,
);

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
