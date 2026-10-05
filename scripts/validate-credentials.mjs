#!/usr/bin/env node
// Validate the DanDanPlay credentials before spending ~15 minutes on an APK
// build, and prove the exact signature algorithm the app uses is accepted.
//
// This is the authoritative check that danmaku will work: the open API rejects
// unauthenticated requests on every endpoint with HTTP 403, so a build with
// wrong or missing credentials produces an app whose danmaku silently fails.
//
// Exit codes:
//   0  credentials work (or were intentionally skipped)
//   1  credentials are present but rejected
import { createHash } from 'node:crypto';

const APPID = (process.env.DANDANAPI_APPID ?? '').trim();
const SECRET = (process.env.DANDANAPI_KEY ?? '').trim();
const BASE = 'https://api.dandanplay.net';

if (!APPID || !SECRET) {
  console.log('::warning::DANDANAPI_APPID / DANDANAPI_KEY are empty.');
  console.log('::warning::Skipping the live credential check; the resulting APK');
  console.log('::warning::will have no danmaku source.');
  process.exit(0);
}

// Identical to DandanCredentials.generateSignature in the app.
const sign = (path, timestamp) =>
  createHash('sha256').update(`${APPID}${timestamp}${path}${SECRET}`).digest('base64');

async function check(label, path, query = '') {
  const timestamp = Math.floor(Date.now() / 1000);
  const url = `${BASE}${path}${query}`;
  const res = await fetch(url, {
    headers: {
      'X-AppId': APPID,
      'X-Timestamp': String(timestamp),
      'X-Signature': sign(path, timestamp),
      'user-agent': 'Kazumi-build-check',
    },
  });
  const body = await res.text();
  const apiError = res.headers.get('x-error-message') ?? '';
  console.log(
    `  ${label}: HTTP ${res.status}${apiError ? ` (${apiError})` : ''} ${body.slice(0, 120)}`,
  );
  return res.status;
}

console.log(`Validating DanDanPlay credentials for AppId ${APPID}`);

let failed = false;
try {
  const searchStatus = await check(
    'search/episodes',
    '/api/v2/search/episodes',
    '?anime=%E5%AD%A4%E7%8B%AC%E6%91%87%E6%BB%9A&v2=true',
  );
  if (searchStatus !== 200) failed = true;

  // The endpoint that actually feeds danmaku. Answers 302 to a pre-signed CDN
  // URL, so any 2xx/3xx means the signature was accepted.
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
