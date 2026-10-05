// Signing helper shared by the credential injector and the live validator.
//
// Its purpose is to make the build-time verification compute the signature the
// same way the Dart client does, over the same bytes that end up compiled into
// the app. A previous build shipped an AppId that GitHub's secret handling had
// prefixed with a byte-order mark: the sha256 reported in the release notes
// still matched, every step looked green, and the app would have failed with
// "Invalid Signature" on every danmaku request. Verifying the exact final bytes
// against the live API is what actually closes that gap.
import { createHash } from 'node:crypto';

/**
 * Removes anything that cannot be part of a real credential.
 *
 * AppIds and AppSecrets are base64/ASCII, so every printable non-space ASCII
 * character is allowed and everything else (BOM, newline, NUL) is not.
 */
export function sanitizeCredential(value) {
  return (value ?? '').replace(/[^\x21-\x7E]/g, '');
}

/** `base64(sha256(appId + timestamp + path + appSecret))`, UTF-8. */
export function generateSignature(appId, appSecret, path, timestamp) {
  return createHash('sha256')
    .update(`${appId}${timestamp}${path}${appSecret}`)
    .digest('base64');
}

/** Hex sha256, used only for logging non-reversible facts. */
export function sha256Hex(value) {
  return createHash('sha256').update(value ?? '').digest('hex');
}

/**
 * Extracts the credentials the app will actually use, by reading them back out
 * of the generated Dart file rather than trusting the environment. Returns null
 * when the file is not injected.
 */
export function readInjectedDartCredentials(dartSource) {
  const injected = /const bool _buildTimeCredentialsInjected = true;/.test(dartSource);
  const appId = /'id':\s*'([^']*)'/.exec(dartSource)?.[1] ?? '';
  const secret = /'value':\s*'([^']*)'/.exec(dartSource)?.[1] ?? '';
  if (!injected || appId.length === 0 || secret.length === 0) return null;
  return { appId, secret };
}
