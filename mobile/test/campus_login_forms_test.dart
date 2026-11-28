import 'dart:io';

import 'package:campus_schedule/design/app_tokens.dart';
import 'package:campus_schedule/platform/campus_native_login.dart';
import 'package:campus_schedule/ui/app_controls.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/ui/campus_login_forms.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// Synthetic-only credentials and notices for widget verification.
const _syntheticAccount = '20260001';
const _syntheticPassword = 'synthetic-pass';
const _syntheticSmsCode = '101010';
const _syntheticPhone = '13800000000';
const _syntheticCaptcha = 'AB12';
const _syntheticMaskedPhone = '138****0000';

Uint8List _syntheticPng({int red = 24, int green = 24, int blue = 24}) {
  const size = 64;
  final scanlines = <int>[];
  for (var y = 0; y < size; y++) {
    scanlines.add(0);
    for (var x = 0; x < size; x++) {
      scanlines.add(red);
      scanlines.add(green);
      scanlines.add(blue);
    }
  }
  final ihdr = <int>[0, 0, 0, size, 0, 0, 0, size, 8, 2, 0, 0, 0];
  final idat = zlib.encode(scanlines);
  int crc32(List<int> bytes) {
    var crc = 0xFFFFFFFF;
    for (final byte in bytes) {
      crc ^= byte;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >>> 1) ^ 0xEDB88320 : (crc >>> 1);
      }
    }
    return crc ^ 0xFFFFFFFF;
  }

  List<int> u32(int v) => [
    (v >> 24) & 0xFF,
    (v >> 16) & 0xFF,
    (v >> 8) & 0xFF,
    v & 0xFF,
  ];

  List<int> chunk(String type, List<int> data) {
    final typeBytes = type.codeUnits;
    return [
      ...u32(data.length),
      ...typeBytes,
      ...data,
      ...u32(crc32([...typeBytes, ...data])),
    ];
  }

  return Uint8List.fromList([
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    ...chunk('IHDR', ihdr),
    ...chunk('IDAT', idat),
    ...chunk('IEND', const []),
  ]);
}

Widget _wrapForm(
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
  bool highContrast = false,
}) => MaterialApp(
  theme: appTheme(brightness),
  locale: const Locale('zh', 'CN'),
  supportedLocales: const [Locale('zh', 'CN')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, content) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
      highContrast: highContrast,
    ),
    child: content!,
  ),
  home: Scaffold(body: SafeArea(child: child)),
);

void _setNarrowViewport(WidgetTester tester, {double keyboardInset = 0}) {
  tester.view.physicalSize = const Size(320, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (keyboardInset > 0) {
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
    addTearDown(tester.view.resetViewInsets);
  }
}

class _StatefulWebStub extends StatefulWidget {
  const _StatefulWebStub({required this.onInit, required this.onTap});

  final VoidCallback onInit;
  final VoidCallback onTap;

  @override
  State<_StatefulWebStub> createState() => _StatefulWebStubState();
}

class _StatefulWebStubState extends State<_StatefulWebStub> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      key: const ValueKey('synthetic-web-button'),
      onPressed: widget.onTap,
      child: const Text('学校官方网页占位'),
    ),
  );
}

