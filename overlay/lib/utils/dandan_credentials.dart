// Build-time DanDanPlay open API credentials.
//
// Resolution order (later wins):
//   1. The constants below, written by the release build:
//      scripts/inject-credentials.mjs replaces the AppId and AppSecret
//      placeholders with the repository secrets.
//   2. Values the user entered in-app (persisted by DanmakuCredentialStore).
//
// Consumers must treat "blank" as "danmaku unavailable" and skip the request
// instead of sending a signature that is guaranteed to fail with HTTP 403 —
// the open API rejects unauthenticated calls on every endpoint.
//
// The placeholders are replaced verbatim; they are valid Dart string contents,
// so an un-injected checkout still compiles and simply reports "not configured".
import 'dart:convert';

import 'package:crypto/crypto.dart';

const Map<String, String> _buildTimeDandanCredentials = {
  'id': '__DANDANAPI_APPID__',
  'value': '__DANDANAPI_KEY__',
};

/// Whether build-time credentials were really injected.
///
/// This single declaration is rewritten by scripts/inject-credentials.mjs to
/// `= true;` when the repository secrets are present, so it must stay a
/// one-line `const bool` with a plain `false` initialiser: the build asserts on
/// that exact shape. The literal `false` is also what keeps an un-injected
/// checkout compiling, so `flutter run` works without the release build script.
const bool _buildTimeCredentialsInjected = false;

class DandanCredentials {
  DandanCredentials._();

  static String _overrideId = '';
  static String _overrideSecret = '';

  static bool get isInjected => _buildTimeCredentialsInjected;

  /// Applies user-provided credentials. Blank values fall back to the
  /// build-time constants.
  ///
  /// Accepts the complete `appId;appSecret` string shown in the DevCenter in
  /// either field, because that is the form users usually copy.
  static void setOverride({String? appId, String? secret}) {
    final parsed = _parseCredentialPair(appId ?? '', secret ?? '');
    _overrideId = parsed.$1;
    _overrideSecret = parsed.$2;
  }

  static void clearOverride() {
    _overrideId = '';
    _overrideSecret = '';
  }

  static String get appId {
    final override = _overrideId.trim();
    if (override.isNotEmpty) return override;
    return isInjected ? _buildTimeDandanCredentials['id']!.trim() : '';
  }

  static String get appSecret {
    final override = _overrideSecret.trim();
    if (override.isNotEmpty) return override;
    return isInjected ? _buildTimeDandanCredentials['value']!.trim() : '';
  }

  /// True when requests can be signed.
  static bool get isConfigured => appId.isNotEmpty && appSecret.isNotEmpty;

  /// True when the build itself carries usable credentials.
  static bool get hasBuildTimeCredentials => isInjected;

  /// True when the user supplied their own credentials in-app.
  static bool get hasUserCredentials => _overrideId.trim().isNotEmpty;

  /// Accepts `id;secret` in either field and returns the `(id, secret)` tuple.
  static (String, String) _parseCredentialPair(String rawId, String rawSecret) {
    var id = rawId.trim();
    var value = rawSecret.trim();
    final combined = id.contains(';') ? id : (value.contains(';') ? value : '');
    if (combined.isNotEmpty) {
      final separator = combined.indexOf(';');
      id = combined.substring(0, separator).trim();
      value = combined.substring(separator + 1).trim();
    }
    return (id, value);
  }

  /// `base64(sha256(appId + timestamp + path + appSecret))` over UTF-8 bytes,
  /// exactly as specified by the DanDanPlay open API documentation.
  ///
  /// [path] is the URL path only: no scheme, host or query string.
  static String generateSignature(String path, int timestamp) {
    final data = appId + timestamp.toString() + path + appSecret;
    final digest = sha256.convert(utf8.encode(data));
    return base64Encode(digest.bytes);
  }

  /// Redacted rendering of the active AppId for logs and UI.
  static String get appIdForDisplay {
    final id = appId;
    if (id.isEmpty) return '(未配置)';
    if (id.length <= 6) return id;
    return '${id.substring(0, 4)}…${id.substring(id.length - 2)}';
  }
}
