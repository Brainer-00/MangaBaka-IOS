import 'package:url_launcher/url_launcher.dart';

/// Validates and opens web URLs that leave the application.
///
/// Validation is deliberately separate from launching so the security policy
/// can be tested without a browser or platform channel.
class ExternalUrlLauncher {
  const ExternalUrlLauncher._();

  static Uri? parseHttpsUrl(
    String value, {
    Set<String>? allowedHosts,
    bool allowSubdomains = false,
  }) {
    if (value.isEmpty || RegExp(r'\s').hasMatch(value)) return null;

    try {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          !isAllowedHttpsUri(
            uri,
            allowedHosts: allowedHosts,
            allowSubdomains: allowSubdomains,
          )) {
        return null;
      }
      return uri;
    } on FormatException {
      return null;
    }
  }

  static bool isAllowedHttpsUri(
    Uri uri, {
    Set<String>? allowedHosts,
    bool allowSubdomains = false,
  }) {
    if (uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return false;
    }

    if (allowedHosts == null) return true;
    if (allowedHosts.isEmpty) return false;

    final host = uri.host.toLowerCase();
    return allowedHosts.any((allowedHost) {
      final normalizedAllowedHost = allowedHost.toLowerCase();
      if (host == normalizedAllowedHost) return true;
      return allowSubdomains && host.endsWith('.$normalizedAllowedHost');
    });
  }

  static Future<bool> launch(
    String value, {
    Set<String>? allowedHosts,
    bool allowSubdomains = false,
    LaunchMode mode = LaunchMode.externalApplication,
  }) async {
    final uri = parseHttpsUrl(
      value,
      allowedHosts: allowedHosts,
      allowSubdomains: allowSubdomains,
    );
    if (uri == null) return false;

    return launchUri(
      uri,
      allowedHosts: allowedHosts,
      allowSubdomains: allowSubdomains,
      mode: mode,
    );
  }

  static Future<bool> launchUri(
    Uri uri, {
    Set<String>? allowedHosts,
    bool allowSubdomains = false,
    LaunchMode mode = LaunchMode.externalApplication,
  }) async {
    if (!isAllowedHttpsUri(
      uri,
      allowedHosts: allowedHosts,
      allowSubdomains: allowSubdomains,
    )) {
      return false;
    }

    try {
      return await launchUrl(uri, mode: mode);
    } catch (_) {
      return false;
    }
  }
}