void main() {
  testWidgets(
    'CampusPasswordForm defaults remember off, redacts inputs, and submits trimmed account',
    (tester) async {
      final submissions = <(String, String, bool)>[];
      await tester.pumpWidget(
        _wrapForm(
          CampusPasswordForm(
            busy: false,
            onSubmit: (account, password, remember) =>
                submissions.add((account, password, remember)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rememberFinder = find.byKey(
        const ValueKey('campus-password-remember-checkbox'),
      );
      expect(tester.widget<CheckboxListTile>(rememberFinder).value, isFalse);
      expect(find.text('保存账号密码'), findsOneWidget);
      expect(find.textContaining('仅保存在此设备'), findsOneWidget);
      expect(find.textContaining('录播或图书馆座位'), findsOneWidget);
      expect(find.textContaining('学校要求短信验证时，仍需本人完成'), findsOneWidget);

      final accountFinder = find.byKey(
        const ValueKey('campus-password-account-field'),
      );
      final passwordFinder = find.byKey(
        const ValueKey('campus-password-password-field'),
      );
      final accountField = tester.widget<TextField>(accountFinder);
      final passwordField = tester.widget<TextField>(passwordFinder);
      expect(passwordField.obscureText, isTrue);
      expect(accountField.restorationId, isNull);
      expect(passwordField.restorationId, isNull);
      expect(accountField.autocorrect, isFalse);
      expect(passwordField.autocorrect, isFalse);
      expect(accountField.enableSuggestions, isFalse);
      expect(passwordField.enableSuggestions, isFalse);
      expect(accountField.enableIMEPersonalizedLearning, isFalse);
      expect(passwordField.enableIMEPersonalizedLearning, isFalse);
      expect(accountField.autofillHints, isNull);
      expect(passwordField.autofillHints, isNull);

      await tester.enterText(accountFinder, '  $_syntheticAccount  ');
      await tester.enterText(passwordFinder, _syntheticPassword);
      await tester.pump();

      expect(
        accountField.controller.toString(),
        isNot(contains(_syntheticAccount)),
      );
      expect(
        passwordField.controller.toString(),
        isNot(contains(_syntheticPassword)),
      );
      final dump = tester
          .element(find.byType(CampusPasswordForm))
          .toStringDeep();
      expect(dump, isNot(contains(_syntheticAccount)));
      expect(dump, isNot(contains(_syntheticPassword)));

      await tester.tap(find.byKey(const ValueKey('campus-password-submit')));
      await tester.pumpAndSettle();

      expect(submissions, [(_syntheticAccount, _syntheticPassword, false)]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CampusPasswordForm toggles password visibility, moves focus with next, checks remember, and submits on done',
    (tester) async {
      final submissions = <(String, String, bool)>[];
      await tester.pumpWidget(
        _wrapForm(
          CampusPasswordForm(
            busy: false,
            onSubmit: (account, password, remember) =>
                submissions.add((account, password, remember)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final accountFinder = find.byKey(
        const ValueKey('campus-password-account-field'),
      );
      final passwordFinder = find.byKey(
        const ValueKey('campus-password-password-field'),
      );
      final visibilityFinder = find.byKey(
        const ValueKey('campus-password-visibility-toggle'),
      );
      final rememberFinder = find.byKey(
        const ValueKey('campus-password-remember-checkbox'),
      );

      await tester.enterText(accountFinder, _syntheticAccount);
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(
        tester.widget<TextField>(passwordFinder).focusNode?.hasFocus,
        isTrue,
      );

      expect(find.text('显示'), findsOneWidget);
      await tester.tap(visibilityFinder);
      await tester.pump();
      expect(tester.widget<TextField>(passwordFinder).obscureText, isFalse);
      expect(find.text('隐藏'), findsOneWidget);

      await tester.enterText(passwordFinder, _syntheticPassword);
      await tester.tap(rememberFinder);
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(rememberFinder).value, isTrue);

      await tester.showKeyboard(passwordFinder);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(submissions, [(_syntheticAccount, _syntheticPassword, true)]);
      expect(tester.widget<TextField>(passwordFinder).obscureText, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CampusPasswordForm rejects empty and whitespace-only inputs and focuses first invalid field',
    (tester) async {
      var submitCount = 0;
      await tester.pumpWidget(
        _wrapForm(
          CampusPasswordForm(busy: false, onSubmit: (_, _, _) => submitCount++),
        ),
      );
      await tester.pumpAndSettle();

      final accountFinder = find.byKey(
        const ValueKey('campus-password-account-field'),
      );
      final passwordFinder = find.byKey(
        const ValueKey('campus-password-password-field'),
      );
      final submitFinder = find.byKey(const ValueKey('campus-password-submit'));

      await tester.tap(submitFinder);
      await tester.pumpAndSettle();
      expect(submitCount, 0);
      expect(find.text('请输入学号或工号'), findsOneWidget);
      expect(find.text('请输入密码'), findsOneWidget);
      expect(
        tester.widget<TextField>(accountFinder).focusNode?.hasFocus,
        isTrue,
      );

      await tester.enterText(accountFinder, _syntheticAccount);
      await tester.enterText(passwordFinder, '   ');
      await tester.tap(submitFinder);
      await tester.pumpAndSettle();
      expect(submitCount, 0);
      expect(find.text('请输入学号或工号'), findsNothing);
      expect(find.text('请输入密码'), findsOneWidget);
      expect(
        tester.widget<TextField>(passwordFinder).focusNode?.hasFocus,
        isTrue,
      );

      await tester.enterText(accountFinder, '   ');
      await tester.enterText(passwordFinder, _syntheticPassword);
      await tester.tap(submitFinder);
      await tester.pumpAndSettle();
      expect(submitCount, 0);
      expect(find.text('请输入学号或工号'), findsOneWidget);
      expect(find.text('请输入密码'), findsNothing);
      expect(
        tester.widget<TextField>(accountFinder).focusNode?.hasFocus,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CampusPasswordForm prevents duplicate submits when busy, renders errors, clears password token, and disposes controllers',
    (tester) async {
      var submitCount = 0;
      var busy = false;
      String? error;
      var clearPasswordToken = 0;
      late StateSetter updateHost;

      await tester.pumpWidget(
        _wrapForm(
          StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return CampusPasswordForm(
                busy: busy,
                error: error,
                clearPasswordToken: clearPasswordToken,
                onSubmit: (_, _, _) {
                  submitCount++;
                  setState(() => busy = true);
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final accountFinder = find.byKey(
        const ValueKey('campus-password-account-field'),
      );
      final passwordFinder = find.byKey(
        const ValueKey('campus-password-password-field'),
      );
      final rememberFinder = find.byKey(
        const ValueKey('campus-password-remember-checkbox'),
      );
      final visibilityFinder = find.byKey(
        const ValueKey('campus-password-visibility-toggle'),
      );
      final submitFinder = find.byKey(const ValueKey('campus-password-submit'));

      final accountController = tester
          .widget<TextField>(accountFinder)
          .controller!;
      final passwordController = tester
          .widget<TextField>(passwordFinder)
          .controller!;

      await tester.enterText(accountFinder, _syntheticAccount);
      await tester.enterText(passwordFinder, _syntheticPassword);
      await tester.tap(submitFinder);
      await tester.pump();

      expect(submitCount, 1);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.widget<TextField>(accountFinder).enabled, isFalse);
      expect(tester.widget<TextField>(passwordFinder).enabled, isFalse);
      expect(tester.widget<CheckboxListTile>(rememberFinder).onChanged, isNull);
      expect(tester.widget<TextButton>(visibilityFinder).onPressed, isNull);
      expect(tester.widget<AppActionButton>(submitFinder).onPressed, isNull);

      await tester.tap(submitFinder);
      await tester.tap(rememberFinder);
      await tester.tap(visibilityFinder, warnIfMissed: false);
      await tester.pump();
      expect(submitCount, 1);
      expect(tester.widget<CheckboxListTile>(rememberFinder).value, isFalse);
      expect(tester.widget<TextField>(passwordFinder).obscureText, isTrue);

      updateHost(() {
        busy = false;
        error = '账号或密码有误，请检查后重试';
        clearPasswordToken++;
      });
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('campus-password-error')),
        findsOneWidget,
      );
      expect(find.text('账号或密码有误，请检查后重试'), findsOneWidget);
      expect(accountController.text, _syntheticAccount);
      expect(passwordController.text, isEmpty);
      expect(
        tester.widget<TextField>(passwordFinder).focusNode?.hasFocus,
        isTrue,
      );

      await tester.pumpWidget(const SizedBox());
      expect(() => accountController.addListener(() {}), throwsFlutterError);
      expect(() => passwordController.addListener(() {}), throwsFlutterError);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CampusPasswordForm lays out and scrolls cleanly at 320dp dark 2.0x text scale with keyboard',
    (tester) async {
      _setNarrowViewport(tester, keyboardInset: 244);
      await tester.pumpWidget(
        _wrapForm(
          CampusPasswordForm(
            busy: false,
            error: '学校认证服务暂时不可用，请稍后重试',
            onSubmit: (_, _, _) {},
          ),
          brightness: Brightness.dark,
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      final errorBanner = find.byKey(const ValueKey('campus-password-error'));
      expect(errorBanner, findsOneWidget);
      final errorRect = tester.getRect(errorBanner);
      expect(errorRect.left, greaterThanOrEqualTo(0));
      expect(errorRect.right, lessThanOrEqualTo(320));

      final submitFinder = find.byKey(const ValueKey('campus-password-submit'));
      await tester.ensureVisible(submitFinder);
      await tester.pumpAndSettle();

      final submitRect = tester.getRect(submitFinder);
      expect(submitRect.height, greaterThanOrEqualTo(AppLayout.minTap));
      expect(submitRect.left, greaterThanOrEqualTo(0));
      expect(submitRect.right, lessThanOrEqualTo(320));
      expect(submitRect.bottom, lessThanOrEqualTo(476));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CampusSmsForm validates 6 digits, hides request action when null, submits explicitly, cancels, and disposes controller',
    (tester) async {
      final submitted = <String>[];
      var cancelCount = 0;

      await tester.pumpWidget(
        _wrapForm(
          CampusSmsForm(
            busy: false,
            notice: '验证码将发送至 $_syntheticMaskedPhone',
            onSubmit: submitted.add,
            onCancel: () => cancelCount++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('短信二次验证'), findsOneWidget);
      expect(find.textContaining('6 位短信验证码'), findsOneWidget);
      expect(find.byKey(const ValueKey('campus-sms-notice')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('campus-sms-request-code')),
        findsNothing,
      );

      final codeFinder = find.byKey(const ValueKey('campus-sms-code-field'));
      final submitFinder = find.byKey(const ValueKey('campus-sms-submit'));
      final cancelFinder = find.byKey(const ValueKey('campus-sms-cancel'));
      final codeField = tester.widget<TextField>(codeFinder);
      final codeController = codeField.controller!;
      expect(codeField.restorationId, isNull);
      expect(codeField.autocorrect, isFalse);
      expect(codeField.enableSuggestions, isFalse);
      expect(codeField.enableIMEPersonalizedLearning, isFalse);
      expect(codeField.autofillHints, isNull);

      await tester.tap(submitFinder);
      await tester.pumpAndSettle();
      expect(submitted, isEmpty);
      expect(find.text('请输入 6 位短信验证码'), findsOneWidget);
      expect(codeField.focusNode?.hasFocus, isTrue);

      await tester.enterText(codeFinder, '1234');
      await tester.tap(submitFinder);
      await tester.pumpAndSettle();
      expect(submitted, isEmpty);
      expect(find.text('短信验证码需为 6 位数字'), findsOneWidget);
      expect(codeField.focusNode?.hasFocus, isTrue);

      await tester.enterText(codeFinder, '10a10b1099');
      await tester.pump();
      expect(codeController.text, _syntheticSmsCode);
      expect(submitted, isEmpty);
      expect(codeController.toString(), isNot(contains(_syntheticSmsCode)));
      expect(
        tester.element(find.byType(CampusSmsForm)).toStringDeep(),
        isNot(contains(_syntheticSmsCode)),
      );

      await tester.tap(submitFinder);
      await tester.pumpAndSettle();
      expect(submitted, [_syntheticSmsCode]);

      await tester.tap(cancelFinder);
      await tester.pumpAndSettle();
      expect(cancelCount, 1);

      await tester.pumpWidget(const SizedBox());
      expect(() => codeController.addListener(() {}), throwsFlutterError);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CampusSmsForm supports send/resend availability and keeps cancel usable when busy',
    (tester) async {
      var requestCount = 0;
      var submitCount = 0;
      var cancelCount = 0;
      var busy = false;
      String? error;
      late StateSetter updateHost;

      await tester.pumpWidget(
        _wrapForm(
          StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return CampusSmsForm(
                busy: busy,
                error: error,
                onSubmit: (_) {
                  submitCount++;
                  setState(() => busy = true);
                },
                onRequestCode: () => requestCount++,
                onCancel: () => cancelCount++,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final requestFinder = find.byKey(
        const ValueKey('campus-sms-request-code'),
      );
      final submitFinder = find.byKey(const ValueKey('campus-sms-submit'));
      final cancelFinder = find.byKey(const ValueKey('campus-sms-cancel'));
      final codeFinder = find.byKey(const ValueKey('campus-sms-code-field'));

      expect(
        find.descendant(of: requestFinder, matching: find.text('发送验证码')),
        findsOneWidget,
      );
      await tester.tap(requestFinder);
      await tester.pump();
      expect(requestCount, 1);
      expect(
        find.descendant(of: requestFinder, matching: find.text('重新发送')),
        findsOneWidget,
      );

      await tester.enterText(codeFinder, _syntheticSmsCode);
      await tester.tap(submitFinder);
      await tester.pump();
      expect(submitCount, 1);

      updateHost(() => error = '验证码有误，请确认后重新输入');
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byKey(const ValueKey('campus-sms-error')), findsOneWidget);
      expect(tester.widget<TextField>(codeFinder).enabled, isFalse);
      expect(tester.widget<AppActionButton>(submitFinder).onPressed, isNull);
      expect(tester.widget<AppActionButton>(requestFinder).onPressed, isNull);
      expect(tester.widget<AppActionButton>(cancelFinder).onPressed, isNotNull);

      await tester.tap(submitFinder);
      await tester.tap(requestFinder);
      await tester.tap(cancelFinder);
      await tester.pump();

      expect(submitCount, 1);
      expect(requestCount, 1);
      expect(cancelCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CampusSmsForm adapts to 320dp dark highContrast 2.0x text scale with keyboard',
    (tester) async {
      _setNarrowViewport(tester, keyboardInset: 244);
      await tester.pumpWidget(
        _wrapForm(
          CampusSmsForm(
            busy: false,
            notice: '验证码已发送至 $_syntheticMaskedPhone',
            error: '验证码输入次数过多，请稍后再试',
            onSubmit: (_) {},
            onRequestCode: () {},
            onCancel: () {},
          ),
          brightness: Brightness.dark,
          textScale: 2.0,
          highContrast: true,
        ),
      );
      await tester.pumpAndSettle();

      final requestFinder = find.byKey(
        const ValueKey('campus-sms-request-code'),
      );
      expect(
        find.descendant(of: requestFinder, matching: find.text('重新发送')),
        findsOneWidget,
      );

      for (final key in const [
        ValueKey('campus-sms-notice'),
        ValueKey('campus-sms-error'),
      ]) {
        final rect = tester.getRect(find.byKey(key));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
      }

      for (final key in const [
        ValueKey('campus-sms-submit'),
        ValueKey('campus-sms-request-code'),
        ValueKey('campus-sms-cancel'),
      ]) {
        final finder = find.byKey(key);
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        final rect = tester.getRect(finder);
        expect(rect.height, greaterThanOrEqualTo(AppLayout.minTap));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.bottom, lessThanOrEqualTo(476));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CampusLoginContent preserves WebView state across waiting, password, SMS, and fallback',
    (tester) async {
      var initCount = 0;
      var webTapCount = 0;
      final webView = _StatefulWebStub(
        onInit: () => initCount++,
        onTap: () => webTapCount++,
      );

      await tester.pumpWidget(
        _wrapForm(
          CampusLoginContent(
            webView: webView,
            waitingForSchool: true,
            onOpenOfficialPage: () {},
          ),
        ),
      );
      await tester.pump();
      expect(initCount, 1);
      expect(find.text('正在连接学校统一身份认证…'), findsOneWidget);

      await tester.pumpWidget(
        _wrapForm(
          CampusLoginContent(
            webView: webView,
            waitingForSchool: false,
            nativeForm: CampusPasswordForm(busy: false, onSubmit: (_, _, _) {}),
            onOpenOfficialPage: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(initCount, 1);
      expect(find.byType(CampusPasswordForm), findsOneWidget);

      await tester.pumpWidget(
        _wrapForm(
          CampusLoginContent(
            webView: webView,
            waitingForSchool: false,
            nativeForm: CampusSmsForm(
              busy: false,
              onSubmit: (_) {},
              onCancel: () {},
            ),
            onOpenOfficialPage: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(initCount, 1);
      expect(find.byType(CampusSmsForm), findsOneWidget);

      await tester.pumpWidget(
        _wrapForm(
          CampusLoginContent(webView: webView, waitingForSchool: false),
        ),
      );
      await tester.pumpAndSettle();
      expect(initCount, 1);
      expect(find.byType(CampusPasswordForm), findsNothing);
      expect(find.byType(CampusSmsForm), findsNothing);

      await tester.tap(find.byKey(const ValueKey('synthetic-web-button')));
      await tester.pump();
      expect(webTapCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CampusLoginContent isolates WebView pointer, focus, and semantics while covered',
    (tester) async {
      var webTapCount = 0;
      final webView = _StatefulWebStub(
        onInit: () {},
        onTap: () => webTapCount++,
      );

      void expectWebIsolation({required bool covered}) {
        final ignorePointer = tester.widget<IgnorePointer>(
          find
              .ancestor(
                of: find.byWidget(webView),
                matching: find.byType(IgnorePointer),
              )
              .first,
        );
        final excludeFocus = tester.widget<ExcludeFocus>(
          find
              .ancestor(
                of: find.byWidget(webView),
                matching: find.byType(ExcludeFocus),
              )
              .first,
        );
        final excludeSemantics = tester.widget<ExcludeSemantics>(
          find
              .ancestor(
                of: find.byWidget(webView),
                matching: find.byType(ExcludeSemantics),
              )
              .first,
        );
        expect(ignorePointer.ignoring, covered);
        expect(excludeFocus.excluding, covered);
        expect(excludeSemantics.excluding, covered);
      }

      await tester.pumpWidget(
        _wrapForm(CampusLoginContent(webView: webView, waitingForSchool: true)),
      );
      await tester.pump();
      expectWebIsolation(covered: true);
      await tester.tapAt(tester.getCenter(find.byType(CampusLoginContent)));
      await tester.pump();
      expect(webTapCount, 0);

      await tester.pumpWidget(
        _wrapForm(
          CampusLoginContent(
            webView: webView,
            waitingForSchool: false,
            nativeForm: CampusPasswordForm(busy: false, onSubmit: (_, _, _) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expectWebIsolation(covered: true);
      await tester.tapAt(tester.getCenter(find.byType(CampusLoginContent)));
      await tester.pump();
      expect(webTapCount, 0);

      await tester.pumpWidget(
        _wrapForm(
          CampusLoginContent(webView: webView, waitingForSchool: false),
        ),
      );
      await tester.pumpAndSettle();
      expectWebIsolation(covered: false);
      await tester.tap(find.byKey(const ValueKey('synthetic-web-button')));
      await tester.pump();
      expect(webTapCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CampusLoginContent shows open official page button only when provided and fits 320dp dark 2.0x with keyboard',
    (tester) async {
      _setNarrowViewport(tester, keyboardInset: 244);
      final webView = _StatefulWebStub(onInit: () {}, onTap: () {});
      var officialTaps = 0;

      await tester.pumpWidget(
        _wrapForm(
          CampusLoginContent(webView: webView, waitingForSchool: true),
          brightness: Brightness.dark,
          textScale: 2.0,
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('campus-login-open-official')),
        findsNothing,
      );

      await tester.pumpWidget(
        _wrapForm(
          CampusLoginContent(
            webView: webView,
            waitingForSchool: true,
            onOpenOfficialPage: () => officialTaps++,
          ),
          brightness: Brightness.dark,
          textScale: 2.0,
        ),
      );
      await tester.pump();

      final waitingButton = find.byKey(
        const ValueKey('campus-login-open-official'),
      );
      expect(waitingButton, findsOneWidget);
      final waitingRect = tester.getRect(waitingButton);
      expect(waitingRect.height, greaterThanOrEqualTo(AppLayout.minTap));
      expect(waitingRect.left, greaterThanOrEqualTo(0));
      expect(waitingRect.right, lessThanOrEqualTo(320));
      await tester.tap(waitingButton);
      await tester.pump();
      expect(officialTaps, 1);

      await tester.pumpWidget(
        _wrapForm(
          CampusLoginContent(
            webView: webView,
            waitingForSchool: false,
            nativeForm: CampusPasswordForm(busy: false, onSubmit: (_, _, _) {}),
            onOpenOfficialPage: () => officialTaps++,
          ),
          brightness: Brightness.dark,
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      final formButton = find.byKey(
        const ValueKey('campus-login-open-official'),
      );
      expect(formButton, findsOneWidget);
      final formButtonRect = tester.getRect(formButton);
      expect(formButtonRect.height, greaterThanOrEqualTo(AppLayout.minTap));
      expect(formButtonRect.left, greaterThanOrEqualTo(0));
      expect(formButtonRect.right, lessThanOrEqualTo(320));
      expect(formButtonRect.bottom, lessThanOrEqualTo(476));
      await tester.tap(formButton);
      await tester.pump();
      expect(officialTaps, 2);

      await tester.pumpWidget(
        _wrapForm(
          CampusLoginContent(
            webView: webView,
            waitingForSchool: false,
            nativeForm: CampusPasswordForm(busy: false, onSubmit: (_, _, _) {}),
          ),
          brightness: Brightness.dark,
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('campus-login-open-official')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CampusQrForm covers loading, ready white contrast, explicit save, expired refresh, and client launch states',
    (tester) async {
      _setNarrowViewport(tester);
      final qrBytes = _syntheticPng(red: 12, green: 34, blue: 56);
      var saves = 0;
      var refreshes = 0;
      final launched = <CampusScanClient>[];

      // 1. Loading disables save and shows placeholder.
      await tester.pumpWidget(
        _wrapForm(
          CampusQrForm(
            state: CampusQrState.loading,
            saving: false,
            refreshing: false,
            availableClients: const {
              CampusScanClient.wework,
              CampusScanClient.wechat,
            },
            onSave: () => saves++,
            onRefresh: () => refreshes++,
            onLaunchClient: launched.add,
          ),
          brightness: Brightness.dark,
          textScale: 2.0,
          highContrast: true,
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('campus-qr-loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('campus-qr-image')), findsNothing);
      final disabledSave = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const ValueKey('campus-qr-save')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(disabledSave.onPressed, isNull);
      expect(saves, 0);

      // 2. Ready keeps white surface in dark mode and exports only on tap.
      await tester.pumpWidget(
        _wrapForm(
          CampusQrForm(
            state: CampusQrState.ready,
            qrBytes: qrBytes,
            saving: false,
            refreshing: false,
            notice: '二维码已保存到系统相册',
            availableClients: const {
              CampusScanClient.wework,
              CampusScanClient.wechat,
            },
            onSave: () => saves++,
            onRefresh: () => refreshes++,
            onLaunchClient: launched.add,
          ),
          brightness: Brightness.dark,
          textScale: 2.0,
          highContrast: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(saves, 0);
      final imageFinder = find.byKey(const ValueKey('campus-qr-image'));
      expect(imageFinder, findsOneWidget);
      final qrSurface = tester.widget<Material>(
        find.ancestor(of: imageFinder, matching: find.byType(Material)).first,
      );
      expect(qrSurface.color, Colors.white);

      await tester.ensureVisible(find.byKey(const ValueKey('campus-qr-save')));
      await tester.tap(find.byKey(const ValueKey('campus-qr-save')));
      await tester.pump();
      expect(saves, 1);

      await tester.ensureVisible(
        find.byKey(const ValueKey('campus-qr-launch-wework')),
      );
      await tester.tap(find.byKey(const ValueKey('campus-qr-launch-wework')));
      await tester.ensureVisible(
        find.byKey(const ValueKey('campus-qr-launch-wechat')),
      );
      await tester.tap(find.byKey(const ValueKey('campus-qr-launch-wechat')));
      await tester.pump();
      expect(launched, [CampusScanClient.wework, CampusScanClient.wechat]);

      // 3. Expired + no local client + save error banner fit 320dp dark 2.0x.
      await tester.pumpWidget(
        _wrapForm(
          CampusQrForm(
            state: CampusQrState.expired,
            saving: false,
            refreshing: false,
            error: '无法保存二维码到系统相册',
            availableClients: const {},
            onSave: () => saves++,
            onRefresh: () => refreshes++,
            onLaunchClient: launched.add,
          ),
          brightness: Brightness.dark,
          textScale: 2.0,
          highContrast: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('campus-qr-expired')), findsOneWidget);
      expect(find.byKey(const ValueKey('campus-qr-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('campus-qr-no-client')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('campus-qr-launch-wework')),
        findsNothing,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('campus-qr-expired-refresh')),
      );
      await tester.tap(find.byKey(const ValueKey('campus-qr-expired-refresh')));
      await tester.pump();
      expect(refreshes, 1);
      expect(saves, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CampusMobileForm validates inputs, redacts controllers, respects cooldown, and never auto-sends SMS',
    (tester) async {
      _setNarrowViewport(tester, keyboardInset: 240);
      final captchaBytes = _syntheticPng(red: 90, green: 20, blue: 140);
      var refreshes = 0;
      final smsRequests = <(String, String)>[];
      final submissions = <(String, String)>[];

      Widget buildForm({
        bool busy = false,
        bool sendingSms = false,
        bool captchaLoading = false,
        int cooldown = 0,
        bool canSendSms = true,
        bool smsSent = false,
        int clearCaptchaToken = 0,
        String? error,
      }) => _wrapForm(
        CampusMobileForm(
          busy: busy,
          sendingSms: sendingSms,
          captchaLoading: captchaLoading,
          captchaBytes: captchaBytes,
          cooldownSeconds: cooldown,
          canSendSms: canSendSms,
          smsSent: smsSent,
          clearCaptchaToken: clearCaptchaToken,
          error: error,
          onRefreshCaptcha: () => refreshes++,
          onRequestSms: (phone, captcha) => smsRequests.add((phone, captcha)),
          onSubmit: (phone, code) => submissions.add((phone, code)),
        ),
        brightness: Brightness.dark,
        textScale: 2.0,
        highContrast: true,
      );

      await tester.pumpWidget(buildForm());
      await tester.pumpAndSettle();
      expect(find.text('保存账号密码'), findsNothing);
      expect(smsRequests, isEmpty);

      // Invalid phone + empty captcha block SMS request.
      await tester.enterText(
        find.byKey(const ValueKey('campus-mobile-phone-field')),
        '12345',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('campus-mobile-send-sms')),
      );
      await tester.tap(find.byKey(const ValueKey('campus-mobile-send-sms')));
      await tester.pumpAndSettle();
      expect(find.text('请输入有效的 11 位手机号'), findsOneWidget);
      expect(find.text('请输入图形验证码'), findsOneWidget);
      expect(smsRequests, isEmpty);

      // Enter valid phone + captcha and tap refresh image + send button.
      await tester.enterText(
        find.byKey(const ValueKey('campus-mobile-phone-field')),
        _syntheticPhone,
      );
      await tester.enterText(
        find.byKey(const ValueKey('campus-mobile-captcha-field')),
        _syntheticCaptcha,
      );
      await tester.enterText(
        find.byKey(const ValueKey('campus-mobile-sms-field')),
        _syntheticSmsCode,
      );
      await tester.pump();

      final diagnostics = tester
          .element(find.byType(CampusMobileForm))
          .toStringDeep();
      expect(diagnostics, isNot(contains(_syntheticPhone)));
      expect(diagnostics, isNot(contains(_syntheticCaptcha)));
      expect(diagnostics, isNot(contains(_syntheticSmsCode)));

      await tester.ensureVisible(
        find.byKey(const ValueKey('campus-mobile-captcha-image')),
      );
      await tester.tap(
        find.byKey(const ValueKey('campus-mobile-captcha-image')),
      );
      await tester.pump();
      expect(refreshes, 1);

      await tester.ensureVisible(
        find.byKey(const ValueKey('campus-mobile-send-sms')),
      );
      await tester.tap(find.byKey(const ValueKey('campus-mobile-send-sms')));
      await tester.pump();
      expect(smsRequests, [(_syntheticPhone, _syntheticCaptcha)]);

      // Cooldown disables resend button cleanly and clearCaptchaToken wipes captcha only.
      await tester.pumpWidget(
        buildForm(
          cooldown: 45,
          canSendSms: false,
          smsSent: true,
          clearCaptchaToken: 1,
          error: '图形验证码错误，已刷新，请重新输入。',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('45秒后重新获取'), findsOneWidget);
      final disabledSend = tester.widget<OutlinedButton>(
        find.descendant(
          of: find.byKey(const ValueKey('campus-mobile-send-sms')),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(disabledSend.onPressed, isNull);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('campus-mobile-phone-field')),
            )
            .controller!
            .text,
        _syntheticPhone,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('campus-mobile-captcha-field')),
            )
            .controller!
            .text,
        isEmpty,
      );

      // Submit valid phone + 6-digit SMS code.
      await tester.ensureVisible(
        find.byKey(const ValueKey('campus-mobile-submit')),
      );
      await tester.tap(find.byKey(const ValueKey('campus-mobile-submit')));
      await tester.pump();
      expect(submissions, [(_syntheticPhone, _syntheticSmsCode)]);
      expect(tester.takeException(), isNull);
    },
  );
}
