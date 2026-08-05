/**
 * `LoadOptions` fields `commons ModelLoadRequest` has no wire path for yet.
 *
 * Only `backendPreferences[0]` (equivalently the deprecated `framework`)
 * reaches commons at load time; `contextLength`, `threads`, a real
 * `accelerator` choice, and ordered fallback across multiple
 * `backendPreferences` are not yet carried by the native load ABI (tracked
 * as a follow-up — see PR #605 review follow-up issue 8). Per the v4 public
 * API spec, "every accepted field is implemented end to end or fails
 * preflight" — `models.load` throws when one of these is set rather than
 * silently dropping it.
 *
 * Kept in its own module (no native/Nitro imports) so it stays unit-testable
 * under the Node jest runner alongside the other pure-TS helpers.
 */

import type { LoadOptions } from './Types';

export function resolvedBackendPreferences(options?: LoadOptions) {
  if (options?.backendPreferences?.length) return options.backendPreferences;
  if (options?.framework !== undefined) {
    return [{ backend: options.framework }];
  }
  return [];
}

export function resolvedAccelerator(options?: LoadOptions) {
  if (options?.accelerator !== undefined) return options.accelerator;
  if (options?.useGpu !== undefined) return options.useGpu ? 'gpu' : 'cpu';
  return undefined;
}

export function unsupportedLoadOptionKeys(options?: LoadOptions): string[] {
  return [
    options?.contextLength !== undefined ? 'contextLength' : undefined,
    options?.threads !== undefined ? 'threads' : undefined,
    resolvedAccelerator(options) !== undefined ? 'accelerator' : undefined,
    resolvedBackendPreferences(options).length > 1
      ? 'backendPreferences (only the first preference reaches commons; ordered fallback is not carried)'
      : undefined,
  ].filter((key): key is string => key !== undefined);
}
