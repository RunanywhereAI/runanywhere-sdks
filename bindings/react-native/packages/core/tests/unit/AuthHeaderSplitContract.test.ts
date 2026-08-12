/**
 * PR #605 review issue #5 — cross-SDK auth header parity.
 *
 * `InitBridge.cpp` / `TelemetryBridge.cpp` build headers in C++ before
 * handing them to the native `rac_http_client_*` transport, so there is no
 * JS-side seam to unit test with a mock HTTP client. This pins the
 * split-header contract (mirrors Kotlin's `HTTPClientAdapter.buildHeaders` /
 * `resolveToken`, characterized in the Flutter `buildAuthHeaders` /
 * `resolveAccessToken` tests) at the source level, the same way
 * `NativeLifecycleSource.test.ts` already pins other C++ invariants in this
 * package:
 *   - `apikey` always travels independently of `Authorization`.
 *   - `Authorization: Bearer` carries only a JWT access token, gated on
 *     `requiresAuth`, and is never a fallback for the API key.
 *   - `requiresAuth` is honored, not discarded.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function readBridgeSource(file: string): string {
  return readFileSync(resolve(__dirname, '../../cpp/bridges', file), 'utf8');
}

function functionBody(
  source: string,
  signature: string,
  nextSignature: string
): string {
  const start = source.indexOf(signature);
  const end = source.indexOf(nextSignature, start + signature.length);
  expect(start).toBeGreaterThanOrEqual(0);
  expect(end).toBeGreaterThan(start);
  return source.slice(start, end);
}

describe('RN auth header split contract (apikey vs Authorization)', () => {
  test('postJsonViaRacHttpClient never derives Bearer from the API key', () => {
    const source = readBridgeSource('InitBridge.cpp');
    const fn = functionBody(
      source,
      'static std::tuple<bool, int, std::string, std::string> postJsonViaRacHttpClient(',
      '\nstd::string InitBridge::'
    );

    // apikey is unconditional on apiKey alone.
    expect(fn).toContain('headers.push_back({"apikey", apiKey.c_str()});');
    // Authorization is gated on requiresAuth AND a non-empty access token,
    // and is built from accessToken, never apiKey.
    expect(fn).toContain('if (requiresAuth && !accessToken.empty())');
    expect(fn).toContain('bearer = "Bearer " + accessToken;');
    expect(fn).not.toContain('bearer = "Bearer " + apiKey;');
    // Regression pin: the old collapsed form must not reappear.
    expect(fn).not.toMatch(/if \(!apiKey\.empty\(\)\)\s*\{\s*headers\.push_back\(\{"apikey", apiKey\.c_str\(\)\}\);\s*bearer/);
  });

  test('httpPostSync takes apiKey and accessToken as independent parameters', () => {
    const source = readBridgeSource('InitBridge.cpp');
    expect(source).toContain(
      'InitBridge::httpPostSync(\n' +
        '    const std::string& url,\n' +
        '    const std::string& jsonBody,\n' +
        '    const std::string& apiKey,\n' +
        '    const std::string& accessToken,\n' +
        '    bool requiresAuth\n' +
        ')'
    );
  });

  test('device httpPost callback honors requiresAuth instead of discarding it', () => {
    const source = readBridgeSource('InitBridge.cpp');
    const fn = functionBody(
      source,
      'callbacks.httpPost = [](',
      'DeviceBridge::shared().setPlatformCallbacks(callbacks);'
    );

    expect(fn).not.toContain('(void)requiresAuth;');
    // No more "token = accessToken.isUsable ? accessToken : apiKey" collapse.
    expect(fn).not.toMatch(/std::string token\s*=\s*config::isUsableSecret\(accessToken\)/);
    expect(fn).toContain(
      'InitBridge::shared().httpPostSync(fullURL, jsonBody, apiKey, accessToken, requiresAuth);'
    );
  });

  test('telemetry HTTP callback keeps apiKey and accessToken split and forwards requiresAuth', () => {
    const source = readBridgeSource('TelemetryBridge.cpp');
    const fn = functionBody(
      source,
      'static void telemetryHttpCallback(',
      '\n} // namespace bridges'
    );

    // The old collapse ("apiKey = accessToken; // Use JWT for Authorization
    // header") must not reappear -- apiKey and accessToken are resolved
    // independently.
    expect(fn).not.toContain('apiKey = accessToken; // Use JWT for Authorization header');
    expect(fn).toContain('const bool requiresAuthBool = requiresAuth == RAC_TRUE;');
    expect(fn).toContain(
      'InitBridge::shared().httpPostSync(fullURL, json, apiKey, accessToken,\n' +
        '                                        requiresAuthBool);'
    );
  });
});
