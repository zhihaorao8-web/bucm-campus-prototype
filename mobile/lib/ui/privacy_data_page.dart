import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/schedule_controller.dart';
import '../design/app_tokens.dart';
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
      detail: '将清除学校网页会话、已导入的录播目录和本机观看进度，离线课表继续保留。',
      confirmLabel: '确认退出',
    )) {
      return;
    }
    await _runAction(() async {
      await SchoolAdapter().clearSession();
      if (mounted) showAppNotice(context, '已清除本机学校会话');
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
                  '密码只在学校官方页面输入。应用不保存密码，不上传课表。学校会话失效后，需要你重新登录。',
                  style: TextStyle(fontSize: AppType.body, height: 1.5),
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  '退出学校会话与清空本地课表相互独立，操作前都会单独确认。',
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
            summary: '保留离线课表，清除录播目录与本机观看进度',
            enabled: !_busy,
            startAction: const AppIcon(AppIcons.logOut),
            onClick: _clearSession,
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
