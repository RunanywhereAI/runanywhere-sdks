/**
 * NetworkConfiguration.ts
 *
 * Tiny set of call-site validators used when building the Phase 1 init
 * payload. The HTTP transport, retry logic, telemetry, auth, and device
 * registration all live in native commons (`rac_http_*`); JavaScript only
 * needs to refuse obviously-broken inputs before crossing the bridge.
 */

const SCAFFOLD_VALUE_PATTERN = /^(?:<your[^>]*>|your(?:[-_ ][a-z0-9]+)+|replace[-_ ]?me|placeholder(?:[-_ ][a-z0-9]+)*)$/i;

/** Default base URL when the app does not override it. */
export const DEFAULT_BASE_URL = 'https://api.runanywhere.ai';

function looksLikePlaceholder(value?: string | null): boolean {
  const trimmed = value?.trim();
  return !trimmed || SCAFFOLD_VALUE_PATTERN.test(trimmed);
}

/** Reject empty values and template strings such as `YOUR_API_KEY`. */
export function isUsableCredential(value?: string | null): boolean {
  return !looksLikePlaceholder(value);
}

export interface HTTPURLValidationOptions {
  /** Production transport must never permit clear-text credentials. */
  requireHTTPS?: boolean;
}

/**
 * Reject placeholders and credential-bearing URL components, and require an
 * absolute HTTP(S) origin. Query strings/fragments do not belong in a base
 * URL and could otherwise be copied into native logs or request URLs.
 */
export function isUsableHTTPURL(
  value?: string | null,
  options: HTTPURLValidationOptions = {}
): boolean {
  const trimmed = value?.trim();
  if (!trimmed || looksLikePlaceholder(trimmed)) return false;
  try {
    const parsed = new URL(trimmed);
    const protocolAllowed = options.requireHTTPS
      ? parsed.protocol === 'https:'
      : parsed.protocol === 'http:' || parsed.protocol === 'https:';
    return (
      protocolAllowed &&
      parsed.hostname.length > 0 &&
      !/[\s<>]/.test(parsed.hostname) &&
      parsed.username.length === 0 &&
      parsed.password.length === 0 &&
      parsed.search.length === 0 &&
      parsed.hash.length === 0
    );
  } catch {
    return false;
  }
}
