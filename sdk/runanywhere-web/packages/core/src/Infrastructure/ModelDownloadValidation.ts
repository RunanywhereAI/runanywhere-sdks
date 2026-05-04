/**
 * Validate that a URL is safe to fetch from.
 *
 * Security: Prevents SSRF-like attacks where user-controlled model URLs
 * could be pointed at internal/private network addresses. Only HTTPS is
 * allowed in production. HTTP is permitted for localhost during development.
 */
export function validateModelUrl(url: string): void {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new Error(`Invalid model URL: ${url}`);
  }

  const isLocalhost =
    parsed.hostname === 'localhost' ||
    parsed.hostname === '127.0.0.1' ||
    parsed.hostname === '[::1]';

  if (parsed.protocol === 'http:' && !isLocalhost) {
    throw new Error(
      `Model URL must use HTTPS (got HTTP for ${parsed.hostname}). ` +
      'HTTP is only allowed for localhost during development.',
    );
  }

  if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
    throw new Error(`Model URL has unsupported protocol: ${parsed.protocol}`);
  }

  const blockedPatterns = [
    /^10\./,
    /^172\.(1[6-9]|2\d|3[0-1])\./,
    /^192\.168\./,
    /^169\.254\./,
    /^0\./,
  ];

  if (!isLocalhost) {
    for (const pattern of blockedPatterns) {
      if (pattern.test(parsed.hostname)) {
        throw new Error(`Model URL points to private network address: ${parsed.hostname}`);
      }
    }
  }
}
