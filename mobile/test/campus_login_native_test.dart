import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:campus_schedule/config/network_policy.dart';
import 'package:campus_schedule/data/classroom_library.dart';
import 'package:campus_schedule/data/classroom_playback_progress.dart';
import 'package:campus_schedule/platform/campus_login_navigation.dart';
import 'package:campus_schedule/platform/campus_native_login.dart';
import 'package:campus_schedule/platform/school_adapter.dart';
import 'package:campus_schedule/ui/campus_login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/campus_login_webview.dart';

// Synthetic-only values for end-to-end native campus login verification.
const _syntheticAccount = '20260001';
const _syntheticAltAccount = '20260002';
const _syntheticPassword = 'synthetic-pass';
const _syntheticNewPassword = 'synthetic-new-pass';
const _syntheticSmsCode = '101010';
const _syntheticAltSmsCode = '654321';
const _syntheticPhone = '13800000000';
const _syntheticCaptcha = 'AB12';
const _syntheticCaptchaRetry = 'CD34';
const _syntheticMaskedPhone = '138****0000';
const _teachingService = 'https://jw.bucm.edu.cn/';
const _teachingCas =
    'https://cas.bucm.edu.cn/cas/login?service=https%3A%2F%2Fjw.bucm.edu.cn%2F';
const _teachingReturn = 'https://jw.bucm.edu.cn/?ticket=ST-synthetic-123';

Uint8List _syntheticPngBytes({int red = 12, int green = 34, int blue = 56}) {
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

String _syntheticPngDataUrl({int red = 12, int green = 34, int blue = 56}) =>
    'data:image/png;base64,${base64Encode(_syntheticPngBytes(red: red, green: green, blue: blue))}';

CampusLoginTestPlatform _installWebPlatform() {
  final platform = CampusLoginTestPlatform();
  final previous = InAppWebViewPlatform.instance;
  InAppWebViewPlatform.instance = platform;
  if (previous != null) {
    addTearDown(() => InAppWebViewPlatform.instance = previous);
  }
  return platform;
}

class _RecordedChannelCall {
  _RecordedChannelCall(this.method, this.arguments);

  final String method;
  final Object? arguments;
}

({
  List<_RecordedChannelCall> credentialCalls,
  List<_RecordedChannelCall> actionCalls,
  List<String> schoolCalls,
  void Function(Future<Object?> Function(MethodCall call)? handler) setHandler,
  void Function(Future<Object?> Function(MethodCall call)? handler)
  setActionsHandler,
})
_installChannelMocks() {
  final credentialCalls = <_RecordedChannelCall>[];
  final actionCalls = <_RecordedChannelCall>[];
  final schoolCalls = <String>[];
  Future<Object?> Function(MethodCall call)? customCredentialHandler;
  Future<Object?> Function(MethodCall call)? customActionsHandler;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final folder = Directory.systemTemp.createTempSync('campus-native-login-');
  const paths = MethodChannel('plugins.flutter.io/path_provider');

  messenger.setMockMethodCallHandler(paths, (_) async => folder.path);
  messenger.setMockMethodCallHandler(CampusNativeLogin.channel, (call) async {
    credentialCalls.add(_RecordedChannelCall(call.method, call.arguments));
    if (customCredentialHandler != null) {
      return customCredentialHandler!(call);
    }
    return call.method == 'hasSaved' ? false : null;
  });
  messenger.setMockMethodCallHandler(CampusNativeLogin.actionsChannel, (
    call,
  ) async {
    actionCalls.add(_RecordedChannelCall(call.method, call.arguments));
    if (customActionsHandler != null) {
      return customActionsHandler!(call);
    }
    return switch (call.method) {
      'availableScanClients' => const {'wework': true, 'wechat': true},
      'saveQrImage' => true,
      'launchScanClient' => 'launched',
      _ => null,
    };
  });
  messenger.setMockMethodCallHandler(SchoolAdapter.channel, (call) async {
    schoolCalls.add(call.method);
    return null;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(paths, null);
    messenger.setMockMethodCallHandler(CampusNativeLogin.channel, null);
    messenger.setMockMethodCallHandler(CampusNativeLogin.actionsChannel, null);
    messenger.setMockMethodCallHandler(SchoolAdapter.channel, null);
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });

  return (
    credentialCalls: credentialCalls,
    actionCalls: actionCalls,
    schoolCalls: schoolCalls,
    setHandler: (handler) => customCredentialHandler = handler,
    setActionsHandler: (handler) => customActionsHandler = handler,
  );
}

Widget _hostApp(
  List<bool> outcomes, {
  CampusLoginTarget target = CampusLoginTarget.teaching,
}) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  supportedLocales: const [Locale('zh', 'CN')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () async => outcomes.add(
            await openCampusLogin(context, target: target, reason: '登录后继续课表操作'),
          ),
          child: const Text('打开登录'),
        ),
      ),
    ),
  ),
);

Future<CampusLoginTestView> _openPage(
  WidgetTester tester,
  CampusLoginTestPlatform platform,
  List<bool> outcomes, {
  CampusLoginTarget target = CampusLoginTarget.teaching,
}) async {
  await tester.pumpWidget(_hostApp(outcomes, target: target));
  await tester.pumpAndSettle();
  await tester.tap(find.text('打开登录'));
  await tester.pump();
  return platform.views.single;
}

Future<void> _submitPassword(
  WidgetTester tester, {
  String account = _syntheticAccount,
  String password = _syntheticPassword,
  bool remember = false,
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('campus-password-account-field')),
    ' $account ',
  );
  await tester.enterText(
    find.byKey(const ValueKey('campus-password-password-field')),
    password,
  );
  if (remember) {
    await tester.tap(
      find.byKey(const ValueKey('campus-password-remember-checkbox')),
    );
    await tester.pump();
  }
  await tester.tap(find.byKey(const ValueKey('campus-password-submit')));
  await tester.pump();
}

