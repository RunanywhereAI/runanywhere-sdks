// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// React Native entry point for @runanywhere/core. Re-exports the shared
// TS adapter from ../../sdk/ts/ and wraps it in a Nitro TurboModule so
// all public APIs land on the RN bridge.

export * from '../../../../ts/src/adapter/PublicAPI';
export * from '../../../../ts/src/adapter/PublicCatalog';

import { NitroModules } from 'react-native-nitro-modules';
import type { RunAnywhereNative } from './RunAnywhereNative';

/**
 * Native bridge handle. Lazy-resolved so importing the package on a
 * non-RN runtime (e.g. Node.js test harness) doesn't crash.
 */
let _native: RunAnywhereNative | undefined;
export function getNativeBridge(): RunAnywhereNative {
  if (_native) return _native;
  _native = NitroModules.createHybridObject<RunAnywhereNative>('RunAnywhere');
  return _native;
}
