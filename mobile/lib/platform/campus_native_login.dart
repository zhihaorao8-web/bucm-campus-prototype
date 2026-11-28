import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../config/runtime_config.dart';
import 'campus_login_navigation.dart';

/// Opt-in campus login credential pair whose string form never exposes values.
class CampusCredentials {
  const CampusCredentials({required this.account, required this.password});

  final String account;
  final String password;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CampusCredentials &&
          other.account == account &&
          other.password == password;

  @override
  int get hashCode => Object.hash(account, password);

  @override
  String toString() => 'CampusCredentials(redacted)';
}

enum CampusNativeForm { password, sms }

enum CampusNativeErrorKind {
  none,
  invalidPassword,
  invalidSmsCode,
  smsExpired,
  smsRateLimited,
  smsSendFailed,
  generic,
}

class CampusNativeProbe {
  const CampusNativeProbe({
    required this.form,
    this.errorKind = CampusNativeErrorKind.none,
    this.maskedPhone,
    this.smsSent = false,
  });

  final CampusNativeForm form;
  final CampusNativeErrorKind errorKind;
  final String? maskedPhone;
  final bool smsSent;
}

class CampusNativeLogin {
  static const channel = MethodChannel(AppChannels.credentials);
  static int _revision = 0;
  static final _changes = ValueNotifier<int>(0);
  static Future<void>? _tail;

  static int get revision => _revision;
  static ValueListenable<int> get changes => _changes;

  static Future<T> _enqueue<T>(Future<T> Function() action) {
    final previous = _tail;
    final operation = previous == null
        ? Future<T>.sync(action)
        : previous.then((_) => action());
    late final Future<void> marker;
    marker = operation.then<void>((_) {}, onError: (_) {}).whenComplete(() {
      if (identical(_tail, marker)) {
        _tail = null;
      }
    });
    _tail = marker;
    return operation;
  }

  static Future<bool> save(CampusCredentials credentials, {int? revision}) {
    final expected = revision ?? _revision;
    return _enqueue(() async {
      if (expected != _revision) return false;
      await channel.invokeMethod<void>('save', {
        'account': credentials.account,
        'password': credentials.password,
      });
      if (expected != _revision) return false;
      _changes.value++;
      return true;
    });
  }

  static Future<void> clear() {
    _revision++;
    _changes.value++;
    return _enqueue(() => channel.invokeMethod<void>('clear'));
  }

  static Future<void> clearWithSession(
    Future<void> Function() clearNativeSession,
  ) {
    _revision++;
    _changes.value++;
    return _enqueue(clearNativeSession);
  }

  static Future<bool> hasSaved() {
    final expected = _revision;
    return _enqueue(() async {
      if (expected != _revision) return false;
      final result = await channel.invokeMethod<bool>('hasSaved');
      return expected == _revision && result == true;
    });
  }

  static String? serviceFor(String address, CampusLoginTarget target) {
    if (target == CampusLoginTarget.vpn || !campusCasForm(address)) return null;
    final services = Uri.parse(address).queryParametersAll['service'];
    if (services == null || services.length != 1) return null;
    final service = services.single;
    if (!target.allows(service) || Uri.parse(service).host != target.host) {
      return null;
    }
    return service;
  }

  static String? smsServiceFor(
    String address,
    CampusLoginTarget target,
    String expectedService,
  ) {
    if (target == CampusLoginTarget.vpn || !campusCasForm(address)) return null;
    final services = Uri.parse(address).queryParametersAll['service'];
    if (services == null || services.isEmpty) return expectedService;
    if (services.length == 1 && services.single == expectedService) {
      return expectedService;
    }
    return null;
  }

