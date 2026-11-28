import 'dart:async';
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
const _syntheticMaskedPhone = '138****0000';
const _teachingService = 'https://jw.bucm.edu.cn/';
const _teachingCas =
    'https://cas.bucm.edu.cn/cas/login?service=https%3A%2F%2Fjw.bucm.edu.cn%2F';
const _teachingReturn = 'https://jw.bucm.edu.cn/?ticket=ST-synthetic-123';

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
  List<String> schoolCalls,
  void Function(Future<Object?> Function(MethodCall call)? handler) setHandler,
})
_installChannelMocks() {
  final credentialCalls = <_RecordedChannelCall>[];
  final schoolCalls = <String>[];
  Future<Object?> Function(MethodCall call)? customCredentialHandler;
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
  messenger.setMockMethodCallHandler(SchoolAdapter.channel, (call) async {
    schoolCalls.add(call.method);
    return null;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(paths, null);
    messenger.setMockMethodCallHandler(CampusNativeLogin.channel, null);
    messenger.setMockMethodCallHandler(SchoolAdapter.channel, null);
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });

  return (
    credentialCalls: credentialCalls,
    schoolCalls: schoolCalls,
    setHandler: (handler) => customCredentialHandler = handler,
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
}
