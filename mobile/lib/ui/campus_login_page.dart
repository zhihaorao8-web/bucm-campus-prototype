import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../config/network_policy.dart';
import '../design/app_tokens.dart';
import '../platform/campus_login_navigation.dart';
import '../platform/campus_native_login.dart';
import '../platform/classroom_page_scripts.dart';
import '../platform/school_adapter.dart';
import '../platform/webview_identity.dart';
import 'app_controls.dart';
import 'app_icons.dart';
import 'campus_login_forms.dart';

/// Completes when the selected service is usable in the official WebView.
/// Callers retain their own task context and receive only a success result.
Future<bool> openCampusLogin(
  BuildContext context, {
  required CampusLoginTarget target,
  required String reason,
}) async =>
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CampusLoginPage(target: target, reason: reason),
      ),
    ) ??
    false;

class CampusLoginPage extends StatefulWidget {
  const CampusLoginPage({
    super.key,
    required this.target,
    required this.reason,
  });

  final CampusLoginTarget target;
  final String reason;

  @override
  State<CampusLoginPage> createState() => _CampusLoginPageState();
}

class _PasswordAttempt {
  _PasswordAttempt(this.service, this.savedCandidate, this.credentialRevision);

  final String service;
  final CampusCredentials? savedCandidate;
  final int credentialRevision;
  bool authenticatedReturn = false;
  bool passwordDispatched = false;
  bool challenged = false;
  bool smsDispatched = false;
  int? submittingDocument;

  CampusCredentials? get verifiedCandidate =>
      authenticatedReturn &&
          passwordDispatched &&
          (!challenged || smsDispatched)
      ? savedCandidate
      : null;
}

enum _MobilePendingAction { none, sendSms, submitLogin }

