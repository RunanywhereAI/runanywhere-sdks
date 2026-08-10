/**
 * Engine-unavailable notice — the one way a surface says "my engine didn't load".
 *
 * WHY THIS EXISTS. Four surfaces (Transcribe, Read Aloud, Voice Activity and
 * Documents) gated their controls on `RunAnywhere.runtime.modalities.<id>.status`.
 * That property reports *where* a modality would execute — worker or main thread
 * — not *whether* an engine registered; with no engine at all it still answers
 * `'main'`. So all four rendered their complete working UI on a session where
 * nothing could possibly run: an enabled "Start recording", an enabled "Speak",
 * an enabled "Ask". The only thing on screen that contradicted them was a
 * floating badge in the corner printing WASM package names across the chat
 * composer's mic and send buttons.
 *
 * `services/engine-availability.ts` owns the truth — the per-package
 * registration outcome this app recorded itself around each `register()` call.
 * This component is the single way to render it, so a fifth surface cannot
 * invent a fifth vocabulary for the same state.
 */

import type { ModelCategory } from '@runanywhere/web';
import {
  canRetryEngines,
  failureDiagnostics,
  describeFailures,
  failuresForEntries,
  isRetryingForEntries,
  retryEngines,
  type EngineFailure,
} from '../services/engine-availability';
import { getCatalogForCategories } from '../services/model-catalog';
import { showToast } from './dialogs';
import { icon } from './icons';

export interface EngineNoticeOptions {
  /** The engine failures that block *this* surface, already scoped to it. */
  failures: readonly EngineFailure[];
  /** True while a retry is re-checking one of those engines. */
  rechecking: boolean;
}

/**
 * The notice state for a surface that deals in one or more model categories.
 *
 * Scoping through the same categories the surface passes to `openSheet` is what
 * keeps the notice honest in both directions: Read Aloud never reports a
 * llama.cpp failure, and Documents — whose embedding picker mixes llama.cpp and
 * ONNX entries — reports whichever engine its own models need.
 *
 * `rechecking` matters as much as `failures`. A retry resets every record to
 * `pending`, so a surface that only asked "any failures?" would drop its blocked
 * layout mid-retry and offer a control that cannot yet succeed.
 */
export function engineNoticeForCategories(
  categories: readonly ModelCategory[],
): EngineNoticeOptions {
  const entries = getCatalogForCategories(categories);
  return {
    failures: failuresForEntries(entries),
    rechecking: isRetryingForEntries(entries),
  };
}

/** Does an engine failure (or an in-flight retry) block this surface? */
export function isEngineBlocked(notice: EngineNoticeOptions): boolean {
  return notice.failures.length > 0 || notice.rechecking;
}

/**
 * The banner markup, or `''` when nothing blocks the surface.
 *
 * Returns a string rather than an element so a view that builds its body with
 * `innerHTML` can interpolate it in place, which is how all four callers render.
 * Pair every call with `wireEngineNotice` — the diagnostic text and the retry
 * handler are attached there, not here.
 */
export function renderEngineNotice(options: EngineNoticeOptions): string {
  const { failures, rechecking } = options;
  if (failures.length === 0 && !rechecking) return '';

  const retry = canRetryEngines()
    ? `<button type="button" class="btn btn-secondary btn-sm" data-engine-retry-action
         ${rechecking ? 'disabled' : ''}>${rechecking ? 'Re-checking&hellip;' : 'Retry setup'}</button>`
    : '';

  return `
    <div class="engine-banner" role="status">
      <div class="engine-banner__glyph">
        ${icon('warning', { size: 24 })}
      </div>
      <div class="engine-banner__text">
        <div class="engine-banner__title">${rechecking ? 'Re-checking the AI engine' : 'On-device AI engine unavailable'}</div>
        <div class="engine-banner__meta"></div>
        ${failures.length > 0
          ? `<details class="engine-banner__details">
               <summary>Technical details</summary>
               <pre class="engine-banner__diagnostic"></pre>
             </details>`
          : ''}
      </div>
      ${retry}
    </div>
  `;
}

/**
 * Fill in the notice's text and wire its retry button.
 *
 * The consumer sentence and the raw diagnostic both go in as `textContent`:
 * `describeFailures` is app-authored, but the diagnostic is upstream fetch/WASM
 * text that can carry a URL, and routing both through the same sink is what
 * keeps the safe path from depending on which string it happens to be.
 */
export function wireEngineNotice(root: ParentNode, options: EngineNoticeOptions): void {
  const banner = root.querySelector<HTMLElement>('.engine-banner');
  if (!banner) return;

  const meta = banner.querySelector<HTMLElement>('.engine-banner__meta');
  if (meta) {
    meta.textContent = options.rechecking
      ? 'Loading the on-device AI engine again…'
      : describeFailures(options.failures);
  }

  const diagnostic = banner.querySelector<HTMLPreElement>('.engine-banner__diagnostic');
  if (diagnostic) diagnostic.textContent = failureDiagnostics(options.failures);

  banner.querySelector('[data-engine-retry-action]')?.addEventListener('click', () => {
    void runEngineRetry();
  });
}

/**
 * Retry, then say what happened.
 *
 * "Nothing changed" is a real outcome and has to be reported: a retry that
 * silently re-renders the same banner is indistinguishable from a click that did
 * nothing at all, which is the failure mode this whole area exists to remove.
 */
export async function runEngineRetry(): Promise<void> {
  const outcome = await retryEngines();
  if (outcome === 'recovered') {
    showToast('On-device AI engine loaded.', 'success');
  } else if (outcome === 'still-unavailable') {
    showToast('The AI engine still could not load. See technical details.', 'warning');
  }
}
