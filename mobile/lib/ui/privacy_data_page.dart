import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/schedule_controller.dart';
import '../design/app_tokens.dart';
import '../platform/campus_native_login.dart';
import '../platform/school_adapter.dart';
import 'app_controls.dart';
import 'app_icon_controls.dart';
import 'app_icons.dart';
import 'settings_scaffold.dart';

/// Privacy boundary explanation and independent local cleanup confirmations.
class PrivacyDataPage extends ConsumerStatefulWidget {
  const PrivacyDataPage({
    super.key,
    required this.demo,
    required this.onScheduleCleared,
  });

  final bool demo;
  final VoidCallback onScheduleCleared;

  @override
  ConsumerState<PrivacyDataPage> createState() => _PrivacyDataPageState();
}

class _PrivacyDataPageState extends ConsumerState<PrivacyDataPage> {
  bool _busy = false;
  bool? _hasSavedCredentials;
  bool _checkingCredentials = true;

  @override
  void initState() {
    super.initState();
    CampusNativeLogin.changes.addListener(_onCredentialsChanged);
    unawaited(_refreshSavedCredentials());
  }

  @override
  void dispose() {
    CampusNativeLogin.changes.removeListener(_onCredentialsChanged);
    super.dispose();
  }

  void _onCredentialsChanged() {
    if (mounted) unawaited(_refreshSavedCredentials());
  }

  Future<void> _refreshSavedCredentials() async {
    final expected = CampusNativeLogin.revision;
    try {
      final saved = await CampusNativeLogin.hasSaved();
      if (!mounted || expected != CampusNativeLogin.revision) return;
      setState(() {
        _hasSavedCredentials = saved;
        _checkingCredentials = false;
      });
    } on MissingPluginException {
      if (!mounted || expected != CampusNativeLogin.revision) return;
      setState(() {
        _hasSavedCredentials = false;
        _checkingCredentials = false;
      });
    } catch (_) {
      if (!mounted || expected != CampusNativeLogin.revision) return;
      setState(() {
        _hasSavedCredentials = null;
        _checkingCredentials = false;
      });
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) showAppNotice(context, '操作未完成，原有数据保留，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String detail,
    required String confirmLabel,
    bool destructive = false,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(detail),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              style: destructive
                  ? TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    )
                  : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _clearSession() async {
    if (!await _confirm(
      title: '退出学校会话？',
      detail: '将清除学校网页会话、已保存的校园账号密码、已导入的录播目录和本机观看进度，离线课表继续保留。',
      confirmLabel: '确认退出',
    )) {
      return;
    }
    await _runAction(() async {
      await SchoolAdapter().clearSession();
      if (mounted) {
        setState(() {
          _hasSavedCredentials = false;
          _checkingCredentials = false;
        });
        showAppNotice(context, '已清除本机学校会话');
      }
    });
  }

  Future<void> _clearCredentials() async {
    if (!await _confirm(
      title: '清除已保存的校园账号密码？',
      detail: '将删除本机加密保存的校园账号密码，不会退出当前学校会话，也不会删除离线课表。',
      confirmLabel: '确认清除',
    )) {
      return;
    }
    await _runAction(() async {
      await CampusNativeLogin.clear();
      if (mounted) {
        setState(() {
          _hasSavedCredentials = false;
          _checkingCredentials = false;
        });
        showAppNotice(context, '已清除已保存的校园账号密码');
      }
    });
  }

  Future<void> _clearSchedule() async {
    if (!await _confirm(
      title: '清空本地课表？',
      detail: '将删除本机保存的所有学期课程。之后可以重新从学校导入，不会退出学校会话。',
      confirmLabel: '确认清空',
      destructive: true,
    )) {
      return;
    }
    await _runAction(() async {
      await ref.read(scheduleProvider.notifier).clear();
      widget.onScheduleCleared();
      if (mounted) showAppNotice(context, '已清空本地课表');
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasCourses =
        ref.watch(scheduleProvider).asData?.value.courses.isNotEmpty ?? false;
    final colors = Theme.of(context).colorScheme;
    final canClearCredentials =
        !_busy && !_checkingCredentials && _hasSavedCredentials != false;
    final canClearSchedule = !_busy && !widget.demo && hasCourses;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.sm,
        AppSpace.sm,
        AppSpace.sm,
        AppSpace.control,
      ),
      child: Text(text, style: TextStyle(color: colors.onSurfaceVariant)),
    );
    return SettingsScaffold(
      title: '隐私与数据',
      children: [
        settingsGroup([
          Padding(
            padding: const EdgeInsets.all(AppSpace.comfortable),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.small),
                      ),
                      child: AppIcon(
                        AppIcons.info,
                        size: 20,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Text(
                        '凭据与本地数据说明',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                const Text(
                  '默认不保存校园账号密码。仅当你主动勾选“保存账号密码”并完成学校全部验证后，应用才会使用本机加密保存一组账密，不上传课表或凭据。',
                  style: TextStyle(fontSize: AppType.body, height: 1.5),
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  '退出学校会话、清除已保存的校园账号密码与清空本地课表相互独立确认；退出学校会话时会一并清除已保存账密，但不删除离线课表。',
                  style: TextStyle(
                    fontSize: AppType.secondary,
                    height: 1.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ]),
        heading('学校会话'),
        settingsGroup([
          AppArrowPreference(
            key: const ValueKey('privacy-clear-session'),
            title: '退出学校会话',
            summary: '保留离线课表，清除录播目录、本机观看进度与已保存账密',
            enabled: !_busy,
            startAction: const AppIcon(AppIcons.logOut),
            onClick: _clearSession,
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            indent: AppSpace.comfortable,
            endIndent: AppSpace.comfortable,
            color: colors.outlineVariant,
          ),
          AppArrowPreference(
            key: const ValueKey('privacy-clear-credentials'),
            title: '清除已保存的校园账号密码',
            summary: _checkingCredentials
                ? '正在检查本机保存状态'
                : _hasSavedCredentials == false
                ? '当前没有已保存的校园账号密码'
                : '仅清除本机加密保存的账密，保留当前学校会话与离线课表',
            enabled: canClearCredentials,
            startAction: AppIcon(
              AppIcons.close,
              color: canClearCredentials ? null : colors.onSurfaceVariant,
            ),
            onClick: _clearCredentials,
          ),
        ]),
        heading('本地数据'),
        settingsGroup([
          AppArrowPreference(
            key: const ValueKey('privacy-clear-schedule'),
            title: '清空本地课表',
            summary: widget.demo
                ? '退出示例后可管理本人本地课表'
                : hasCourses
                ? '删除所有学期的本地课程，不影响学校会话'
                : '当前没有已保存的本地课表',
            destructive: true,
            enabled: canClearSchedule,
            startAction: AppIcon(
              AppIcons.trash,
              color: canClearSchedule ? colors.error : colors.onSurfaceVariant,
            ),
            onClick: _clearSchedule,
          ),
        ]),
      ],
    );
  }
}
