import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/dandan_credentials.dart';

/// Persists user-supplied DanDanPlay API credentials and pushes them into
/// [DandanCredentials] at startup.
///
/// This exists because the upstream project binds the credentials at compile
/// time and its release pipeline injects them from private CI secrets. Builds
/// that cannot read those secrets (community 32-bit builds, local builds,
/// forks) would otherwise ship with blank credentials and every danmaku
/// request would fail with HTTP 403.
class DanmakuCredentialStore {
  DanmakuCredentialStore._();

  /// Loads the persisted override into [DandanCredentials].
  ///
  /// Call once during startup, after `GStorage.init`.
  static void load() {
    try {
      final appId = GStorage.getSetting(SettingsKeys.danmakuCredentialAppId);
      final secret = GStorage.getSetting(SettingsKeys.danmakuCredentialSecret);
      if (appId.trim().isEmpty && secret.trim().isEmpty) {
        DandanCredentials.clearOverride();
        return;
      }
      DandanCredentials.setOverride(appId: appId, secret: secret);
      KazumiLogger().i(
        'DanmakuCredentialStore: using user-supplied credentials '
        '(appId=${DandanCredentials.appIdForDisplay})',
      );
    } catch (e) {
      // Storage is optional: fall back to the build-time constants.
      KazumiLogger().w(
        'DanmakuCredentialStore: failed to read stored credentials',
        error: e,
      );
      DandanCredentials.clearOverride();
    }
  }

  /// Persists and activates user-supplied credentials.
  static Future<void> save({
    required String appId,
    required String secret,
  }) async {
    await GStorage.putSetting(SettingsKeys.danmakuCredentialAppId, appId);
    await GStorage.putSetting(SettingsKeys.danmakuCredentialSecret, secret);
    DandanCredentials.setOverride(appId: appId, secret: secret);
    KazumiLogger().i(
      'DanmakuCredentialStore: stored credentials '
      '(appId=${DandanCredentials.appIdForDisplay})',
    );
  }

  /// Removes the stored override, falling back to the build-time constants.
  static Future<void> clear() async {
    await GStorage.putSetting(SettingsKeys.danmakuCredentialAppId, '');
    await GStorage.putSetting(SettingsKeys.danmakuCredentialSecret, '');
    DandanCredentials.clearOverride();
    KazumiLogger().i('DanmakuCredentialStore: cleared stored credentials');
  }

  /// The persisted AppId, for prefilling the settings form.
  static String get storedAppId =>
      GStorage.getSetting(SettingsKeys.danmakuCredentialAppId);

  /// The persisted secret, for prefilling the settings form.
  static String get storedSecret =>
      GStorage.getSetting(SettingsKeys.danmakuCredentialSecret);
}
