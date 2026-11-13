import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'ui/app_shell.dart';
import 'ui/app_theme.dart';
import 'application/appearance_controller.dart';
import 'platform/app_platform.dart';
import 'ui/interface_scale.dart';
import 'ui/app_icons.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerAppIconLicenses();
  // The plugin's debug event logger may include navigation URLs or page messages.
  PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
  runApp(const ProviderScope(child: CampusApp()));
}

class CampusApp extends ConsumerStatefulWidget {
  const CampusApp({super.key});
  @override
  ConsumerState<CampusApp> createState() => _CampusAppState();
}

class _CampusAppState extends ConsumerState<CampusApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(appInfoProvider);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentAppearanceProvider);
    final info = ref.watch(appInfoProvider).asData?.value;
    return MaterialApp(
      title: '校园课表',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: settings.mode,
      theme: appTheme(
        Brightness.light,
        settings: settings,
        systemAccent: info?.systemAccent,
      ),
      darkTheme: appTheme(
        Brightness.dark,
        settings: settings,
        systemAccent: info?.systemAccent,
      ),
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          key: const ValueKey('app-system-bars'),
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarIconBrightness: dark
                    ? Brightness.light
                    : Brightness.dark,
              ),
          child: InterfaceScale(
            scale: settings.scale,
            child: MiuixThemeBridge(child: child!),
          ),
        );
      },
      home: const AppShell(),
    );
  }
}
