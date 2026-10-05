#!/usr/bin/env bash
# Build the Android 32-bit (armeabi-v7a) APK for Kazumi.
#
# Credentials arrive from the environment and are written into the Dart sources
# by scripts/inject-credentials.mjs (see that file for why --dart-define is not
# used). Kept in a script rather than inline in the workflow so shell variables
# are expanded by bash, not by GitHub Actions' expression parser.
#
# Required environment:
#   DANDANAPI_APPID   DanDanPlay AppId. May be empty (danmaku stays disabled).
#   DANDANAPI_KEY     DanDanPlay AppSecret. May be empty.
#   KAZUMI_APPID      Bangumi mirror AppId. May be empty.
#   KAZUMI_KEY        Bangumi mirror AppSecret. May be empty.
#   APP_VERSION_NAME  Version string recorded in the artifact name.
#
# Optional environment:
#   SPLIT_PER_ABI     "0" to emit a single universal APK instead of splits.
set -euo pipefail

# This script is invoked from the *upstream* working directory, so anything it
# needs from this repository must be resolved from its own location rather than
# from $PWD. Hardcoding `scripts/...` here silently looked for the injector under
# upstream/scripts/ and failed with MODULE_NOT_FOUND.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "repo root: $REPO_ROOT"
echo "working dir: $PWD"

APP_VERSION_NAME="${APP_VERSION_NAME:-unknown}"
SPLIT_PER_ABI="${SPLIT_PER_ABI:-1}"

if [ -z "${DANDANAPI_APPID:-}" ] || [ -z "${DANDANAPI_KEY:-}" ]; then
  echo "::warning::DANDANAPI_APPID / DANDANAPI_KEY are not set."
  echo "::warning::The build will have NO danmaku source. Configure the repository"
  echo "::warning::secrets, or users must enter credentials in the app."
else
  echo "DanDanPlay credentials present."
fi

if [ -z "${KAZUMI_APPID:-}" ] || [ -z "${KAZUMI_KEY:-}" ]; then
  echo "::warning::KAZUMI_APPID / KAZUMI_KEY are not set; the Bangumi mirror"
  echo "::warning::cannot be signed, so the app falls back to ECH."
fi

node "$REPO_ROOT/scripts/inject-credentials.mjs"

if [ -n "${DANDANAPI_KEY:-}" ]; then
  grep -qF -- "$DANDANAPI_KEY" lib/utils/dandan_credentials.dart \
    || { echo "::error::the AppSecret did not reach lib/utils/dandan_credentials.dart"; exit 1; }
fi
if [ -n "${KAZUMI_KEY:-}" ]; then
  grep -qF -- "$KAZUMI_KEY" lib/utils/bangumi_mirror_credentials.dart \
    || { echo "::error::the mirror AppSecret did not reach lib/utils/bangumi_mirror_credentials.dart"; exit 1; }
fi

# --- build ------------------------------------------------------------------
read -r -a BUILD_ARGS <<< "build apk --release"
if [ "$SPLIT_PER_ABI" != "0" ]; then
  BUILD_ARGS+=(--split-per-abi)
fi

flutter "${BUILD_ARGS[@]}"

mkdir -p release-files
if [ "$SPLIT_PER_ABI" != "0" ]; then
  SRC="build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk"
  DEST="release-files/Kazumi_android_armeabi-v7a_${APP_VERSION_NAME}.apk"
else
  SRC="build/app/outputs/flutter-apk/app-release.apk"
  DEST="release-files/Kazumi_android_universal_${APP_VERSION_NAME}.apk"
fi

if [ ! -f "$SRC" ]; then
  echo "::error::expected APK not found: $SRC"
  echo "Available outputs:"
  ls -la build/app/outputs/flutter-apk/ || true
  exit 1
fi

cp "$SRC" "$DEST"

# Checksums let users and mirrors verify the published artifact, and make it
# possible to tell whether a rebuilt APK actually changed.
APK_SHA256="$(sha256sum "$DEST" | cut -d' ' -f1)"
{
  echo "# Kazumi Android 32-bit ${APP_VERSION_NAME}"
  echo "# built from Predidit/Kazumi ${APP_VERSION_NAME} + patches/ in this repository"
  echo "# danmaku credentials: ${DANDANAPI_APPID:-<not injected>}"
  echo "$APK_SHA256  $(basename "$DEST")"
} > release-files/checksums.txt

echo "sha256=$APK_SHA256"
{
  echo "artifact=${DEST}"
  echo "dandan_key_sha256=$(printf '%s' "${DANDANAPI_KEY:-}" | sha256sum | cut -d' ' -f1)"
} >> "${GITHUB_ENV:-/dev/null}"
ls -la release-files/
cat release-files/checksums.txt
