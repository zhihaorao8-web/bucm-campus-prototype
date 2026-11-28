/// Public resource/bridge identifiers only. No session or credential values.
abstract final class AppAssets {
  static const exportNavigation = 'assets/export-nav.js';
  static const coverage = 'assets/coverage-check.js';
  static const extract = 'assets/extract.js';
  static const viewport = 'assets/school-viewport.js';
  static const classroom = 'assets/classroom.js';
  static const classroomEntry = 'assets/classroom-entry.js';
  static const recordingApi = 'assets/recording-api.cjs';
  static const recordingBridge = 'assets/recording-api-bridge.js';
  static const appIcon = 'assets/app-icon.png';
  static const developerAvatar = 'assets/developer-avatar.png';
}

abstract final class AppChannels {
  static const app = 'cn.bucm.campus/app';
  static const school = 'cn.bucm.campus/school';
  static const playback = 'cn.bucm.campus/playback';
  static const credentials = 'cn.bucm.campus/credentials';
  static const loginActions = 'cn.bucm.campus/login_actions';
}

abstract final class AppFeatures {
  static const directCatalog = bool.fromEnvironment('CAMPUS_DIRECT_CATALOG');
  static const diagnostics = bool.fromEnvironment(
    'CAMPUS_TEST_DIAGNOSTICS',
    defaultValue: true,
  );
}

abstract final class AppLinks {
  static const developer = 'https://github.com/zhihaorao8-web';
  static const repository = '$developer/bucm-campus-prototype';
}
