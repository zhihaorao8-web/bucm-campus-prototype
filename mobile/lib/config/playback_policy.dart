/// Millisecond thresholds are shared by stored-progress validation and the
/// active session. This is local resume metadata, never school watch history.
abstract final class PlaybackPolicy {
  static const resumeMinimumMs = 10000;
  static const resumeTailMs = 30000;
  static const durationToleranceMs = 2000;
  static const maximumDurationMs = 7 * 24 * 3600000;
  static const saveInterval = Duration(seconds: 5);
  static const durationWait = Duration(seconds: 10);
  static const statePoll = Duration(milliseconds: 400);
  static const prepareTimeout = Duration(seconds: 25);
  static bool resumablePosition(int position, int duration) =>
      position >= resumeMinimumMs && duration - position >= resumeTailMs;
}
