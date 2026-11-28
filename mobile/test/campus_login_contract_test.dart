import 'dart:async';

import 'package:campus_schedule/platform/campus_login_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

// Test-only form values and routes. The fixture does not drive a real WebView.
const _credentials = (account: 'synthetic-student', password: 'synthetic-pass');
const _code = '101010';
const _cas = 'https://cas.bucm.edu.cn/cas/login';
const _foreign = 'https://untrusted.invalid/login';

typedef _Credentials = ({String account, String password});

enum _Document { password, smsChallenge, unknown, service }

class _SyntheticPage {
  _SyntheticPage(
    this.url,
    this.document, {
    this.topLevel = true,
    this.formAction = _cas,
  });

  final String url;
  final _Document document;
  final bool topLevel;
  final String formAction;
  _Credentials? enteredCredentials;
  String? enteredCode;
}

// Probe the proposed flow without adding a production credential entry point.
class _SyntheticLogin {
  _SyntheticLogin(this.target);

  final CampusLoginTarget target;
  _SyntheticPage? page;
  CampusLoginMethod _method = CampusLoginMethod.password;
  int _revision = 0;
  bool _foreground = true;
  bool _cancelled = false;
  bool _passwordPending = false;
  bool _passwordSubmitted = false;
  bool _submittedChallenge = false;
  bool recovered = false;

  void visit(_SyntheticPage nextPage) {
    page = nextPage;
    _revision++;
    _submittedChallenge = false;
  }

  void select(CampusLoginMethod method) {
    _method = method;
    _revision++;
  }

  void setForeground(bool value) {
    _foreground = value;
    _revision++;
  }

  void cancel() {
    _cancelled = true;
    _revision++;
  }

  bool _accepts(_Document form) {
    final current = page;
    if (_cancelled ||
        !_foreground ||
        recovered ||
        _method != CampusLoginMethod.password ||
        current == null ||
        !current.topLevel ||
        current.document != form ||
        !campusCasForm(current.url) ||
        !campusCasForm(current.formAction)) {
      return false;
    }
    final services = Uri.parse(current.url).queryParametersAll['service'];
    return services?.length == 1 && services!.single == target.entry;
  }

  Future<bool> submitPassword(Future<_Credentials> Function() input) async {
    if (_passwordPending ||
        _passwordSubmitted ||
        !_accepts(_Document.password)) {
      return false;
    }
    final revision = _revision;
    _passwordPending = true;
    try {
      final credentials = await input();
      if (revision != _revision || !_accepts(_Document.password)) return false;
      page!.enteredCredentials = credentials;
      _passwordSubmitted = true;
      return true;
    } finally {
      _passwordPending = false;
    }
  }

  bool submitChallenge(String code) {
    if (!_passwordSubmitted ||
        _submittedChallenge ||
        !_accepts(_Document.smsChallenge)) {
      return false;
    }
    page!.enteredCode = code;
    _submittedChallenge = true;
    return true;
  }

  bool confirmService({required bool ready}) {
    final current = page;
    if (_cancelled ||
        recovered ||
        !_foreground ||
        current == null ||
        !current.topLevel ||
        current.document != _Document.service ||
        !target.isDestination(current.url) ||
        !ready) {
      return false;
    }
    recovered = true;
    return true;
  }
}

String _loginUrl(String service) =>
    '$_cas?service=${Uri.encodeQueryComponent(service)}';

