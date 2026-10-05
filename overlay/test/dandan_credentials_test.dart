import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/utils/dandan_credentials.dart';

void main() {
  // DandanCredentials keeps process-wide state, so always start clean.
  setUp(DandanCredentials.clearOverride);
  tearDown(DandanCredentials.clearOverride);

  // These tests run both on a developer checkout (template not injected) and on
  // a release build (credentials injected from CI secrets), so every assertion
  // about the *build-time* state has to branch on [isInjected]. Assertions that
  // only touch the runtime override are unconditional.
  final injected = DandanCredentials.isInjected;

  group('build-time credentials', () {
    test('are reported consistently with the injected flag', () {
      expect(DandanCredentials.hasBuildTimeCredentials, injected);
      expect(DandanCredentials.isInjected, injected);
      if (injected) {
        expect(DandanCredentials.appId, isNotEmpty);
        expect(DandanCredentials.appSecret, isNotEmpty);
      }
    });

    test('never surface un-replaced placeholder text', () {
      // This is the failure mode that produced HTTP 403 for every danmaku
      // request before the credentials were injected properly.
      expect(DandanCredentials.appId, isNot(contains('__DANDANAPI_')));
      expect(DandanCredentials.appSecret, isNot(contains('__DANDANAPI_')));
    });

    test('decide whether requests can be signed at all', () {
      expect(DandanCredentials.isConfigured, injected);
    });
  });

  group('user override', () {
    test('makes requests signable', () {
      DandanCredentials.setOverride(appId: 'appid', secret: 'secret');
      expect(DandanCredentials.isConfigured, isTrue);
      expect(DandanCredentials.hasUserCredentials, isTrue);
      expect(DandanCredentials.appId, 'appid');
      expect(DandanCredentials.appSecret, 'secret');
    });

    test('falls back to the build-time state when cleared', () {
      DandanCredentials.setOverride(appId: 'appid', secret: 'secret');
      DandanCredentials.clearOverride();
      expect(DandanCredentials.hasUserCredentials, isFalse);
      // An injected build is configured again through its own credentials.
      expect(DandanCredentials.isConfigured, injected);
    });

    test('a blank override does not count as user credentials', () {
      DandanCredentials.setOverride(appId: '   ', secret: '');
      expect(DandanCredentials.hasUserCredentials, isFalse);
    });

    test('partial credentials are not enough to sign', () {
      DandanCredentials.setOverride(appId: 'appid', secret: '');
      expect(DandanCredentials.isConfigured, injected);
      DandanCredentials.setOverride(appId: '', secret: 'secret');
      expect(DandanCredentials.isConfigured, injected);
    });

    test('user credentials win over the build-time ones', () {
      DandanCredentials.setOverride(appId: 'mine', secret: 'mine-secret');
      expect(DandanCredentials.appId, 'mine');
      expect(DandanCredentials.appSecret, 'mine-secret');
    });
  });

  group('DevCenter "appId;appSecret" paste', () {
    // Deliberately synthetic values: this repository is public, so real
    // credentials must never appear in it, not even in a test fixture.
    const appId = 'exampleappid';
    const secret = 'examplesecretvalue';

    test('splits a combined value passed as appId', () {
      DandanCredentials.setOverride(appId: '$appId;$secret');
      expect(DandanCredentials.appId, appId);
      expect(DandanCredentials.appSecret, secret);
      expect(DandanCredentials.isConfigured, isTrue);
    });

    test('splits a combined value passed as secret', () {
      DandanCredentials.setOverride(appId: '', secret: '$appId;$secret');
      expect(DandanCredentials.appId, appId);
      expect(DandanCredentials.appSecret, secret);
    });

    test('tolerates surrounding whitespace', () {
      DandanCredentials.setOverride(appId: '  $appId ; $secret ');
      expect(DandanCredentials.appId, appId);
      expect(DandanCredentials.appSecret, secret);
    });
  });

  group('generateSignature', () {
    test('matches the open API spec algorithm', () {
      // Reference implementation straight from the documentation:
      // base64(sha256(appId + timestamp + path + appSecret)).
      DandanCredentials.setOverride(
        appId: 'your_app_id',
        secret: 'your_app_secret',
      );
      const payload = 'your_app_id'
          '1735660800'
          '/api/v2/comment/123450001'
          'your_app_secret';
      final expected =
          base64Encode(sha256.convert(utf8.encode(payload)).bytes);
      expect(
        DandanCredentials.generateSignature(
          '/api/v2/comment/123450001',
          1735660800,
        ),
        expected,
      );
    });

    test('excludes the query string from the signed path', () {
      DandanCredentials.setOverride(appId: 'id', secret: 'value');
      const timestamp = 1700000000;
      final fromLiteral =
          DandanCredentials.generateSignature('/api/v2/comment/1', timestamp);
      final fromUri = DandanCredentials.generateSignature(
        Uri.parse('https://api.dandanplay.net/api/v2/comment/1?withRelated=true')
            .path,
        timestamp,
      );
      expect(fromLiteral, fromUri);
    });

    test('changing the secret changes the signature', () {
      const path = '/api/v2/comment/1';
      const timestamp = 1700000000;
      DandanCredentials.setOverride(appId: 'id', secret: 'one');
      final first = DandanCredentials.generateSignature(path, timestamp);
      DandanCredentials.setOverride(appId: 'id', secret: 'two');
      final second = DandanCredentials.generateSignature(path, timestamp);
      expect(first, isNot(second));
    });

    test('is base64 of a 32-byte sha256 digest', () {
      DandanCredentials.setOverride(appId: 'id', secret: 'value');
      final signature =
          DandanCredentials.generateSignature('/api/v2/search/episodes', 1);
      final decoded = base64Decode(signature);
      expect(decoded.length, 32);
      // A raw secret would leak in the clear; a digest never contains it.
      expect(
        utf8.decode(decoded, allowMalformed: true).contains('value'),
        isFalse,
      );
    });
  });

  group('appIdForDisplay', () {
    test('never leaks the full appId', () {
      DandanCredentials.setOverride(appId: 'abcdef123456', secret: 's');
      final display = DandanCredentials.appIdForDisplay;
      expect(display, isNot(contains('abcdef123456')));
      expect(display, contains('…'));
    });

    test('reports the unconfigured state explicitly', () {
      if (injected) {
        // A release build always has an AppId to redact.
        expect(DandanCredentials.appIdForDisplay, isNot(equals('(未配置)')));
      } else {
        expect(DandanCredentials.appIdForDisplay, '(未配置)');
      }
    });

    test('keeps short ids intact', () {
      DandanCredentials.setOverride(appId: 'abc', secret: 's');
      expect(DandanCredentials.appIdForDisplay, 'abc');
    });
  });

  group('placeholder hardening', () {
    test('an un-replaced placeholder is never treated as a credential', () {
      // Guards the scenario where the injected flag is stale but the template
      // was not rewritten: returning the literal would produce HTTP 403 again.
      expect(DandanCredentials.appSecret, isNot(startsWith('__DANDANAPI_')));
      if (!injected) {
        expect(DandanCredentials.appSecret, isEmpty);
        expect(DandanCredentials.appId, isEmpty);
      }
    });
  });
}
