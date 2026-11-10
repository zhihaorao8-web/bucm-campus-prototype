import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

@immutable
class AppearanceSettings {
  const AppearanceSettings({
    this.mode = ThemeMode.system,
    this.monet = false,
    this.accent = 0xff3482ff,
    this.variant = DynamicSchemeVariant.tonalSpot,
    this.contrast = 0,
    this.blur = true,
    this.floating = true,
    this.glass = true,
    this.predictiveBack = true,
    this.swipeBack = true,
    this.swipePages = false,
    this.scale = 1,
  });
  final ThemeMode mode;
  final bool monet,
      blur,
      floating,
      glass,
      predictiveBack,
      swipeBack,
      swipePages;
  final int accent;
  final DynamicSchemeVariant variant;
  final double contrast, scale;
  AppearanceSettings copyWith({
    ThemeMode? mode,
    bool? monet,
    int? accent,
    DynamicSchemeVariant? variant,
    double? contrast,
    bool? blur,
    bool? floating,
    bool? glass,
    bool? predictiveBack,
    bool? swipeBack,
    bool? swipePages,
    double? scale,
  }) => AppearanceSettings(
    mode: mode ?? this.mode,
    monet: monet ?? this.monet,
    accent: accent ?? this.accent,
    variant: variant ?? this.variant,
    contrast: contrast ?? this.contrast,
    blur: blur ?? this.blur,
    floating: floating ?? this.floating,
    glass: glass ?? this.glass,
    predictiveBack: predictiveBack ?? this.predictiveBack,
    swipeBack: swipeBack ?? this.swipeBack,
    swipePages: swipePages ?? this.swipePages,
    scale: scale ?? this.scale,
  );
  Map<String, Object> toJson() => {
    'schema': 1,
    'mode': mode.name,
    'monet': monet,
    'accent': accent,
    'variant': variant.name,
    'contrast': contrast,
    'blur': blur,
    'floating': floating,
    'glass': glass,
    'predictiveBack': predictiveBack,
    'swipeBack': swipeBack,
    'swipePages': swipePages,
    'scale': scale,
  };
  factory AppearanceSettings.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != 1) throw const FormatException('外观设置版本不支持');
    const defaults = AppearanceSettings();
    final values = {...defaults.toJson(), ...json};
    for (final name in [
      'monet',
      'blur',
      'floating',
      'glass',
      'predictiveBack',
      'swipeBack',
      'swipePages',
    ]) {
      if (values[name] is! bool) throw const FormatException('外观设置格式错误');
    }
    final accent = values['accent'],
        scale = values['scale'],
        contrast = values['contrast'];
    if (accent is! int ||
        accent < 0xff000000 ||
        accent > 0xffffffff ||
        scale is! num ||
        !scale.isFinite ||
        scale < .8 ||
        scale > 1.2 ||
        contrast is! num ||
        !contrast.isFinite ||
        contrast < 0 ||
        contrast > 1) {
      throw const FormatException('外观设置超出范围');
    }
    try {
      return AppearanceSettings(
        mode: ThemeMode.values.byName(values['mode'] as String),
        variant: DynamicSchemeVariant.values.byName(
          values['variant'] as String,
        ),
        monet: values['monet'] as bool,
        accent: accent,
        contrast: contrast.toDouble(),
        scale: scale.toDouble(),
        blur: values['blur'] as bool,
        floating: values['floating'] as bool,
        glass: values['glass'] as bool,
        predictiveBack: values['predictiveBack'] as bool,
        swipeBack: values['swipeBack'] as bool,
        swipePages: values['swipePages'] as bool,
      );
    } on Object {
      throw const FormatException('外观设置格式错误');
    }
  }
}

abstract interface class AppearanceRepository {
  Future<AppearanceSettings> load();
  Future<void> save(AppearanceSettings value);
}

class FileAppearanceRepository implements AppearanceRepository {
  FileAppearanceRepository({this.directory});
  final Directory? directory;
  Future<File> _file() async {
    final folder = directory ?? await getApplicationSupportDirectory();
    await folder.create(recursive: true);
    return File('${folder.path}/appearance-v1.json');
  }

  @override
  Future<AppearanceSettings> load() async {
    final file = await _file();
    if (!await file.exists()) return const AppearanceSettings();
    if (await file.length() > 65536) throw const FormatException('外观设置文件过大');
    return AppearanceSettings.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> save(AppearanceSettings value) async {
    final file = await _file();
    final temporary = File('${file.path}.pending');
    try {
      await temporary.writeAsString(jsonEncode(value.toJson()), flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

final appearanceRepositoryProvider = Provider<AppearanceRepository>(
  (ref) => FileAppearanceRepository(),
);
final appearanceProvider =
    AsyncNotifierProvider<AppearanceController, AppearanceSettings>(
      AppearanceController.new,
    );
final currentAppearanceProvider = Provider<AppearanceSettings>(
  (ref) =>
      ref.watch(appearanceProvider).asData?.value ?? const AppearanceSettings(),
);

class AppearanceController extends AsyncNotifier<AppearanceSettings> {
  Future<void> _pending = Future.value();
  @override
  Future<AppearanceSettings> build() =>
      ref.watch(appearanceRepositoryProvider).load();
  Future<void> change(AppearanceSettings Function(AppearanceSettings) change) {
    final next = _pending.then((_) async {
      final previous = state.requireValue;
      final value = change(previous);
      await ref.read(appearanceRepositoryProvider).save(value);
      state = AsyncData(value);
    });
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}
