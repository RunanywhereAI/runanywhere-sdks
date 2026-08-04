/**
 * `LoadOptions` fields `commons ModelLoadRequest` has no wire path for yet.
 *
 * Only `framework` reaches commons at load time; `contextLength`, `threads`,
 * and `useGpu` are accepted on `LoadOptions` for cross-SDK API parity but are
 * dropped below `models.load()` until the native load ABI grows placement
 * fields (tracked as a follow-up — see PR #605 review follow-up issue 8).
 *
 * Kept in its own module (no native/Nitro imports) so it stays unit-testable
 * under the Node jest runner alongside the other pure-TS helpers.
 */

import type { LoadOptions } from './Types';

export function ignoredLoadOptionKeys(options?: LoadOptions): string[] {
  return [
    options?.contextLength !== undefined ? 'contextLength' : undefined,
    options?.threads !== undefined ? 'threads' : undefined,
    options?.useGpu !== undefined ? 'useGpu' : undefined,
  ].filter((key): key is string => key !== undefined);
}
