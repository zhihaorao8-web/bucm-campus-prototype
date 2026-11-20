import 'package:campus_schedule/ui/quiet_backdrop.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/main.dart';
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/application/schedule_controller.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/platform/app_platform.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/ui/interface_scale.dart';
import 'schedule_test.dart' show MemoryRepository;
import 'support/memory_appearance.dart';

void main() {
  test(
    'appearance survives a new repository and rejects invalid files without deleting them',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'campus-appearance-synthetic-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final repo = FileAppearanceRepository(directory: folder);
      expect((await repo.load()).mode, ThemeMode.system);
      const settings = AppearanceSettings(
        mode: ThemeMode.dark,
        monet: true,
        accent: 0xff00897b,
        variant: DynamicSchemeVariant.fidelity,
        contrast: .5,
        blur: false,
        floating: false,
        predictiveBack: false,
        swipeBack: false,
        swipePages: true,
        scale: 1.2,
        aurora: false,
        paperTexture: false,
        softCards: true,
        showWeekend: true,
      );
      await repo.save(settings);
      expect(
        (await FileAppearanceRepository(directory: folder).load()).toJson(),
        settings.toJson(),
      );
      final file = File('${folder.path}/appearance-v1.json');
      await file.writeAsString(jsonEncode({...settings.toJson(), 'scale': 7}));
      await expectLater(repo.load(), throwsFormatException);
      expect(await file.exists(), isTrue);
      expect((jsonDecode(await file.readAsString()) as Map)['scale'], 7);
    },
  );
  test(
    'old appearance files gain optional quiet-depth defaults without losing choices',
    () {
      final old = const AppearanceSettings(accent: 0xff00897b).toJson()
        ..remove('aurora')
        ..remove('paperTexture')
        ..remove('softCards')
        ..remove('showWeekend');
      final loaded = AppearanceSettings.fromJson(old);
      expect(loaded.accent, 0xff00897b);
      expect(loaded.aurora, isTrue);
      expect(loaded.paperTexture, isTrue);
      expect(loaded.softCards, isFalse);
      expect(loaded.showWeekend, isFalse);
      expect(
        () => AppearanceSettings.fromJson({...old, 'aurora': 'true'}),
        throwsFormatException,
      );
    },
  );
  test(
    'queued changes retain previous updates; failed writes retain published settings',
    () async {
      final repo = MemoryAppearanceRepository();
      final container = ProviderContainer(
        overrides: [
          ambientMotionEnabledProvider.overrideWithValue(false),
          appearanceRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      await container.read(appearanceProvider.future);
      final controller = container.read(appearanceProvider.notifier);
      await Future.wait([
        controller.change((v) => v.copyWith(mode: ThemeMode.dark)),
        controller.change((v) => v.copyWith(blur: false)),
      ]);
      expect(repo.value.mode, ThemeMode.dark);
      expect(repo.value.blur, isFalse);
      repo.fail = true;
      await expectLater(
        controller.change((v) => v.copyWith(scale: 1.2)),
        throwsStateError,
      );
      expect(container.read(appearanceProvider).requireValue.scale, 1);
      repo.fail = false;
      await controller.change((v) => v.copyWith(glass: false));
      expect(repo.value.glass, isFalse);
    },
  );
  test(
    'accent, color variant, contrast and predictive animation change real theme values',
    () {
      final base = appTheme(Brightness.light);
      final custom = appTheme(
        Brightness.light,
        settings: const AppearanceSettings(accent: 0xffc05072),
      );
      expect(custom.colorScheme.primary, isNot(base.colorScheme.primary));
      final fidelity = appTheme(
        Brightness.light,
        settings: const AppearanceSettings(
          accent: 0xffc05072,
          variant: DynamicSchemeVariant.fidelity,
        ),
      );
      expect(
        fidelity.colorScheme.primaryContainer,
        isNot(custom.colorScheme.primaryContainer),
      );
      expect(
        appTheme(
          Brightness.light,
          settings: const AppearanceSettings(accent: 0xffc05072, contrast: 1),
        ).colorScheme.primary,
        isNot(custom.colorScheme.primary),
      );
      expect(
        appTheme(
          Brightness.light,
          settings: const AppearanceSettings(predictiveBack: false),
        ).pageTransitionsTheme.builders[TargetPlatform.android],
        isA<ZoomPageTransitionsBuilder>(),
      );
      expect(
        base.pageTransitionsTheme.builders[TargetPlatform.android],
        isA<PredictiveBackPageTransitionsBuilder>(),
      );
    },
  );
  testWidgets(
    'root applies theme, system Monet, blur, flat dock and scale with working hit testing',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MemoryAppearanceRepository();
      final container = ProviderContainer(
        overrides: [
          ambientMotionEnabledProvider.overrideWithValue(false),
          appearanceRepositoryProvider.overrideWithValue(repo),
          repositoryProvider.overrideWithValue(
            MemoryRepository(const ScheduleData()),
          ),
          appInfoProvider.overrideWith(
            (ref) async =>
                const AppPlatformInfo(sdk: 36, systemAccent: 0xff00897b),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(appearanceProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CampusApp(),
        ),
      );
      await tester.pumpAndSettle();
      final controller = container.read(appearanceProvider.notifier);
      Color primary() => Theme.of(
        tester.element(find.byKey(const ValueKey('tab-0'))),
      ).colorScheme.primary;
      await controller.change(
        (v) => v.copyWith(mode: ThemeMode.light, accent: 0xffc05072),
      );
      await tester.pumpAndSettle();
      SystemUiOverlayStyle systemBars() => tester
          .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.byKey(const ValueKey('app-system-bars')),
          )
          .value;
      expect(systemBars().statusBarIconBrightness, Brightness.dark);
      expect(systemBars().systemNavigationBarIconBrightness, Brightness.dark);
      final manual = primary();
      await controller.change((v) => v.copyWith(monet: true));
      await tester.pumpAndSettle();
      final system = primary();
      expect(system, isNot(manual));
      await controller.change((v) => v.copyWith(accent: 0xff7e57c2));
      await tester.pumpAndSettle();
      expect(primary(), system);
      await controller.change(
        (v) => v.copyWith(mode: ThemeMode.dark, blur: false, floating: false),
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(
          tester.element(find.byKey(const ValueKey('tab-0'))),
        ).brightness,
        Brightness.dark,
      );
      expect(
        tester
            .widget<BackdropFilter>(find.byKey(const ValueKey('dock-blur')))
            .enabled,
        isFalse,
      );
      expect(
        tester.widget<MiuixTopAppBar>(find.byType(MiuixTopAppBar)).blurred,
        isFalse,
      );
      expect(systemBars().statusBarIconBrightness, Brightness.light);
      expect(systemBars().systemNavigationBarIconBrightness, Brightness.light);
      final dock = tester.getRect(find.byKey(const ValueKey('dock-blur')));
      expect(dock.left, 0);
      expect(dock.right, 390);
      await controller.change((v) => v.copyWith(scale: 1.2));
      await tester.pumpAndSettle();
      expect(
        tester.widget<InterfaceScale>(find.byType(InterfaceScale)).scale,
        1.2,
      );
      expect(
        tester.getSize(find.byType(Scaffold).first).width,
        closeTo(325, .1),
      );
      await tester.tap(find.byKey(const ValueKey('tab-3')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('tab-3')))
            .properties
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'appearance controls save and disabled glass requires floating blur',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MemoryAppearanceRepository();
      final container = ProviderContainer(
        overrides: [
          ambientMotionEnabledProvider.overrideWithValue(false),
          appearanceRepositoryProvider.overrideWithValue(repo),
          repositoryProvider.overrideWithValue(
            MemoryRepository(const ScheduleData()),
          ),
          appInfoProvider.overrideWith(
            (ref) async =>
                const AppPlatformInfo(sdk: 36, systemAccent: 0xff00897b),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(appearanceProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CampusApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外观设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(repo.value.mode, ThemeMode.dark);
      final blur = find.byKey(const ValueKey('appearance-模糊'));
      await tester.scrollUntilVisible(
        blur,
        220,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('settings-route-外观设置')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await Scrollable.ensureVisible(tester.element(blur), alignment: .5);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(blur),
        matchesSemantics(
          label: '模糊\n启用顶栏和底栏的背景模糊',
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(blur);
      await tester.pumpAndSettle();
      expect(repo.value.blur, isFalse);
      expect(
        tester.getSemantics(blur),
        matchesSemantics(
          label: '模糊\n启用顶栏和底栏的背景模糊',
          hasToggledState: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      final node = tester.getSemantics(blur);
      node.owner!.performAction(node.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(repo.value.blur, isTrue);
      await tester.tap(blur);
      await tester.pumpAndSettle();
      expect(repo.value.blur, isFalse);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('appearance-液态玻璃'))),
        matchesSemantics(
          label: '液态玻璃\n悬浮底栏的高光与半透明玻璃效果',
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
        ),
      );
      expect(
        tester
            .widget<MiuixSwitchPreference>(
              find.byKey(const ValueKey('appearance-液态玻璃')),
            )
            .enabled,
        isFalse,
      );
      await tester.drag(
        find.byKey(const ValueKey('edge-back-gesture')),
        const Offset(140, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BackdropFilter>(find.byKey(const ValueKey('dock-blur')))
            .enabled,
        isFalse,
      );
      await container
          .read(appearanceProvider.notifier)
          .change((v) => v.copyWith(swipeBack: false, swipePages: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外观设置'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edge-back-gesture')), findsNothing);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const PageStorageKey('settings-page')),
        const Offset(260, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('tab-2')))
            .properties
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );
}
