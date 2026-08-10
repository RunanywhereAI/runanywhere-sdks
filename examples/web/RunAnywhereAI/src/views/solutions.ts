/**
 * Solutions Tab — `RunAnywhere.solutions.run({ yaml })`.
 *
 * A "solution" is a prepackaged pipeline: one YAML file names a set of models
 * and the C++ core compiles it into a GraphScheduler DAG. This view runs the
 * two canonical solutions shipped at
 * `sdk/runanywhere-commons/examples/solutions/`, synced into a generated module
 * by `scripts/sync-solutions.mjs` (iOS parity:
 * `examples/ios/RunAnywhereAI/scripts/sync-solutions-yamls.sh`) so the view
 * never embeds a drift-prone inline copy.
 *
 * WHAT A RUN HERE ACTUALLY PROVES — and why the copy is worded so carefully.
 * The exported C ABI has no output channel and no non-destructive join:
 * `rac_solution_destroy` cancels then joins native workers, which is why
 * `SolutionHandle.wait()` is documented as a teardown point rather than a
 * graceful-output iterator (SolutionAdapter.ts:156-166). On top of that, the
 * voice-agent graph's root input is the VAD node, typed `audio.pcm_s16le`
 * (op_engine_backed.cpp `detect_voice`), and `handle.feed()` only accepts
 * UTF-8 text — so there is no way from this view to push audio through that
 * pipeline. A run therefore validates exactly one thing: that the YAML
 * compiles into a schedulable graph against resident models, and that the
 * lifecycle verbs succeed. It produces no transcript, no answer, and no audio.
 * Saying "ran the voice agent" would be a lie, so this view doesn't.
 *
 * The readiness gate mirrors Android (`SolutionsViewModel.kt` +
 * `AndroidSolutionsConfig.kt`) — the reference implementation, since iOS has no
 * Solutions surface. Every model id a YAML names must be resident before its
 * Run button enables; otherwise the graph fails at the first item with
 * `*_NOT_LOADED` and the failure reads like a bug in the SDK rather than a
 * missing download.
 */
import { ModelCategory, RunAnywhere, type RagSession } from '@runanywhere/web';
import type { TabLifecycle } from '../app';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';
import { RAG_YAML, VOICE_AGENT_YAML } from '../services/solutions-config';
import { getCatalog, type CatalogEntry } from '../services/model-catalog';
import {
  ensureModelReady,
  getModelStatus,
  onModelStateChange,
  refreshModelSelectionState,
  runEngineRetry,
} from '../components/model-selection';
import { renderModelSlot, type ModelSlotView } from '../components/model-slot';
import { icon } from '../components/icons';
import {
  canRetryEngines,
  describeFailures,
  failuresForEntries,
  isRetryingForEntries,
  onEngineStateChange,
  type EngineFailure,
} from '../services/engine-availability';

// ---------------------------------------------------------------------------
// Solution definitions
// ---------------------------------------------------------------------------

/** One model role a solution YAML names, for the readiness gate. */
interface SolutionRole {
  /** The YAML key, so a mismatch with the generated config is obvious. */
  yamlKey: string;
  label: string;
  modelId: string;
  category: ModelCategory;
}

interface SolutionDef {
  key: 'voice-agent' | 'rag';
  title: string;
  /** What the pipeline is, in one line. */
  summary: string;
  /** The DAG, as the converter expands it. */
  graph: string;
  yaml: string;
  roles: readonly SolutionRole[];
  /** True when the solution needs a live `RunAnywhere.rag` session. */
  needsRagSession: boolean;
}

/**
 * The roles below are transcribed from the canonical YAMLs. They are asserted
 * against the generated config at module load (see `assertRolesMatchYaml`) so a
 * commons-side model-id change cannot silently leave this gate checking a stale
 * id — which would gate on a model the graph does not use and let the run fail
 * for a model nobody was asked to download.
 */
