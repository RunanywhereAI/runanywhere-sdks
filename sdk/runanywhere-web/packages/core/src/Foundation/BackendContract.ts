/** Lifecycle states shared by independently packaged Web inference backends. */
export type BackendRegistrationState =
  | 'unregistered'
  | 'registering'
  | 'registered'
  | 'failed';

/**
 * Return a resource URL that is safe to include in diagnostics.
 *
 * Backend WASM and model URLs may be signed or contain basic-auth credentials.
 * Keep the useful origin/path while dropping credentials, query parameters,
 * and fragments so logging cannot disclose those values.
 */
export function redactResourceURL(value: string): string {
  if (/^data:/i.test(value)) return 'data:[redacted]';

  try {
    const protocolRelative = value.startsWith('//');
    const parsed = new URL(protocolRelative ? `https:${value}` : value);
    parsed.username = '';
    parsed.password = '';
    parsed.search = '';
    parsed.hash = '';
    return protocolRelative ? parsed.href.replace(/^https:/, '') : parsed.href;
  } catch {
    // Ordinary relative paths are not accepted by URL without a base, but may
    // still carry signed query parameters.
    return value.replace(/[?#].*$/, '');
  }
}
