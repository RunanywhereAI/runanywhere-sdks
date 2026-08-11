/**
 * Batch-query commons model-fit via the Web SDK bridge.
 *
 * Returns an empty map when the SDK is not ready, the WASM export is missing,
 * or a probe fails — callers must not invent a local substitute budget.
 */

import { RunAnywhere } from '@runanywhere/web';

/**
 * Probe `canRun` for each id through `RunAnywhere.models.checkCompatibility`.
 * Missing / failed probes are omitted (unknown), never replaced with a
 * local size heuristic.
 */
export async function canRunByModelID(
  modelIDs: readonly string[],
): Promise<Record<string, boolean>> {
  if (!RunAnywhere.isReady) return {};
  const result: Record<string, boolean> = {};
  for (const id of new Set(modelIDs)) {
    if (!id) continue;
    try {
      const verdict = await RunAnywhere.models.checkCompatibility(id);
      result[id] = verdict.canRun;
    } catch {
      // Leave absent — unknown, not a fabricated fit.
    }
  }
  return result;
}
