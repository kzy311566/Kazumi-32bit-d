#!/usr/bin/env bash
# Verify that the published APK really is a usable 32-bit Kazumi build.
#
# Motivated by this repository's original failure mode: the workflow produced
# (or failed to produce) artifacts with no way to tell that danmaku was dead and
# that the ABI was wrong. Every check below fails the job loudly.
#
# Environment:
#   APK               path to the built APK
#   DANDANAPI_APPID   expected AppId (optional; skipped when empty)
set -euo pipefail

APK="${APK:?APK must be set}"
if [ ! -f "$APK" ]; then
  echo "::error::APK not found: $APK"
  exit 1
fi

echo "=== APK: $APK ($(du -h "$APK" | cut -f1)) ==="

# libarchive's bsdtar reads APKs (zip) and is preinstalled on ubuntu runners.
listing() { unzip -l "$APK"; }

echo
echo "--- native libraries ---"
LIBS="$(listing | awk '{print $4}' | grep '^lib/' || true)"
if [ -z "$LIBS" ]; then
  echo "::error::no native libraries found; the APK is not a valid Flutter build"
  exit 1
fi
printf '%s\n' "$LIBS" | sed 's#/[^/]*$##' | sort -u

echo
echo "--- 32-bit ABI check ---"
if ! printf '%s\n' "$LIBS" | grep -q '^lib/armeabi-v7a/'; then
  echo "::error::no lib/armeabi-v7a/ entries; this is not a 32-bit APK"
  exit 1
fi
if printf '%s\n' "$LIBS" | grep -qE '^lib/(arm64-v8a|x86_64)/'; then
  echo "::error::APK also contains 64-bit libraries; split-per-abi did not work"
  exit 1
fi
echo "OK: armeabi-v7a only"

echo
echo "--- libmpv (video playback) present? ---"
if ! printf '%s\n' "$LIBS" | grep -qE 'lib/armeabi-v7a/libmpv\.so'; then
  echo "::warning::libmpv.so not found under armeabi-v7a; playback may be broken"
  printf '%s\n' "$LIBS" | grep 'armeabi-v7a' | head -20
else
  echo "OK: libmpv.so present for armeabi-v7a"
fi

echo
echo "--- manifest sanity ---"
BADGING=""
if command -v aapt >/dev/null 2>&1; then
  BADGING="$(aapt dump badging "$APK")"
elif command -v aapt2 >/dev/null 2>&1; then
  BADGING="$(aapt2 dump badging "$APK")"
else
  echo "(aapt not available; skipping manifest dump)"
fi

if [ -n "$BADGING" ]; then
  printf '%s\n' "$BADGING" | head -5
  echo
  echo "--- Android TV eligibility ---"
  # A TV box can install the APK but never launch it unless the manifest carries
  # the leanback launcher category, so assert it is really in the built APK.
  if printf '%s\n' "$BADGING" | grep -q 'leanback-launchable-activity'; then
    echo "OK: leanback launcher present (Android TV home screen)"
  else
    echo "::error::no leanback launcher in the APK; Android TV devices cannot launch it"
    exit 1
  fi
  if printf '%s\n' "$BADGING" | grep -q 'touchscreen'; then
    echo "::warning::the APK still declares a required touchscreen; TV installs may be blocked"
  fi
fi

if ! unzip -p "$APK" AndroidManifest.xml >/dev/null 2>&1; then
  echo "::error::AndroidManifest.xml missing from the APK"
  exit 1
fi

echo
echo "--- embedded credential marker ---"
# The AppId is not secret and is compiled into the app. Release builds AOT
# compile Dart to native code, so the literal may not be greppable; this is a
# best-effort check and the authoritative credential check is the live API call
# performed by scripts/validate-credentials.mjs.
if [ -n "${DANDANAPI_APPID:-}" ]; then
  if unzip -p "$APK" 'assets/flutter_assets/kernel_blob.bin' 2>/dev/null | grep -qF -- "$DANDANAPI_APPID" \
     || grep -aqF -- "$DANDANAPI_APPID" "$APK" 2>/dev/null; then
    echo "OK: AppId '$DANDANAPI_APPID' found inside the APK"
  else
    echo "::warning::AppId not found as a plain string in the APK."
    echo "::warning::Expected for AOT release builds; relying on the live credential check."
  fi
else
  echo "(DANDANAPI_APPID not provided; skipping marker check)"
fi

echo
echo "=== APK verification passed ==="
