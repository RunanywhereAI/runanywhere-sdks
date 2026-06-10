/**
 * NetworkConfiguration.ts
 *
 * Tiny set of call-site validators used when building the Phase 1 init
 * payload. The HTTP transport, retry logic, telemetry, auth, and device
 * registration all live in native commons (`rac_http_*`); JavaScript only
 * needs to refuse obviously-broken inputs before crossing the bridge.
 */

const PLACEHOLDER_PATTERN = /YOUR_|<your|REPLACE_ME|PLACEHOLDER/i;

/** Default base URL when the app does not override it. */
export const DEFAULT_BASE_URL = 'https://api.runanywhere.ai';

function looksLikePlaceholder(value?: string | null): boolean {
  return !value || value.trim().length === 0 || PLACEHOLDER_PATTERN.test(value);
}

/** Reject empty values and template strings such as `YOUR_API_KEY`. */
export function isUsableCredential(value?: string | null): boolean {
  return !looksLikePlaceholder(value);
}
