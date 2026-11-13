import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../platform/app_platform.dart';
import '../platform/test_diagnostics.dart';
import 'test_diagnostics_page.dart';
import 'settings_scaffold.dart';

const developerName = 'Muzhi';
const developerLogin = 'zhihaorao8-web';
const developerUrl = 'https://github.com/zhihaorao8-web';
const repositoryUrl = 'https://github.com/zhihaorao8-web/bucm-campus-prototype';

class ProjectInfoPage extends ConsumerWidget {
  const ProjectInfoPage({super.key});
  Future<void> open(BuildContext context, String target) async {
    try {
      await openProjectLink(target);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开浏览器，可复制地址后访问')));
      }
    }
  }

  Future<void> copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已复制地址')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(appInfoProvider);
    final colors = Theme.of(context).colorScheme;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Text(text, style: TextStyle(color: colors.onSurfaceVariant)),
    );
    Widget linkGroup({
      required String target,
      required String title,
      required String address,
      required IconData icon,
    }) => settingsGroup([
      MiuixArrowPreference(
        title: title,
        startAction: Icon(icon),
        onClick: () => open(context, target),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            address,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium!.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 8),
          child: TextButton.icon(
            key: ValueKey('copy-$target'),
            onPressed: () => copy(context, address),
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: const Text('复制地址'),
          ),
        ),
      ),
    ]);
    return SettingsScaffold(
      title: '项目信息',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset(
                  'assets/app-icon.png',
                  key: const ValueKey('project-app-icon'),
                  width: 112,
                  height: 112,
                  cacheWidth: 336,
                  semanticLabel: '应用图标',
                ),
              ),
              const SizedBox(height: 20),
              Text(
                info.asData?.value.name ?? '校园课表',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              if (info.asData case final data?)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 4,
                  ),
                  child: Text(
                    '${data.value.buildType}\n${data.value.sourceLabel}',
                    key: const ValueKey('project-build-identity'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              info.when(
                data: (value) => Text(
                  '版本 ${value.version} (${value.build})',
                  key: const ValueKey('project-version'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                loading: () => const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (_, _) => TextButton(
                  onPressed: () => ref.invalidate(appInfoProvider),
                  child: const Text('重新读取版本信息'),
                ),
              ),
            ],
          ),
        ),
        if (TestDiagnostics.available) heading('测试工具'),
        if (TestDiagnostics.available)
          settingsGroup([
            MiuixArrowPreference(
              title: '测试诊断',
              summary: '查看、复制或清空本次导入记录',
              onClick: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TestDiagnosticsPage(),
                ),
              ),
            ),
          ]),
        heading('开发者信息'),
        settingsGroup([
          MiuixArrowPreference(
            title: developerName,
            summary: '@$developerLogin',
            startAction: ClipOval(
              child: Image.asset(
                'assets/developer-avatar.png',
                key: const ValueKey('developer-avatar'),
                width: 48,
                height: 48,
                cacheWidth: 144,
                semanticLabel: '开发者 GitHub 头像',
              ),
            ),
            onClick: () => open(context, 'developer'),
          ),
        ]),
        heading('项目仓库'),
        linkGroup(
          target: 'repository',
          title: 'bucm-campus-prototype',
          address: repositoryUrl,
          icon: Icons.code,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          child: Text('非官方校园课表应用', textAlign: TextAlign.center),
        ),
      ],
    );
  }
}