void main() {
  const classroom = CampusLoginTarget.classroom;
  const library = CampusLoginTarget.library;

  for (final target in [classroom, library]) {
    test('${target.name}: existing school session reads no password', () async {
      final login = _SyntheticLogin(target)
        ..visit(_SyntheticPage(target.entry, _Document.service));
      expect(
        await login.submitPassword(() async => fail('unexpected read')),
        isFalse,
      );
      expect(login.confirmService(ready: false), isFalse);
      expect(login.confirmService(ready: true), isTrue);
      expect(login.confirmService(ready: true), isFalse);
    });

    test(
      '${target.name}: password, same-session SMS, service return',
      () async {
        final url = _loginUrl(target.entry);
        final passwordPage = _SyntheticPage(url, _Document.password);
        final login = _SyntheticLogin(target)..visit(passwordPage);
        final input = Completer<_Credentials>();
        final submission = login.submitPassword(() => input.future);
        expect(
          await login.submitPassword(() async => fail('concurrent read')),
          isFalse,
        );
        input.complete(_credentials);
        expect(await submission, isTrue);
        expect(passwordPage.enteredCredentials, _credentials);
        expect(login.confirmService(ready: true), isFalse);

        final challenge = _SyntheticPage(url, _Document.smsChallenge);
        login.visit(challenge);
        expect(
          await login.submitPassword(() async => fail('SMS reads no password')),
          isFalse,
        );
        expect(login.submitChallenge(_code), isTrue);
        expect(challenge.enteredCode, _code);
        expect(login.submitChallenge(_code), isFalse);
        expect(login.confirmService(ready: true), isFalse);

        login.visit(_SyntheticPage(target.entry, _Document.service));
        expect(login.confirmService(ready: false), isFalse);
        expect(login.confirmService(ready: true), isTrue);
        expect(login.confirmService(ready: true), isFalse);
      },
    );
  }

  test('blocked origins, forms and services do not read credentials', () async {
    final url = _loginUrl(classroom.entry);
    final login = _SyntheticLogin(classroom);
    for (final page in [
      _SyntheticPage(_foreign, _Document.password),
      _SyntheticPage(url.replaceFirst('https:', 'http:'), _Document.password),
      _SyntheticPage(url, _Document.password, topLevel: false),
      _SyntheticPage(url, _Document.password, formAction: _foreign),
      _SyntheticPage(_loginUrl(library.entry), _Document.password),
      _SyntheticPage('$url&service=$url', _Document.password),
      _SyntheticPage(url, _Document.unknown),
      _SyntheticPage(url, _Document.smsChallenge),
    ]) {
      login.visit(page);
      expect(
        await login.submitPassword(() async => fail('unexpected read')),
        isFalse,
      );
      expect(login.submitChallenge(_code), isFalse);
      expect(page.enteredCredentials, isNull);
      expect(page.enteredCode, isNull);
      expect(login.confirmService(ready: true), isFalse);
    }
  });

  final interruptions = <String, void Function(_SyntheticLogin)>{
    'same URL navigation': (login) => login.visit(
      _SyntheticPage(_loginUrl(classroom.entry), _Document.password),
    ),
    'method switch': (login) => login.select(CampusLoginMethod.qr),
    'background and return': (login) {
      login.setForeground(false);
      login.setForeground(true);
    },
    'cancellation': (login) => login.cancel(),
  };
  for (final interruption in interruptions.entries) {
    test('${interruption.key} invalidates a pending password read', () async {
      final original = _SyntheticPage(
        _loginUrl(classroom.entry),
        _Document.password,
      );
      final login = _SyntheticLogin(classroom)..visit(original);
      final input = Completer<_Credentials>();
      final submission = login.submitPassword(() => input.future);
      interruption.value(login);
      input.complete(_credentials);
      expect(await submission, isFalse);
      expect(original.enteredCredentials, isNull);
      expect(login.page?.enteredCredentials, isNull);
    });
  }

  test('a repeated password page cannot automatically resubmit', () async {
    final url = _loginUrl(classroom.entry);
    final login = _SyntheticLogin(classroom)
      ..visit(_SyntheticPage(url, _Document.password));
    expect(await login.submitPassword(() async => _credentials), isTrue);
    final secondPage = _SyntheticPage(url, _Document.password);
    login.visit(secondPage);
    expect(
      await login.submitPassword(() async => fail('unexpected retry')),
      isFalse,
    );
    expect(secondPage.enteredCredentials, isNull);
  });
}
