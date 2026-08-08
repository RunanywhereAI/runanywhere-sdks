/**
 * Engine availability — which inference engine package actually registered at
 * boot, and what to tell the user when one didn't.
 *
 * WHY THIS EXISTS. `main.ts` already catches both backend registration
 * failures and builds a precise diagnostic naming the missing artifact. Until
 * this module existed, that diagnostic went only into
 * `window.__RUNANYWHERE_AI_READY__` and a `data-` attribute — nothing rendered
 * it. The consequence was the exact failure this app's rules forbid: with both
 * WASM engines missing, the picker still opened with 25 rows, a "Recommended
 * for your device" banner, and an orange Download button for models that
 * could not possibly load. A click produced a raw fetch error and no state
 * change.
 *
 * This is presentation state, not SDK logic: `main.ts` reports each
 * registration outcome here, and the picker/overlay read it to render a typed
 * unavailable state. Nothing in this file decides *whether* an engine works —
 * only how to say that it didn't.
 */

import { InferenceFramework } from '@runanywhere/proto-ts/model_types';
import {
  WebModelCompatibilityCode,
  type CatalogEntry,
  type WebModelCompatibility,
} from './model-catalog';
import { appLogger } from './app-logger';

/**
 * The two engine packages this example registers. These are packages, not
 * modalities: one `.wasm` artifact per id, so one failure takes out every
 * modality that artifact serves (see the WASM table in AGENTS.md).
 */
export type EngineId = 'llamacpp' | 'onnx';

export type EngineState = 'pending' | 'registered' | 'unavailable';

/** What each engine is called and what the user loses when it's missing. */
const ENGINES: Record<EngineId, { label: string; powers: string }> = {
  llamacpp: {
    label: 'llama.cpp',
    powers: 'chat, image understanding, and document answers',
  },
  onnx: {
    label: 'ONNX / Sherpa',
    // Document indexing belongs here too: the same artifact serves the ONNX
    // embedding models the Documents tab and the Document Q&A solution index
    // with. Naming only the speech modalities made those screens contradict
    // themselves — a row reading "Embeddings … Unavailable" sat directly under a
    // sentence promising that everything except speech still worked.
    powers: 'speech recognition, speech synthesis, voice detection, and document indexing',
  },
};

export const ENGINE_IDS: readonly EngineId[] = ['llamacpp', 'onnx'];

interface EngineRecord {
  state: EngineState;
  /** The raw registration diagnostic — shown only behind a disclosure. */
  error?: string;
}

const records = new Map<EngineId, EngineRecord>(
  ENGINE_IDS.map((id) => [id, { state: 'pending' }]),
);

const listeners: Array<() => void> = [];
let retryHandler: (() => Promise<void>) | null = null;
let retryInFlight: Promise<EngineRetryOutcome> | null = null;
/**
 * The engines a retry is currently re-checking.
 *
 * A retry resets every record to `pending`, which erases the reason a surface
 * was blocked. Without this, each surface would fall from "blocked" straight
 * back to its happy state for the length of the retry — offering a Download or
 * Set-up button while the runtime is mid-teardown. Scoped to the engines that
 * had actually failed, so retrying llama.cpp never makes a speech-only surface
 * claim it is re-checking something.
 */
let retryingIds: ReadonlySet<EngineId> = new Set();

// ---------------------------------------------------------------------------
// Reporting — called by `main.ts` around each `register()`
// ---------------------------------------------------------------------------

/** Registration outcome for one engine package. */
export type EngineRegistrationResult =
  | { ok: true }
  | { ok: false; error: string };

export function reportEngineRegistration(id: EngineId, result: EngineRegistrationResult): void {
  records.set(id, result.ok
    ? { state: 'registered' }
    : { state: 'unavailable', error: result.error });
  notify();
}

/** Mark every engine as re-registering, so the UI stops claiming a failure. */
export function resetEngineAvailability(): void {
  for (const id of ENGINE_IDS) records.set(id, { state: 'pending' });
  notify();
}

// ---------------------------------------------------------------------------
// Reading
// ---------------------------------------------------------------------------

