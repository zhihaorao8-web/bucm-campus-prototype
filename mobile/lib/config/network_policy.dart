/// Fixed public entries are separate from navigation/download/media allowlists.
/// Keep the purpose-specific TLS, host, port and path checks at each boundary.
abstract final class SchoolEndpoints {
  static const portal = 'https://i.bucm.edu.cn/';
  static const vpn = 'https://webvpn.bucm.edu.cn/';
  static const classroom = 'https://qhz.bucm.edu.cn/cc/';
  static const teaching = 'https://jw.bucm.edu.cn/';
  static const librarySeatHost = 'kjyy.bucm.edu.cn';
  static const librarySeatHome = 'https://$librarySeatHost/#/ic/home';
  static const classroomVpnPrefix =
      '/https/77726476706e69737468656265737421e1ff5bd225256b5d300d8db9d6562d/';
  static const courseRoute =
      'coursePlatform/#/courseCenter/index?firstMenuId=11';
}

abstract final class ProbePolicy {
  static const connectTimeout = Duration(seconds: 3);
  static const totalTimeout = Duration(seconds: 4);
  static const maxBytes = 65536;
  static const redirectHops = 3;
}

abstract final class ImportPolicy {
  static const exportWait = Duration(seconds: 20);
  static const navigationPoll = Duration(milliseconds: 1500);
  static const viewportTimeout = Duration(seconds: 3);
}

abstract final class LibrarySeatPolicy {
  static const _host = SchoolEndpoints.librarySeatHost;
  static const origin = 'https://$_host';
  static const document = '/config/config.js';
  static const readAsset = 'assets/library-seat-read.js';
  static const bookingPageSize = 10;
  static const bookingStatusFilter = '8582';
  static const timeout = Duration(seconds: 12);
  static const maxRows = 2048;
  static const maxBodyBytes = 4 * 1024 * 1024;
}

abstract final class QuotePolicy {
  static const endpoint = 'https://v1.hitokoto.cn/?encode=json';
  static const responseBytes = 16 * 1024;
  static const timeout = Duration(seconds: 4);
}
