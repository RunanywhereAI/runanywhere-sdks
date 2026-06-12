/**
 * no-llm-stream-adapter.test.ts (vitest-discoverable companion)
 *
 * pass2-syn-122 regression guard, in the package-local test root so the
 * core package's `vitest run` picks it up via the existing
 * `tests/unit/**\/*.test.ts` include glob (see
 * `sdk/runanywhere-web/packages/core/vitest.config.ts`). The
 * organization-mandated copy lives at
 * `sdk/runanywhere-web/tests/unit/Adapters/no-llm-stream-adapter.test.ts`
 * and shares the same assertion contract.
 *
 * Fails if a future commit reintroduces
 * `packages/core/src/Adapters/LLMStreamAdapter.ts` (the pre-Tier-6
 * per-modality streaming wrapper whose responsibilities migrated to
 * `streamCallback` and `OffscreenRuntimeBridge.getStreamIterator`).
 */

import { describe, expect, it } from 'vitest';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const DELETED_ADAPTER_PATH = resolve(
  HERE,
  '..',
  '..',
  '..',
  'src',
  'Adapters',
  'LLMStreamAdapter.ts',
);

describe('pass2-syn-122 — LLMStreamAdapter.ts must remain deleted', () => {
  it('does not reintroduce packages/core/src/Adapters/LLMStreamAdapter.ts', () => {
    expect(
      existsSync(DELETED_ADAPTER_PATH),
      `LLMStreamAdapter.ts has been reintroduced at ${DELETED_ADAPTER_PATH}. ` +
        `Per pass2-syn-122, that file's responsibilities migrated to ` +
        `streamCallback + OffscreenRuntimeBridge.getStreamIterator. If a new ` +
        `feature needs multi-consumer fan-out on a single stream handle ` +
        `(mirroring Swift's HandleStreamAdapter), wrap the new behavior around ` +
        `the existing bridge rather than reviving this adapter.`,
    ).toBe(false);
  });
});