export function engineState(id: EngineId): EngineState {
  return records.get(id)?.state ?? 'pending';
}

export interface EngineFailure {
  id: EngineId;
  label: string;
  powers: string;
  /** Raw diagnostic from the failed `register()` call. */
  error: string;
}

/** Every engine that failed to register, in declaration order. */
export function engineFailures(): readonly EngineFailure[] {
  const failures: EngineFailure[] = [];
  for (const id of ENGINE_IDS) {
    const record = records.get(id);
    if (record?.state !== 'unavailable') continue;
    failures.push({ id, ...ENGINES[id], error: record.error ?? 'Registration failed.' });
  }
  return failures;
}

/**
 * Which engine package serves a catalog entry.
 *
 * The mapping is a property of this app's packaging (which `.wasm` ships which
 * runtime), documented in the WASM table in AGENTS.md — not an SDK routing
 * decision. The SDK picks a plugin by priority at inference time; this only
 * decides which failure message applies to a row.
 */
export function engineForFramework(framework: InferenceFramework): EngineId | null {
  switch (framework) {
    case InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP:
      return 'llamacpp';
    case InferenceFramework.INFERENCE_FRAMEWORK_ONNX:
    case InferenceFramework.INFERENCE_FRAMEWORK_SHERPA:
      return 'onnx';
    default:
      // A framework this app doesn't package can't be attributed to an engine,
      // so it is never blamed on one. The size gate and the SDK's own typed
      // errors still apply.
      return null;
  }
}

/** The engines a set of catalog entries needs, deduplicated. */
export function enginesForEntries(entries: readonly CatalogEntry[]): readonly EngineId[] {
  const ids = new Set<EngineId>();
  for (const entry of entries) {
    const id = engineForFramework(entry.framework);
    if (id) ids.add(id);
  }
  return ENGINE_IDS.filter((id) => ids.has(id));
}

/** The subset of `engineFailures()` relevant to the given entries. */
export function failuresForEntries(entries: readonly CatalogEntry[]): readonly EngineFailure[] {
  const needed = new Set(enginesForEntries(entries));
  return engineFailures().filter((failure) => needed.has(failure.id));
}

/**
 * Is this model runnable at all right now, engine-wise?
 *
 * Returns the same typed union as the WASM32 size gate so the picker has one
 * "why this row is not actionable" shape to render, and one disabled-button
 * path, regardless of which check tripped.
 */
export function engineCompatibility(entry: CatalogEntry): WebModelCompatibility {
  const id = engineForFramework(entry.framework);
  if (!id) return { supported: true };
  const engine = ENGINES[id];

  // A retry resets this engine to `pending`, so `state` alone would report the
  // model as fine for the length of the retry. It isn't — the runtime is being
  // torn down and rebuilt — so the row stays unactionable and says why.
  if (retryInFlight !== null && retryingIds.has(id)) {
    return {
      supported: false,
      code: WebModelCompatibilityCode.ENGINE_UNAVAILABLE,
      actionLabel: 'Re-checking…',
      reason: `Re-checking the ${engine.label} engine.`,
    };
  }

  if (engineState(id) !== 'unavailable') return { supported: true };
  return {
    supported: false,
    code: WebModelCompatibilityCode.ENGINE_UNAVAILABLE,
    actionLabel: 'Engine unavailable',
    // Deliberately one short line, unlike the size gate's per-model
    // explanation. This reason is identical for every row the engine serves and
    // the banner above already gives the full story plus the retry — repeating
    // three lines of it on eight rows turns the list into a wall of the same
    // paragraph. The row still needs its own text so the disabled button has
    // something to point `aria-describedby` at.
    reason: `Needs the ${engine.label} engine, which didn't load this session.`,
  };
}

/**
 * One consumer-facing sentence for a set of engine failures.
 *
 * Deliberately says what the user cannot do — not which artifact 404'd. The
 * artifact-level diagnostic is real and useful, but it belongs behind a
 * disclosure; leading with it makes a browser app read like a build log.
 */