const SOLUTIONS: readonly SolutionDef[] = [
  {
    key: 'voice-agent',
    title: 'Voice agent',
    summary: 'Speech in, speech out — voice detection, transcription, a reply, and synthesis, wired as one graph.',
    graph: 'Voice detection → Transcribe → Chat model → Speech',
    yaml: VOICE_AGENT_YAML,
    needsRagSession: false,
    roles: [
      { yamlKey: 'vad_model_id', label: 'Voice detection', modelId: 'silero-vad', category: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION },
      { yamlKey: 'stt_model_id', label: 'Speech-to-text', modelId: 'sherpa-onnx-whisper-tiny.en', category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION },
      { yamlKey: 'llm_model_id', label: 'Chat model', modelId: 'smollm2-360m-q8_0', category: ModelCategory.MODEL_CATEGORY_LANGUAGE },
      { yamlKey: 'tts_model_id', label: 'Text-to-speech', modelId: 'vits-piper-en_US-lessac-medium', category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS },
    ],
  },
  {
    key: 'rag',
    title: 'Document Q&A',
    summary: 'A question is embedded, matched against an indexed corpus, and answered from what was retrieved.',
    graph: 'Question → Retrieve → Build context → Chat model',
    yaml: RAG_YAML,
    needsRagSession: true,
    roles: [
      { yamlKey: 'embed_model_id', label: 'Embeddings', modelId: 'all-minilm-l6-v2', category: ModelCategory.MODEL_CATEGORY_EMBEDDING },
      { yamlKey: 'llm_model_id', label: 'Chat model', modelId: 'smollm2-360m-q8_0', category: ModelCategory.MODEL_CATEGORY_LANGUAGE },
    ],
  },
];

/**
 * Fail loudly at load if a declared role no longer matches the generated YAML.
 *
 * `solutions-config.ts` is regenerated from commons, so the ids there can move
 * without this file being touched. A stale id would produce the worst possible
 * outcome: a green "Ready" gate for a model the graph never loads.
 */
function assertRolesMatchYaml(): string | null {
  for (const solution of SOLUTIONS) {
    for (const role of solution.roles) {
      const match = new RegExp(`^\\s*${role.yamlKey}\\s*:\\s*"([^"]*)"`, 'm').exec(solution.yaml);
      if (!match) {
        return `${solution.title}: the generated YAML has no ${role.yamlKey} field.`;
      }
      if (match[1] !== role.modelId) {
        return `${solution.title}: ${role.yamlKey} is "${match[1]}" in the generated YAML `
          + `but this view checks "${role.modelId}". Re-sync src/views/solutions.ts.`;
      }
    }
  }
  return null;
}

const CONFIG_DRIFT = assertRolesMatchYaml();

// ---------------------------------------------------------------------------
// View state
// ---------------------------------------------------------------------------

/** What happened on the last run of one solution. */
type RunOutcome =
  | { status: 'idle' }
  | { status: 'preparing' }
  | { status: 'running' }
  | { status: 'compiled' }
  | { status: 'failed'; message: string };

let container: HTMLElement;
let unmounted = false;
let unsubscribeModelState: (() => void) | null = null;
let unsubscribeEngineState: (() => void) | null = null;
const outcomes = new Map<string, RunOutcome>();
/** Solutions whose models are being downloaded/loaded from this view. */
const preparing = new Set<string>();

function outcomeOf(key: string): RunOutcome {
  return outcomes.get(key) ?? { status: 'idle' };
}

function catalogEntry(modelId: string): CatalogEntry | null {
  return getCatalog().find((entry) => entry.id === modelId) ?? null;
}

/** Roles whose model is resident and loaded — the only honest run precondition. */
function missingRoles(solution: SolutionDef): SolutionRole[] {
  return solution.roles.filter((role) => getModelStatus(role.modelId).status !== 'loaded');
}

function isReady(solution: SolutionDef): boolean {
  return CONFIG_DRIFT === null && missingRoles(solution).length === 0;
}

/**
 * Engine failures that block this solution's graph.
 *
 * Scoped per solution: the RAG pipeline and the voice-agent pipeline name
 * different models, so one may be blocked while the other is not.
 */
function solutionFailures(solution: SolutionDef): readonly EngineFailure[] {
  return failuresForEntries(solutionEntries(solution));
}

function solutionEntries(solution: SolutionDef): CatalogEntry[] {
  return solution.roles
    .map((role) => catalogEntry(role.modelId))
    .filter((entry): entry is CatalogEntry => entry !== null);
}

/** True while a retry is re-checking an engine this solution needs. */
function solutionRechecking(solution: SolutionDef): boolean {
  return isRetryingForEntries(solutionEntries(solution));
}

/** Blocked, or mid-recheck after being blocked — either way, not runnable. */
function solutionBlocked(solution: SolutionDef): boolean {
  return solutionFailures(solution).length > 0 || solutionRechecking(solution);
}

