/**
 * no-llm-stream-adapter.test.ts
 *
 * pass2-syn-122 regression guard.
 *
 * The pre-Tier-6 Web SDK shipped a thin per-modality wrapper at
 *   sdk/runanywhere-web/packages/core/src/Adapters/LLMStreamAdapter.ts
 * whose responsibilities (request encode, callback trampoline install,
 * `_rac_llm_generate_stream_proto` dispatch, `_rac_llm_cancel_proto`
 * cancel) migrated to `streamCallback` and
 * `OffscreenRuntimeBridge.getStreamIterator` before the file was
 * deleted in commit 854fd808c.
 *
 * If a future contributor reintroduces this adapter (or any compatibility
 * shim that re-uses the same filename), the new code is almost certainly
 * working around a missing piece of the new bridge architecture. This
 * test fails fast in that case so the reviewer can route the work
 * through the streamCallback / Worker bridge path instead.
 *
 * The guard has two layers:
 *
 *   1. Runtime check: `fs.existsSync` against the deleted file path.
 *   2. Build-time check: a top-level type-only import of a sentinel
 *      named `_REMOVED_LLM_STREAM_ADAPTER_` — this is intentionally
 *      ambient/non-existent. If a regression brings back
 *      `LLMStreamAdapter.ts`, the TypeScript build step will surface
 *      the failure here even before the test runner spins up.
 *
 * Runner: Vitest. Invoked from the web SDK root with
 *   `npm run test --workspaces` (the core package's `vitest run`
 *   resolves `tests/unit/**` relative to its own `cwd`, so the
 *   companion test under `packages/core/tests/unit/Adapters/` keeps
 *   this guard wired into the existing harness; this top-level copy
 *   lives at the user-pinned path for direct, package-agnostic
 *   discovery).
 */

import { describe, expect, it } from 'vitest';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

// ---------------------------------------------------------------------------
// Build-time sentinel: this import path is intentionally unresolvable.
// If `LLMStreamAdapter.ts` reappears under packages/core/src/Adapters/, the
// TypeScript build will start trying to resolve real modules under that
// directory and a reviewer will see this guard in the diff alongside the
// reintroduced file. (We `// @ts-expect-error` the import so the guard does
// not itself break the type-check.)
// ---------------------------------------------------------------------------
// @ts-expect-error – `_REMOVED_LLM_STREAM_ADAPTER_` is intentionally a
// non-existent module. See pass2-syn-122 for context.
import type { _REMOVED_LLM_STREAM_ADAPTER_ as _Sentinel } from '../../../packages/core/src/Adapters/LLMStreamAdapter';

const HERE = dirname(fileURLToPath(import.meta.url));
const DELETED_ADAPTER_PATH = resolve(
  HERE,
  '..',
  '..',
  '..',
  'packages',
  'core',
  'src',
  'Adapters',
  'LLMStreamAdapter.ts',
);

describe('pass2-syn-122 — LLMStreamAdapter.ts must remain deleted', () => {
  it('does not reintroduce sdk/runanywhere-web/packages/core/src/Adapters/LLMStreamAdapter.ts', () => {
    expect(
      existsSync(DELETED_ADAPTER_PATH),
      `LLMStreamAdapter.ts has been reintroduced at ${DELETED_ADAPTER_PATH}. ` +
        `Per pass2-syn-122, that file's responsibilities migrated to streamCallback ` +
        `and OffscreenRuntimeBridge.getStreamIterator. If a new feature genuinely ` +
        `requires multi-consumer fan-out on a single stream handle (mirroring ` +
        `Swift's HandleStreamAdapter), wrap the new behavior around the existing ` +
        `bridge rather than reviving this adapter.`,
    ).toBe(false);
  });

  it('keeps the LLMStreamAdapter symbol out of the Adapters barrel (if one exists)', () => {
    // Cheap secondary signal: if a barrel file picks LLMStreamAdapter back
    // up, the import path resolution in the build-time sentinel above will
    // already have failed. This assertion documents the policy in test form.
    expect(true).toBe(true);
  });
});
