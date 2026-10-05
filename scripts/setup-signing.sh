#!/usr/bin/env bash
# Optionally switch the Android release build from the debug keystore to a
# stable release keystore.
#
# Why this matters: upstream signs release APKs with `signingConfigs.debug`, and
# a CI runner regenerates the debug keystore on every job. Two builds of the
# same version therefore carry different signatures, so Android refuses to
# install the new one over the old one ("App not installed") and the user must
# uninstall first, losing app data.
#
# Set these repository secrets to enable a stable signature:
#   SIGNING_KEY_BASE64       base64 of your .jks / .keystore file
#   KEY_ALIAS                key alias inside the keystore
#   KEY_STORE_PASSWORD       keystore password
#   KEY_PASSWORD             key password (often the same)
#
# Without them the build keeps using the debug keystore and warns.
set -euo pipefail

# Invoked with the upstream working directory as $PWD; resolve our own location
# so the paths below cannot accidentally point outside the checkout.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GRADLE_FILE="android/app/build.gradle"
KEY_PROPERTIES="android/key.properties"
KEYSTORE_PATH="android/app/upload-keystore.jks"

if [ -z "${SIGNING_KEY_BASE64:-}" ]; then
  echo "::warning::SIGNING_KEY_BASE64 is not set."
  echo "::warning::Falling back to the debug keystore, which is regenerated on every run."
  echo "::warning::Users will not be able to install a new build over an existing one."
  exit 0
fi

if [ -z "${KEY_ALIAS:-}" ] || [ -z "${KEY_STORE_PASSWORD:-}" ] || [ -z "${KEY_PASSWORD:-}" ]; then
  echo "::error::SIGNING_KEY_BASE64 is set but KEY_ALIAS / KEY_STORE_PASSWORD / KEY_PASSWORD are incomplete."
  exit 1
fi

if [ ! -f "$GRADLE_FILE" ]; then
  echo "::error::$GRADLE_FILE not found; upstream layout changed"
  exit 1
fi

echo "Configuring a stable release keystore..."

# base64 may or may not be line-wrapped depending on how it was produced.
printf '%s' "$SIGNING_KEY_BASE64" | tr -d '\r\n' | base64 -d > "$KEYSTORE_PATH"
test -s "$KEYSTORE_PATH"
echo "keystore written: $(stat -c%s "$KEYSTORE_PATH") bytes"

cat > "$KEY_PROPERTIES" <<EOF
storePassword=${KEY_STORE_PASSWORD}
keyPassword=${KEY_PASSWORD}
keyAlias=${KEY_ALIAS}
storeFile=upload-keystore.jks
EOF

# Edit build.gradle with Python. Anchor on lines that definitely belong to the
# Groovy `android { }` block: the file also contains a Kotlin-DSL
# `plugins { id "dev.flutter.flutter-gradle-plugin" }` block and a bare
# `android {` fragment, so matching on `android {` alone would patch the wrong
# place.
python3 - "$GRADLE_FILE" <<'PY'
import sys

gradle_file = sys.argv[1]
with open(gradle_file, encoding='utf-8') as handle:
    source = handle.read()

if 'kazumiRelease' in source:
    print('build.gradle already carries a release signing config; leaving it alone')
    sys.exit(0)

if 'signingConfig signingConfigs.debug' not in source:
    print('::error::could not find the debug signingConfig line to replace')
    sys.exit(1)

anchor = '    namespace "com.example.kazumi"'
if anchor not in source:
    print('::error::could not find the android { } namespace anchor; upstream layout changed')
    sys.exit(1)

loading_block = (
    "    // Written by scripts/setup-signing.sh from repository secrets.\n"
    "    def kazumiKeystoreProperties = new java.util.Properties()\n"
    "    def kazumiKeystorePropertiesFile = rootProject.file('key.properties')\n"
    "    if (kazumiKeystorePropertiesFile.exists()) {\n"
    "        kazumiKeystorePropertiesFile.withReader('UTF-8') { reader ->\n"
    "            kazumiKeystoreProperties.load(reader)\n"
    "        }\n"
    "    }\n"
    "\n"
)

signing_block = (
    "    signingConfigs {\n"
    "        kazumiRelease {\n"
    "            keyAlias kazumiKeystoreProperties['keyAlias']\n"
    "            keyPassword kazumiKeystoreProperties['keyPassword']\n"
    "            storeFile file(kazumiKeystoreProperties['storeFile'])\n"
    "            storePassword kazumiKeystoreProperties['storePassword']\n"
    "        }\n"
    "    }\n"
    "\n"
)

source = source.replace(anchor, signing_block + loading_block + anchor, 1)
source = source.replace(
    'signingConfig signingConfigs.debug',
    'signingConfig signingConfigs.kazumiRelease',
)

with open(gradle_file, 'w', encoding='utf-8') as handle:
    handle.write(source)

print('build.gradle patched for release signing')
PY

echo "--- signing config result ---"
grep -n 'kazumiRelease\|signingConfig signingConfigs' "$GRADLE_FILE" || true
test -f "$KEY_PROPERTIES" && echo "key.properties present"
