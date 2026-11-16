import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Resolve existing app-private file names. Repositories still own their schema,
/// backup policy and write queue; this helper never enumerates user data.
Future<File> applicationFile(String name, {Directory? directory}) async {
  final folder = directory ?? await getApplicationSupportDirectory();
  await folder.create(recursive: true);
  return File('${folder.path}/$name');
}

File pendingFile(File file) => File('${file.path}.pending');

/// Stage and flush beside the target before rename. The synchronous guard is
/// checked after staging, so a cleared account cannot commit a stale write.
/// False means discarded, not saved. Callers must serialize writes per target.
Future<bool> writeAtomicText(
  File file,
  String content, {
  bool Function()? canCommit,
}) async {
  final pending = pendingFile(file);
  try {
    await pending.writeAsString(content, flush: true);
    if (canCommit != null && !canCommit()) return false;
    await pending.rename(file.path);
    return true;
  } finally {
    if (await pending.exists()) await pending.delete();
  }
}
