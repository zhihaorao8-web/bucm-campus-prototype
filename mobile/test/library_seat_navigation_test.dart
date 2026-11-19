import 'package:campus_schedule/config/network_policy.dart';
import 'package:campus_schedule/platform/library_seat_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allows the official booking page and school CAS in the main frame', () {
    expect(librarySeatNavigation(SchoolEndpoints.librarySeatHome), isTrue);
    expect(librarySeatPage(SchoolEndpoints.librarySeatHome), isTrue);
    expect(
      librarySeatNavigation('https://kjyy.bucm.edu.cn:443/#/ic/userinfo'),
      isTrue,
    );
    expect(librarySeatNavigation('https://cas.bucm.edu.cn/cas/login'), isTrue);
    expect(librarySeatPage('https://cas.bucm.edu.cn/cas/login'), isFalse);
  });

  test('rejects alternate schemes, hosts, ports and user information', () {
    for (final url in [
      null,
      '',
      'about:blank',
      'file:///tmp/booking.html',
      '//kjyy.bucm.edu.cn/',
      'http://kjyy.bucm.edu.cn/',
      'https://kjyy.bucm.edu.cn:8443/',
      'https://kjyy.bucm.edu.cn.evil.example/',
      'https://other.kjyy.bucm.edu.cn/',
      'https://kjyy.bucm.edu.cn@evil.example/',
      'https://user@kjyy.bucm.edu.cn/',
      'https://@kjyy.bucm.edu.cn/',
      'https://webvpn.bucm.edu.cn/',
      'https://work.weixin.qq.com/',
    ]) {
      expect(librarySeatNavigation(url), isFalse, reason: url);
      expect(librarySeatPage(url), isFalse, reason: url);
    }
  });
}
