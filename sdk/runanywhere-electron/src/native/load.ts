// Resolves and loads runanywhere_native.node, then wraps every binding so a
// thrown or rejected native value becomes an SDKException with its rac code and
// category recovered. Kept apart from NativeBackend so the resolution logic is
// testable and the backend stays pure.

import * as fs from 'node:fs';
import * as path from 'node:path';

import { asSDKException } from '../errors.js';
import type { NativeAddon } from './addon-api.js';

/** Candidate paths for the compiled addon, in priority order. */
export function addonCandidates(dir: string, env = process.env): string[] {
  const platarch = `${process.platform}-${process.arch}`;
  return [
    env.RUNANYWHERE_NATIVE_PATH,
    // Packaged prebuild bundled by scripts/bundle-native.js (dist -> pkg root).
    path.resolve(dir, '..', '..', 'prebuilds', platarch, 'runanywhere_native.node'),
    // cmake-js default output next to the native package.
    path.resolve(dir, '..', '..', 'native', 'build', 'Release', 'runanywhere_native.node'),
  ].filter((p): p is string => Boolean(p));
}

function resolveAddon(): NativeAddon {
  const candidates = addonCandidates(__dirname);
  for (const p of candidates) {
    if (fs.existsSync(p)) {
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      return require(p) as NativeAddon;
    }
  }
  throw new Error(
    'runanywhere_native.node not found. Set RUNANYWHERE_NATIVE_PATH to the built addon.\nTried:\n  ' +
      candidates.join('\n  ')
  );
}

/**
 * Wrap every native binding so a thrown or rejected value surfaces as an
 * SDKException. The native layer tags errors with `code` / `cAbiCode`; when it
 * only has a message, asSDKException recovers the rac code from a trailing
 * "… failed: -<n>".
 */
export function wrapNative(raw: NativeAddon): NativeAddon {
  return new Proxy(raw, {
    get(target, prop, receiver) {
      const value = Reflect.get(target, prop, receiver);
      if (typeof value !== 'function') return value;
      return (...args: unknown[]) => {
        try {
          const result = (value as (...a: unknown[]) => unknown).apply(target, args);
          if (result != null && typeof (result as { then?: unknown }).then === 'function') {
            return (result as Promise<unknown>).catch((e) => {
              throw asSDKException(e);
            });
          }
          return result;
        } catch (e) {
          throw asSDKException(e);
        }
      };
    },
  }) as NativeAddon;
}

let cached: NativeAddon | null = null;

/** The wrapped addon, loaded once per process. */
export function loadAddon(): NativeAddon {
  if (!cached) cached = wrapNative(resolveAddon());
  return cached;
}
