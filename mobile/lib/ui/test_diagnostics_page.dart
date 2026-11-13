import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../platform/test_diagnostics.dart';
import 'settings_scaffold.dart';

class TestDiagnosticsPage extends StatelessWidget {
  const TestDiagnosticsPage({super.key, this.diagnostics});
  final TestDiagnostics? diagnostics;
  @override
  Widget build(BuildContext context) {
    final log = diagnostics ?? TestDiagnostics.shared;
    if (!log.enabled) {
      return const Scaffold(body: Center(child: Text('此构建未启用测试诊断')));
    }
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        return SettingsScaffold(
          title: '测试诊断',
          children: [
            const Text(
              '仅记录导入/播放准备阶段、路径、数量、耗时和错误类别，不读取系统日志或认证信息。保留最近200条，清空记录、退出学校会话或结束进程后清除。',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    var copied = false;
                    try {
                      await Clipboard.setData(
                        ClipboardData(text: log.export()),
                      );
                      copied = true;
                    } catch (_) {
                      /* Only a generic UI message; never log export data. */
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(copied ? '诊断记录已复制' : '复制失败，请重试'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('复制诊断记录'),
                ),
                TextButton(onPressed: log.clear, child: const Text('清空记录')),
              ],
            ),
            const SizedBox(height: 12),
            Text('当前 ${log.events.length} 条'),
            const SizedBox(height: 8),
            SelectableText(
              log.events.isEmpty ? '暂无记录。请返回统一导入录播，再打开本页。' : log.export(),
            ),
          ],
        );
      },
    );
  }
}
