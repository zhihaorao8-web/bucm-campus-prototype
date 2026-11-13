import 'package:flutter/material.dart';
import 'course_surface.dart';
import '../application/classroom_connection_status.dart';

class ClassroomConnectionCard extends StatelessWidget {
  const ClassroomConnectionCard({
    super.key,
    required this.status,
    required this.directoryLabel,
    required this.busy,
    this.onRetry,
    this.onOpenSchool,
  });

  final ClassroomConnectionStatus status;
  final String directoryLabel;
  final bool busy;
  final VoidCallback? onRetry, onOpenSchool;

  @override
  Widget build(BuildContext context) => QuietCard(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(directoryLabel),
          const SizedBox(height: 8),
          Text(status.label, style: Theme.of(context).textTheme.titleSmall),
          if (status.detail != null) ...[
            const SizedBox(height: 8),
            Text(status.detail!),
          ],
          if (busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (status.needsRecovery)
            Wrap(
              spacing: 8,
              children: [
                if (onRetry != null)
                  TextButton(
                    onPressed: busy ? null : onRetry,
                    child: const Text('重试连接'),
                  ),
                if (onOpenSchool != null)
                  TextButton(
                    onPressed: onOpenSchool,
                    child: const Text('打开学校页面'),
                  ),
              ],
            ),
        ],
      ),
    ),
  );
}
