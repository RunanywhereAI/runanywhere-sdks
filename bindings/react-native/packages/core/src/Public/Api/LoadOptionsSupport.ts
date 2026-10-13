/**
 * Load-option support and lossless protobuf validation for this binding.
 *
 * `contextLength` and the ordered `backendPreferences` list now ride
 * `ModelLoadRequest.context_length`/`.backend_preferences`, so only `threads`
 * (retired from the load ABI — reserved tag 7) and `accelerator` remain
 * unsupported by this React Native binding. Accelerator policy has a wire
 * field, but this binding does not forward it yet.
 *
 * Kept in its own module (no native/Nitro imports) so it stays unit-testable
 * under the Node jest runner alongside the other pure-TS helpers.
 */

import type { LoadOptions } from './Types';
import { SDKException } from '../../Foundation/Errors/SDKException';

/** Reject context values that would be changed by int32 protobuf encoding. */
export function requireValidContextLength(contextLength?: number): void {
  if (
    contextLength !== undefined &&
    (!Number.isInteger(contextLength) ||
      contextLength < 0 ||
      contextLength > 2_147_483_647)
  ) {
    throw SDKException.invalidInput(
      'LoadOptions.contextLength must be a non-negative integer that fits int32'
    );
  }
}

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
