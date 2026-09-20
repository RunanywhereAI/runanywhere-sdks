/**
 * `LoadOptions` fields `commons ModelLoadRequest` has no wire path for yet.
 *
 * `contextLength` and the ordered `backendPreferences` list now ride
 * `ModelLoadRequest.context_length`/`.backend_preferences`, so only `threads`
 * (retired from the load ABI — reserved tag 7) and a real `accelerator`
 * choice still lack a wire path. Per the v4 public API spec, "every accepted
 * field is implemented end to end or fails preflight" — `models.load` throws
 * when one of these is set rather than silently dropping it.
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
    options?.threads !== undefined ? 'threads' : undefined,
    resolvedAccelerator(options) !== undefined ? 'accelerator' : undefined,
  ].filter((key): key is string => key !== undefined);
}
