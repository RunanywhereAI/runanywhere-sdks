/**
 * Error Formatting Helper
 *
 * Converts an unknown thrown value into a human-readable string. Hand-rolled
 * because the WASM / proto-byte adapters frequently throw plain objects (e.g.
 * `{ message: '...', code: 12 }`) that fall through `instanceof Error` and
 * stringify to `[object Object]` via `String(err)`.
 *
 * Order of precedence:
 *   1. `Error` instances — use `.message`.
 *   2. Objects with a `message` property — coerce that to string.
 *   3. Strings — return as-is.
 *   4. Anything else — fall back to `String(err)`.
 */

export function formatError(err: unknown): string {
  if (err instanceof Error) return err.message;
  if (typeof err === 'string') return err;
  if (typeof err === 'object' && err !== null && 'message' in err) {
    return String((err as { message: unknown }).message);
  }
  return String(err);
}
