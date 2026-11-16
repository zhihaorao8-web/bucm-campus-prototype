import '../config/classroom_limits.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../domain/classroom.dart';
import '../domain/schedule.dart';

/// Metadata and its existing official document stay together. No media URLs,
/// credentials or browser storage are extracted or serialized by this cache.
class ClassroomSession {
  ClassroomSession({
    required this.view,
    required this.records,
    required this.entry,
    required this.fetchedAt,
    this.offset = 0,
    this.documentPage,
  });
  final InAppWebViewKeepAlive view;
  final RecordingPage records;
  final String entry;
  final DateTime fetchedAt;
  final double offset;
  final int? documentPage;
}

class ClassroomSessionCache {
  ClassroomSessionCache({
    this.ttl = ClassroomLimits.sessionTtl,
    this.capacity = ClassroomLimits.sessionCapacity,
    DateTime Function()? clock,
    Future<void> Function(InAppWebViewKeepAlive)? release,
  }) : assert(capacity > 0),
       _clock = clock ?? DateTime.now,
       _release = release ?? InAppWebViewController.disposeKeepAlive;

  static final shared = ClassroomSessionCache();
  final Duration ttl;
  final int capacity;
  final DateTime Function() _clock;
  final Future<void> Function(InAppWebViewKeepAlive) _release;
  final _entries = <String, ClassroomSession>{};
  Timer? _timer;
  int _revision = 0;
  int get revision => _revision;

  String _key(Course course) =>
      jsonEncode([course.semester, course.id, classroomName(course.name)]);

  bool fresh(DateTime fetchedAt) {
    final age = _clock().difference(fetchedAt);
    return !age.isNegative && age < ttl;
  }

  void release(InAppWebViewKeepAlive view) {
    unawaited(
      Future<void>.sync(() => _release(view)).catchError((Object _) {}),
    );
  }

  void _prune() {
    for (final key in _entries.keys.toList()) {
      if (!fresh(_entries[key]!.fetchedAt)) release(_entries.remove(key)!.view);
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_entries.isEmpty) return;
    final earliest = _entries.values
        .map((entry) => entry.fetchedAt.add(ttl))
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final delay = earliest.difference(_clock());
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _prune();
      _schedule();
    });
  }

  /// Transfer exclusive ownership: two mounted WebViews must never share a
  /// keep-alive handle. Reoffering a session does not extend its fetch time.
  ClassroomSession? take(Course course) {
    _prune();
    final value = _entries.remove(_key(course));
    _schedule();
    return value;
  }

  /// Reuse one already-authenticated classroom document for a different course.
  /// The caller must return to the official catalog and revalidate the match.
  ClassroomSession? takeWorkspace() {
    _prune();
    final value = _entries.isEmpty ? null : _entries.remove(_entries.keys.last);
    _schedule();
    return value;
  }

  void put(Course course, ClassroomSession value, {required int revision}) =>
      _put(_key(course), value, revision);

  void putWorkspace(ClassroomSession value, {required int revision}) =>
      _put('workspace', value, revision);

  void _put(String key, ClassroomSession value, int revision) {
    _prune();
    if (revision != _revision || !fresh(value.fetchedAt)) {
      release(value.view);
    } else {
      final old = _entries.remove(key);
      if (old != null && !identical(old.view, value.view)) release(old.view);
      _entries[key] = value;
      while (_entries.length > capacity) {
        release(_entries.remove(_entries.keys.first)!.view);
      }
    }
    _schedule();
  }

  /// Epoch also prevents an in-flight page from repopulating an old account.
  void clear() {
    _revision++;
    _timer?.cancel();
    for (final entry in _entries.values) {
      release(entry.view);
    }
    _entries.clear();
  }
}
