// Shared plumbing for the feature suite. Not a test file (the runner's glob is
// `*.test.js`), so nothing here executes on its own.
//
// The one load-bearing detail: `dist/bridge` resolves the native addon AT MODULE
// LOAD and throws when it cannot find one. A top-level `import { addon }` would
// therefore crash the whole file on a machine with no addon staged, instead of
// letting the per-test `{ skip }` do its job. Every feature test reaches the
// addon through `nativeAddon()` below, which defers that require until a test
// that already decided not to skip actually runs.
import * as fs from 'fs';

import type { NativeAddon } from '../../dist/bridge';

/** Exists on disk, tolerating an undefined path and an unreadable parent. */
export function exists(p: string | undefined): boolean {
  try {
    return Boolean(p) && fs.existsSync(p as string);
  } catch {
    return false;
  }
}

/** The built addon, resolved on first use. Throws when none is staged. */
export function nativeAddon(): NativeAddon {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const bridge = require('../../dist/bridge') as typeof import('../../dist/bridge');
  return bridge.addon;
}
