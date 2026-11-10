import 'school_adapter.dart';

/// Main documents stay on the existing school/explicit authentication boundary.
/// HTTPS media on the observed school node is a subresource, not a login target.
bool classroomNavigation(String value) => authenticationUrl(value);

bool classroomMedia(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      ((uri.host == 'qxkt4.bucm.edu.cn' && uri.port == 8880) ||
          (uri.host == 'qhz.bucm.edu.cn' && uri.port == 443));
}
