import 'dart:convert';

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

enum CampusNativeForm { password, sms, mobile, qr }

enum CampusQrState { loading, ready, expired }

enum CampusScanClient {
  wework('企业微信', 'wework'),
  wechat('微信', 'wechat');

  const CampusScanClient(this.label, this.key);

  final String label;
  final String key;
}

enum CampusScanLaunchResult { launched, notInstalled, failed }

enum CampusNativeErrorKind {
  none,
  invalidPassword,
  invalidSmsCode,
  smsExpired,
  smsRateLimited,
  smsSendFailed,
  invalidPhone,
  invalidCaptcha,
  generic,
}

class CampusNativeProbe {
  const CampusNativeProbe({
    required this.form,
    this.errorKind = CampusNativeErrorKind.none,
    this.maskedPhone,
    this.smsSent = false,
    this.qrState = CampusQrState.loading,
    this.qrBytes,
    this.captchaBytes,
    this.smsCooldownSeconds = 0,
    this.canSendSms = true,
    this.requiresAccountChoice = false,
  });

  final CampusNativeForm form;
  final CampusNativeErrorKind errorKind;
  final String? maskedPhone;
  final bool smsSent;
  final CampusQrState qrState;
  final Uint8List? qrBytes;
  final Uint8List? captchaBytes;
  final int smsCooldownSeconds;
  final bool canSendSms;
  final bool requiresAccountChoice;

  @override
  String toString() => 'CampusNativeProbe(form: $form, error: $errorKind)';
}