Future<void> _submitSms(
  WidgetTester tester, {
  String code = _syntheticSmsCode,
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('campus-sms-code-field')),
    code,
  );
  await tester.tap(find.byKey(const ValueKey('campus-sms-submit')));
  await tester.pump();
}

void main() {
  // Shared queues must be initialized outside each widget test's FakeAsync zone.
  setUpAll(() {
    expect(ClassroomLibrary.shared.revision, greaterThanOrEqualTo(0));
    expect(
      ClassroomPlaybackProgressStore.shared.revision,
      greaterThanOrEqualTo(0),
    );
  });

  test('CampusCredentials redacts values and validates CAS/service contracts', () {
    const credentials = CampusCredentials(
      account: _syntheticAccount,
      password: _syntheticPassword,
    );
    expect(credentials.toString(), 'CampusCredentials(redacted)');
    expect(credentials.toString(), isNot(contains(_syntheticAccount)));
    expect(credentials.toString(), isNot(contains(_syntheticPassword)));

    expect(
      CampusNativeLogin.serviceFor(_teachingCas, CampusLoginTarget.teaching),
      _teachingService,
    );
    expect(
      CampusNativeLogin.serviceFor(
        'https://cas.bucm.edu.cn/cas//login?service=https%3A%2F%2Fjw.bucm.edu.cn%2F',
        CampusLoginTarget.teaching,
      ),
      _teachingService,
    );
    for (final blocked in [
      'https://cas.bucm.edu.cn/cas/login',
      'https://cas.bucm.edu.cn/cas/logout?service=https%3A%2F%2Fjw.bucm.edu.cn%2F',
      'http://cas.bucm.edu.cn/cas/login?service=https%3A%2F%2Fjw.bucm.edu.cn%2F',
      'https://@cas.bucm.edu.cn/cas/login?service=https%3A%2F%2Fjw.bucm.edu.cn%2F',
      'https://cas.bucm.edu.cn/cas/login?service=https%3A%2F%2Fkjyy.bucm.edu.cn%2F',
      '$_teachingCas&service=https%3A%2F%2Fjw.bucm.edu.cn%2F',
    ]) {
      expect(
        CampusNativeLogin.serviceFor(blocked, CampusLoginTarget.teaching),
        isNull,
        reason: blocked,
      );
    }
    expect(
      CampusNativeLogin.serviceFor(_teachingCas, CampusLoginTarget.vpn),
      isNull,
    );

    expect(
      CampusNativeLogin.smsServiceFor(
        'https://cas.bucm.edu.cn/cas/login',
        CampusLoginTarget.teaching,
        _teachingService,
      ),
      _teachingService,
    );
    expect(
      CampusNativeLogin.smsServiceFor(
        _teachingCas,
        CampusLoginTarget.teaching,
        _teachingService,
      ),
      _teachingService,
    );
    expect(
      CampusNativeLogin.smsServiceFor(
        'https://cas.bucm.edu.cn/cas/login?service=https%3A%2F%2Fkjyy.bucm.edu.cn%2F',
        CampusLoginTarget.teaching,
        _teachingService,
      ),
      isNull,
    );

    expect(
      CampusNativeLogin.isServiceReturn(_teachingReturn, _teachingService),
      isTrue,
    );
    expect(
      CampusNativeLogin.isServiceReturn(
        'https://jw.bucm.edu.cn?ticket=ST-1',
        _teachingService,
      ),
      isTrue,
    );
    expect(
      CampusNativeLogin.isServiceReturn(
        'https://qhz.bucm.edu.cn/coursePlatform/?ticket=ST-1#/courseCenter/index?firstMenuId=11',
        SchoolEndpoints.classroomCourses,
      ),
      isTrue,
    );
    for (final invalidReturn in [
      null,
      _teachingService,
      'https://jw.bucm.edu.cn/?ticket=LT-1',
      'https://jw.bucm.edu.cn/?ticket=ST-',
      'https://jw.bucm.edu.cn/?ticket=ST-%20bad',
      'http://jw.bucm.edu.cn/?ticket=ST-1',
      'https://@jw.bucm.edu.cn/?ticket=ST-1',
      'https://jw.bucm.edu.cn:444/?ticket=ST-1',
      'https://i.bucm.edu.cn/?ticket=ST-1',
      'https://jw.bucm.edu.cn/?ticket=ST-1&extra=1',
    ]) {
      expect(
        CampusNativeLogin.isServiceReturn(invalidReturn, _teachingService),
        isFalse,
        reason: '$invalidReturn',
      );
    }

    expect(
      CampusNativeLogin.sanitizeMaskedPhone(' 138****0000 '),
      _syntheticMaskedPhone,
    );
    expect(CampusNativeLogin.sanitizeMaskedPhone('139*****123'), '139*****123');
    expect(CampusNativeLogin.sanitizeMaskedPhone('13812345678'), isNull);
    expect(CampusNativeLogin.sanitizeMaskedPhone('138****00'), isNull);
    expect(CampusNativeLogin.sanitizeMaskedPhone(13800000000), isNull);

    final smsProbe = CampusNativeLogin.parseProbe({
      'form': 'sms',
      'error': 'smsRateLimited',
      'maskedPhone': _syntheticMaskedPhone,
      'smsSent': true,
    });
    expect(smsProbe, isNotNull);
    expect(smsProbe!.form, CampusNativeForm.sms);
    expect(smsProbe.errorKind, CampusNativeErrorKind.smsRateLimited);
    expect(smsProbe.maskedPhone, _syntheticMaskedPhone);
    expect(smsProbe.smsSent, isTrue);

    final passwordProbe = CampusNativeLogin.parseProbe({
      'form': 'password',
      'error': 'invalidPassword',
      'maskedPhone': _syntheticMaskedPhone,
      'smsSent': true,
    });
    expect(passwordProbe, isNotNull);
    expect(passwordProbe!.form, CampusNativeForm.password);
    expect(passwordProbe.errorKind, CampusNativeErrorKind.invalidPassword);
    expect(passwordProbe.maskedPhone, isNull);
    expect(passwordProbe.smsSent, isFalse);

    expect(
      CampusNativeLogin.parseProbe('password')?.form,
      CampusNativeForm.password,
    );
    expect(CampusNativeLogin.parseProbe('sms')?.form, CampusNativeForm.sms);
    expect(CampusNativeLogin.parseProbe({'form': 'other'}), isNull);
    expect(CampusNativeLogin.parseProbe(null), isNull);
  });

  test(
    'credential serial queue blocks stale revisions and isolates errors',
    () async {
      final mocks = _installChannelMocks();
      final events = <String>[];
      final gate = Completer<void>();
      var failFirstClear = true;
      var changeEvents = 0;
      void countChange() => changeEvents++;
      CampusNativeLogin.changes.addListener(countChange);
      addTearDown(() => CampusNativeLogin.changes.removeListener(countChange));

      mocks.setHandler((call) async {
        events.add('start:${call.method}');
        if (call.method == 'save') {
          await gate.future;
        } else if (call.method == 'clear' && failFirstClear) {
          failFirstClear = false;
          throw PlatformException(code: 'IO');
        } else if (call.method == 'hasSaved') {
          events.add('end:${call.method}');
          return true;
        }
        events.add('end:${call.method}');
        return null;
      });

      final staleRevision = CampusNativeLogin.revision;
      final inFlightSave = CampusNativeLogin.save(
        const CampusCredentials(
          account: _syntheticAccount,
          password: _syntheticPassword,
        ),
        revision: staleRevision,
      );
      final firstClear = CampusNativeLogin.clear();
      final supersededHasSaved = CampusNativeLogin.hasSaved();
      final secondClear = CampusNativeLogin.clear();
      final currentHasSaved = CampusNativeLogin.hasSaved();

      // Wait for save call to begin, then unblock it.
      await Future<void>.delayed(Duration.zero);
      expect(events, ['start:save']);
      gate.complete();

      expect(await inFlightSave, isFalse);
      await expectLater(firstClear, throwsA(isA<PlatformException>()));
      expect(await supersededHasSaved, isFalse);
      await secondClear;
      expect(await currentHasSaved, isTrue);

      expect(events, [
        'start:save',
        'end:save',
        'start:clear',
        'start:clear',
        'end:clear',
        'start:hasSaved',
        'end:hasSaved',
      ]);
      expect(changeEvents, greaterThanOrEqualTo(2));

      expect(
        await CampusNativeLogin.save(
          const CampusCredentials(
            account: _syntheticAccount,
            password: _syntheticPassword,
          ),
          revision: staleRevision,
        ),
        isFalse,
      );
      // Skipped stale revision did not dispatch a second save call.
      expect(
        mocks.credentialCalls.where((c) => c.method == 'save'),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'remember unchecked performs zero saves even after full verification',
    (tester) async {
      final platform = _installWebPlatform();
      final mocks = _installChannelMocks();
      final outcomes = <bool>[];
      final view = await _openPage(tester, platform, outcomes);
      view.controller.executeAsync = (body, args) {
        if (args['account'] != null) return true;
        return {'form': 'password', 'error': 'none'};
      };

      view.visit(_teachingCas);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('campus-login-password-form')),
        findsOneWidget,
      );

      await _submitPassword(tester, remember: false);
      view.controller.ready = true;
      view.visit(_teachingReturn);
      await tester.pumpAndSettle();

      expect(outcomes, [true]);
      expect(find.byType(CampusLoginPage), findsNothing);
      expect(mocks.credentialCalls, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'remember checked saves normalized pair once after ST return and service ready',
    (tester) async {
      final platform = _installWebPlatform();
      final mocks = _installChannelMocks();
      final outcomes = <bool>[];
      final view = await _openPage(tester, platform, outcomes);
      view.controller.executeAsync = (body, args) {
        if (args['account'] != null) {
          expect(args['account'], _syntheticAccount);
          expect(args['password'], _syntheticPassword);
          return true;
        }
        return {'form': 'password', 'error': 'none'};
      };

      view.visit(_teachingCas);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('campus-password-account-field')),
        '  $_syntheticAccount  ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('campus-password-password-field')),
        _syntheticPassword,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('campus-password-password-field')),
            )
            .obscureText,
        isTrue,
      );
      expect(
        tester.element(find.byType(CampusLoginPage)).toStringDeep(),
        isNot(contains(_syntheticPassword)),
      );
      await tester.tap(
        find.byKey(const ValueKey('campus-password-remember-checkbox')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('campus-password-submit')));
      await tester.pump();

      view.controller.ready = true;
      view.visit(_teachingReturn);
      await tester.pumpAndSettle();

      expect(outcomes, [true]);
      final saves = mocks.credentialCalls
          .where((c) => c.method == 'save')
          .toList();
      expect(saves, hasLength(1));
      expect(saves.single.arguments, {
        'account': _syntheticAccount,
        'password': _syntheticPassword,
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'SMS challenge hides tabs, omits resend, saves only after SMS + ST return',
    (tester) async {
      final platform = _installWebPlatform();
      final mocks = _installChannelMocks();
      final outcomes = <bool>[];
      final view = await _openPage(tester, platform, outcomes);
      var phase = 'password';
      view.controller.executeAsync = (body, args) {
        if (args['account'] != null) {
          phase = 'sms';
          return true;
        }
        if (args['code'] != null) {
          expect(args['code'], _syntheticSmsCode);
          return true;
        }
        if (phase == 'sms') {
          return {
            'form': 'sms',
            'error': 'none',
            'maskedPhone': _syntheticMaskedPhone,
            'smsSent': true,
          };
        }
        return {'form': 'password', 'error': 'none'};
      };

      view.visit(_teachingCas);
      await tester.pumpAndSettle();
      await _submitPassword(tester, remember: true);

      // Even if destination briefly loads without ST- before SMS, never save yet.
      view.visit('https://cas.bucm.edu.cn/cas/login');
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('campus-login-sms-form-0')),
        findsOneWidget,
      );
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('验证码已发送至 $_syntheticMaskedPhone'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('campus-sms-request-code')),
        findsNothing,
      );
      expect(mocks.credentialCalls, isEmpty);

      await _submitSms(tester, code: _syntheticSmsCode);
      view.controller.ready = true;
      view.visit(_teachingReturn);
      await tester.pumpAndSettle();

      expect(outcomes, [true]);
      expect(
        mocks.credentialCalls.where((c) => c.method == 'save'),
        hasLength(1),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'wrong password preserves account, clears password, and saves after retry',
    (tester) async {
      final platform = _installWebPlatform();
      final mocks = _installChannelMocks();
      final outcomes = <bool>[];
      final view = await _openPage(tester, platform, outcomes);
      var passwordError = 'none';
      view.controller.executeAsync = (body, args) {
        if (args['account'] != null) {
          passwordError = args['password'] == _syntheticNewPassword
              ? 'none'
              : 'invalidPassword';
          return true;
        }
        return {'form': 'password', 'error': passwordError};
      };

      view.visit(_teachingCas);
      await tester.pumpAndSettle();
      await _submitPassword(tester, remember: true);

      view.visit(_teachingCas);
      await tester.pumpAndSettle();

      expect(find.text('账号或密码错误，请修改密码后重试。'), findsOneWidget);
      expect(mocks.credentialCalls, isEmpty);
      final accountField = tester.widget<TextField>(
        find.byKey(const ValueKey('campus-password-account-field')),
      );
      final passwordField = tester.widget<TextField>(
        find.byKey(const ValueKey('campus-password-password-field')),
      );
      expect(accountField.controller!.text.trim(), _syntheticAccount);
      expect(passwordField.controller!.text, isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('campus-password-password-field')),
        _syntheticNewPassword,
      );
      await tester.tap(find.byKey(const ValueKey('campus-password-submit')));
      await tester.pump();
      view.controller.ready = true;
      view.visit(_teachingReturn);
      await tester.pumpAndSettle();

      expect(outcomes, [true]);
      final saves = mocks.credentialCalls
          .where((c) => c.method == 'save')
          .toList();
      expect(saves, hasLength(1));
      expect(saves.single.arguments, {
        'account': _syntheticAccount,
        'password': _syntheticNewPassword,
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'SMS errors (invalid, rate limit, send fail, expired) and cancel perform zero saves',
    (tester) async {
      final platform = _installWebPlatform();
      final mocks = _installChannelMocks();
      final outcomes = <bool>[];
      final view = await _openPage(tester, platform, outcomes);
      var phase = 'password';
      var smsError = 'none';
      var smsDispatches = 0;
      view.controller.executeAsync = (body, args) {
        if (args['account'] != null) {
          phase = 'sms';
          return true;
        }
        if (args['code'] != null) {
          smsDispatches++;
          return true;
        }
        if (phase == 'sms') {
          return {
            'form': 'sms',
            'error': smsError,
            'maskedPhone': _syntheticMaskedPhone,
            'smsSent': false,
          };
        }
        return {'form': 'password', 'error': 'none'};
      };

      view.visit(_teachingCas);
      await tester.pumpAndSettle();
      await _submitPassword(tester, remember: true);
      view.visit(_teachingCas);
      await tester.pumpAndSettle();
      expect(find.text('验证手机号：$_syntheticMaskedPhone'), findsOneWidget);

      // 1. Invalid SMS code clears field and allows retry.
      smsError = 'invalidSmsCode';
      await _submitSms(tester, code: _syntheticSmsCode);
      view.visit(_teachingCas);
      await tester.pumpAndSettle();
      expect(find.text('短信验证码错误，请核对后重试。'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('campus-sms-code-field')),
            )
            .controller!
            .text,
        isEmpty,
      );

      // 2. Rate limited (in-place DOM update).
      smsError = 'smsRateLimited';
      await _submitSms(tester, code: _syntheticAltSmsCode);
      await tester.pump(CampusLoginPolicy.readinessPoll);
      await tester.pumpAndSettle();
      expect(find.text('短信验证次数受限或操作过于频繁，请稍后再试。'), findsOneWidget);

      // 3. Send failed.
      smsError = 'smsSendFailed';
      await _submitSms(tester, code: _syntheticAltSmsCode);
      view.visit(_teachingCas);
      await tester.pumpAndSettle();
      expect(find.text('学校未能发送短信验证码，请稍后重试或打开学校官方页面。'), findsOneWidget);

      // 4. Expired SMS challenge blocks subsequent dispatch.
      smsError = 'smsExpired';
      await _submitSms(tester, code: _syntheticAltSmsCode);
      view.visit(_teachingCas);
      await tester.pumpAndSettle();
      expect(find.text('短信验证码或本次验证已过期，请取消后重新登录。'), findsOneWidget);
      final dispatchesBeforeBlockedSubmit = smsDispatches;
      await _submitSms(tester, code: _syntheticAltSmsCode);
      expect(smsDispatches, dispatchesBeforeBlockedSubmit);

      // 5. Cancel closes route with false and zero saves.
      await tester.tap(find.byKey(const ValueKey('campus-sms-cancel')));
      await tester.pumpAndSettle();
      expect(outcomes, [false]);
      expect(mocks.credentialCalls, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'existing session without ST return and destination without ticket save nothing',
    (tester) async {
      final platform = _installWebPlatform();
      final mocks = _installChannelMocks();
      final outcomes = <bool>[];
      final view = await _openPage(tester, platform, outcomes);
      view.controller.executeAsync = (_, _) => {
        'form': 'password',
        'error': 'none',
      };

      // Already logged in directly at destination.
      view.controller.ready = true;
      view.visit(_teachingService);
      await tester.pumpAndSettle();

      expect(outcomes, [true]);
      expect(mocks.credentialCalls, isEmpty);

      // Returning to destination without ST- after opening CAS also does not save.
      await tester.tap(find.text('打开登录'));
      await tester.pump();
      final view2 = platform.views.last;
      view2.controller.executeAsync = (_, args) => args['account'] != null
          ? true
          : {'form': 'password', 'error': 'none'};
      view2.visit(_teachingCas);
      await tester.pumpAndSettle();
      await _submitPassword(tester, remember: true);
      view2.controller.ready = true;
      view2.visit(_teachingService);
      await tester.pumpAndSettle();

      expect(outcomes, [true, true]);
      expect(mocks.credentialCalls, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'save failure still finishes login with notice and account switch overwrites saved pair',
    (tester) async {
      final platform = _installWebPlatform();
      final mocks = _installChannelMocks();
      mocks.setHandler((call) async {
        if (call.method == 'save') throw PlatformException(code: 'KEYSTORE');
        return null;
      });
      final outcomes = <bool>[];
      final view = await _openPage(tester, platform, outcomes);
      view.controller.executeAsync = (_, args) => args['account'] != null
          ? true
          : {'form': 'password', 'error': 'none'};

      view.visit(_teachingCas);
      await tester.pumpAndSettle();
      await _submitPassword(tester, remember: true);
      view.controller.ready = true;
      view.visit(_teachingReturn);
      await tester.pumpAndSettle();

      expect(outcomes, [true]);
      expect(find.text('已登录，未能在本机保存校园账号密码。'), findsOneWidget);

      // Account switch succeeds cleanly on subsequent login.
      mocks.setHandler(null);
      await tester.tap(find.text('打开登录'));
      await tester.pump();
      final second = platform.views.last;
      second.controller.executeAsync = (_, args) => args['account'] != null
          ? true
          : {'form': 'password', 'error': 'none'};
      second.visit(_teachingCas);
      await tester.pumpAndSettle();
      await _submitPassword(
        tester,
        account: _syntheticAltAccount,
        password: _syntheticNewPassword,
        remember: true,
      );
      second.controller.ready = true;
      second.visit(_teachingReturn);
      await tester.pumpAndSettle();

      expect(outcomes, [true, true]);
      expect(mocks.credentialCalls.last.method, 'save');
      expect(mocks.credentialCalls.last.arguments, {
        'account': _syntheticAltAccount,
        'password': _syntheticNewPassword,
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'clearing credentials or school session mid-login/mid-save prevents stale completion',
    (tester) async {
      final platform = _installWebPlatform();
      final mocks = _installChannelMocks();
      final outcomes = <bool>[];
      final view = await _openPage(tester, platform, outcomes);
      view.controller.executeAsync = (_, args) => args['account'] != null
          ? true
          : {'form': 'password', 'error': 'none'};

      view.visit(_teachingCas);
      await tester.pumpAndSettle();
      await _submitPassword(tester, remember: true);

      // Clear saved credentials independently before destination returns.
      await CampusNativeLogin.clear();
      view.controller.ready = true;
      view.visit(_teachingReturn);
      await tester.pumpAndSettle();
      expect(outcomes, [true]);
      expect(find.text('已登录，校园账号密码未保存。'), findsOneWidget);
      expect(mocks.credentialCalls.where((c) => c.method == 'save'), isEmpty);

      // Mid-save clearSession prevents popping true and marks session cleared.
      final saveGate = Completer<void>();
      mocks.setHandler((call) async {
        if (call.method == 'save') await saveGate.future;
        return null;
      });
      await tester.tap(find.text('打开登录'));
      await tester.pump();
      final second = platform.views.last;
      second.controller.executeAsync = (_, args) => args['account'] != null
          ? true
          : {'form': 'password', 'error': 'none'};
      second.visit(_teachingCas);
      await tester.pumpAndSettle();
      await _submitPassword(tester, remember: true);
      second.controller.ready = true;
      second.visit(_teachingReturn);
      await tester.pump();

      await tester.runAsync(() async {
        final clearFuture = SchoolAdapter().clearSession();
        saveGate.complete();
        await clearFuture;
      });
      await tester.pumpAndSettle();

      expect(outcomes, [true]);
      expect(find.byType(CampusLoginPage), findsOneWidget);
      expect(find.text('学校会话已清除，请重新登录。'), findsOneWidget);
      expect(mocks.schoolCalls, contains('clearSession'));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'official fallback, method switch, unknown probe, and background pause perform zero saves',
    (tester) async {
      final platform = _installWebPlatform();
      final mocks = _installChannelMocks();
      final outcomes = <bool>[];
      final view = await _openPage(tester, platform, outcomes);
      Object? probeResult = {'form': 'password', 'error': 'none'};
      var dispatches = 0;
      view.controller.executeAsync = (_, args) {
        if (args['account'] != null) {
          dispatches++;
          return true;
        }
        return probeResult;
      };

      view.visit(_teachingCas);
      await tester.pumpAndSettle();

      // Backgrounding blocks native submit and resuming does not auto-submit.
      addTearDown(() {
        if (WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.paused) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
        }
        if (WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.hidden) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        }
        if (WidgetsBinding.instance.lifecycleState !=
            AppLifecycleState.resumed) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
      });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await _submitPassword(tester, remember: true);
      expect(dispatches, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(dispatches, 0);

      // Switching to QR uncovers the official WebView.
      await tester.tap(find.widgetWithText(ChoiceChip, '企业微信扫码'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('campus-login-password-form')),
        findsNothing,
      );
      expect(find.text('用另一台设备的企业微信扫描官方页面二维码。'), findsOneWidget);

      // Switching back to password with unknown probe falls back without form.
      probeResult = null;
      await tester.tap(find.widgetWithText(ChoiceChip, '账号密码'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('campus-login-password-form')),
        findsNothing,
      );

      // Explicit open-official button removes native form cleanly.
      probeResult = {'form': 'password', 'error': 'none'};
      view.visit(_teachingCas);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('campus-login-password-form')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('campus-login-open-official')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('campus-login-password-form')),
        findsNothing,
      );

      view.controller.ready = true;
      view.visit(_teachingReturn);
      await tester.pumpAndSettle();
      expect(outcomes, [true]);
      expect(mocks.credentialCalls, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  test(
    'parseProbe and decodePngDataUrl validate Stage 3 QR/mobile contracts',
    () {
      final qrDataUrl = _syntheticPngDataUrl(red: 10, green: 20, blue: 30);
      final captchaDataUrl = _syntheticPngDataUrl(red: 70, green: 80, blue: 90);

      expect(CampusNativeLogin.decodePngDataUrl(qrDataUrl), isNotNull);
      expect(
        CampusNativeLogin.decodePngDataUrl('data:image/jpeg;base64,/9j/4AAQ'),
        isNull,
      );
      expect(
        CampusNativeLogin.decodePngDataUrl(
          'data:image/png;base64,${base64Encode(List<int>.filled(80, 1))}',
        ),
        isNull,
      );

      final readyQr = CampusNativeLogin.parseProbe({
        'form': 'qr',
        'qrState': 'ready',
        'qrDataUrl': qrDataUrl,
      });
      expect(readyQr, isNotNull);
      expect(readyQr!.form, CampusNativeForm.qr);
      expect(readyQr.qrState, CampusQrState.ready);
      expect(readyQr.qrBytes, isNotNull);
      expect(readyQr.toString(), isNot(contains(qrDataUrl)));

      final invalidReadyQr = CampusNativeLogin.parseProbe({
        'form': 'qr',
        'qrState': 'ready',
        'qrDataUrl': 'not-a-png',
      });
      expect(invalidReadyQr!.qrState, CampusQrState.loading);
      expect(invalidReadyQr.qrBytes, isNull);

      final expiredQr = CampusNativeLogin.parseProbe({
        'form': 'qr',
        'qrState': 'expired',
        'qrDataUrl': qrDataUrl,
      });
      expect(expiredQr!.qrState, CampusQrState.expired);
      expect(expiredQr.qrBytes, isNull);

      final mobileProbe = CampusNativeLogin.parseProbe({
        'form': 'mobile',
        'error': 'invalidCaptcha',
        'smsSent': false,
        'cooldownSeconds': 999,
        'canSendSms': false,
        'captchaDataUrl': captchaDataUrl,
        'requiresAccountChoice': true,
      });
      expect(mobileProbe, isNotNull);
      expect(mobileProbe!.form, CampusNativeForm.mobile);
      expect(mobileProbe.errorKind, CampusNativeErrorKind.invalidCaptcha);
      expect(mobileProbe.smsCooldownSeconds, 300);
      expect(mobileProbe.canSendSms, isFalse);
      expect(mobileProbe.captchaBytes, isNotNull);
      expect(mobileProbe.requiresAccountChoice, isTrue);
    },
  );

  testWidgets(
    'QR login displays image, saves only on explicit tap, keeps WebView alive on launch, and clears on completion',
    (tester) async {
      final platform = _installWebPlatform();
      final mocks = _installChannelMocks();
      final outcomes = <bool>[];
      final view = await _openPage(tester, platform, outcomes);
      final qrDataUrl = _syntheticPngDataUrl(red: 15, green: 25, blue: 35);
      final expectedBytes = CampusNativeLogin.decodePngDataUrl(qrDataUrl)!;
      var activeTab = 'password';

      view.controller.execute = (source) {
        if (source.contains("querySelector('a#qrcode_login').click()")) {
          activeTab = 'qr';
          return true;
        }
        if (source.contains("querySelector('a#password_login').click()")) {
          activeTab = 'password';
          return true;
        }
        return view.controller.ready;
      };
      view.controller.executeAsync = (_, args) {
        if (activeTab == 'qr') {
          return {'form': 'qr', 'qrState': 'ready', 'qrDataUrl': qrDataUrl};
        }
        return {'form': 'password', 'error': 'none'};
      };

      view.visit(_teachingCas);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '企业微信扫码'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('campus-qr-image')), findsOneWidget);
      expect(
        mocks.actionCalls.where((call) => call.method == 'saveQrImage'),
        isEmpty,
      );
      expect(platform.views, hasLength(1));

      await tester.ensureVisible(find.byKey(const ValueKey('campus-qr-save')));
      await tester.tap(find.byKey(const ValueKey('campus-qr-save')));
      await tester.pumpAndSettle();
      final saves = mocks.actionCalls
          .where((call) => call.method == 'saveQrImage')
          .toList();
      expect(saves, hasLength(1));
      expect((saves.single.arguments as Map)['bytes'], expectedBytes);
      expect(find.text('二维码已保存到系统相册，请在企业微信或微信扫一扫中从相册选择。'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('campus-qr-launch-wework')),
      );
      await tester.tap(find.byKey(const ValueKey('campus-qr-launch-wework')));
      await tester.pumpAndSettle();
      expect(
        mocks.actionCalls
            .where((call) => call.method == 'launchScanClient')
            .map((call) => (call.arguments as Map)['client']),
        ['wework'],
      );
      expect(find.textContaining('已打开企业微信'), findsOneWidget);

      addTearDown(() {
        if (WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.paused) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
        }
        if (WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.hidden) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        }
        if (WidgetsBinding.instance.lifecycleState !=
            AppLifecycleState.resumed) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
      });

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(platform.views, hasLength(1));

      view.controller.ready = true;
      view.visit(_teachingReturn);
      await tester.pumpAndSettle();
      expect(outcomes, [true]);
      expect(mocks.credentialCalls, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'QR login handles save failures, missing clients, expiry refresh, and clearing on switch/cancel',
    (tester) async {
      final platform = _installWebPlatform();
      final mocks = _installChannelMocks();
      mocks.setActionsHandler((call) async {
        return switch (call.method) {
          'availableScanClients' => const {'wework': false, 'wechat': true},
          'saveQrImage' => throw PlatformException(code: 'QR_SAVE_FAILED'),
          'launchScanClient' => 'not_installed',
          _ => null,
        };
      });
      final outcomes = <bool>[];
      final view = await _openPage(tester, platform, outcomes);
      final qrDataUrlA = _syntheticPngDataUrl(red: 11, green: 22, blue: 33);
      final qrDataUrlB = _syntheticPngDataUrl(red: 44, green: 55, blue: 66);
      final expectedBytesB = CampusNativeLogin.decodePngDataUrl(qrDataUrlB)!;
      var activeTab = 'password';
      var qrState = 'ready';
      var currentUrl = qrDataUrlA;

      view.controller.execute = (source) {
        if (source.contains("querySelector('a#qrcode_login').click()")) {
          activeTab = 'qr';
          return true;
        }
        if (source.contains("querySelector('a#password_login').click()")) {
          activeTab = 'password';
          return true;
        }
        return view.controller.ready;
      };
      view.controller.executeAsync = (_, args) {
        if (activeTab == 'qr') {
          if (args['action'] == 'refreshQr') {
            qrState = 'ready';
            currentUrl = qrDataUrlB;
          }
          return {
            'form': 'qr',
            'qrState': qrState,
            if (qrState == 'ready') 'qrDataUrl': currentUrl,
          };
        }
        return {'form': 'password', 'error': 'none'};
      };

      view.visit(_teachingCas);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '企业微信扫码'));
      await tester.pumpAndSettle();

      // Unavailable WeCom button omitted; WeChat launch reports not installed.
      expect(
        find.byKey(const ValueKey('campus-qr-launch-wework')),
        findsNothing,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('campus-qr-launch-wechat')),
      );
      await tester.tap(find.byKey(const ValueKey('campus-qr-launch-wechat')));
      await tester.pumpAndSettle();
      expect(find.textContaining('当前设备未安装微信'), findsOneWidget);

      // Save failure shows error banner cleanly.
      await tester.ensureVisible(find.byKey(const ValueKey('campus-qr-save')));
      await tester.tap(find.byKey(const ValueKey('campus-qr-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('campus-qr-error')), findsOneWidget);
      expect(find.textContaining('无法保存二维码到系统相册'), findsOneWidget);

      // Expiry poll hides image, disables save, and refresh replaces with new QR.
      qrState = 'expired';
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('campus-qr-image')), findsNothing);
      expect(find.byKey(const ValueKey('campus-qr-expired')), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('campus-qr-expired-refresh')),
      );
      await tester.tap(find.byKey(const ValueKey('campus-qr-expired-refresh')));
      await tester.pumpAndSettle();
      final refreshedImage = tester.widget<Image>(
        find.byKey(const ValueKey('campus-qr-image')),
      );
      expect((refreshedImage.image as MemoryImage).bytes, expectedBytesB);

      // Switching away to password clears QR form cleanly and cancel leaves zero pending timers.
      await tester.tap(find.widgetWithText(ChoiceChip, '账号密码'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('campus-login-qr-form')), findsNothing);
      expect(
        find.byKey(const ValueKey('campus-login-password-form')),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(outcomes, [false]);
      expect(mocks.credentialCalls, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'mobile login refreshes captcha, reports errors, blocks auto-resend on resume, and completes with zero saves',
    (tester) async {
      final platform = _installWebPlatform();
      final mocks = _installChannelMocks();
      final outcomes = <bool>[];
      final view = await _openPage(tester, platform, outcomes);
      final captchaUrlA = _syntheticPngDataUrl(red: 25, green: 45, blue: 65);
      final captchaUrlB = _syntheticPngDataUrl(red: 95, green: 35, blue: 15);
      final expectedBytesB = CampusNativeLogin.decodePngDataUrl(captchaUrlB)!;
      var activeTab = 'password';
      var currentCaptcha = captchaUrlA;
      var mobileError = 'none';
      var smsSent = false;
      var cooldownSeconds = 0;
      var canSendSms = true;
      var smsSendCalls = 0;
      var submitCalls = 0;

      view.controller.execute = (source) {
        if (source.contains("querySelector('a#loginByMobile').click()")) {
          activeTab = 'mobile';
          return true;
        }
        if (source.contains("querySelector('a#password_login').click()")) {
          activeTab = 'password';
          return true;
        }
        return view.controller.ready;
      };
      view.controller.executeAsync = (_, args) {
        if (activeTab != 'mobile') {
          return {'form': 'password', 'error': 'none'};
        }
        final action = args['action'];
        if (action == 'refreshCaptcha') {
          currentCaptcha = captchaUrlB;
          mobileError = 'none';
        } else if (action == 'sendMobileSms') {
          smsSendCalls++;
          if (args['captcha'] == _syntheticCaptcha) {
            mobileError = 'invalidCaptcha';
            currentCaptcha = captchaUrlB;
          } else {
            expect(args['phone'], _syntheticPhone);
            expect(args['captcha'], _syntheticCaptchaRetry);
            mobileError = 'none';
            smsSent = true;
            cooldownSeconds = 60;
            canSendSms = false;
          }
          return true;
        } else if (action == 'submitMobile') {
          submitCalls++;
          expect(args['phone'], _syntheticPhone);
          expect(args['mobileCode'], _syntheticSmsCode);
          mobileError = 'none';
          return true;
        }
        return {
          'form': 'mobile',
          'error': mobileError,
          'smsSent': smsSent,
          'cooldownSeconds': cooldownSeconds,
          'canSendSms': canSendSms,
          'captchaDataUrl': currentCaptcha,
          'requiresAccountChoice': false,
        };
      };

      view.visit(_teachingCas);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '手机号'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('campus-login-mobile-form')),
        findsOneWidget,
      );
      expect(find.text('保存账号密码'), findsNothing);
      expect(smsSendCalls, 0);

      // Explicit captcha refresh updates displayed captcha bytes.
      await tester.ensureVisible(
        find.byKey(const ValueKey('campus-mobile-captcha-refresh')),
      );
      await tester.tap(
        find.byKey(const ValueKey('campus-mobile-captcha-refresh')),
      );
      await tester.pumpAndSettle();
      final refreshedCaptcha = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const ValueKey('campus-mobile-captcha-image')),
          matching: find.byType(Image),
        ),
      );
      expect((refreshedCaptcha.image as MemoryImage).bytes, expectedBytesB);

      // Graphic captcha error preserves phone, clears captcha, and shows error.
      await tester.enterText(
        find.byKey(const ValueKey('campus-mobile-phone-field')),
        _syntheticPhone,
      );
      await tester.enterText(
        find.byKey(const ValueKey('campus-mobile-captcha-field')),
        _syntheticCaptcha,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('campus-mobile-send-sms')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('campus-mobile-send-sms')));
      await tester.pump();
      await tester.pump(CampusLoginPolicy.readinessPoll);
      await tester.pumpAndSettle();
      expect(smsSendCalls, 1);
      expect(find.text('图形验证码错误，请重新输入。'), findsOneWidget);
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

      // Valid SMS send enters cooldown and resume from background never auto-resends.
      await tester.enterText(
        find.byKey(const ValueKey('campus-mobile-captcha-field')),
        _syntheticCaptchaRetry,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('campus-mobile-send-sms')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('campus-mobile-send-sms')));
      await tester.pump();
      await tester.pump(CampusLoginPolicy.readinessPoll);
      await tester.pumpAndSettle();
      expect(smsSendCalls, 2);
      expect(find.text('短信验证码已发送，请注意查收。'), findsOneWidget);
      expect(find.text('60秒后重新获取'), findsOneWidget);

      addTearDown(() {
        if (WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.paused) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
        }
        if (WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.hidden) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        }
        if (WidgetsBinding.instance.lifecycleState !=
            AppLifecycleState.resumed) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
      });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(smsSendCalls, 2);

      // Submit 6-digit SMS code and finish cleanly with zero credential saves.
      await tester.enterText(
        find.byKey(const ValueKey('campus-mobile-sms-field')),
        _syntheticSmsCode,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('campus-mobile-submit')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('campus-mobile-submit')));
      await tester.pump();
      expect(submitCalls, 1);

      view.controller.ready = true;
      view.visit(_teachingReturn);
      await tester.pumpAndSettle();
      expect(outcomes, [true]);
      expect(mocks.credentialCalls, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'mobile multi-account chooser uncovers official WebView and password SMS remains independent',
    (tester) async {
      final platform = _installWebPlatform();
      final mocks = _installChannelMocks();
      final outcomes = <bool>[];
      final view = await _openPage(tester, platform, outcomes);
      var activeTab = 'password';
      var phase = 'password';
      var requiresChoice = false;

      view.controller.execute = (source) {
        if (source.contains("querySelector('a#loginByMobile').click()")) {
          activeTab = 'mobile';
          return true;
        }
        if (source.contains("querySelector('a#password_login').click()")) {
          activeTab = 'password';
          return true;
        }
        return view.controller.ready;
      };
      view.controller.executeAsync = (_, args) {
        if (activeTab == 'mobile') {
          if (args['action'] == 'submitMobile') {
            requiresChoice = true;
            return true;
          }
          return {
            'form': 'mobile',
            'error': 'none',
            'smsSent': false,
            'cooldownSeconds': 0,
            'canSendSms': true,
            'captchaDataUrl': _syntheticPngDataUrl(),
            'requiresAccountChoice': requiresChoice,
          };
        }
        if (args['account'] != null) {
          phase = 'sms';
          return true;
        }
        if (args['code'] != null) {
          return true;
        }
        if (phase == 'sms') {
          return {
            'form': 'sms',
            'error': 'none',
            'maskedPhone': _syntheticMaskedPhone,
            'smsSent': true,
          };
        }
        return {'form': 'password', 'error': 'none'};
      };

      view.visit(_teachingCas);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '手机号'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('campus-mobile-phone-field')),
        _syntheticPhone,
      );
      await tester.enterText(
        find.byKey(const ValueKey('campus-mobile-sms-field')),
        _syntheticSmsCode,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('campus-mobile-submit')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('campus-mobile-submit')));
      await tester.pump();
      await tester.pump(CampusLoginPolicy.readinessPoll);
      await tester.pumpAndSettle();

      // Official WebView uncovered for multi-account selection.
      expect(
        find.byKey(const ValueKey('campus-login-mobile-form')),
        findsNothing,
      );
      expect(find.text('该手机号绑定了多个校园账号，请在官方页面选择账号完成登录。'), findsOneWidget);

      // Re-opening retains completely independent password + #PM1 secondary SMS flow.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开登录'));
      await tester.pump();
      final second = platform.views.last;
      activeTab = 'password';
      phase = 'password';
      second.controller.execute = (source) {
        if (source.contains("querySelector('a#loginByMobile').click()")) {
          activeTab = 'mobile';
          return true;
        }
        if (source.contains("querySelector('a#password_login').click()")) {
          activeTab = 'password';
          return true;
        }
        return second.controller.ready;
      };
      second.controller.executeAsync = view.controller.executeAsync;

      second.visit(_teachingCas);
      await tester.pumpAndSettle();
      await _submitPassword(tester, remember: true);
      second.visit(_teachingCas);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('campus-login-sms-form-0')),
        findsOneWidget,
      );
      await _submitSms(tester, code: _syntheticSmsCode);
      second.controller.ready = true;
      second.visit(_teachingReturn);
      await tester.pumpAndSettle();

      expect(outcomes, [false, true]);
      expect(
        mocks.credentialCalls.where((c) => c.method == 'save'),
        hasLength(1),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
