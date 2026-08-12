// SPDX-License-Identifier: Apache-2.0
//
// Characterizes the split-header auth contract for `HTTPClientAdapter`
// (PR #605 review issue #5): `apikey` always travels independently of
// `Authorization`, and `Authorization: Bearer` carries only a JWT access
// token — never a fallback to the API key. Mirrors Kotlin's
// `HTTPClientAdapter.buildHeaders` / `resolveToken`.
//
// `buildAuthHeaders` / `resolveAccessToken` are pure (aside from the
// injected token-resolver callback), so this exercises the real contract
// without a native library.

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/adapters/http_client_adapter.dart';

void main() {
  group('buildAuthHeaders', () {
    test('API-key-only: apikey header set, no Authorization', () {
      final headers = buildAuthHeaders(apiKey: 'sk-test-key');

      expect(headers['apikey'], 'sk-test-key');
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('JWT-only: Authorization set, no apikey header', () {
      final headers = buildAuthHeaders(apiKey: '', accessToken: 'jwt-token');

      expect(headers.containsKey('apikey'), isFalse);
      expect(headers['Authorization'], 'Bearer jwt-token');
    });

    test('API key and JWT together: both headers set independently', () {
      final headers = buildAuthHeaders(
        apiKey: 'sk-test-key',
        accessToken: 'jwt-token',
      );

      expect(headers['apikey'], 'sk-test-key');
      expect(headers['Authorization'], 'Bearer jwt-token');
    });

    test('keyless: neither header set', () {
      final headers = buildAuthHeaders(apiKey: '');

      expect(headers, isEmpty);
    });

    test('never falls back to the API key as a bearer token', () {
      // A caller accidentally passing the API key as the access token is
      // exactly the collapsed-header regression this contract forbids —
      // this test only pins that `buildAuthHeaders` itself never conflates
      // the two inputs it is given.
      final headers = buildAuthHeaders(apiKey: 'sk-test-key');

      expect(headers['Authorization'], isNot(contains('sk-test-key')));
    });
  });

  group('resolveAccessToken', () {
    test('requiresAuth=false never attempts resolution and returns null', () async {
      var resolverCalled = false;
      final token = await resolveAccessToken(
        requiresAuth: false,
        cachedAccessToken: 'cached-jwt',
        tokenResolver: ({required requiresAuth}) async {
          resolverCalled = true;
          return 'resolved-jwt';
        },
      );

      expect(token, isNull);
      expect(resolverCalled, isFalse);
    });

    test('requiresAuth=true with no resolver falls back to the cached token', () async {
      final token = await resolveAccessToken(
        requiresAuth: true,
        cachedAccessToken: 'cached-jwt',
      );

      expect(token, 'cached-jwt');
    });

    test('requiresAuth=true resolves through the token resolver', () async {
      final token = await resolveAccessToken(
        requiresAuth: true,
        tokenResolver: ({required requiresAuth}) async {
          expect(requiresAuth, isTrue);
          return 'resolved-jwt';
        },
      );

      expect(token, 'resolved-jwt');
    });

    test('expired token: resolver returns null, no cached fallback leaks through', () async {
      final token = await resolveAccessToken(
        requiresAuth: true,
        cachedAccessToken: 'stale-jwt',
        tokenResolver: ({required requiresAuth}) async => null,
      );

      expect(token, isNull);
    });

    test('token-resolver failure reports the error and returns null instead of throwing', () async {
      Object? reportedError;
      final token = await resolveAccessToken(
        requiresAuth: true,
        cachedAccessToken: 'stale-jwt',
        tokenResolver: ({required requiresAuth}) async {
          throw StateError('resolver blew up');
        },
        onResolverError: (error) => reportedError = error,
      );

      expect(token, isNull);
      expect(reportedError, isA<StateError>());
    });
  });

  group('buildAuthHeaders + resolveAccessToken end-to-end matrix', () {
    Future<Map<String, String>> headersFor({
      required bool requiresAuth,
      required String apiKey,
      String? cachedAccessToken,
      Future<String?> Function({required bool requiresAuth})? tokenResolver,
    }) async {
      final token = await resolveAccessToken(
        requiresAuth: requiresAuth,
        cachedAccessToken: cachedAccessToken,
        tokenResolver: tokenResolver,
      );
      return buildAuthHeaders(apiKey: apiKey, accessToken: token);
    }

    test('API-key-only request (requiresAuth=false)', () async {
      final headers = await headersFor(requiresAuth: false, apiKey: 'sk-key');

      expect(headers, {'apikey': 'sk-key'});
    });

    test('JWT-only request (requiresAuth=true, no apiKey)', () async {
      final headers = await headersFor(
        requiresAuth: true,
        apiKey: '',
        tokenResolver: ({required requiresAuth}) async => 'jwt-token',
      );

      expect(headers, {'Authorization': 'Bearer jwt-token'});
    });

    test('keyless unauthenticated request', () async {
      final headers = await headersFor(requiresAuth: false, apiKey: '');

      expect(headers, isEmpty);
    });

    test('expired token on an authenticated request omits Authorization but keeps apikey', () async {
      final headers = await headersFor(
        requiresAuth: true,
        apiKey: 'sk-key',
        tokenResolver: ({required requiresAuth}) async => null,
      );

      expect(headers, {'apikey': 'sk-key'});
    });

    test('token-resolver failure omits Authorization but keeps apikey', () async {
      final headers = await headersFor(
        requiresAuth: true,
        apiKey: 'sk-key',
        tokenResolver: ({required requiresAuth}) async =>
            throw Exception('network down'),
      );

      expect(headers, {'apikey': 'sk-key'});
    });
  });
}
