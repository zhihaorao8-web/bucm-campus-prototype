import 'dart:async';
import '../config/classroom_limits.dart';
import '../platform/classroom_access.dart';
import '../platform/classroom_read_progress.dart';
import '../platform/test_diagnostics.dart';

/// Owns connection epochs and read scheduling, without owning a WebView or UI.
/// Advancing an epoch invalidates pending route decisions; authentication has
/// its own unbounded human-wait budget in ClassroomReadProgress.
class ClassroomConnectionCoordinator {
  ClassroomConnectionCoordinator({
    ProbeEndpoint? probe,
    TestDiagnostics? diagnostics,
  }) : probe = probe ?? probeClassroomEndpoint,
       diagnostics = diagnostics ?? TestDiagnostics.shared;
  final ProbeEndpoint probe;
  final TestDiagnostics diagnostics;
  final readProgress = ClassroomReadProgress();
  int _generation = 0;
  bool _disposed = false;
  Timer? _poll;
  int get generation => _generation;
  int advance() => ++_generation;
  bool current(int ticket) => !_disposed && ticket == _generation;

  Future<AccessDecision?> select(
    ClassroomAccess mode, {
    required int ticket,
  }) async {
    diagnostics.record(switch (mode) {
      ClassroomAccess.automatic => TestEvent.accessAutomatic,
      ClassroomAccess.direct => TestEvent.accessDirect,
      ClassroomAccess.vpn => TestEvent.accessWebVpn,
    });
    final decision = mode == ClassroomAccess.automatic
        ? await chooseClassroomAccess(probe)
        : AccessDecision(
            mode,
            mode == ClassroomAccess.vpn ? '已选择学校 WebVPN。' : '已选择直接访问。',
          );
    if (!current(ticket)) return null;
    if (decision.url != null) {
      diagnostics.record(
        decision.mode == ClassroomAccess.vpn
            ? TestEvent.selectedWebVpn
            : TestEvent.selectedDirect,
      );
    }
    return decision;
  }

  void cancelPoll() => _poll?.cancel();
  void schedulePoll(ClassroomReadStage? stage, void Function() read) {
    cancelPoll();
    if (_disposed) return;
    _poll = Timer(
      stage == ClassroomReadStage.authentication
          ? ClassroomLimits.authenticationPoll
          : ClassroomLimits.dataPoll,
      read,
    );
  }

  void dispose() {
    _disposed = true;
    advance();
    cancelPoll();
  }
}