class _CampusLoginPageState extends State<CampusLoginPage>
    with WidgetsBindingObserver {
  InAppWebViewController? _web;
  Timer? _timeout;
  Timer? _poll;
  Timer? _qrPoll;
  Timer? _mobilePoll;
  final _requestedHttpsUpgrades = <Uri>{};
  final _classroomScripts = ClassroomPageScripts();
  int _document = 0;
  int _probeSeq = 0;
  int _httpsUpgrades = 0;
  bool _loading = true;
  bool _switching = false;
  bool _retryDefaultSelect = false;
  bool _completed = false;
  CampusLoginMethod? _method;
  String? _error;
  ({
    CampusNativeForm form,
    String address,
    String service,
    String? notice,
    bool expired,
  })?
  _nativeForm;
  _PasswordAttempt? _passwordAttempt;
  bool _nativeBusy = false;
  bool _probingNative = false;
  bool _manualWeb = false;
  String? _nativeError;
  int _clearPasswordToken = 0;
  int _smsResetCount = 0;
  CampusQrState _qrState = CampusQrState.loading;
  Uint8List? _qrBytes;
  bool _qrSaving = false;
  bool _qrRefreshing = false;
  String? _qrNotice;
  String? _qrError;
  Set<CampusScanClient>? _availableScanClients;
  bool _clientsQueried = false;
  int _qrLoadingPolls = 0;
  Uint8List? _captchaBytes;
  bool _captchaLoading = false;
  bool _mobileSmsSending = false;
  int _mobileCooldownSeconds = 0;
  bool _mobileCanSendSms = true;
  bool _mobileSmsSent = false;
  _MobilePendingAction _mobileAction = _MobilePendingAction.none;
  String? _mobileNotice;
  String? _mobileError;
  int _clearCaptchaToken = 0;
  int _mobileWaitPolls = 0;

  bool _current(InAppWebViewController web, int document) =>
      mounted &&
      !_completed &&
      sameWebViewController(web, _web) &&
      document == _document;

  bool get _waitingForSchool =>
      widget.target != CampusLoginTarget.vpn &&
      !_manualWeb &&
      _nativeForm == null &&
      (_probingNative || _nativeBusy || _passwordAttempt != null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SchoolAdapter.sessionChanges.addListener(_sessionCleared);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SchoolAdapter.sessionChanges.removeListener(_sessionCleared);
    _cancelTimers();
    _passwordAttempt = null;
    _clearQrState();
    _clearMobileState();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Lifecycle return must never auto-resubmit credentials or auto-send SMS.
    if (state == AppLifecycleState.paused) {
      _qrPoll?.cancel();
      _mobilePoll?.cancel();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      final web = _web;
      if (web != null &&
          !_completed &&
          _error == null &&
          !_manualWeb &&
          widget.target != CampusLoginTarget.vpn) {
        unawaited(_recheckAfterResume(web, _document));
      }
    }
  }

  void _cancelTimers() {
    _timeout?.cancel();
    _poll?.cancel();
    _qrPoll?.cancel();
    _mobilePoll?.cancel();
  }

  void _clearQrState() {
    _qrPoll?.cancel();
    _qrState = CampusQrState.loading;
    _qrBytes = null;
    _qrSaving = false;
    _qrRefreshing = false;
    _qrNotice = null;
    _qrError = null;
    _qrLoadingPolls = 0;
  }

  void _clearMobileState() {
    _mobilePoll?.cancel();
    _captchaBytes = null;
    _captchaLoading = false;
    _mobileSmsSending = false;
    _mobileCooldownSeconds = 0;
    _mobileCanSendSms = true;
    _mobileSmsSent = false;
    _mobileAction = _MobilePendingAction.none;
    _mobileNotice = null;
    _mobileError = null;
    _mobileWaitPolls = 0;
  }

  void _sessionCleared() {
    final web = _web;
    if (web != null) _fail(web, '学校会话已清除，请重新登录。');
  }

  void _fail(InAppWebViewController web, String message) {
    if (!mounted || !sameWebViewController(web, _web) || _completed) return;
    _cancelTimers();
    _probeSeq++;
    setState(() {
      _web = null;
      _document++;
      _httpsUpgrades = 0;
      _requestedHttpsUpgrades.clear();
      _loading = false;
      _method = null;
      _nativeForm = null;
      _passwordAttempt = null;
      _nativeBusy = false;
      _probingNative = false;
      _nativeError = null;
      _clearQrState();
      _clearMobileState();
      _switching = false;
      _retryDefaultSelect = false;
      _error = message;
    });
  }

  void _waitForPage(InAppWebViewController web, String message) {
    _timeout?.cancel();
    final document = _document;
    _timeout = Timer(CampusLoginPolicy.pageTimeout, () {
      if (widget.target == CampusLoginTarget.vpn) {
        // A visible WebVPN form can precede both Android page callbacks.
        unawaited(_inspectPage(web, document, timeoutError: message));
      } else {
        _fail(web, message);
      }
    });
  }

  void _scheduleSubmitCheck(InAppWebViewController web, int document) {
    _poll?.cancel();
    _poll = Timer(
      CampusLoginPolicy.readinessPoll,
      () => unawaited(_probeNativeForm(web, document, afterSubmit: true)),
    );
  }

  bool _isReplacedHttpNavigation(String? address) => _requestedHttpsUpgrades
      .contains(widget.target.upgradeSameHostHttps(address));

  bool _checkDocument(InAppWebViewController web, WebUri? url) {
    if (!mounted || !sameWebViewController(web, _web) || _completed) {
      return false;
    }
    if (url == null) return false;
    final address = url.toString();
    if (widget.target.allows(address)) return true;
    // Android can deliver a page callback for the canceled HTTP request while
    // the replacement HTTPS document is loading.
    if (_isReplacedHttpNavigation(address)) return false;
    _fail(web, '已停止打开非当前学校服务或统一身份认证的页面。');
    return false;
  }

  Future<void> _inspectPage(
    InAppWebViewController web,
    int document, {
    String? timeoutError,
  }) async {
    if (!_current(web, document)) return;
    bool ready;
    bool vpnLogin = false;
    try {
      if (widget.target == CampusLoginTarget.classroom) {
        final result = await _classroomScripts
            .command(web, {'action': 'snapshot'})
            .timeout(CampusLoginPolicy.readinessPoll);
        ready = result['state'] == 'catalog';
      } else if (widget.target.asyncReadiness) {
        final result = await web
            .callAsyncJavaScript(functionBody: widget.target.readinessScript)
            .timeout(CampusLoginPolicy.asyncReadinessTimeout);
        ready = result?.error == null && result?.value == true;
      } else {
        ready =
            await web
                .evaluateJavascript(source: widget.target.readinessScript)
                .timeout(CampusLoginPolicy.readinessPoll) ==
            true;
      }
      if (!ready &&
          widget.target == CampusLoginTarget.vpn &&
          _current(web, document)) {
        vpnLogin =
            await web
                .evaluateJavascript(source: campusVpnLoginScript)
                .timeout(CampusLoginPolicy.readinessPoll) ==
            true;
      }
    } catch (_) {
      ready = false;
    }
    if (!mounted || !_current(web, document)) return;
    if (vpnLogin) {
      _timeout?.cancel();
      if (_loading) setState(() => _loading = false);
    } else if (!ready && timeoutError != null) {
      _fail(web, timeoutError);
      return;
    }
    if (ready && ModalRoute.of(context)?.isCurrent == true) {
      await _finishLogin();
      return;
    }
    _poll?.cancel();
    _poll = Timer(
      CampusLoginPolicy.readinessPoll,
      () => _inspectPage(web, document),
    );
  }

  Future<void> _finishLogin() async {
    final sessionRevision = SchoolAdapter.sessionChanges.value;
    final attempt = _passwordAttempt;
    final candidate = attempt?.verifiedCandidate;
    _completed = true;
    _cancelTimers();
    _passwordAttempt = null;
    _clearQrState();
    _clearMobileState();
    if (candidate != null) {
      try {
        final saved = await CampusNativeLogin.save(
          candidate,
          revision: attempt!.credentialRevision,
        );
        if (!saved &&
            mounted &&
            sessionRevision == SchoolAdapter.sessionChanges.value) {
          showAppNotice(context, '已登录，校园账号密码未保存。');
        }
      } catch (_) {
        if (mounted && sessionRevision == SchoolAdapter.sessionChanges.value) {
          showAppNotice(context, '已登录，未能在本机保存校园账号密码。');
        }
      }
    }
    if (!mounted) return;
    if (sessionRevision != SchoolAdapter.sessionChanges.value) {
      setState(() {
        _completed = false;
        _web = null;
        _document++;
        _httpsUpgrades = 0;
        _requestedHttpsUpgrades.clear();
        _loading = false;
        _method = null;
        _nativeForm = null;
        _nativeBusy = false;
        _probingNative = false;
        _nativeError = null;
        _clearQrState();
        _clearMobileState();
        _switching = false;
        _retryDefaultSelect = false;
        _error = '学校会话已清除，请重新登录。';
      });
      return;
    }
    if (ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop(true);
    }
  }

  void _cancelLogin() {
    _cancelTimers();
    _passwordAttempt = null;
    _clearQrState();
    _clearMobileState();
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop(false);
    }
  }

  void _observeServiceReturn(String? address) {
    final attempt = _passwordAttempt;
    if (attempt != null &&
        CampusNativeLogin.isServiceReturn(address, attempt.service)) {
      attempt.authenticatedReturn = true;
    }
  }

  Future<void> _probeNativeForm(
    InAppWebViewController web,
    int document, {
    bool afterSubmit = false,
  }) async {
    if (_manualWeb ||
        !_current(web, document) ||
        (!afterSubmit &&
            _nativeBusy &&
            _passwordAttempt?.submittingDocument == document)) {
      return;
    }
    final seq = ++_probeSeq;
    if (!afterSubmit && _nativeForm == null && !_probingNative) {
      setState(() => _probingNative = true);
    }
    try {
      final address = (await web.getUrl())?.toString();
      if (address == null || !_current(web, document) || _manualWeb) return;
      final attempt = _passwordAttempt;
      final passwordService = CampusNativeLogin.serviceFor(
        address,
        widget.target,
      );
      final service =
          passwordService ??
          (attempt != null && attempt.passwordDispatched
              ? CampusNativeLogin.smsServiceFor(
                  address,
                  widget.target,
                  attempt.service,
                )
              : null);
      if (service == null) {
        if (afterSubmit) {
          _scheduleSubmitCheck(web, document);
          return;
        }
        if (attempt != null) _openOfficialForm();
        return;
      }
      final result = await CampusNativeLogin.perform(
        web,
        address: address,
        service: service,
      ).timeout(CampusLoginPolicy.readinessPoll);
      if (seq != _probeSeq || !_current(web, document) || _manualWeb) return;
      final probe = CampusNativeLogin.parseProbe(result);
      if (probe == null) {
        if (afterSubmit) {
          _scheduleSubmitCheck(web, document);
          return;
        }
        if (attempt != null) _openOfficialForm();
        return;
      }

      if (probe.form == CampusNativeForm.password) {
        if (passwordService != service ||
            (_method != CampusLoginMethod.password && attempt == null)) {
          if (afterSubmit) {
            _scheduleSubmitCheck(web, document);
            return;
          }
          if (attempt != null) _openOfficialForm();
          return;
        }
        if (afterSubmit && probe.errorKind == CampusNativeErrorKind.none) {
          _scheduleSubmitCheck(web, document);
          return;
        }
        final attemptedHere = attempt != null && attempt.service == service;
        if (afterSubmit) _cancelTimers();
        setState(() {
          _probingNative = false;
          _nativeForm = (
            form: CampusNativeForm.password,
            address: address,
            service: service,
            notice: null,
            expired: false,
          );
          _nativeBusy = false;
          if (attemptedHere) {
            _method = CampusLoginMethod.password;
            _passwordAttempt = null;
            if (probe.errorKind == CampusNativeErrorKind.invalidPassword) {
              _nativeError = '账号或密码错误，请修改密码后重试。';
              _clearPasswordToken++;
            } else if (attempt.challenged) {
              _nativeError = '短信验证已过期或失效，请重新登录。';
              _clearPasswordToken++;
            } else {
              _nativeError = '学校未完成账号验证，请核对后重试。';
            }
          } else if (probe.errorKind == CampusNativeErrorKind.invalidPassword) {
            _nativeError = '账号或密码错误，请修改密码后重试。';
          }
        });
        return;
      }

      if (probe.form == CampusNativeForm.qr) {
        if (passwordService != service ||
            _method != CampusLoginMethod.qr ||
            attempt != null) {
          if (attempt != null) _openOfficialForm();
          return;
        }
        _qrPoll?.cancel();
        var shouldPollSoon = false;
        var shouldWatchExpiry = false;
        String? nextError;
        if (probe.qrState == CampusQrState.loading) {
          if (++_qrLoadingPolls < 12) {
            shouldPollSoon = true;
          } else {
            nextError = '暂未获取到二维码，请点击刷新或打开学校官方页面。';
          }
        } else if (probe.qrState == CampusQrState.ready) {
          _qrLoadingPolls = 0;
          shouldWatchExpiry = true;
        } else {
          _qrLoadingPolls = 0;
        }
        setState(() {
          _probingNative = false;
          _nativeBusy = false;
          _nativeError = null;
          _qrRefreshing = false;
          _qrState = probe.qrState;
          _qrBytes = probe.qrState == CampusQrState.ready
              ? probe.qrBytes
              : null;
          if (probe.qrState == CampusQrState.expired) {
            _qrNotice = null;
            _qrError = null;
          } else if (nextError != null) {
            _qrError = nextError;
          }
          _nativeForm = (
            form: CampusNativeForm.qr,
            address: address,
            service: service,
            notice: null,
            expired: probe.qrState == CampusQrState.expired,
          );
        });
        if (shouldPollSoon) {
          _qrPoll = Timer(
            CampusLoginPolicy.readinessPoll,
            () => unawaited(_probeNativeForm(web, document)),
          );
        } else if (shouldWatchExpiry) {
          _qrPoll = Timer(
            const Duration(seconds: 2),
            () => unawaited(_probeNativeForm(web, document)),
          );
        }
        return;
      }

      if (probe.form == CampusNativeForm.mobile) {
        if (passwordService != service ||
            _method != CampusLoginMethod.mobile ||
            attempt != null) {
          if (afterSubmit) {
            _scheduleSubmitCheck(web, document);
            return;
          }
          if (attempt != null) _openOfficialForm();
          return;
        }
        if (probe.requiresAccountChoice) {
          _openOfficialForm();
          if (mounted) {
            showAppNotice(context, '该手机号绑定了多个校园账号，请在官方页面选择账号完成登录。');
          }
          return;
        }
        _mobilePoll?.cancel();
        var nextAction = _mobileAction;
        var nextSmsSending = _mobileSmsSending;
        var nextBusy = _nativeBusy;
        var nextNotice = _mobileNotice;
        var nextError = _mobileError;
        var clearCaptcha = false;
        var nextCaptchaLoading = _captchaLoading;
        Timer? followUp;

        if (nextAction == _MobilePendingAction.sendSms) {
          if (probe.errorKind != CampusNativeErrorKind.none) {
            nextAction = _MobilePendingAction.none;
            nextSmsSending = false;
            _mobileWaitPolls = 0;
            clearCaptcha = true;
            nextNotice = null;
            nextError = _mobileErrorMessage(probe.errorKind, forSmsSend: true);
          } else if (probe.smsSent ||
              probe.smsCooldownSeconds > 0 ||
              !probe.canSendSms) {
            nextAction = _MobilePendingAction.none;
            nextSmsSending = false;
            _mobileWaitPolls = 0;
            nextError = null;
            nextNotice = '短信验证码已发送，请注意查收。';
          } else if (++_mobileWaitPolls < 20) {
            followUp = Timer(
              CampusLoginPolicy.readinessPoll,
              () => unawaited(_probeNativeForm(web, document)),
            );
          } else {
            nextAction = _MobilePendingAction.none;
            nextSmsSending = false;
            _mobileWaitPolls = 0;
            nextNotice = null;
            nextError = '学校暂未返回短信发送结果，请重试或打开学校官方页面。';
          }
        } else if (nextAction == _MobilePendingAction.submitLogin) {
          if (probe.errorKind != CampusNativeErrorKind.none) {
            _cancelTimers();
            nextAction = _MobilePendingAction.none;
            nextBusy = false;
            _mobileWaitPolls = 0;
            nextNotice = null;
            nextError = _mobileErrorMessage(probe.errorKind, forSmsSend: false);
          } else if (afterSubmit) {
            followUp = Timer(
              CampusLoginPolicy.readinessPoll,
              () =>
                  unawaited(_probeNativeForm(web, document, afterSubmit: true)),
            );
          }
        }

        if (probe.captchaBytes != null) {
          nextCaptchaLoading = false;
          if (nextAction == _MobilePendingAction.none) {
            _mobileWaitPolls = 0;
          }
        } else if (clearCaptcha ||
            (nextAction == _MobilePendingAction.none &&
                _captchaBytes == null &&
                !nextSmsSending)) {
          if (++_mobileWaitPolls < 12) {
            nextCaptchaLoading = true;
            followUp ??= Timer(
              CampusLoginPolicy.readinessPoll,
              () => unawaited(_probeNativeForm(web, document)),
            );
          } else {
            nextCaptchaLoading = false;
          }
        }
        if (nextAction == _MobilePendingAction.none &&
            probe.smsCooldownSeconds > 0) {
          followUp ??= Timer(
            const Duration(seconds: 1),
            () => unawaited(_probeNativeForm(web, document)),
          );
        }

        setState(() {
          _probingNative = false;
          _nativeBusy = nextBusy;
          _nativeError = null;
          _mobileAction = nextAction;
          _mobileSmsSending = nextSmsSending;
          _mobileNotice = nextNotice;
          _mobileError = nextError;
          _captchaLoading = nextCaptchaLoading;
          if (probe.captchaBytes != null) {
            _captchaBytes = probe.captchaBytes;
          }
          _mobileCooldownSeconds = probe.smsCooldownSeconds;
          _mobileCanSendSms = probe.canSendSms;
          if (probe.smsSent || probe.smsCooldownSeconds > 0) {
            _mobileSmsSent = true;
          }
          if (clearCaptcha) {
            _clearCaptchaToken++;
          }
          _nativeForm = (
            form: CampusNativeForm.mobile,
            address: address,
            service: service,
            notice: null,
            expired: false,
          );
        });
        if (followUp != null) {
          _mobilePoll = followUp;
        }
        return;
      }

      if (probe.form != CampusNativeForm.sms) {
        if (afterSubmit) {
          _scheduleSubmitCheck(web, document);
          return;
        }
        if (attempt != null) _openOfficialForm();
        return;
      }

      // SMS challenge form.
      if (attempt == null ||
          attempt.service != service ||
          !attempt.passwordDispatched) {
        if (afterSubmit) {
          _scheduleSubmitCheck(web, document);
          return;
        }
        if (attempt != null) _openOfficialForm();
        return;
      }
      if (afterSubmit &&
          attempt.smsDispatched &&
          probe.errorKind == CampusNativeErrorKind.none) {
        _scheduleSubmitCheck(web, document);
        return;
      }
      if (afterSubmit) _cancelTimers();
      attempt.challenged = true;
      final notice = switch ((probe.maskedPhone, probe.smsSent)) {
        (final phone?, true) => '验证码已发送至 $phone',
        (final phone?, false) => '验证手机号：$phone',
        (null, true) => '学校已发送短信验证码，请查收。',
        (null, false) => null,
      };
      var expired = false;
      String? errorMessage;
      switch (probe.errorKind) {
        case CampusNativeErrorKind.smsExpired:
          expired = true;
          errorMessage = '短信验证码或本次验证已过期，请取消后重新登录。';
        case CampusNativeErrorKind.smsRateLimited:
          errorMessage = '短信验证次数受限或操作过于频繁，请稍后再试。';
        case CampusNativeErrorKind.smsSendFailed:
          errorMessage = '学校未能发送短信验证码，请稍后重试或打开学校官方页面。';
        case CampusNativeErrorKind.invalidSmsCode:
          errorMessage = '短信验证码错误，请核对后重试。';
        case CampusNativeErrorKind.generic:
        case CampusNativeErrorKind.invalidPassword:
        case CampusNativeErrorKind.invalidPhone:
        case CampusNativeErrorKind.invalidCaptcha:
          errorMessage = '学校未通过短信验证，请核对验证码后重试。';
        case CampusNativeErrorKind.none:
          if (attempt.smsDispatched) {
            errorMessage = '学校未通过短信验证，请核对验证码后重试。';
          }
      }
      setState(() {
        _probingNative = false;
        _nativeForm = (
          form: CampusNativeForm.sms,
          address: address,
          service: service,
          notice: notice,
          expired: expired,
        );
        _nativeBusy = false;
        _nativeError = errorMessage;
        if (expired) {
          _passwordAttempt = null;
        }
        if (attempt.smsDispatched) {
          attempt.smsDispatched = false;
          _smsResetCount++;
        }
      });
    } catch (_) {
      if (afterSubmit && _current(web, document)) {
        _scheduleSubmitCheck(web, document);
      } else if (_current(web, document) && _nativeForm == null) {
        _openOfficialForm();
      }
    } finally {
      if (mounted && seq == _probeSeq && _probingNative) {
        setState(() => _probingNative = false);
      }
    }
  }

  Future<void> _submitNative({
    CampusCredentials? credentials,
    bool remember = false,
    String? code,
  }) async {
    final web = _web;
    final form = _nativeForm;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (web == null ||
        form == null ||
        _nativeBusy ||
        _completed ||
        ModalRoute.of(context)?.isCurrent != true ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      return;
    }
    if (form.form == CampusNativeForm.sms && form.expired) {
      setState(() {
        _nativeError = '短信验证码或本次验证已过期，请取消后重新登录。';
      });
      return;
    }
    final document = _document;
    final attempt =
        credentials != null && form.form == CampusNativeForm.password
        ? _PasswordAttempt(
            form.service,
            remember ? credentials : null,
            CampusNativeLogin.revision,
          )
        : _passwordAttempt;
    if (attempt == null) return;
    attempt.submittingDocument = document;
    _passwordAttempt = attempt;
    setState(() {
      _nativeBusy = true;
      _nativeError = null;
    });
    bool dispatched = false;
    try {
      dispatched =
          await CampusNativeLogin.perform(
            web,
            address: form.address,
            service: form.service,
            credentials: credentials,
            code: code,
          ).timeout(CampusLoginPolicy.readinessPoll) ==
          true;
    } catch (_) {
      // The official page is the safe recovery path for an unknown result.
    }
    if (!mounted || !identical(attempt, _passwordAttempt)) return;
    if (!dispatched) {
      _openOfficialForm();
      return;
    }
    if (credentials != null) {
      attempt.passwordDispatched = true;
    } else {
      attempt.smsDispatched = true;
    }
    if (_current(web, document)) {
      _waitForPage(web, '学校暂未确认登录，请重新尝试。');
      _scheduleSubmitCheck(web, document);
    }
  }

  String _mobileErrorMessage(
    CampusNativeErrorKind kind, {
    required bool forSmsSend,
  }) => switch (kind) {
    CampusNativeErrorKind.invalidPhone => '手机号格式错误或未在学校登记。',
    CampusNativeErrorKind.invalidCaptcha => '图形验证码错误，请重新输入。',
    CampusNativeErrorKind.invalidSmsCode =>
      forSmsSend ? '图形验证码错误，已刷新，请重新输入。' : '短信验证码错误，请核对后重试。',
    CampusNativeErrorKind.smsRateLimited => '短信发送过于频繁或次数已达上限，请稍后再试。',
    CampusNativeErrorKind.smsSendFailed => '学校未能发送短信验证码，请稍后重试。',
    CampusNativeErrorKind.smsExpired => '短信验证码已过期，请重新获取。',
    CampusNativeErrorKind.generic ||
    CampusNativeErrorKind.invalidPassword ||
    CampusNativeErrorKind.none =>
      forSmsSend ? '未能发送短信验证码，请核对后重试。' : '学校未完成手机登录，请核对后重试。',
  };

  Future<void> _recheckAfterResume(
    InAppWebViewController web,
    int document,
  ) async {
    if (!_current(web, document) ||
        _manualWeb ||
        widget.target == CampusLoginTarget.vpn) {
      return;
    }
    final address = (await web.getUrl())?.toString();
    if (address == null || !_current(web, document) || _manualWeb) return;
    if (widget.target.isDestination(address)) {
      _observeServiceReturn(address);
      final nextDocument = ++_document;
      _waitForPage(web, '学校服务暂未就绪，请检查网络后重试。');
      unawaited(_inspectPage(web, nextDocument));
      return;
    }
    if (campusCasForm(address) &&
        (_method == CampusLoginMethod.qr ||
            _method == CampusLoginMethod.mobile)) {
      unawaited(_probeNativeForm(web, document));
    }
  }

  Future<void> _loadScanClients() async {
    final clients = await CampusNativeLogin.availableScanClients();
    if (mounted) {
      setState(() => _availableScanClients = clients);
    }
  }

  Future<void> _saveQr() async {
    final form = _nativeForm;
    final bytes = _qrBytes;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (form == null ||
        form.form != CampusNativeForm.qr ||
        _qrState != CampusQrState.ready ||
        bytes == null ||
        _qrSaving ||
        _qrRefreshing ||
        _completed ||
        ModalRoute.of(context)?.isCurrent != true ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      return;
    }
    setState(() {
      _qrSaving = true;
      _qrError = null;
      _qrNotice = null;
    });
    try {
      await CampusNativeLogin.saveQrImage(bytes);
      if (!mounted || _completed || _method != CampusLoginMethod.qr) return;
      setState(() {
        _qrSaving = false;
        _qrNotice = '二维码已保存到系统相册，请在企业微信或微信扫一扫中从相册选择。';
      });
    } on PlatformException catch (error) {
      if (!mounted || _completed || _method != CampusLoginMethod.qr) return;
      setState(() {
        _qrSaving = false;
        _qrError =
            error.code == 'QR_PERMISSION_DENIED' &&
                (error.message?.isNotEmpty ?? false)
            ? error.message!
            : '无法保存二维码到系统相册，请重试或使用另一台设备扫码。';
      });
    } catch (_) {
      if (!mounted || _completed || _method != CampusLoginMethod.qr) return;
      setState(() {
        _qrSaving = false;
        _qrError = '无法保存二维码到系统相册，请重试或使用另一台设备扫码。';
      });
    }
  }

  Future<void> _refreshQr() async {
    final web = _web;
    final form = _nativeForm;
    if (web == null ||
        form == null ||
        form.form != CampusNativeForm.qr ||
        _qrSaving ||
        _qrRefreshing ||
        _completed) {
      return;
    }
    final document = _document;
    final seq = ++_probeSeq;
    _qrPoll?.cancel();
    setState(() {
      _qrRefreshing = true;
      _qrBytes = null;
      _qrState = CampusQrState.loading;
      _qrNotice = null;
      _qrError = null;
      _qrLoadingPolls = 0;
    });
    CampusNativeProbe? probe;
    try {
      final raw = await CampusNativeLogin.perform(
        web,
        address: form.address,
        service: form.service,
        action: 'refreshQr',
      ).timeout(CampusLoginPolicy.readinessPoll);
      probe = CampusNativeLogin.parseProbe(raw);
    } catch (_) {
      probe = null;
    }
    if (seq != _probeSeq ||
        !_current(web, document) ||
        _manualWeb ||
        _method != CampusLoginMethod.qr) {
      return;
    }
    if (probe != null && probe.form == CampusNativeForm.qr) {
      final resolved = probe;
      setState(() {
        _qrRefreshing = false;
        _qrState = resolved.qrState;
        _qrBytes = resolved.qrState == CampusQrState.ready
            ? resolved.qrBytes
            : null;
        _nativeForm = (
          form: CampusNativeForm.qr,
          address: form.address,
          service: form.service,
          notice: null,
          expired: resolved.qrState == CampusQrState.expired,
        );
      });
      if (resolved.qrState == CampusQrState.loading) {
        _qrPoll = Timer(
          CampusLoginPolicy.readinessPoll,
          () => unawaited(_probeNativeForm(web, document)),
        );
      } else if (resolved.qrState == CampusQrState.ready) {
        _qrPoll = Timer(
          const Duration(seconds: 2),
          () => unawaited(_probeNativeForm(web, document)),
        );
      }
      return;
    }
    setState(() {
      _qrRefreshing = false;
      _qrError = '未能刷新二维码，请重试或打开学校官方页面。';
    });
  }

  Future<void> _launchScanClient(CampusScanClient client) async {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (_qrSaving ||
        _completed ||
        ModalRoute.of(context)?.isCurrent != true ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      return;
    }
    final result = await CampusNativeLogin.launchScanClient(client);
    if (!mounted || _completed || _method != CampusLoginMethod.qr) return;
    setState(() {
      switch (result) {
        case CampusScanLaunchResult.launched:
          _qrError = null;
          _qrNotice = '已打开${client.label}，请在扫一扫中从相册选择刚保存的二维码，完成后返回本页。';
        case CampusScanLaunchResult.notInstalled:
          _qrError = '当前设备未安装${client.label}，可先保存二维码或使用另一台设备扫码。';
        case CampusScanLaunchResult.failed:
          _qrError = '未能打开${client.label}，请手动打开并从相册选择二维码，或用另一台设备扫码。';
      }
    });
  }

  Future<void> _refreshMobileCaptcha() async {
    final web = _web;
    final form = _nativeForm;
    if (web == null ||
        form == null ||
        form.form != CampusNativeForm.mobile ||
        _nativeBusy ||
        _mobileSmsSending ||
        _captchaLoading ||
        _completed) {
      return;
    }
    final document = _document;
    final seq = ++_probeSeq;
    setState(() {
      _captchaLoading = true;
      _mobileError = null;
    });
    try {
      final raw = await CampusNativeLogin.perform(
        web,
        address: form.address,
        service: form.service,
        action: 'refreshCaptcha',
      ).timeout(const Duration(seconds: 6));
      if (seq != _probeSeq ||
          !_current(web, document) ||
          _manualWeb ||
          _method != CampusLoginMethod.mobile) {
        return;
      }
      final probe = CampusNativeLogin.parseProbe(raw);
      setState(() {
        _captchaLoading = false;
        if (probe != null && probe.form == CampusNativeForm.mobile) {
          if (probe.captchaBytes != null) {
            _captchaBytes = probe.captchaBytes;
          } else {
            _mobileError = '暂未获取到新图形验证码，请重试。';
          }
        } else {
          _mobileError = '未能刷新图形验证码，请重试。';
        }
      });
    } catch (_) {
      if (mounted && seq == _probeSeq && _method == CampusLoginMethod.mobile) {
        setState(() {
          _captchaLoading = false;
          _mobileError = '未能刷新图形验证码，请重试。';
        });
      }
    }
  }

  Future<void> _requestMobileSms(String phone, String captcha) async {
    final web = _web;
    final form = _nativeForm;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (web == null ||
        form == null ||
        form.form != CampusNativeForm.mobile ||
        _nativeBusy ||
        _mobileSmsSending ||
        !_mobileCanSendSms ||
        _mobileCooldownSeconds > 0 ||
        _completed ||
        ModalRoute.of(context)?.isCurrent != true ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      return;
    }
    final document = _document;
    final seq = ++_probeSeq;
    _mobilePoll?.cancel();
    setState(() {
      _mobileSmsSending = true;
      _mobileAction = _MobilePendingAction.sendSms;
      _mobileWaitPolls = 0;
      _mobileError = null;
      _mobileNotice = null;
    });
    var dispatched = false;
    try {
      dispatched =
          await CampusNativeLogin.perform(
            web,
            address: form.address,
            service: form.service,
            action: 'sendMobileSms',
            phone: phone,
            captcha: captcha,
          ).timeout(CampusLoginPolicy.readinessPoll) ==
          true;
    } catch (_) {
      dispatched = false;
    }
    if (seq != _probeSeq ||
        !_current(web, document) ||
        _manualWeb ||
        _method != CampusLoginMethod.mobile) {
      return;
    }
    if (!dispatched) {
      setState(() {
        _mobileSmsSending = false;
        _mobileAction = _MobilePendingAction.none;
        _mobileError = '未能发起短信发送，请核对后重试或打开学校官方页面。';
      });
      return;
    }
    _mobilePoll = Timer(
      CampusLoginPolicy.readinessPoll,
      () => unawaited(_probeNativeForm(web, document)),
    );
  }

  Future<void> _submitMobile(String phone, String smsCode) async {
    final web = _web;
    final form = _nativeForm;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (web == null ||
        form == null ||
        form.form != CampusNativeForm.mobile ||
        _nativeBusy ||
        _mobileSmsSending ||
        _completed ||
        ModalRoute.of(context)?.isCurrent != true ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      return;
    }
    final document = _document;
    final seq = ++_probeSeq;
    _mobilePoll?.cancel();
    _passwordAttempt = null;
    setState(() {
      _nativeBusy = true;
      _mobileAction = _MobilePendingAction.submitLogin;
      _mobileWaitPolls = 0;
      _mobileError = null;
      _mobileNotice = null;
    });
    var dispatched = false;
    try {
      dispatched =
          await CampusNativeLogin.perform(
            web,
            address: form.address,
            service: form.service,
            action: 'submitMobile',
            phone: phone,
            mobileCode: smsCode,
          ).timeout(CampusLoginPolicy.readinessPoll) ==
          true;
    } catch (_) {
      dispatched = false;
    }
    if (seq != _probeSeq ||
        !_current(web, document) ||
        _manualWeb ||
        _method != CampusLoginMethod.mobile) {
      return;
    }
    if (!dispatched) {
      _openOfficialForm();
      return;
    }
    _waitForPage(web, '学校暂未确认登录，请重新尝试。');
    _scheduleSubmitCheck(web, document);
  }

  void _openOfficialForm() {
    _cancelTimers();
    _probeSeq++;
    setState(() {
      _manualWeb = true;
      _passwordAttempt = null;
      _nativeForm = null;
      _nativeBusy = false;
      _probingNative = false;
      _nativeError = null;
      _clearQrState();
      _clearMobileState();
    });
  }

  Future<void> _select(CampusLoginMethod method) async {
    final web = _web;
    if (web == null || _switching || _completed) return;
    if (method == _method && (_manualWeb || _nativeForm != null)) return;
    final document = _document;
    _cancelTimers();
    _probeSeq++;
    setState(() {
      _switching = true;
      _passwordAttempt = null;
      _nativeForm = null;
      _nativeBusy = false;
      _probingNative = false;
      _nativeError = null;
      _clearQrState();
      _clearMobileState();
    });
    bool selected;
    try {
      selected =
          await web.evaluateJavascript(source: method.selectScript) == true;
    } catch (_) {
      selected = false;
    }
    if (!_current(web, document)) return;
    final shouldRetry =
        !selected &&
        _retryDefaultSelect &&
        method == CampusLoginMethod.password;
    setState(() {
      _method = selected ? method : null;
      _switching = false;
      _retryDefaultSelect = false;
    });
    if (shouldRetry) {
      unawaited(_select(CampusLoginMethod.password));
    } else if (selected && !_manualWeb) {
      if (method == CampusLoginMethod.qr && !_clientsQueried) {
        _clientsQueried = true;
        unawaited(_loadScanClients());
      }
      unawaited(_probeNativeForm(web, document));
    }
  }

  void _loaded(
    InAppWebViewController web,
    WebUri? url, {
    required bool complete,
  }) {
    if (!_checkDocument(web, url)) return;
    _cancelTimers();
    setState(() => _loading = false);
    final address = url.toString();
    if (widget.target != CampusLoginTarget.vpn && campusCasForm(address)) {
      if (_passwordAttempt != null || _method != null) {
        if (!_manualWeb) {
          unawaited(_probeNativeForm(web, _document));
        }
      } else {
        if (_switching && complete) {
          _retryDefaultSelect = true;
        } else {
          unawaited(_select(CampusLoginMethod.password));
        }
      }
    } else if (widget.target.isDestination(address)) {
      _observeServiceReturn(address);
      final document = ++_document;
      _waitForPage(web, '学校服务暂未就绪，请检查网络后重试。');
      unawaited(_inspectPage(web, document));
    }
  }

  Widget? _buildNativeForm() {
    if (widget.target == CampusLoginTarget.vpn || _manualWeb) return null;
    final form = _nativeForm;
    if (form == null) return null;
    return switch (form.form) {
      CampusNativeForm.password => CampusPasswordForm(
        key: const ValueKey('campus-login-password-form'),
        busy: _nativeBusy,
        error: _nativeError,
        clearPasswordToken: _clearPasswordToken,
        onSubmit: (account, password, remember) => unawaited(
          _submitNative(
            credentials: CampusCredentials(
              account: account,
              password: password,
            ),
            remember: remember,
          ),
        ),
      ),
      CampusNativeForm.sms => CampusSmsForm(
        key: ValueKey('campus-login-sms-form-$_smsResetCount'),
        busy: _nativeBusy,
        error: _nativeError,
        notice: form.notice,
        onRequestCode: null,
        onSubmit: (code) => unawaited(_submitNative(code: code)),
        onCancel: _cancelLogin,
      ),
      CampusNativeForm.qr => CampusQrForm(
        key: const ValueKey('campus-login-qr-form'),
        state: _qrState,
        qrBytes: _qrBytes,
        saving: _qrSaving,
        refreshing: _qrRefreshing,
        notice: _qrNotice,
        error: _qrError,
        availableClients: _availableScanClients,
        onSave: () => unawaited(_saveQr()),
        onRefresh: () => unawaited(_refreshQr()),
        onLaunchClient: (client) => unawaited(_launchScanClient(client)),
      ),
      CampusNativeForm.mobile => CampusMobileForm(
        key: const ValueKey('campus-login-mobile-form'),
        busy: _nativeBusy,
        sendingSms: _mobileSmsSending,
        captchaLoading: _captchaLoading,
        captchaBytes: _captchaBytes,
        cooldownSeconds: _mobileCooldownSeconds,
        canSendSms: _mobileCanSendSms,
        smsSent: _mobileSmsSent,
        clearCaptchaToken: _clearCaptchaToken,
        notice: _mobileNotice,
        error: _mobileError,
        onRefreshCaptcha: () => unawaited(_refreshMobileCaptcha()),
        onRequestSms: (phone, captcha) =>
            unawaited(_requestMobileSms(phone, captcha)),
        onSubmit: (phone, code) => unawaited(_submitMobile(phone, code)),
      ),
    };
  }

  Widget _buildWeb() => InAppWebView(
    initialUrlRequest: URLRequest(url: WebUri(widget.target.loginEntry)),
    initialSettings: InAppWebViewSettings(
      useWideViewPort: true,
      loadWithOverviewMode: true,
      supportZoom: true,
      builtInZoomControls: true,
      displayZoomControls: false,
      domStorageEnabled: true,
      useShouldOverrideUrlLoading: true,
      supportMultipleWindows: true,
      allowFileAccess: false,
      allowContentAccess: false,
      allowFileAccessFromFileURLs: false,
      allowUniversalAccessFromFileURLs: false,
      thirdPartyCookiesEnabled: false,
      cacheEnabled: false,
      saveFormData: false,
      isInspectable: false,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
    ),
    onWebViewCreated: (web) {
      _web = web;
      _waitForPage(web, '学校页面加载超时，请检查网络后重试。');
    },
    shouldOverrideUrlLoading: (web, action) async {
      if (!_current(web, _document)) return NavigationActionPolicy.CANCEL;
      final raw = action.request.url?.toString();
      if (widget.target.allows(raw)) {
        if (action.isForMainFrame && action.hasGesture != true) {
          _observeServiceReturn(raw);
        }
        return NavigationActionPolicy.ALLOW;
      }
      if (action.isForMainFrame && action.hasGesture != true) {
        final upgraded = widget.target.upgradeSameHostHttps(raw);
        if (upgraded != null &&
            _httpsUpgrades < CampusLoginPolicy.maxHttpsUpgrades) {
          _httpsUpgrades++;
          _requestedHttpsUpgrades.add(upgraded);
          _document++;
          _poll?.cancel();
          _waitForPage(web, '学校页面加载超时，请检查网络后重试。');
          unawaited(
            web.loadUrl(urlRequest: URLRequest(url: WebUri.uri(upgraded))),
          );
        } else {
          _fail(web, '已停止打开非当前学校服务或统一身份认证的页面。');
        }
      }
      return NavigationActionPolicy.CANCEL;
    },
    onLoadStart: (web, url) {
      if (!_checkDocument(web, url)) return;
      final address = url?.toString();
      _observeServiceReturn(address);
      _document++;
      _probeSeq++;
      _poll?.cancel();
      _waitForPage(web, '学校页面加载超时，请检查网络后重试。');
      final preserveForm =
          _passwordAttempt != null &&
          _nativeForm != null &&
          !_manualWeb &&
          !widget.target.isDestination(address);
      setState(() {
        _loading = true;
        if (preserveForm) {
          _nativeBusy = true;
          _probingNative = false;
        } else {
          _nativeForm = null;
          _nativeBusy = false;
          _probingNative = false;
          _clearQrState();
          _clearMobileState();
        }
        _nativeError = null;
        _method = null;
        _switching = false;
        _retryDefaultSelect = false;
      });
    },
    // Android can paint the official form while a subresource is still loading.
    onPageCommitVisible: (web, url) => _loaded(web, url, complete: false),
    onLoadStop: (web, url) => _loaded(web, url, complete: true),
    onReceivedError: (web, request, _) {
      if (request.isForMainFrame == true &&
          !_isReplacedHttpNavigation(request.url.toString())) {
        _fail(web, '学校页面无法加载，请检查网络后重试。');
      }
    },
    onReceivedHttpError: (web, request, _) {
      if (request.isForMainFrame == true) {
        _fail(web, '学校服务暂时无法打开，请稍后重试。');
      }
    },
    onCreateWindow: (_, _) async => false,
    onReceivedServerTrustAuthRequest: (web, _) async {
      _fail(web, '学校连接的证书未通过校验，已停止加载。');
      return ServerTrustAuthResponse(
        action: ServerTrustAuthResponseAction.CANCEL,
      );
    },
    onPermissionRequest: (_, request) async => PermissionResponse(
      resources: request.resources,
      action: PermissionResponseAction.DENY,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('校园账号登录'),
      bottom: _loading && defaultTargetPlatform == TargetPlatform.android
          ? const PreferredSize(
              preferredSize: Size.fromHeight(AppSpace.xs),
              child: LinearProgressIndicator(),
            )
          : null,
    ),
    body: SafeArea(
      child: defaultTargetPlatform != TargetPlatform.android
          ? const Center(child: Text('校园账号登录目前支持 Android。'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg,
                      vertical: AppSpace.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.reason),
                        Text(
                          '学校官方页面 · ${widget.target.label}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (_method != null &&
                            _nativeForm?.form != CampusNativeForm.sms)
                          Wrap(
                            spacing: AppSpace.sm,
                            children: [
                              for (final method in CampusLoginMethod.values)
                                ChoiceChip(
                                  selected: method == _method,
                                  label: Text(method.label),
                                  onSelected:
                                      _switching ||
                                          _nativeBusy ||
                                          _mobileSmsSending ||
                                          _qrSaving ||
                                          _qrRefreshing
                                      ? null
                                      : (_) => _select(method),
                                ),
                            ],
                          ),
                        if (widget.target == CampusLoginTarget.vpn ||
                            (_method == CampusLoginMethod.qr &&
                                _nativeForm?.form != CampusNativeForm.qr))
                          const Text('用另一台设备的企业微信扫描官方页面二维码。'),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _error == null
                      ? CampusLoginContent(
                          webView: _buildWeb(),
                          nativeForm: _buildNativeForm(),
                          waitingForSchool: _waitingForSchool,
                          onOpenOfficialPage:
                              widget.target == CampusLoginTarget.vpn ||
                                  _manualWeb
                              ? null
                              : _openOfficialForm,
                        )
                      : Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(AppSpace.lg),
                            child: Column(
                              children: [
                                Text(_error!, textAlign: TextAlign.center),
                                const SizedBox(height: AppSpace.lg),
                                AppActionButton(
                                  label: '重试',
                                  icon: AppIcons.refresh,
                                  onPressed: () {
                                    _cancelTimers();
                                    _probeSeq++;
                                    setState(() {
                                      _error = null;
                                      _loading = true;
                                      _httpsUpgrades = 0;
                                      _retryDefaultSelect = false;
                                      _manualWeb = false;
                                      _nativeForm = null;
                                      _passwordAttempt = null;
                                      _nativeBusy = false;
                                      _probingNative = false;
                                      _nativeError = null;
                                      _clearQrState();
                                      _clearMobileState();
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            ),
    ),
  );
}
