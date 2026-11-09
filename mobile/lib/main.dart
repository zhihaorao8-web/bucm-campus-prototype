import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'ui/app_shell.dart';
import 'ui/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The plugin's debug event logger may include navigation URLs or page messages.
  PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
  runApp(const ProviderScope(child: CampusApp()));
}

class CampusApp extends StatelessWidget {
  const CampusApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '校园课表',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: appTheme(Brightness.light),
    darkTheme: appTheme(Brightness.dark),
    builder: (context, child) => MiuixThemeBridge(child: child!),
    home: const AppShell(),
  );
}
