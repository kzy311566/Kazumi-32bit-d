#!/usr/bin/env node
// Injects build-time API credentials into the Dart sources.
//
// Why not --dart-define: it cannot express an empty value, so a build without
// the secrets would fail to compile. Writing the credentials into the source
// instead keeps the "no credentials" build valid and gives the client a
// single, testable entry point for both build-time and in-app credentials.
//
// Placeholders are replaced with plain string splitting (not a regex or shell
// substitution) because AppSecrets are base64 and may contain `/`, `&`, `$` and
// other characters that are special to those languages.
//
// Every file is rewritten independently and idempotently: a file that already
// carries injected values is left untouched (and reported), while a file still
// holding its template is filled in. That keeps the workflow safe to re-run
// without resetting the checkout.
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';

const dandanAppId = process.env.DANDANAPI_APPID ?? '';
const dandanKey = process.env.DANDANAPI_KEY ?? '';
const kazumiAppId = process.env.KAZUMI_APPID ?? '';
const kazumiKey = process.env.KAZUMI_KEY ?? '';

/**
 * @typedef {object} Target
 * @property {string} file            path relative to the repo root
 * @property {string} uninjectedFlag  the `= false;` declaration to swap
 * @property {boolean} injected       whether this run carries usable values
 * @property {Array<[string, string, string]>} values
 *   `[placeholder, value, label]` triples
 * @property {string} describe        one-line summary for the log
 */

/** @type {Target[]} */
const targets = [
  {
    file: 'lib/utils/dandan_credentials.dart',
    uninjectedFlag: 'const bool _buildTimeCredentialsInjected = false;',
    injected: dandanAppId.length > 0 && dandanKey.length > 0,
    values: [
      ['__DANDANAPI_APPID__', dandanAppId, 'DANDANAPI_APPID'],
      ['__DANDANAPI_KEY__', dandanKey, 'DANDANAPI_KEY'],
    ],
    describe: 'DanDanPlay danmaku credentials',
  },
  {
    file: 'lib/utils/bangumi_mirror_credentials.dart',
    uninjectedFlag: 'const bool _buildTimeMirrorCredentialsInjected = false;',
    injected: kazumiAppId.length > 0 && kazumiKey.length > 0,
    values: [
      ['__KAZUMI_APPID__', kazumiAppId, 'KAZUMI_APPID'],
      ['__KAZUMI_KEY__', kazumiKey, 'KAZUMI_KEY'],
    ],
    describe: 'Bangumi mirror credentials',
  },
];

// Matches the injected-flag declaration with either truth value so that the
// idempotency check never depends on which secrets a particular run carries.
const flagDeclaration = (name) =>
  new RegExp(`const bool ${name} = (?:true|false);`);

let failures = 0;

for (const target of targets) {
  const flagName = /const bool (\w+) = false;/.exec(target.uninjectedFlag)?.[1];
  const injectedFlag = target.uninjectedFlag.replace(
    / = false;/,
    ` = ${target.injected};`,
  );
  const hashOf = (value) =>
    createHash('sha256').update(value).digest('hex');

  console.log(`\n--- ${target.file} (${target.describe}) ---`);

  let source = readFileSync(target.file, 'utf8');
  const templateStillPresent = target.values.some(([placeholder]) =>
    source.includes(placeholder),
  );

  if (!templateStillPresent && flagDeclaration(flagName).test(source)) {
    console.log('  already injected; leaving the file untouched');
    for (const [, value, label] of target.values) {
      console.log(
        label.includes('KEY')
          ? `  ${label} sha256 = ${hashOf(value)}`
          : `  ${label} = ${value || '<empty>'}`,
      );
    }
    continue;
  }

  if (!source.includes(target.uninjectedFlag)) {
    console.error(
      `::error::could not find the expected declaration ${JSON.stringify(target.uninjectedFlag)} in ${target.file}`,
    );
    console.error(
      '::error::update scripts/inject-credentials.mjs to match the current template',
    );
    failures++;
    continue;
  }
  source = source.split(target.uninjectedFlag).join(injectedFlag);

  for (const [placeholder, value, label] of target.values) {
    const occurrences = source.split(placeholder).length - 1;
    if (occurrences !== 1) {
      console.error(
        `::error::expected exactly 1 occurrence of ${placeholder} in ${target.file}, found ${occurrences}`,
      );
      failures++;
      break;
    }
    source = source.split(placeholder).join(value);
    console.log(
      label.includes('KEY')
        ? `  ${label} sha256 = ${hashOf(value)}`
        : `  ${label} = ${value || '<empty>'}`,
    );
  }

  writeFileSync(target.file, source);
  console.log(`  credentials injected = ${target.injected}`);

  const leftover = target.values
    .map(([placeholder]) => placeholder)
    .filter((placeholder) => source.includes(placeholder));
  if (leftover.length > 0) {
    console.error(`::error::placeholders left unresolved: ${leftover.join(', ')}`);
    failures++;
  }
}

console.log('');
if (failures > 0) {
  console.error(`inject-credentials: ${failures} problem(s)`);
  process.exit(1);
}
console.log('inject-credentials: done');
