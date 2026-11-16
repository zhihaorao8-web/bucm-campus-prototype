import '../config/runtime_config.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

enum TestEvent {
  directoryStart,
  catalogRequest,
  catalogReady,
  pageRequest,
  pageReady,
  directReady,
  fallbackUnsupported,
  authenticationNeeded,
  permissionDenied,
  invalidResponse,
  requestFailed,
  requestTimeout,
  cancelled,
  bridgeFailed,
  importSaved,
  importSaveFailed,
  unmatched,
  mediaPrepare,
  mediaReady,
  mediaFailed,
  mediaNetwork,
  mediaBoundary,
  mediaWatermark,
  accessAutomatic,
  accessDirect,
  accessWebVpn,
  selectedDirect,
  selectedWebVpn,
  officialContextDirect,
  officialContextWebVpn,
  officialContextUnknown,
  upstreamConnectionFailed,
}

/// Only fixed enums and bounded numeric fields enter stored/exported events.
class TestDiagnostics extends ChangeNotifier {
  TestDiagnostics({required this.enabled, this.capacity = 200})
    : assert(capacity > 0 && capacity <= 1000);
  static const available = kDebugMode && AppFeatures.diagnostics;
  static final shared = TestDiagnostics(enabled: available);
  final bool enabled;
  final int capacity;
  final _events = <Map<String, Object>>[];
  int _dropped = 0;
  List<Map<String, Object>> get events => List.unmodifiable(
    _events.map((e) => Map<String, Object>.unmodifiable(e)),
  );
  void record(TestEvent event, {int? elapsedMs, int? count}) {
    if (!enabled) return;
    final entry = <String, Object>{
      'timeUtc': DateTime.now().toUtc().toIso8601String(),
      'event': event.name,
      if (elapsedMs != null) 'elapsedMs': elapsedMs.clamp(0, 3600000),
      if (count != null) 'count': count.clamp(0, 10000),
    };
    if (_events.length == capacity) {
      _events.removeAt(0);
      _dropped++;
    }
    _events.add(entry);
    notifyListeners();
  }

  void failure(String? state) => record(switch (state) {
    'authentication' => TestEvent.authenticationNeeded,
    'forbidden' => TestEvent.permissionDenied,
    'timeout' => TestEvent.requestTimeout,
    'cancelled' => TestEvent.cancelled,
    'invalid-data' || 'catalog-changed' => TestEvent.invalidResponse,
    _ => TestEvent.requestFailed,
  });
  void mediaFailure(String? code) => record(switch (code) {
    'MEDIA_NETWORK' => TestEvent.mediaNetwork,
    'MEDIA_BOUNDARY' || 'UNTRUSTED_PAGE' => TestEvent.mediaBoundary,
    'WATERMARK' || 'POLICY' => TestEvent.mediaWatermark,
    _ => TestEvent.mediaFailed,
  });
  void officialContext(Object? value) => record(switch (value) {
    'direct' => TestEvent.officialContextDirect,
    'webvpn' => TestEvent.officialContextWebVpn,
    _ => TestEvent.officialContextUnknown,
  });
  void clear() {
    _events.clear();
    _dropped = 0;
    notifyListeners();
  }

  String export() => const JsonEncoder.withIndent('  ').convert({
    'schema': 1,
    'scope': 'test-recording-directory',
    'enabled': enabled,
    'directCatalogEnabled': AppFeatures.directCatalog,
    'dropped': _dropped,
    'events': events,
  });
}
