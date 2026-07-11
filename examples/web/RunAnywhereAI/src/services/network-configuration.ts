const SCAFFOLD_VALUE_PATTERN = /^(?:<your[^>]*>|your(?:[-_ ][a-z0-9]+)+|replace[-_ ]?me|placeholder(?:[-_ ][a-z0-9]+)*)$/i;

/** Reject empty values and exact template scaffolding without inspecting opaque keys. */
export function isUsableCredential(value: string | null | undefined): boolean {
  const trimmed = value?.trim();
  return Boolean(trimmed) && !SCAFFOLD_VALUE_PATTERN.test(trimmed ?? '');
}

/**
 * Normalize a production API base URL and reject credential-bearing or
 * request-specific components. A missing scheme is treated as HTTPS for the
 * settings form, while an explicit non-HTTPS scheme is never rewritten.
 */
export function normalizeProductionBaseURL(
  value: string | null | undefined,
): string | null {
  const trimmed = value?.trim();
  if (!trimmed || SCAFFOLD_VALUE_PATTERN.test(trimmed)) return null;

  const hasExplicitScheme = /^[a-z][a-z0-9+.-]*:\/\//i.test(trimmed);
  const candidate = hasExplicitScheme ? trimmed : `https://${trimmed}`;
  try {
    const parsed = new URL(candidate);
    if (
      parsed.protocol !== 'https:'
      || parsed.hostname.length === 0
      || /[\s<>]/.test(parsed.hostname)
      || parsed.username.length > 0
      || parsed.password.length > 0
      || parsed.search.length > 0
      || parsed.hash.length > 0
    ) {
      return null;
    }
    return parsed.toString().replace(/\/$/, '');
  } catch {
    return null;
  }
}
