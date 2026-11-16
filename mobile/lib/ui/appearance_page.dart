import '../design/app_palette.dart';
import '../design/app_tokens.dart';
import 'app_icon_controls.dart';
import 'app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/appearance_controller.dart';
import '../platform/app_platform.dart';
import 'settings_scaffold.dart';

const accentChoices = <int, String>{
  AppPalette.accentValue: 'MIUIX 蓝',
  AppPalette.indigoValue: '靛青',
  AppPalette.violetValue: '紫罗兰',
  AppPalette.tealValue: '青绿',
  AppPalette.roseValue: '玫瑰',
  AppPalette.amberValue: '琥珀',
};
const variantChoices = <DynamicSchemeVariant, String>{
  DynamicSchemeVariant.tonalSpot: '柔和色调 · Tonal Spot',
  DynamicSchemeVariant.fidelity: '忠实原色 · Fidelity',
  DynamicSchemeVariant.vibrant: '鲜明 · Vibrant',
  DynamicSchemeVariant.expressive: '活力 · Expressive',
  DynamicSchemeVariant.neutral: '低饱和 · Neutral',
  DynamicSchemeVariant.monochrome: '单色 · Monochrome',
};

class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});
  Future<void> save(
    BuildContext context,
    WidgetRef ref,
    AppearanceSettings Function(AppearanceSettings) change,
  ) async {
    try {
      await ref.read(appearanceProvider.notifier).change(change);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('设置未能保存，请重试')));
      }
    }
  }

  Future<T?> choose<T>(
    BuildContext context,
    String title,
    Map<T, String> choices,
    T current,
  ) => showDialog<T>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (final entry in choices.entries)
          ListTile(
            title: Text(entry.value),
            selected: entry.key == current,
            trailing: entry.key == current
                ? const AppIcon(AppIcons.check)
                : null,
            leading: entry.key is int
                ? CircleAvatar(
                    radius: 12,
                    backgroundColor: Color(entry.key as int),
                  )
                : null,
            onTap: () => Navigator.pop(context, entry.key),
          ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appearanceProvider);
    final p = ref.watch(currentAppearanceProvider);
    final info = ref.watch(appInfoProvider).asData?.value;
    final ready = state.hasValue;
    Widget toggle(
      String title,
      String summary,
      AppIconData icon,
      bool value,
      AppearanceSettings Function(AppearanceSettings, bool) change, {
      bool enabled = true,
    }) => Semantics(
      container: true,
      excludeSemantics: true,
      label: '$title\n$summary',
      toggled: value,
      enabled: ready && enabled,
      onTap: ready && enabled
          ? () => save(context, ref, (previous) => change(previous, !value))
          : null,
      child: MiuixSwitchPreference(
        key: ValueKey('appearance-$title'),
        title: title,
        summary: summary,
        startAction: AppIcon(icon),
        value: value,
        enabled: ready && enabled,
        onChanged: (value) =>
            save(context, ref, (previous) => change(previous, value)),
      ),
    );
    Widget choice(
      String title,
      String summary,
      AppIconData icon,
      VoidCallback onTap, {
      bool enabled = true,
    }) => AppArrowPreference(
      title: title,
      summary: summary,
      startAction: AppIcon(icon),
      enabled: ready && enabled,
      onClick: onTap,
    );
    return SettingsScaffold(
      title: '外观设置',
      children: [
        const Center(child: ThemePhonePreview()),
        const SizedBox(height: 32),
        Center(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (mode, label) in [
                (ThemeMode.system, '跟随系统'),
                (ThemeMode.light, '浅色'),
                (ThemeMode.dark, '深色'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: p.mode == mode,
                  onSelected: ready
                      ? (_) => save(context, ref, (v) => v.copyWith(mode: mode))
                      : null,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (state.hasError) ...[
          const Text('外观设置暂时无法读取，原文件已保留。'),
          TextButton(
            onPressed: () => ref.invalidate(appearanceProvider),
            child: const Text('重新读取'),
          ),
        ],
        settingsGroup([
          toggle(
            '启用 Monet 颜色',
            info?.systemAccent != null ? '从系统壁纸提取强调色' : '当前设备未提供动态颜色，使用手动强调色',
            AppIcons.wallpaper,
            p.monet,
            (v, value) => v.copyWith(monet: value),
            enabled: info?.systemAccent != null,
          ),
          choice(
            '强调色',
            p.monet && info?.systemAccent != null
                ? '跟随系统壁纸'
                : accentChoices[p.accent] ?? '自定义',
            AppIcons.pipette,
            () async {
              final color = await choose(
                context,
                '强调色',
                accentChoices,
                p.accent,
              );
              if (color != null && context.mounted) {
                await save(context, ref, (v) => v.copyWith(accent: color));
              }
            },
            enabled: !p.monet || info?.systemAccent == null,
          ),
          choice(
            '色彩风格',
            variantChoices[p.variant] ?? p.variant.name,
            AppIcons.palette,
            () async {
              final variant = await choose(
                context,
                '色彩风格',
                variantChoices,
                p.variant,
              );
              if (variant != null && context.mounted) {
                await save(context, ref, (v) => v.copyWith(variant: variant));
              }
            },
          ),
          const ListTile(
            leading: AppIcon(AppIcons.palette),
            title: Text('色彩标准'),
            subtitle: Text('Material 3'),
          ),
          choice(
            '色彩对比度',
            p.contrast == 0
                ? '标准'
                : p.contrast == .5
                ? '中对比度'
                : '高对比度',
            AppIcons.contrast,
            () async {
              final value = await choose(context, '色彩对比度', {
                0.0: '标准',
                .5: '中对比度',
                1.0: '高对比度',
              }, p.contrast);
              if (value != null && context.mounted) {
                await save(context, ref, (v) => v.copyWith(contrast: value));
              }
            },
          ),
        ]),
        settingsGroup([
          toggle(
            '左上角极光',
            '今日页柔光缓慢流转；减少动画时静止，高对比度时关闭',
            AppIcons.sun,
            p.aurora,
            (v, value) => v.copyWith(aurora: value),
          ),
          toggle(
            '宣纸微纹理',
            '轻微纸感，不影响文字和触控',
            AppIcons.wallpaper,
            p.paperTexture,
            (v, value) => v.copyWith(paperTexture: value),
          ),
          choice(
            '课程卡片着色',
            p.softCards ? '柔和全底' : '极简色条',
            AppIcons.palette,
            () async {
              final value = await choose(context, '课程卡片着色', {
                false: '极简色条',
                true: '柔和全底',
              }, p.softCards);
              if (value != null && context.mounted) {
                await save(context, ref, (v) => v.copyWith(softCards: value));
              }
            },
          ),
          toggle(
            '显示周末列',
            '周表扩展为七天；关闭时仍可在日视图查看周末',
            AppIcons.calendarWeek,
            p.showWeekend,
            (v, value) => v.copyWith(showWeekend: value),
          ),
          toggle(
            '在线一言',
            '开启后在“今日”页随机请求公开一言接口（v1.hitokoto.cn），离线或失败时自动使用本地语录',
            AppIcons.refresh,
            p.onlineQuotes,
            (v, value) => v.copyWith(onlineQuotes: value),
          ),
        ]),
        settingsGroup([
          toggle(
            '模糊',
            '启用顶栏和底栏的背景模糊',
            AppIcons.blur,
            p.blur,
            (v, value) => v.copyWith(blur: value),
          ),
          toggle(
            '悬浮底栏',
            '使用 Apple 风格的悬浮底栏',
            AppIcons.dock,
            p.floating,
            (v, value) => v.copyWith(floating: value),
          ),
          toggle(
            '液态玻璃',
            '悬浮底栏的高光与半透明玻璃效果',
            AppIcons.droplet,
            p.glass,
            (v, value) => v.copyWith(glass: value),
            enabled: p.floating && p.blur,
          ),
        ]),
        settingsGroup([
          toggle(
            '预测性返回动画',
            '子页面跟随系统返回手势预览（Android 14 及以上）',
            AppIcons.swipe,
            p.predictiveBack,
            (v, value) => v.copyWith(predictiveBack: value),
            enabled: (info?.sdk ?? 0) >= 34,
          ),
          toggle(
            '横移返回手势',
            '从子页面左侧边缘右滑返回',
            AppIcons.swipe,
            p.swipeBack,
            (v, value) => v.copyWith(swipeBack: value),
          ),
          toggle(
            '页面切换手势',
            '在主页面横向滑动切换今日、课表和设置',
            AppIcons.swapHorizontal,
            p.swipePages,
            (v, value) => v.copyWith(swipePages: value),
          ),
          const _ScaleSetting(),
        ]),
      ],
    );
  }
}

class _ScaleSetting extends ConsumerStatefulWidget {
  const _ScaleSetting();
  @override
  ConsumerState<_ScaleSetting> createState() => _ScaleSettingState();
}

class _ScaleSettingState extends ConsumerState<_ScaleSetting> {
  double? draft;
  @override
  Widget build(BuildContext context) {
    final p = ref.watch(currentAppearanceProvider),
        value = draft ?? ref.watch(currentAppearanceProvider).scale;
    return Column(
      children: [
        ListTile(
          leading: const AppIcon(AppIcons.fontSize),
          title: const Text('界面缩放'),
          subtitle: const Text('调整整体界面比例，保留系统字号设置'),
          trailing: Text('${(value * 100).round()}%'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: Slider(
            key: const ValueKey('interface-scale-slider'),
            value: value,
            min: .8,
            max: 1.2,
            divisions: 4,
            semanticFormatterCallback: (v) => '${(v * 100).round()}%',
            onChanged: (v) => setState(() => draft = v),
            onChangeEnd: (v) async {
              await const AppearancePage().save(
                context,
                ref,
                (previous) => previous.copyWith(scale: v),
              );
              if (mounted) setState(() => draft = null);
            },
          ),
        ),
        if (p.scale != 1)
          TextButton(
            onPressed: () => const AppearancePage().save(
              context,
              ref,
              (v) => v.copyWith(scale: 1),
            ),
            child: const Text('恢复 100%'),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class ThemePhonePreview extends StatelessWidget {
  const ThemePhonePreview({super.key});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: 136,
        height: 246,
        padding: const EdgeInsets.all(AppSpace.sm),
        margin: const EdgeInsets.symmetric(vertical: AppSpace.comfortable),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: c.outline, width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Text(
              '校园课表',
              style: TextStyle(fontSize: AppType.micro, color: c.onSurface),
            ),
            const SizedBox(height: 8),
            Container(
              height: 42,
              decoration: BoxDecoration(
                color: c.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 7),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: c.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 24,
              decoration: BoxDecoration(
                color: c.surfaceContainer,
                borderRadius: BorderRadius.circular(AppRadius.section),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var i = 0; i < 3; i++)
                    AppIcon(
                      [AppIcons.sun, AppIcons.calendar, AppIcons.sliders][i],
                      size: 12,
                      color: i == 2 ? c.primary : c.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
