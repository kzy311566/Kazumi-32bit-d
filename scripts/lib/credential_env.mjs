#!/usr/bin/env node
// Emit shell assignments for the sanitized credentials.
//
// `eval "$(node scripts/lib/credential_env.mjs)"` gives the build script the
// same values the injector writes into the Dart sources, so its checks compare
// like with like. Slashes and plus signs are preserved because credentials are
// base64; only characters that cannot appear in a credential are removed.
import { credentialsFromEnv, sha256Hex } from './credentials.mjs';

const { dandanAppId, dandanKey, kazumiAppId, kazumiKey } = credentialsFromEnv();

// Credentials are printable ASCII (guaranteed by sanitizeCredential), so single
// quotes are safe and no escaping is needed.
const emit = (name, value) => `export ${name}='${value}'`;

console.log(emit('DANDANAPI_APPID_CLEAN', dandanAppId));
console.log(emit('KAZUMI_APPID_CLEAN', kazumiAppId));
console.log(emit('DANDANAPI_KEY_SHA256', sha256Hex(dandanKey)));
console.log(emit('KAZUMI_KEY_SHA256', sha256Hex(kazumiKey)));
console.log(emit('DANDANAPI_CREDENTIALS_STATE', dandanAppId ? `injected (${dandanAppId})` : 'not injected'));
