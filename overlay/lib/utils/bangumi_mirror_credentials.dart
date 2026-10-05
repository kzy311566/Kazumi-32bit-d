// Bangumi mirror API credentials for the search signature flow.
//
// Resolution order (later wins):
//   1. The constants below, written by the release build:
//      scripts/inject-credentials.mjs replaces the AppId and AppSecret
//      placeholders with the repository secrets.
//   2. Nothing else — unlike the DanDanPlay pair these have no in-app entry,
//      because the mirror is an optional acceleration path.
//
// `BangumiAcceleration` reads these through `mirrorAvailable` to decide whether
// the `api.kazumi.fyi` mirror can be used at all. An un-injected checkout still
// compiles and simply reports the mirror as unavailable, which makes the app
// fall back to ECH.
const bool _buildTimeMirrorCredentialsInjected = false;

const Map<String, String> bangumiMirrorCredentials = {
  'id': '__KAZUMI_APPID__',
  'value': '__KAZUMI_KEY__',
};

/// True when the mirror signature can actually be produced.
bool get bangumiMirrorCredentialsAvailable =>
    _buildTimeMirrorCredentialsInjected &&
    bangumiMirrorCredentials['id']!.trim().isNotEmpty &&
    bangumiMirrorCredentials['value']!.trim().isNotEmpty;