export function describeFailures(failures: readonly EngineFailure[]): string {
  if (failures.length === 0) return '';
  const powers = failures.map((failure) => failure.powers);
  // Each entry is itself a comma list ("chat, image understanding, and document
  // answers"), so stitching them with "and" produces "…answers; and speech…".
  // Past one engine, a colon and semicolons read as the list they are.
  const tail = powers.length === 1
    ? `so ${powers[0]} are unavailable`
    : `so these are unavailable: ${powers.join('; ')}`;
  return `This browser session could not load the on-device AI engine, ${tail}. `
    + 'Everything else in the app still works.';
}

/** The concatenated raw diagnostics, for the details disclosure. */
export function failureDiagnostics(failures: readonly EngineFailure[]): string {
  return failures.map((failure) => `${failure.label}: ${failure.error}`).join('\n\n');
}

// ---------------------------------------------------------------------------
// Change notification
// ---------------------------------------------------------------------------

export function onEngineStateChange(listener: () => void): () => void {
  listeners.push(listener);
  return () => {
    const index = listeners.indexOf(listener);
    if (index >= 0) listeners.splice(index, 1);
  };
}

function notify(): void {
  for (const listener of listeners) {
    try {
      listener();
    } catch (err) {
      appLogger.warning('[engine-availability] listener threw', err);
    }
  }
}

// ---------------------------------------------------------------------------
// Retry
// ---------------------------------------------------------------------------

/**
 * Install the boot-path retry. `main.ts` owns the only correct sequence
 * (tear the runtime down, then re-run it), exactly as Settings does when it
 * applies credentials; this inversion keeps that sequence out of the UI.
 */
export function setEngineRetryHandler(handler: (() => Promise<void>) | null): void {
  retryHandler = handler;
}

export function canRetryEngines(): boolean {
  return retryHandler !== null;
}

/**
 * Is a retry currently re-checking an engine any of these entries need?
 *
 * Surfaces use this to hold their blocked layout — with the action swapped for
 * a "Re-checking…" affordance — instead of briefly reverting to a CTA that
 * cannot succeed yet.
 */
export function isRetryingForEntries(entries: readonly CatalogEntry[]): boolean {
  if (retryInFlight === null) return false;
  return enginesForEntries(entries).some((id) => retryingIds.has(id));
}

/** What the last retry achieved, for the surface that triggered it. */
export type EngineRetryOutcome = 'recovered' | 'still-unavailable' | 'unsupported';

/**
 * How long a retry stays visibly in-flight, at minimum.
 *
 * A 404 for the WASM chunk rejects in well under 100 ms, so without a floor the
 * button flips to "Retrying…" and back within one frame: the user clicks, the
 * screen is identical, and a button that did exactly what it promised looks
 * broken. This is not a fake delay standing in for real work — the work is
 * genuinely finished; the floor only ensures the state change is perceivable
 * before the result is reported.
 */
const MIN_RETRY_FEEDBACK_MS = 600;

/**
 * Re-run boot. A failed engine registration is frequently transient (the WASM
 * chunk request failed, the tab was offline), so a retry that doesn't lose
 * app state is worth more than telling the user to reload.
 */
export function retryEngines(): Promise<EngineRetryOutcome> {
  if (retryInFlight) return retryInFlight;
  const handler = retryHandler;
  if (!handler) return Promise.resolve('unsupported');

  // Remember what was broken before the reset erases it, so surfaces can keep
  // showing a scoped in-flight state rather than a premature happy one.
  retryingIds = new Set(engineFailures().map((failure) => failure.id));
  resetEngineAvailability();
  retryInFlight = Promise.all([
    handler().catch((err) => {
      // `main.ts` already recorded the per-engine outcome through
      // `reportEngineRegistration`, so the UI is truthful either way; this
      // only keeps an unhandled rejection out of the console.
      appLogger.warning('[engine-availability] retry failed', err);
    }),
    new Promise((resolve) => setTimeout(resolve, MIN_RETRY_FEEDBACK_MS)),
  ])
    .then((): EngineRetryOutcome => (
      engineFailures().length === 0 ? 'recovered' : 'still-unavailable'
    ))
    .finally(() => {
      retryInFlight = null;
      retryingIds = new Set();
      notify();
    });
  notify();
  return retryInFlight;
}
