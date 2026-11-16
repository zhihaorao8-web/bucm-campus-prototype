/// Dart metadata bounds. The official API page size is a protocol contract;
/// JavaScript/native validation keeps its own independent trust boundary.
abstract final class ClassroomLimits {
  static const fieldLength = 500;
  static const pageSize = 10;
  static const maxModelPageSize = 100;
  static const pages = 1000;
  static const sources = 1000;
  static const localCourses = 1000;
  static const records = 10000;
  static const bridgeResponseLength = 1024 * 1024;
  static const entryResponseLength = 512;
  static const entryHops = 4;
  static const stageAttempts = 20;
  static const sessionCapacity = 2;
  static const sessionTtl = Duration(minutes: 5);
  static const requestTimeout = Duration(seconds: 15);
  static const cancelTimeout = Duration(seconds: 2);
  static const documentTimeout = Duration(seconds: 30);
  static const readyTimeout = Duration(seconds: 3);
  static const authenticationPoll = Duration(seconds: 2);
  static const dataPoll = Duration(milliseconds: 900);
}