  static bool isServiceReturn(String? address, String service) {
    if (address == null) return false;
    final actual = Uri.tryParse(address);
    final expected = Uri.parse(service);
    if (actual == null ||
        actual.scheme != 'https' ||
        actual.userInfo.isNotEmpty ||
        actual.port != 443) {
      return false;
    }
    final authority = RegExp(
      r'^https://([^/?#]+)',
      caseSensitive: false,
    ).firstMatch(address)?.group(1)?.toLowerCase();
    if (authority != actual.host && authority != '${actual.host}:443') {
      return false;
    }
    if (actual.host != expected.host ||
        actual.port != expected.port ||
        (actual.path.isEmpty ? '/' : actual.path) !=
            (expected.path.isEmpty ? '/' : expected.path)) {
      return false;
    }
    final parameters = Map.of(actual.queryParametersAll);
    final ticket = parameters.remove('ticket');
    return ticket?.length == 1 &&
        ticket!.single.startsWith('ST-') &&
        ticket.single.length > 3 &&
        !RegExp(r'\s').hasMatch(ticket.single) &&
        parameters.length == expected.queryParametersAll.length &&
        parameters.entries.every(
          (entry) =>
              listEquals(entry.value, expected.queryParametersAll[entry.key]),
        );
  }

  static String? sanitizeMaskedPhone(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    if (text.length != 11) return null;
    return RegExp(r'^1[3-9]\d\*{4,5}\d{3,4}$').hasMatch(text) ? text : null;
  }

  static CampusNativeProbe? parseProbe(Object? raw) {
    if (raw == 'password') {
      return const CampusNativeProbe(form: CampusNativeForm.password);
    }
    if (raw == 'sms') {
      return const CampusNativeProbe(form: CampusNativeForm.sms);
    }
    if (raw is! Map) return null;
    final form = switch (raw['form']) {
      'password' => CampusNativeForm.password,
      'sms' => CampusNativeForm.sms,
      _ => null,
    };
    if (form == null) return null;
    final errorKind = switch (raw['error']) {
      'invalidPassword' => CampusNativeErrorKind.invalidPassword,
      'invalidSmsCode' => CampusNativeErrorKind.invalidSmsCode,
      'smsExpired' => CampusNativeErrorKind.smsExpired,
      'smsRateLimited' => CampusNativeErrorKind.smsRateLimited,
      'smsSendFailed' => CampusNativeErrorKind.smsSendFailed,
      'generic' => CampusNativeErrorKind.generic,
      _ => CampusNativeErrorKind.none,
    };
    if (form != CampusNativeForm.sms) {
      return CampusNativeProbe(form: form, errorKind: errorKind);
    }
    return CampusNativeProbe(
      form: form,
      errorKind: errorKind,
      maskedPhone: sanitizeMaskedPhone(raw['maskedPhone']),
      smsSent: raw['smsSent'] == true,
    );
  }

  /// The site still owns the login and challenge. Only fixed-form actions are
  /// allowed, with a document and service check in the same JavaScript call.
  static Future<Object?> perform(
    InAppWebViewController web, {
    required String address,
    required String service,
    CampusCredentials? credentials,
    String? code,
  }) async {
    final result = await web.callAsyncJavaScript(
      functionBody: _script,
      arguments: {
        'address': address,
        'service': service,
        'account': credentials?.account,
        'password': credentials?.password,
        'code': code,
      },
    );
    return result?.error == null ? result?.value : null;
  }