function isBusy(solution: SolutionDef): boolean {
  const status = outcomeOf(solution.key).status;
  return status === 'preparing' || status === 'running';
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

export function initSolutionsTab(host: HTMLElement): TabLifecycle {
  container = host;
  unmounted = false;
  renderView();
  return {
    onActivate: () => {
      unmounted = false;
      // Another surface (Voice AI, the picker, Documents) may have loaded or
      // evicted one of these models while this tab was inactive.
      refreshModelSelectionState();
      if (!unsubscribeModelState) {
        unsubscribeModelState = onModelStateChange(() => {
          if (!unmounted) renderView();
        });
      }
      if (!unsubscribeEngineState) {
        // A successful retry has to turn the blocked cards back into Get/Run
        // without a tab switch.
        unsubscribeEngineState = onEngineStateChange(() => {
          if (!unmounted) renderView();
        });
      }
      renderView();
    },
    onDeactivate: () => {
      unmounted = true;
      if (!container.isConnected) {
        unsubscribeModelState?.();
        unsubscribeModelState = null;
        unsubscribeEngineState?.();
        unsubscribeEngineState = null;
      }
    },
  };
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

function renderView(): void {
  if (unmounted) return;

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Solutions</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="solutions-refresh-btn">Refresh</button>
      </div>
    </div>
    <div class="scroll-area">
      <div class="docs-section">
        <h3>Whole pipelines from one config file</h3>
        <p class="text-secondary">
          A solution is a prepackaged pipeline. One YAML file names the models and
          the SDK compiles it into a running graph — no wiring code in the app.
          These two are the canonical examples shipped with the SDK, byte-identical
          to the ones the iOS and Android samples run.
        </p>
      </div>
      ${CONFIG_DRIFT
        ? `<div class="docs-section">
             <h3>Configuration out of sync</h3>
             <p class="text-secondary">${escapeHtml(CONFIG_DRIFT)}</p>
           </div>`
        : ''}
      ${SOLUTIONS.map(renderSolutionCard).join('')}
    </div>
  `;

  attachHandlers();
}

function renderSolutionCard(solution: SolutionDef): string {
  const ready = isReady(solution);
  const busy = isBusy(solution);
  const missing = missingRoles(solution);
  const rows = solution.roles.map((role) => renderModelSlot(slotView(role))).join('');

  // The primary action is "get the models" until they are all resident, then
  // "run". Two buttons that trade places, never one button that lies about
  // being available — and neither, when the engine those models need is gone:
  // downloading them would succeed and Run would still be unreachable.
  const failures = solutionFailures(solution);
  const rechecking = solutionRechecking(solution);
  const action = failures.length > 0 || rechecking
    ? `<div class="setup-card__note">${escapeHtml(
        rechecking
          ? 'Re-checking the on-device AI engine…'
          : describeFailures(failures),
      )}</div>
       ${canRetryEngines()
         ? `<button class="btn btn-secondary" data-engine-retry="${solution.key}" ${rechecking ? 'disabled' : ''}>
              ${rechecking ? 'Re-checking…' : 'Retry setup'}
            </button>`
         : ''}`
    : ready
      ? `<button class="btn btn-primary" data-run="${solution.key}" ${busy ? 'disabled' : ''}>
           ${busy ? 'Working…' : 'Run'}
         </button>`
      : `<button class="btn btn-primary" data-prepare="${solution.key}" ${busy ? 'disabled' : ''}>
           ${busy ? 'Getting models…' : `Get ${missing.length} model${missing.length === 1 ? '' : 's'}`}
         </button>`;

  return `
    <div class="setup-card setup-card--plain">
      <div class="setup-card__head">
        <div class="setup-card__glyph">
          ${icon('stack', { size: 24 })}
        </div>
        <div>
          <div class="setup-card__title">${escapeHtml(solution.title)}</div>
          <div class="setup-card__subtitle">${escapeHtml(solution.summary)}</div>
        </div>
      </div>
      <div class="solution-card__graph">${escapeHtml(solution.graph)}</div>
      <div class="setup-card__slots">${rows}</div>
      <div class="setup-card__actions">
        ${action}
        ${renderOutcome(solution)}
      </div>
    </div>
  `;
}

/** Adapt a solution role to the shared setup-card row. */
function slotView(role: SolutionRole): ModelSlotView {
  return {
    key: role.modelId,
    label: role.label,
    category: role.category,
    entry: catalogEntry(role.modelId),
    missingHint: `${role.modelId} is not in this app's catalog.`,
  };
}

function renderOutcome(solution: SolutionDef): string {
  const outcome = outcomeOf(solution.key);
  switch (outcome.status) {
    case 'preparing':
      return '<div class="setup-card__note">Downloading and loading the models this pipeline names…</div>';
    case 'running':
      return '<div class="setup-card__note">Compiling the config into a graph…</div>';
    case 'compiled':
      // Precise about scope: the graph built and the lifecycle verbs succeeded.
      // No output was produced, because the C ABI exposes no output channel.
      return `<div class="setup-card__ready">
                <span class="badge badge-green">Compiled</span>
                Built and started a live graph from the config, then tore it down. Results aren't surfaced yet.
              </div>`;
    case 'failed':
      return `<div class="docs-status error">${escapeHtml(outcome.message)}</div>`;
    default:
      // While the engine is missing, "get the models onto the device first"
      // names the wrong prerequisite — the action block above already states
      // the real one, so adding this would send the user after the wrong fix.
      if (solutionBlocked(solution)) return '';
      return isReady(solution)
        ? '<div class="setup-card__note">Compiles the config into a graph, starts it, and tears it down. Nothing is recorded or played back.</div>'
        : '<div class="setup-card__note">Every model this pipeline names has to be on the device first.</div>';
  }
}

function attachHandlers(): void {
  container.querySelector('#solutions-refresh-btn')?.addEventListener('click', () => {
    refreshModelSelectionState();
    renderView();
  });
  container.querySelectorAll<HTMLElement>('[data-prepare]').forEach((el) => {
    el.addEventListener('click', () => {
      const solution = SOLUTIONS.find((s) => s.key === el.dataset.prepare);
      if (solution) void prepareSolution(solution);
    });
  });
  container.querySelectorAll<HTMLElement>('[data-run]').forEach((el) => {
    el.addEventListener('click', () => {
      const solution = SOLUTIONS.find((s) => s.key === el.dataset.run);
      if (solution) void runSolution(solution);
    });
  });
  container.querySelectorAll<HTMLElement>('[data-engine-retry]').forEach((el) => {
    el.addEventListener('click', () => void runEngineRetry());
  });
}

function setOutcome(solution: SolutionDef, outcome: RunOutcome): void {
  outcomes.set(solution.key, outcome);
  if (!unmounted) renderView();
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

/**
 * Download + load every model the solution names.
 *
 * Sequential on purpose: `ensureModelReady` drives the shared picker's
 * download/load path, and parallel loads of several hundred MB into one WASM
 * heap is how the tab runs out of memory.
 */
async function prepareSolution(solution: SolutionDef): Promise<void> {
  if (preparing.has(solution.key)) return;
  preparing.add(solution.key);
  setOutcome(solution, { status: 'preparing' });
  try {
    const failed: string[] = [];
    for (const role of missingRoles(solution)) {
      if (!await ensureModelReady(role.modelId)) failed.push(role.label);
    }
    if (failed.length > 0) {
      // The picker already toasted the specific reason (quota, network, …);
      // name the roles so the card itself says which rows to look at.
      setOutcome(solution, {
        status: 'failed',
        message: `Could not set up ${failed.join(', ')}. See the rows above for the reason.`,
      });
      return;
    }
    setOutcome(solution, { status: 'idle' });
  } finally {
    preparing.delete(solution.key);
    if (!unmounted) renderView();
  }
}

/**
 * Compile the YAML into a graph, start it, and tear it down.
 *
 * The sequence is deliberately short because the ABI supports no more than
 * this: `run` compiles, `start` schedules the operators, and `destroy` — which
 * `wait()` calls — cancels and joins. There is no feed step: the voice-agent
 * graph's root input is PCM audio and `feed()` is UTF-8-only, so feeding it
 * would fail the payload-type contract in `SolutionRunner::feed`. Silently
 * skipping the feed and reporting success, as this view used to, described work
 * that never happened.
 */
async function runSolution(solution: SolutionDef): Promise<void> {
  if (isBusy(solution)) return;
  setOutcome(solution, { status: 'running' });

  // The RAG graph's `retrieve` operator resolves a host-supplied session
  // handle, so the session has to exist before the graph starts.
  let ragSession: RagSession | null = null;
  if (solution.needsRagSession) {
    const embed = solution.roles.find((role) => role.yamlKey === 'embed_model_id');
    const llm = solution.roles.find((role) => role.yamlKey === 'llm_model_id');
    if (!embed || !llm) {
      setOutcome(solution, {
        status: 'failed',
        message: 'This solution needs an embedding model and a chat model, and one is missing from its config.',
      });
      return;
    }
    try {
      ragSession = await RunAnywhere.rag.open({ id: embed.modelId }, { id: llm.modelId });
    } catch (err) {
      setOutcome(solution, {
        status: 'failed',
        message: `Couldn't open a document index: ${formatError(err)}`,
      });
      return;
    }
  }

  try {
    const handle = RunAnywhere.solutions.run({ yaml: solution.yaml });
    try {
      handle.start();
    } finally {
      // `wait()` IS `destroy()` — cancel + join. Always reached, so a throwing
      // start() cannot leak the native handle.
      await handle.wait();
    }
    setOutcome(solution, { status: 'compiled' });
  } catch (err) {
    setOutcome(solution, { status: 'failed', message: formatError(err) });
  } finally {
    await ragSession?.close().catch(() => undefined);
  }
}
