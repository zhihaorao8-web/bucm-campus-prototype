import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/app_tokens.dart';
import 'app_controls.dart';
import 'app_icons.dart';
import 'app_theme.dart';

/// Text controller that hides entered credentials or verification codes from
/// widget and element diagnostic dumps.
class _RedactedTextEditingController extends TextEditingController {
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  String toString() => _disposed
      ? 'RedactedTextEditingController(disposed)'
      : 'RedactedTextEditingController';
}

/// Native student/staff account and password form for direct CAS login.
class CampusPasswordForm extends StatefulWidget {
  const CampusPasswordForm({
    super.key,
    required this.busy,
    this.error,
    required this.onSubmit,
    this.clearPasswordToken = 0,
  });

  final bool busy;
  final String? error;
  final void Function(String account, String password, bool remember) onSubmit;

  /// Increment when the school explicitly rejects the password so only the
  /// password field clears while the entered account remains intact.
  final int clearPasswordToken;

  @override
  State<CampusPasswordForm> createState() => _CampusPasswordFormState();
}

class _CampusPasswordFormState extends State<CampusPasswordForm> {
  final _account = _RedactedTextEditingController();
  final _password = _RedactedTextEditingController();
  final _accountFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _remember = false;
  bool _obscurePassword = true;
  String? _accountError;
  String? _passwordError;

