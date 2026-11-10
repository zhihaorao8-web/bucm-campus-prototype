import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum ClassroomAccess { automatic, direct, vpn }

enum ProbeState {
  available,
  authentication,
  unavailable,
  unexpected,
  certificateError,
}

class AccessProbe {
  const AccessProbe(this.state);
  final ProbeState state;
  bool get reachable =>
      state == ProbeState.available || state == ProbeState.authentication;
}

const directEntry = 'https://i.bucm.edu.cn/';
const vpnEntry = 'https://webvpn.bucm.edu.cn/';
const classroomProbe = 'https://qhz.bucm.edu.cn/cc/';

/// Only validates public page signatures. Does not authenticate or share cookies.
AccessProbe classifyProbe(
  String address,
  int status,
  String body,
  String? location,
) {
  if (address != classroomProbe && address != vpnEntry) {
    return const AccessProbe(ProbeState.unexpected);
  }
  final source = Uri.parse(address);
  if ({301, 302, 303, 307, 308}.contains(status)) {
    final relative = Uri.tryParse(location ?? '');
    if (relative == null) return const AccessProbe(ProbeState.unexpected);
    final target = source.resolveUri(relative);
    if (location != null &&
        target.scheme == 'https' &&
        target.userInfo.isEmpty &&
        target.port == 443 &&
        target.host == 'cas.bucm.edu.cn') {
      return const AccessProbe(ProbeState.authentication);
    }
    return const AccessProbe(ProbeState.unexpected);
  }
  if (status != 200) return const AccessProbe(ProbeState.unavailable);
  final title =
      RegExp(
        r'<title[^>]*>([\s\S]*?)</title>',
        caseSensitive: false,
      ).firstMatch(body)?.group(1) ??
      '';
  final branded = source.host == 'qhz.bucm.edu.cn'
      ? title.contains('智慧教学平台') || title.contains('岐黄智')
      : source.host == 'webvpn.bucm.edu.cn' &&
            title.toLowerCase().contains('webvpn');
  return AccessProbe(
    branded && RegExp(r'<script\b', caseSensitive: false).hasMatch(body)
        ? ProbeState.available
        : ProbeState.unexpected,
  );
}

typedef ProbeEndpoint = Future<AccessProbe> Function(String address);

class AccessDecision {
  const AccessDecision(this.mode, this.message);
  final ClassroomAccess? mode;
  final String message;
  String? get url => switch (mode) {
    ClassroomAccess.direct => directEntry,
    ClassroomAccess.vpn => vpnEntry,
    _ => null,
  };
}

Future<AccessDecision> chooseClassroomAccess(ProbeEndpoint probe) async {
  final direct = await probe(classroomProbe);
  if (direct.reachable) {
    return const AccessDecision(
      ClassroomAccess.direct,
      '学校服务可直接访问，请在官方页面完成认证。',
    );
  }
  final vpn = await probe(vpnEntry);
  if (vpn.reachable) {
    return const AccessDecision(ClassroomAccess.vpn, '直连暂未确认可用，已选择学校 WebVPN。');
  }
  return AccessDecision(
    null,
    direct.state == ProbeState.certificateError ||
            vpn.state == ProbeState.certificateError
        ? '学校连接证书校验失败，未自动打开。请检查网络或手动选择访问方式。'
        : '暂未确认可用的访问路径。请检查网络后重试，或手动选择；离线课表仍可使用。',
  );
}

/// Small, bounded, credential-free requests. Normal TLS validation remains on.
Future<AccessProbe> probeClassroomEndpoint(String address) async {
  if (address != classroomProbe && address != vpnEntry) {
    return const AccessProbe(ProbeState.unexpected);
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    return await (() async {
      var uri = Uri.parse(address);
      for (var hop = 0; hop < 3; hop++) {
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        final response = await request.close();
        final location = response.headers.value(HttpHeaders.locationHeader);
        if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
          final target = uri.resolve(location ?? '');
          if (location != null &&
              target.origin == uri.origin &&
              target.userInfo.isEmpty) {
            // Drain neither arbitrary bodies nor redirects outside this origin.
            await response.listen((_) {}).cancel();
            uri = target;
            continue;
          }
          final result = classifyProbe(
            address,
            response.statusCode,
            '',
            location == null ? null : target.toString(),
          );
          await response.listen((_) {}).cancel();
          return result;
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk.take(65536 - bytes.length));
          if (bytes.length == 65536) break;
        }
        return classifyProbe(
          address,
          response.statusCode,
          utf8.decode(bytes, allowMalformed: true),
          null,
        );
      }
      return const AccessProbe(ProbeState.unexpected);
    })().timeout(const Duration(seconds: 4));
  } on HandshakeException {
    return const AccessProbe(ProbeState.certificateError);
  } catch (_) {
    return const AccessProbe(ProbeState.unavailable);
  } finally {
    client.close(force: true);
  }
}