  static const _script = r'''
if (window !== window.top || location.origin !== 'https://cas.bucm.edu.cn' ||
    location.href !== address || !/^\/+cas\/+login\/?$/.test(location.pathname)) return null;
const services = new URL(location.href).searchParams.getAll('service');
if (services.length > 1 || (services.length === 1 && services[0] !== service)) return null;
const expected = new URL(service);
if (expected.protocol !== 'https:' || expected.username || expected.password) return null;
const shown = element => !!element?.getClientRects().length &&
    getComputedStyle(element).visibility !== 'hidden';
const visible = element => shown(element) && !element.disabled;
function schoolForm(form, button, requireService) {
  if (!(form instanceof HTMLFormElement) || form.method !== 'post') return false;
  if (button.hasAttribute('formaction') || button.hasAttribute('formmethod') ||
      button.hasAttribute('formtarget') || (form.target && form.target !== '_self')) return false;
  const destination = new URL(form.action, location.href);
  const targets = destination.searchParams.getAll('service');
  const serviceOk = requireService
      ? targets.length === 1 && targets[0] === service
      : targets.length === 0 || (targets.length === 1 && targets[0] === service);
  return destination.origin === location.origin &&
      /^\/+cas\/+login\/?$/.test(destination.pathname) &&
      !destination.username && !destination.password && serviceOk;
}
function errorBoxText(form) {
  const selectors = '#errormsg, #errormsgs, #msg, .errormsg, .error-msg, .login-error, .alert-danger, [role="alert"], .tips, .tip-error';
  const parts = [];
  for (const node of document.querySelectorAll(selectors)) {
    if (shown(node)) {
      const text = (node.innerText ?? '').trim();
      if (text) parts.push(text);
    }
  }
  return parts.join('\n');
}
function classifyPasswordError(form) {
  const dedicated = errorBoxText(form);
  const text = dedicated || (form?.innerText ?? document.body?.innerText ?? '');
  if (/用户名或密码错误|账号或密码错误|密码错误|密码不正确|密码有误|认证失败|用户名不存在|账号不存在|学号或密码错误/.test(text)) {
    return 'invalidPassword';
  }
  return dedicated ? 'generic' : 'none';
}
function classifySmsError(form) {
  const dedicated = errorBoxText(form);
  const text = dedicated || (form?.innerText ?? document.body?.innerText ?? '');
  if (/验证码已过期|验证码过期|验证码失效|已超时|认证已过期|会话已过期|请重新登录/.test(text)) {
    return 'smsExpired';
  }
  if (/发送次数|次数已达上限|次数过多|过于频繁|操作频繁|超出限制|稍后再试|上限/.test(text)) {
    return 'smsRateLimited';
  }
  if (/发送失败|获取失败|短信发送异常|无法发送/.test(text)) {
    return 'smsSendFailed';
  }
  if (/验证码错误|验证码不正确|验证码有误|动态码错误|校验失败|验证失败|请输入正确的验证码/.test(text)) {
    return 'invalidSmsCode';
  }
  return dedicated ? 'generic' : 'none';
}
const submit = document.getElementById('index_login_btn');
const form = document.getElementById('loginForm');
const sms = document.getElementById('PM1');
if (sms instanceof HTMLInputElement && sms.type === 'text' &&
    sms.maxLength === 6 && visible(sms) &&
    /短信验证|短信验证码/.test(document.body?.innerText ?? '')) {
  if (sms.form !== form || !form?.contains(submit) || !visible(submit) ||
      !schoolForm(form, submit, false)) return null;
  if (account !== null || password !== null) return null;
  if (code === null) {
    const bodyText = document.body?.innerText ?? '';
    const scopeText = form.innerText || bodyText;
    const phoneMatch = /(?:^|[^\d*])(1[3-9]\d\*{4,5}\d{3,4})(?:[^\d*]|$)/.exec(scopeText);
    const maskedPhone = phoneMatch && phoneMatch[1].length === 11 ? phoneMatch[1] : null;
    const error = classifySmsError(form);
    return {
      form: 'sms',
      error,
      maskedPhone,
      smsSent: error === 'none' && /已发送|发送成功/.test(bodyText),
    };
  }
  if (!/^\d{6}$/.test(code)) return false;
  sms.value = code;
  sms.dispatchEvent(new Event('input', { bubbles: true }));
  sms.dispatchEvent(new Event('change', { bubbles: true }));
  submit.click();
  return true;
}
const user = document.getElementById('un');
const secret = document.getElementById('pd');
if (!(user instanceof HTMLInputElement) || user.type !== 'text' ||
    !(secret instanceof HTMLInputElement) || secret.type !== 'password' ||
    user.form !== form || secret.form !== form || !form?.contains(submit) ||
    !visible(user) || !visible(secret) || !visible(submit) ||
    !schoolForm(form, submit, true) || services.length !== 1 || code !== null) return null;
if (account === null && password === null) {
  return {
    form: 'password',
    error: classifyPasswordError(form),
  };
}
if (typeof account !== 'string' || typeof password !== 'string' ||
    !account.trim() || account.length > 128 || !password || password.length > 1024) return false;
user.value = account;
user.dispatchEvent(new Event('input', { bubbles: true }));
user.dispatchEvent(new Event('change', { bubbles: true }));
secret.value = password;
secret.dispatchEvent(new Event('input', { bubbles: true }));
secret.dispatchEvent(new Event('change', { bubbles: true }));
submit.click();
return true;
''';
}