  @override
  void didUpdateWidget(CampusPasswordForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && !oldWidget.busy && !_obscurePassword) {
      _obscurePassword = true;
    }
    if (widget.clearPasswordToken != oldWidget.clearPasswordToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _password.clear();
        setState(() {
          _passwordError = null;
          _obscurePassword = true;
        });
        if (!widget.busy) {
          _passwordFocus.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    _accountFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.busy) return;
    final account = _account.text.trim();
    final password = _password.text;
    final accountError = account.isEmpty ? '请输入学号或工号' : null;
    final passwordError = password.trim().isEmpty ? '请输入密码' : null;
    if (accountError != null || passwordError != null) {
      setState(() {
        _accountError = accountError;
        _passwordError = passwordError;
      });
      if (accountError != null) {
        _accountFocus.requestFocus();
      } else {
        _passwordFocus.requestFocus();
      }
      return;
    }
    if (_accountError != null || _passwordError != null || !_obscurePassword) {
      setState(() {
        _accountError = null;
        _passwordError = null;
        _obscurePassword = true;
      });
    }
    FocusScope.of(context).unfocus();
    widget.onSubmit(account, password, _remember);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final errorText = widget.error?.trim();

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: FocusTraversalGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.busy) ...[
                    const _BusyNotice('正在提交登录信息，请稍候…'),
                    const SizedBox(height: AppSpace.md),
                  ],
                  if (errorText != null && errorText.isNotEmpty) ...[
                    _FormStatusBanner(
                      key: const ValueKey('campus-password-error'),
                      message: errorText,
                      isError: true,
                    ),
                    const SizedBox(height: AppSpace.md),
                  ],
                  const _FieldLabel('学号或工号'),
                  const SizedBox(height: AppSpace.xs),
                  TextField(
                    key: const ValueKey('campus-password-account-field'),
                    controller: _account,
                    focusNode: _accountFocus,
                    enabled: !widget.busy,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    autofillHints: null,
                    scrollPadding: const EdgeInsets.all(AppSpace.xl),
                    decoration: _formInputDecoration(
                      context,
                      hintText: '学号或工号',
                      errorText: _accountError,
                    ),
                    onChanged: (_) {
                      if (_accountError != null) {
                        setState(() => _accountError = null);
                      }
                    },
                    onSubmitted: (_) {
                      if (!widget.busy) {
                        _passwordFocus.requestFocus();
                      }
                    },
                  ),
                  const SizedBox(height: AppSpace.md),
                  const _FieldLabel('密码'),
                  const SizedBox(height: AppSpace.xs),
                  TextField(
                    key: const ValueKey('campus-password-password-field'),
                    controller: _password,
                    focusNode: _passwordFocus,
                    enabled: !widget.busy,
                    obscureText: _obscurePassword,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    autofillHints: null,
                    scrollPadding: const EdgeInsets.all(AppSpace.xl),
                    decoration: _formInputDecoration(
                      context,
                      hintText: '校园密码',
                      errorText: _passwordError,
                      suffixIcon: TextButton(
                        key: const ValueKey(
                          'campus-password-visibility-toggle',
                        ),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(
                            AppLayout.minTap,
                            AppLayout.minTap,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.sm,
                          ),
                        ),
                        onPressed: widget.busy
                            ? null
                            : () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                        child: Text(
                          _obscurePassword ? '显示' : '隐藏',
                          semanticsLabel: _obscurePassword ? '显示密码' : '隐藏密码',
                        ),
                      ),
                    ),
                    onChanged: (_) {
                      if (_passwordError != null) {
                        setState(() => _passwordError = null);
                      }
                    },
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Material(
                    color: colors.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      side: BorderSide(
                        color: highContrast
                            ? colors.outline
                            : colors.outlineVariant,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CheckboxListTile(
                      key: const ValueKey('campus-password-remember-checkbox'),
                      value: _remember,
                      onChanged: widget.busy
                          ? null
                          : (value) =>
                                setState(() => _remember = value ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.sm,
                        vertical: AppSpace.xs,
                      ),
                      title: Text(
                        '保存账号密码',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        '仅保存在此设备，后续只在查看录播或图书馆座位时用于自动登录。学校要求短信验证时，仍需本人完成。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  AppActionButton(
                    key: const ValueKey('campus-password-submit'),
                    label: '登录',
                    icon: AppIcons.check,
                    onPressed: widget.busy ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Standalone 6-digit SMS secondary verification form shown when CAS requests
/// an SMS challenge after password submission.
class CampusSmsForm extends StatefulWidget {
  const CampusSmsForm({
    super.key,
    required this.busy,
    this.error,
    this.notice,
    required this.onSubmit,
    this.onRequestCode,
    required this.onCancel,
  });

  final bool busy;
  final String? error;
  final String? notice;
  final ValueChanged<String> onSubmit;
  final VoidCallback? onRequestCode;
  final VoidCallback onCancel;

  @override
  State<CampusSmsForm> createState() => _CampusSmsFormState();
}

class _CampusSmsFormState extends State<CampusSmsForm> {
  final _code = _RedactedTextEditingController();
  final _codeFocus = FocusNode();

  String? _codeError;
  bool _requestedCode = false;

  @override
  void dispose() {
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.busy) return;
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _codeError = code.isEmpty ? '请输入 6 位短信验证码' : '短信验证码需为 6 位数字';
      });
      _codeFocus.requestFocus();
      return;
    }
    if (_codeError != null) {
      setState(() => _codeError = null);
    }
    FocusScope.of(context).unfocus();
    widget.onSubmit(code);
  }

  void _requestCode() {
    if (widget.busy || widget.onRequestCode == null) return;
    if (!_requestedCode) {
      setState(() => _requestedCode = true);
    }
    widget.onRequestCode!();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final noticeText = widget.notice?.trim();
    final errorText = widget.error?.trim();
    final resendLabel = _requestedCode || (noticeText?.contains('已发送') ?? false)
        ? '重新发送'
        : '发送验证码';

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: FocusTraversalGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('短信二次验证', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    '学校要求完成短信验证后继续本次登录。请输入收到的 6 位短信验证码，验证码仅用于本次验证，离开页面后自动清除。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  if (widget.busy) ...[
                    const _BusyNotice('正在向学校提交验证码，请稍候…'),
                    const SizedBox(height: AppSpace.md),
                  ],
                  if (noticeText != null && noticeText.isNotEmpty) ...[
                    _FormStatusBanner(
                      key: const ValueKey('campus-sms-notice'),
                      message: noticeText,
                      isError: false,
                    ),
                    const SizedBox(height: AppSpace.md),
                  ],
                  if (errorText != null && errorText.isNotEmpty) ...[
                    _FormStatusBanner(
                      key: const ValueKey('campus-sms-error'),
                      message: errorText,
                      isError: true,
                    ),
                    const SizedBox(height: AppSpace.md),
                  ],
                  const _FieldLabel('短信验证码'),
                  const SizedBox(height: AppSpace.xs),
                  TextField(
                    key: const ValueKey('campus-sms-code-field'),
                    controller: _code,
                    focusNode: _codeFocus,
                    enabled: !widget.busy,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    autofillHints: null,
                    scrollPadding: const EdgeInsets.all(AppSpace.xl),
                    style: theme.textTheme.titleMedium?.copyWith(
                      letterSpacing: 4,
                      fontFeatures: tabularTime,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: _formInputDecoration(
                      context,
                      hintText: '6 位数字验证码',
                      errorText: _codeError,
                    ),
                    onChanged: (_) {
                      if (_codeError != null) {
                        setState(() => _codeError = null);
                      }
                    },
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  AppActionButton(
                    key: const ValueKey('campus-sms-submit'),
                    label: '验证',
                    icon: AppIcons.check,
                    onPressed: widget.busy ? null : _submit,
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.sm,
                    children: [
                      if (widget.onRequestCode != null)
                        AppActionButton(
                          key: const ValueKey('campus-sms-request-code'),
                          label: resendLabel,
                          icon: AppIcons.refresh,
                          outlined: true,
                          onPressed: widget.busy ? null : _requestCode,
                        ),
                      AppActionButton(
                        key: const ValueKey('campus-sms-cancel'),
                        label: '取消',
                        icon: AppIcons.close,
                        outlined: true,
                        onPressed: widget.onCancel,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hosts the official WebView under an optional waiting state or native login
/// form while keeping the underlying WebView widget tree alive across transitions.
class CampusLoginContent extends StatelessWidget {
  const CampusLoginContent({
    super.key,
    required this.webView,
    this.nativeForm,
    required this.waitingForSchool,
    this.onOpenOfficialPage,
  });

  final Widget webView;
  final Widget? nativeForm;
  final bool waitingForSchool;
  final VoidCallback? onOpenOfficialPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final covered = nativeForm != null || waitingForSchool;

    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: covered,
          child: ExcludeFocus(
            excluding: covered,
            child: IgnorePointer(ignoring: covered, child: webView),
          ),
        ),
        if (covered)
          Positioned.fill(
            child: ColoredBox(
              color: colors.surface,
              child: nativeForm != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: nativeForm!),
                        if (onOpenOfficialPage != null) ...[
                          const Divider(height: 1),
                          Align(
                            alignment: Alignment.center,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 480),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpace.lg,
                                  vertical: AppSpace.sm,
                                ),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: AppActionButton(
                                    key: const ValueKey(
                                      'campus-login-open-official',
                                    ),
                                    label: '打开学校官方页面',
                                    icon: AppIcons.globe,
                                    outlined: true,
                                    onPressed: onOpenOfficialPage,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    )
                  : Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpace.lg),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Semantics(
                            liveRegion: true,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                ),
                                const SizedBox(height: AppSpace.md),
                                Text(
                                  '正在连接学校统一身份认证…',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: AppSpace.xs),
                                Text(
                                  '页面就绪后将显示登录表单，如需也可直接打开学校官方页面。',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                if (onOpenOfficialPage != null) ...[
                                  const SizedBox(height: AppSpace.lg),
                                  AppActionButton(
                                    key: const ValueKey(
                                      'campus-login-open-official',
                                    ),
                                    label: '打开学校官方页面',
                                    icon: AppIcons.globe,
                                    outlined: true,
                                    onPressed: onOpenOfficialPage,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
      ],
    );
  }
}

InputDecoration _formInputDecoration(
  BuildContext context, {
  required String hintText,
  required String? errorText,
  Widget? suffixIcon,
}) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  final highContrast = MediaQuery.highContrastOf(context);
  final radius = BorderRadius.circular(AppRadius.input);
  final baseBorder = OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(
      color: highContrast ? colors.outline : colors.outlineVariant,
    ),
  );
  return InputDecoration(
    hintText: hintText,
    hintStyle: theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    ),
    errorText: errorText,
    errorMaxLines: 3,
    filled: true,
    fillColor: colors.surfaceContainerLow,
    contentPadding: const EdgeInsets.all(AppSpace.md),
    enabledBorder: baseBorder,
    disabledBorder: baseBorder.copyWith(
      borderSide: BorderSide(
        color: colors.outlineVariant.withValues(alpha: .5),
      ),
    ),
    focusedBorder: baseBorder.copyWith(
      borderSide: BorderSide(color: colors.primary, width: 2),
    ),
    errorBorder: baseBorder.copyWith(
      borderSide: BorderSide(color: colors.error),
    ),
    focusedErrorBorder: baseBorder.copyWith(
      borderSide: BorderSide(color: colors.error, width: 2),
    ),
    suffixIcon: suffixIcon,
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
  );
}

class _BusyNotice extends StatelessWidget {
  const _BusyNotice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(AppSpace.xs)),
            child: LinearProgressIndicator(minHeight: 3),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _FormStatusBanner extends StatelessWidget {
  const _FormStatusBanner({
    super.key,
    required this.message,
    required this.isError,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final background =
        (isError ? colors.errorContainer : colors.primaryContainer).withValues(
          alpha: highContrast ? 1 : .82,
        );
    final foreground = isError
        ? colors.onErrorContainer
        : colors.onPrimaryContainer;
    final accent = isError ? colors.error : colors.primary;

    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.input),
          border: Border.all(
            color: highContrast ? accent : accent.withValues(alpha: .35),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.control,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: AppIcon(
                  AppIcons.info,
                  size: AppControl.icon,
                  color: foreground,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