class CampusNativeLogin {
  static const channel = MethodChannel(AppChannels.credentials);
  static const actionsChannel = MethodChannel(AppChannels.loginActions);
  static const _maxQrBytes = 2 * 1024 * 1024;
  static const _maxProbeImageBytes = 1024 * 1024;
  static const _pngSignature = <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ];
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

  static bool _hasPngSignature(Uint8List bytes) {
    if (bytes.length < 67) return false;
    for (var i = 0; i < _pngSignature.length; i++) {
      if (bytes[i] != _pngSignature[i]) return false;
    }
    return true;
  }

  static Uint8List? decodePngDataUrl(
    Object? raw, {
    int maxBytes = _maxProbeImageBytes,
  }) {
    const prefix = 'data:image/png;base64,';
    if (raw is! String || !raw.startsWith(prefix) || maxBytes < 67) {
      return null;
    }
    final payload = raw.substring(prefix.length);
    final maxPayload = ((maxBytes + 2) ~/ 3) * 4 + 4;
    if (payload.isEmpty || payload.length > maxPayload) return null;
    try {
      final bytes = base64Decode(payload);
      if (bytes.length > maxBytes || !_hasPngSignature(bytes)) return null;
      return bytes;
    } on FormatException {
      return null;
    }
  }

  static Future<void> saveQrImage(Uint8List bytes) async {
    if (!_hasPngSignature(bytes) || bytes.length > _maxQrBytes) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'Invalid PNG image bytes',
      );
    }
    final saved = await actionsChannel.invokeMethod<bool>('saveQrImage', {
      'bytes': bytes,
    });
    if (saved != true) {
      throw PlatformException(code: 'QR_SAVE_FAILED', message: '无法保存二维码到系统相册');
    }
  }

  static Future<Set<CampusScanClient>?> availableScanClients() async {
    try {
      final raw = await actionsChannel.invokeMethod<Map<Object?, Object?>>(
        'availableScanClients',
      );
      if (raw == null) return null;
      return {
        for (final client in CampusScanClient.values)
          if (raw[client.key] == true) client,
      };
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<CampusScanLaunchResult> launchScanClient(
    CampusScanClient client,
  ) async {
    try {
      final raw = await actionsChannel.invokeMethod<String>(
        'launchScanClient',
        {'client': client.key},
      );
      return switch (raw) {
        'launched' => CampusScanLaunchResult.launched,
        'not_installed' => CampusScanLaunchResult.notInstalled,
        _ => CampusScanLaunchResult.failed,
      };
    } on PlatformException {
      return CampusScanLaunchResult.failed;
    } on MissingPluginException {
      return CampusScanLaunchResult.failed;
    }
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
      'mobile' => CampusNativeForm.mobile,
      'qr' => CampusNativeForm.qr,
      _ => null,
    };
    if (form == null) return null;
    final errorKind = switch (raw['error']) {
      'invalidPassword' => CampusNativeErrorKind.invalidPassword,
      'invalidSmsCode' => CampusNativeErrorKind.invalidSmsCode,
      'smsExpired' => CampusNativeErrorKind.smsExpired,
      'smsRateLimited' => CampusNativeErrorKind.smsRateLimited,
      'smsSendFailed' => CampusNativeErrorKind.smsSendFailed,
      'invalidPhone' => CampusNativeErrorKind.invalidPhone,
      'invalidCaptcha' => CampusNativeErrorKind.invalidCaptcha,
      'generic' => CampusNativeErrorKind.generic,
      _ => CampusNativeErrorKind.none,
    };
    if (form == CampusNativeForm.qr) {
      final qrBytes = decodePngDataUrl(raw['qrDataUrl']);
      var qrState = switch (raw['qrState']) {
        'ready' => CampusQrState.ready,
        'expired' => CampusQrState.expired,
        _ => CampusQrState.loading,
      };
      if (qrState == CampusQrState.ready && qrBytes == null) {
        qrState = CampusQrState.loading;
      }
      return CampusNativeProbe(
        form: form,
        errorKind: errorKind,
        qrState: qrState,
        qrBytes: qrState == CampusQrState.ready ? qrBytes : null,
      );
    }
    if (form == CampusNativeForm.mobile) {
      final rawCooldown = raw['cooldownSeconds'];
      final cooldown = rawCooldown is num
          ? rawCooldown.toInt().clamp(0, 300)
          : 0;
      return CampusNativeProbe(
        form: form,
        errorKind: errorKind,
        smsSent: raw['smsSent'] == true,
        captchaBytes: decodePngDataUrl(raw['captchaDataUrl']),
        smsCooldownSeconds: cooldown,
        canSendSms: raw['canSendSms'] != false && cooldown == 0,
        requiresAccountChoice: raw['requiresAccountChoice'] == true,
      );
    }
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
    String? action,
    String? phone,
    String? captcha,
    String? mobileCode,
  }) async {
    final result = await web.callAsyncJavaScript(
      functionBody: _script,
      arguments: {
        'address': address,
        'service': service,
        'account': credentials?.account,
        'password': credentials?.password,
        'code': code,
        'action': action,
        'phone': phone,
        'captcha': captcha,
        'mobileCode': mobileCode,
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
const noCredentialArgs = account === null && password === null && code === null;
const noMobileArgs = action === null && phone === null && captcha === null && mobileCode === null;
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
function errorBoxText() {
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
  const dedicated = errorBoxText();
  const text = dedicated || (form?.innerText ?? document.body?.innerText ?? '');
  if (/用户名或密码错误|账号或密码错误|密码错误|密码不正确|密码有误|认证失败|用户名不存在|账号不存在|学号或密码错误/.test(text)) {
    return 'invalidPassword';
  }
  return dedicated ? 'generic' : 'none';
}
function classifySmsError(form) {
  const dedicated = errorBoxText();
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
function classifyMobileError(dedicated) {
  if (!dedicated) return 'none';
  if (/手机号不能为空|手机号格式错误|手机号码.*(?:错误|不存在|未绑定|未登记)|未找到.*手机/.test(dedicated)) {
    return 'invalidPhone';
  }
  if (/图片验证码|图形验证码|验证码不能为空/.test(dedicated)) {
    return 'invalidCaptcha';
  }
  if (/验证码已过期|验证码过期|验证码失效|已超时|认证已过期|会话已过期|请重新获取/.test(dedicated)) {
    return 'smsExpired';
  }
  if (/发送次数|次数已达上限|次数过多|过于频繁|操作频繁|超出限制|稍后再试|上限/.test(dedicated)) {
    return 'smsRateLimited';
  }
  if (/发送失败|获取失败|短信发送异常|无法发送/.test(dedicated)) {
    return 'smsSendFailed';
  }
  if (/动态验证码错误|短信验证码|验证码错误|验证码不正确|验证码有误|动态码错误|校验失败|验证失败|请输入正确的验证码/.test(dedicated)) {
    return 'invalidSmsCode';
  }
  return 'generic';
}
function sameOriginOrDataImage(source) {
  if (typeof source !== 'string' || !source) return false;
  if (/^data:image\/(?:png|jpeg|webp);base64,/i.test(source)) return true;
  try {
    return new URL(source, location.href).origin === location.origin;
  } catch (_) {
    return false;
  }
}
function renderPngDataUrl(node, targetSize, quietPad) {
  try {
    const isImg = node instanceof HTMLImageElement;
    const isCanvas = node instanceof HTMLCanvasElement;
    if (!isImg && !isCanvas) return null;
    const width = isImg ? node.naturalWidth : node.width;
    const height = isImg ? node.naturalHeight : node.height;
    if (!width || !height) return null;
    if (isImg) {
      if (!node.complete || !sameOriginOrDataImage(node.currentSrc || node.src)) return null;
    }
    const canvas = document.createElement('canvas');
    const outW = targetSize ?? width;
    const outH = targetSize ?? height;
    const pad = quietPad ?? 0;
    canvas.width = outW;
    canvas.height = outH;
    const ctx = canvas.getContext('2d');
    if (!ctx) return null;
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, outW, outH);
    ctx.imageSmoothingEnabled = targetSize == null;
    ctx.drawImage(node, pad, pad, outW - pad * 2, outH - pad * 2);
    return canvas.toDataURL('image/png');
  } catch (_) {
    return null;
  }
}
const submit = document.getElementById('index_login_btn');
const form = document.getElementById('loginForm');
const sms = document.getElementById('PM1');
if (noMobileArgs && sms instanceof HTMLInputElement && sms.type === 'text' &&
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
const qrBox = document.getElementById('qrcode');
if (qrBox && shown(qrBox) && services.length === 1 &&
    noCredentialArgs && phone === null && captcha === null && mobileCode === null) {
  if (action !== null && action !== 'refreshQr') return null;
  if (action === 'refreshQr') {
    const refreshBtn = qrBox.querySelector('.code-refresh');
    const pwTab = document.querySelector('a#password_login');
    const qrTab = document.querySelector('a#qrcode_login');
    if (refreshBtn instanceof HTMLElement && shown(refreshBtn)) {
      refreshBtn.click();
    } else if (pwTab instanceof HTMLElement && qrTab instanceof HTMLElement &&
               shown(pwTab) && shown(qrTab)) {
      pwTab.click();
      qrTab.click();
    } else {
      return null;
    }
    await new Promise(resolve => setTimeout(resolve, 60));
  }
  const activeQr = document.getElementById('qrcode');
  if (!activeQr || !shown(activeQr)) {
    return { form: 'qr', qrState: 'loading' };
  }
  if (activeQr.querySelector('.code-gray, .code-fail, .code-refresh') ||
      /已失效|已过期/.test(activeQr.innerText ?? '')) {
    return { form: 'qr', qrState: 'expired' };
  }
  const qrImg = activeQr.querySelector('img');
  const qrCanvas = activeQr.querySelector('canvas');
  let qrDataUrl = null;
  if (qrImg instanceof HTMLImageElement && qrImg.naturalWidth >= 64 && qrImg.naturalHeight >= 64) {
    qrDataUrl = renderPngDataUrl(qrImg, 384, 24);
  }
  if (!qrDataUrl && qrCanvas instanceof HTMLCanvasElement &&
      qrCanvas.width >= 64 && qrCanvas.height >= 64) {
    qrDataUrl = renderPngDataUrl(qrCanvas, 384, 24);
  }
  return qrDataUrl
      ? { form: 'qr', qrState: 'ready', qrDataUrl }
      : { form: 'qr', qrState: 'loading' };
}
const accountChooser = document.querySelector(
  '#accountForm .login-popup-box, #accountForm div[name="numbercard"]'
);
if (accountChooser && shown(accountChooser) && services.length === 1 &&
    noCredentialArgs && (action === null || action === 'submitMobile')) {
  return { form: 'mobile', requiresAccountChoice: true };
}
const mobileInput = document.getElementById('loginMobile');
const captchaInput = document.getElementById('sendConfirm');
const captchaImg = document.getElementById('codeImage');
const smsInput = document.getElementById('phoneCode');
const sendBtn = document.getElementById('getMobileVerifyCode');
const mobileSubmit = document.getElementById('finishloginbymobile');
const mobileSubmitSpan = document.getElementById('mobile_login_btn');
if (mobileInput instanceof HTMLInputElement &&
    captchaInput instanceof HTMLInputElement &&
    captchaImg instanceof HTMLImageElement &&
    smsInput instanceof HTMLInputElement &&
    sendBtn instanceof HTMLElement &&
    mobileSubmit instanceof HTMLElement &&
    shown(mobileInput) && !mobileInput.disabled &&
    shown(captchaInput) && !captchaInput.disabled &&
    shown(smsInput) && !smsInput.disabled &&
    (shown(mobileSubmit) || shown(mobileSubmitSpan)) && !mobileSubmit.disabled &&
    services.length === 1 && noCredentialArgs) {
  const readMobileState = () => {
    const activeChooser = document.querySelector(
      '#accountForm .login-popup-box, #accountForm div[name="numbercard"]'
    );
    if (activeChooser && shown(activeChooser)) {
      return { form: 'mobile', requiresAccountChoice: true };
    }
    const dedicated = errorBoxText();
    const sentNotice = /发送成功|已发送/.test(dedicated);
    const sendText = (sendBtn.textContent ?? '').trim();
    const timerMatch = /(\d+)\s*秒/.exec(sendText);
    const cooldownSeconds = timerMatch
        ? Math.min(300, Math.max(0, parseInt(timerMatch[1], 10)))
        : 0;
    const canSendSms = !sendBtn.disabled && cooldownSeconds === 0 && !/秒/.test(sendText);
    const error = sentNotice ? 'none' : classifyMobileError(dedicated);
    const smsSent = error === 'none' && (sentNotice || cooldownSeconds > 0 || sendBtn.disabled);
    return {
      form: 'mobile',
      error,
      smsSent,
      cooldownSeconds,
      canSendSms,
      captchaDataUrl: shown(captchaImg) ? renderPngDataUrl(captchaImg) : null,
      requiresAccountChoice: false,
    };
  };
  if (noMobileArgs) {
    return readMobileState();
  }
  if (action === 'refreshCaptcha' && phone === null && captcha === null && mobileCode === null) {
    await new Promise(resolve => {
      let done = false;
      const finish = () => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        captchaImg.removeEventListener('load', finish);
        captchaImg.removeEventListener('error', finish);
        resolve();
      };
      const timer = setTimeout(finish, 4000);
      captchaImg.addEventListener('load', finish, { once: true });
      captchaImg.addEventListener('error', finish, { once: true });
      captchaImg.click();
    });
    return readMobileState();
  }
  if (action === 'sendMobileSms') {
    if (typeof phone !== 'string' || !/^0?1\d{10}$/.test(phone) ||
        typeof captcha !== 'string' || !captcha.trim() || captcha.length > 16 ||
        sendBtn.disabled || /(\d+)\s*秒/.test(sendBtn.textContent ?? '') ||
        mobileCode !== null) {
      return false;
    }
    mobileInput.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true }));
    mobileInput.value = phone;
    mobileInput.dispatchEvent(new Event('input', { bubbles: true }));
    mobileInput.dispatchEvent(new Event('change', { bubbles: true }));
    captchaInput.value = captcha;
    captchaInput.dispatchEvent(new Event('input', { bubbles: true }));
    captchaInput.dispatchEvent(new Event('change', { bubbles: true }));
    sendBtn.click();
    return true;
  }
  if (action === 'submitMobile') {
    if (typeof phone !== 'string' || !/^0?1\d{10}$/.test(phone) ||
        typeof mobileCode !== 'string' || !/^\d{6}$/.test(mobileCode) ||
        captcha !== null) {
      return false;
    }
    mobileInput.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true }));
    mobileInput.value = phone;
    mobileInput.dispatchEvent(new Event('input', { bubbles: true }));
    mobileInput.dispatchEvent(new Event('change', { bubbles: true }));
    smsInput.value = mobileCode;
    smsInput.dispatchEvent(new Event('input', { bubbles: true }));
    smsInput.dispatchEvent(new Event('change', { bubbles: true }));
    mobileSubmit.click();
    return true;
  }
  return null;
}
const user = document.getElementById('un');
const secret = document.getElementById('pd');
if (!noMobileArgs || !(user instanceof HTMLInputElement) || user.type !== 'text' ||
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
