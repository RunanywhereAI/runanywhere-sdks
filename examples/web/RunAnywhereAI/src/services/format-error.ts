/**
 * Error Formatting Helper
 *
 * Converts an unknown thrown value into a human-readable string. Hand-rolled
 * because the WASM / proto-byte adapters frequently throw plain objects (e.g.
 * `{ message: '...', code: 12 }`) that fall through `instanceof Error` and
 * stringify to `[object Object]` via `String(err)`.
 *
 * Order of precedence:
 *   1. `Error` instances — use `.message`, and when present append
 *      `SDKException.proto.nestedMessage` (the actionable detail often lives
 *      there while `.message` is a generic "Backend not available for: …").
 *   2. Objects with a `message` property — coerce that to string; append
 *      `nestedMessage` the same way when present.
 *   3. Strings — return as-is.
 *   4. Anything else — fall back to `String(err)`.
 */

import { sanitizeDiagnosticText } from './app-logger';

function nestedDetail(err: object): string | undefined {
  const proto = (err as { proto?: { nestedMessage?: unknown } }).proto;
  const fromProto = proto?.nestedMessage;
  if (typeof fromProto === 'string' && fromProto.trim().length > 0) {
    return fromProto.trim();
  }
  const nested = (err as { nestedMessage?: unknown }).nestedMessage;
  if (typeof nested === 'string' && nested.trim().length > 0) {
    return nested.trim();
  }
  return undefined;
}

function withNestedDetail(message: string, err: object): string {
  const nested = nestedDetail(err);
  if (!nested) return message;
  if (message.includes(nested)) return message;
  // Prefer the nested detail when the outer message is a generic backend
  // wrapper — users need the storage/auth reason, not the feature name.
  if (/^Backend not available for:/i.test(message)) {
    return nested;
  }
  return `${message}: ${nested}`;
}

export function formatError(err: unknown): string {
  let message: string;
  if (err instanceof Error) {
    message = withNestedDetail(err.message, err);
  } else if (typeof err === 'string') {
    message = err;
  } else if (typeof err === 'object' && err !== null && 'message' in err) {
    message = withNestedDetail(String((err as { message: unknown }).message), err);
  } else {
    message = String(err);
  }
  return sanitizeDiagnosticText(message);
}
