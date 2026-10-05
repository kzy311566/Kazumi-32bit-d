#!/usr/bin/env node
// Validate the DanDanPlay credentials against the live API before spending build
// minutes on an APK.
//
// This is the authoritative check that danmaku will work: the open API rejects
// unauthenticated requests on every endpoint with HTTP 403, so a build with
// wrong credentials produces an app whose danmaku silently fails.
//
// When the injected Dart file exists its contents are used instead of the
// environment. That matters: the environment previously carried an AppId with a
// leading byte-order mark, which made every signature invalid while all local
// checks still passed. Verifying the bytes that actually get compiled is the
// difference between a green build and a working one.
//
// Usage: node scripts/validate-credentials.mjs [path/to/dandan_credentials.dart]
//
// Exit codes:
//   0  credentials work (or were intentionally skipped)
//   1  credentials are present but rejected
import { readFileSync } from 'node:fs';

import {
  generateSignature,
  readInjectedDartCredentials,
  sanitizeCredential,
} from './lib/credentials.mjs';

const BASE = 'https://api.dandanplay.net';

const dartPath = process.argv[2] ?? 'lib/utils/dandan_credentials.dart';
let appId = '';
let secret = '';
let source = 'environment';

try {
  const injected = readInjectedDartCredentials(readFileSync(dartPath, 'utf8'));
  if (injected) {
    appId = injected.appId;
    secret = injected.secret;
    source = dartPath;
  }
} catch {
  // File absent: fall back to the environment.
}

if (!appId || !secret) {
  appId = sanitizeCredential(process.env.DANDANAPI_APPID);
  secret = sanitizeCredential(process.env.DANDANAPI_KEY);
  source = 'environment';
}

if (!appId || !secret) {
  console.log('::warning::DANDANAPI_APPID / DANDANAPI_KEY are empty.');
  console.log('::warning::Skipping the live credential check; the resulting APK');
  console.log('::warning::will have no danmaku source.');
  process.exit(0);
}

// A credential with characters outside printable ASCII is a red flag: the app
// signs the exact string, so an invisible prefix breaks every request.
const nonPrintable = [...appId, ...secret].filter(
  (char) => char.codePointAt(0) < 0x21 || char.codePointAt(0) > 0x7e,
).length;
if (nonPrintable > 0) {
  console.error(
    `::error::credentials contain ${nonPrintable} non-printable character(s); the signature would be invalid`,
  );
  process.exit(1);
}

async function check(label, path, query = '') {
  const timestamp = Math.floor(Date.now() / 1000);
  const url = `${BASE}${path}${query}`;
  const res = await fetch(url, {
    headers: {
      'X-AppId': appId,
      'X-Timestamp': String(timestamp),
      'X-Signature': generateSignature(appId, secret, path, timestamp),
      'user-agent': 'Kazumi-build-check',
    },
  });
  const body = await res.text();
  const apiError = res.headers.get('x-error-message') ?? '';
  console.log(
    `  ${label}: HTTP ${res.status}${apiError ? ` (${apiError})` : ''} ${body.slice(0, 100)}`,
  );
  return res.status;
}

console.log(`Validating DanDanPlay credentials from ${source}`);
console.log(`  AppId length=${appId.length} (${appId.slice(0, 4)}...)`);
console.log(`  secret length=${secret.length}`);

let failed = false;
try {
  const searchStatus = await check(
    'search/episodes',
    '/api/v2/search/episodes',
    '?anime=%E5%AD%A4%E7%8B%AC%E6%91%87%E6%BB%9A&v2=true',
  );
  if (searchStatus !== 200) failed = true;

  // The endpoint that actually feeds danmaku. An authenticated call answers 302
  // to a pre-signed CDN URL, so any 2xx/3xx means the signature was accepted.
  const commentStatus = await check(
    'comment',
    '/api/v2/comment/154490001',
    '?withRelated=true&chConvert=0',
  );
  if (commentStatus >= 400) failed = true;
} catch (e) {
  console.error(`::error::credential check failed to reach the API: ${e.message}`);
  process.exit(1);
}

if (failed) {
  console.error('::error::DanDanPlay rejected these credentials.');
  console.error('::error::Check the DANDANAPI_APPID / DANDANAPI_KEY repository secrets.');
  process.exit(1);
}

console.log('Credentials accepted. Danmaku will work in the built APK.');
