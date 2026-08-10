/**
 * Model Selection — minimal in-toolbar model picker + bottom-sheet list.
 *
 * This component satisfies two probe targets read by `main.ts:probeAppShell`:
 *
 *   1. `#chat-toolbar-model` — a pill-button shown on top of the chat panel
 *      listing the currently loaded model (or "Select Model"). It is
 *      actionable whenever at least one catalog entry has been registered.
 *   2. `#chat-model-overlay` + `#chat-get-started-btn` — a "Get Started"
 *      overlay shown before any model is chosen. The readiness probe accepts
 *      either one so the chat tab is considered interactive as soon as the
 *      user has a clear path to a model.
 *
 * Model actions flow through the `models` namespace:
 *
 *   - `RunAnywhere.models.list()` / `models.get(...)` — catalog list / get
 *   - `RunAnywhere.models.download(...)` — download events as an async iterable
 *   - `RunAnywhere.models.load(...)`     — load through the C++ lifecycle ABI
 *
 * No legacy app-side registries or extension-point routing.
 */

import type { DownloadEvent, ModelInfo } from '@runanywhere/web';
import {
  RunAnywhere,
  ModelCategory,
} from '@runanywhere/web';
import {
  ensureDownloadStorageReady,
  LARGE_DOWNLOAD_BYTES,
} from '@runanywhere/web/browser';
import {
  getCatalog,
  webModelCompatibility,
  type CatalogEntry,
  type WebModelCompatibility,
} from '../services/model-catalog';
import {
  canRetryEngines,
  describeFailures,
  engineCompatibility,
  failureDiagnostics,
  failuresForEntries,
  isRetryingForEntries,
  onEngineStateChange,
  type EngineFailure,
} from '../services/engine-availability';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';
import {
  formatBytes,
  formatFramework,
  formatModelSize,
  formatTransferBytes,
  modelDisplaySizeBytes,
  modalityIcon,
  cleanModelName,
  consumerTags,
  modelOrg,
  modelCapability,
  transferDetailLine,
  variantSizeFeel,
  type ConsumerTag,
} from '../services/model-display';
import {
  detectDeviceCapabilities,
  describeCapabilities,
  type DeviceCapabilities,
} from '../services/device-capabilities';
import {
  recommendModels,
  type RecommendedSelection,
} from '../services/model-recommendation';
import { openModal, showToast } from './dialogs';
import { icon } from './icons';
import { runEngineRetry } from './engine-notice';
import { appLogger } from '../services/app-logger';
import { openAddFromHuggingFace } from './add-from-huggingface';

// ---------------------------------------------------------------------------
// State (module-scope, one selection sheet per app)
// ---------------------------------------------------------------------------

/**
 * What a download is doing right now.
 *
 * `verifying` and `extracting` were both being folded into a 100% transfer bar,
 * which is the single worst moment to go silent: a multi-gigabyte checksum or
 * unpack can take tens of seconds, and a bar sitting at 100% with no label is
 * indistinguishable from a hung download. Naming the phase is what tells the
 * user the wait is expected.
 *
 * `queued` covers the gap between the click and the first byte — planning the
 * download, checking quota, opening the connection. It can run for seconds on a
 * multi-file model, and a determinate bar frozen at 0% through it reads as a
 * transfer that stalled before it started.
 *
 * `cancelling` is the wind-down after the user's tap: the iterator has been
 * broken out of but the SDK has not confirmed the stop. Leaving the row on its
 * last progress frame there makes an ignored tap look identical to a stuck one.
 *
 * The five names, and the interrupted states below, are the vocabulary shared
 * with iOS `ModelDownloadPhase` and Android `DownloadPhase`, so one download
 * cannot be described three ways.
 */
type DownloadPhase = 'queued' | 'transferring' | 'verifying' | 'extracting' | 'cancelling';

type RowState =
  | { status: 'registered' }      // not downloaded yet, never attempted
  | {
      status: 'downloading';
      /** 0..1. Only a real position when `measured`; otherwise just a width. */
      progress: number;
      /**
       * True when `progress` is a position somebody reported, rather than a
       * placeholder for a phase whose length nobody knows. A determinate bar is
       * a claim, and the phases that cannot back it sweep instead.
       */
      measured?: boolean;
      phase: DownloadPhase;
      /** Absent until the first progress event reports a total. */
      bytesDone?: number;
      bytesTotal?: number;
      /** Bytes/second, smoothed. Absent until two samples exist. */
      bytesPerSecond?: number;
      /** Seconds remaining, derived from the smoothed rate. Absent until then. */
      etaSeconds?: number;
    }
  /**
   * Stopped by the user, bytes kept.
   *
   * A distinct state rather than a return to `registered` because the two differ
   * in exactly the thing the user is deciding about: whether pressing the button
   * again re-spends the gigabytes already fetched. It does not — the SDK cancels
   * with `deletePartialBytes: false` — and only a state that remembers the
   * interruption can say so.
   */
  | { status: 'paused' }
  | { status: 'downloaded' }      // on disk but not loaded
  | { status: 'loading' }
  | { status: 'loaded' }
  | {
      status: 'error';
      error: string;
      /** Which step failed, so a Retry repeats that step and not the other one. */
      stage: 'download' | 'load';
      /**
       * Whether pressing the button again could plausibly end differently.
       *
       * The SDK's planner already knows which refusals are permanent and says so
       * on `SDKError.retryable`; a UI that offers Retry on every failure sends
       * the user straight back into the identical error. This is that verdict
       * carried through to the button.
       */
      retryable: boolean;
    };

type RowStatus = RowState['status'];

const rowStates = new Map<string, RowState>();

/**
 * Live download iterators, by model id.
 *
 * Held so Cancel has something to break out of: `models.download()` treats
 * abandoning its iterator as the cancellation signal and preserves the resume
 * token, so this map is the whole mechanism behind both stopping a transfer and
 * later continuing it instead of starting over.
 */
const activeDownloads = new Map<string, AsyncIterator<DownloadEvent>>();

/**
 * The open sheet's backdrop, or null.
 *
 * Doubles as the "is the picker open" flag every render path already checks, and
 * as the identity a long-running load compares against so a completed selection
 * is never delivered to a sheet the user has since closed and reopened.
 */
let modalEl: HTMLElement | null = null;
/** Dismisses the open sheet through the shared modal, which owns teardown. */
let closeActiveSheet: (() => void) | null = null;
let toolbarBtn: HTMLElement | null = null;
let toolbarText: HTMLElement | null = null;
let getStartedOverlay: HTMLElement | null = null;
let getStartedBtn: HTMLButtonElement | null = null;
let overlaySheetOptions: OpenSheetOptions = {};
let catalogRegistered = false;
const listeners: Array<() => void> = [];

/**
 * Sheet open options — used by tabs that want to restrict the visible catalog
 * to a single modality (Vision → MULTIMODAL, Transcribe → SPEECH_RECOGNITION,
 * Speak → SPEECH_SYNTHESIS). When omitted, the whole catalog is shown.
 */
export interface OpenSheetOptions {
  filterCategories?: readonly ModelCategory[];
  title?: string;
  /**
   * Called only after the chosen catalog entry is loaded and ready. This lets
   * multi-model surfaces (for example Voice AI) update a specific pipeline
   * slot without coupling the shared picker to that surface's state.
   */
  onModelReady?: (entry: CatalogEntry) => void;
}

let activeSheetOptions: OpenSheetOptions = {};
let toolbarSheetOptions: OpenSheetOptions = {};
let overlayLoadedCategories: readonly ModelCategory[] | undefined;

// Hardware detection is async and stable for a session, so we probe once and
// cache. The recommendation set is derived purely from the tier + catalog.
let capabilitiesCache: DeviceCapabilities | null = null;
let recommendationCache: RecommendedSelection | null = null;
let searchQuery = '';

// Which family cards are expanded to reveal their variants (keyed by family
// key). Reset whenever the sheet is opened so it always starts collapsed.
const expandedOrgs = new Set<string>();

// ---------------------------------------------------------------------------
// Public API — wiring into the chat view
// ---------------------------------------------------------------------------

/**
 * Notify this component that the catalog was registered at SDK init
 * (`main.ts` runs the `registerAll()` bootstrap once — iOS parity:
 * RunAnywhereAIApp.swift:98 `ModelCatalogBootstrap.registerAll()`). The
 * former lazy per-view registration mechanism was removed; views no longer
 * trigger catalog registration themselves.
 */
export function notifyCatalogRegistered(registeredCount: number): void {
  catalogRegistered = registeredCount > 0;
  if (catalogRegistered) {
    hydrateRowStatesFromRegistry();
  }
  refreshToolbarLabel();
  refreshOverlayVisibility();
}

/**
 * Re-read on-disk state after `RunAnywhere.storage.refresh()` so rows show
 * Load instead of Download for models already present from a previous session.
 */
export function refreshFromRegistry(): void {
  hydrateRowStatesFromRegistry();
  if (modalEl) renderRows();
  refreshToolbarLabel();
  refreshOverlayVisibility();
  for (const listener of listeners) {
    try {
      listener();
    } catch (err) {
      appLogger.warning('[model-selection] registry listener threw', err);
    }
  }
}

/**
 * Forget everything this component remembered about one model's artifacts.
 *
 * Called after the files are deleted. The interrupted states deliberately
 * survive a registry hydrate (see `hydrateRowStatesFromRegistry`), so without
 * this a deleted model would keep offering "Resume" for partial bytes that no
 * longer exist — the exact untruthful control the paused state was added to
 * avoid.
 */
export function resetModelRowState(modelId: string): void {
  rowStates.delete(modelId);
  refreshModelSelectionState();
}

/** Clear the view's SDK-lifetime state before `RunAnywhere.reset()`. */
export function resetCatalogRegistrationState(): void {
  catalogRegistered = false;
  refreshToolbarLabel();
  refreshOverlayVisibility();
}

/**
 * Mount the `#chat-toolbar-model` pill into the chat toolbar. Returns the
 * element so the caller can place it wherever the toolbar layout expects.
 *
 * `sheetOptions` scope the picker opened from this pill to a modality —
 * Chat passes a LANGUAGE filter (iOS parity: ModelSelectionSheet(context: .llm)).
 * Optional and unfiltered by default so other tabs keep their behavior.
 */
export function buildToolbarModelButton(sheetOptions: OpenSheetOptions = {}): HTMLElement {
  toolbarSheetOptions = sheetOptions;
  const btn = document.createElement('button');
  btn.id = 'chat-toolbar-model';
  btn.className = 'toolbar-model-btn';
  btn.type = 'button';
  btn.innerHTML = `
    ${icon('model', { size: 16, className: 'model-icon' })}
    <span id="chat-toolbar-model-text">Select Model</span>
    ${icon('chevronDown', { size: 16, className: 'chevron' })}
  `;
  btn.addEventListener('click', () => openSheet(sheetOptions));

  toolbarBtn = btn;
  toolbarText = btn.querySelector('#chat-toolbar-model-text') as HTMLElement;
  refreshToolbarLabel();
  return btn;
}

/**
 * Mount the `#chat-model-overlay` "Get Started" overlay into the panel host.
 * The overlay is hidden automatically as soon as a model is loaded.
 * `sheetOptions` scope the picker opened from the overlay (see
 * `buildToolbarModelButton`). `loadedCategories` may broaden which loaded
 * model types make the underlying experience usable without broadening that
 * picker (for example, Chat accepts VLM-only image conversations while its
 * primary model picker remains language-model scoped).
 */
export function buildGetStartedOverlay(
  sheetOptions: OpenSheetOptions = {},
  loadedCategories: readonly ModelCategory[] | undefined = sheetOptions.filterCategories,
): HTMLElement {
  overlayLoadedCategories = loadedCategories;
  overlaySheetOptions = sheetOptions;
  const overlay = document.createElement('div');
  overlay.id = 'chat-model-overlay';
  overlay.className = 'chat-model-overlay';

  getStartedOverlay = overlay;
  renderOverlayCard();
  refreshOverlayVisibility();
  return overlay;
}

/**
 * Re-sync the overlay's panel state once it has been inserted into the DOM.
 *
 * `buildGetStartedOverlay` runs before its caller inserts the node, so
 * `refreshOverlayVisibility()`'s `parentElement` is still null there and the
 * `chat-panel--model-blocked` class — which stands the panel's own empty state
 * down — cannot be applied. It therefore only landed on a *later* refresh, after
 * the first paint, and hiding `#chat-messages` at that point doubled the
 * overlay's height (376px to 752px) and shoved the nav 30px down: a 0.19 layout
 * shift, nearly twice the "good" CLS threshold, on every cold load with no model.
 *
 * Callers must invoke this immediately after inserting the overlay.
 */
export function syncMountedOverlayState(): void {
  refreshOverlayVisibility();
}

/**
 * Render the overlay's card for the current engine state.
 *
 * Two mutually exclusive states, never a blend: an invitation to pick a model
 * when one could actually load, or a plain statement that the engine didn't
 * load when it couldn't. The old overlay only had the first, so a session with
 * no engine still opened with "Welcome / Choose your AI model and start
 * chatting" and an orange CTA into a catalog where every download was futile.
 */
function renderOverlayCard(): void {
  const overlay = getStartedOverlay;
  if (!overlay) return;

  const scoped = overlayScopedEntries();
  const failures = failuresForEntries(scoped);
  // Mid-retry every engine record is `pending`, so `failures` is briefly empty.
  // Falling back to the welcome card there would flash "Choose a Model" over a
  // catalog that still can't load anything — so the unavailable card stays up
  // and says it is re-checking instead.
  const rechecking = isRetryingForEntries(scoped);
  overlay.innerHTML = failures.length > 0 || rechecking
    ? unavailableOverlayCard(failures, rechecking)
    : welcomeOverlayCard();

  getStartedBtn = overlay.querySelector<HTMLButtonElement>('#chat-get-started-btn');
  getStartedBtn?.addEventListener('click', () => openSheet(overlaySheetOptions));
  const diagnostic = overlay.querySelector<HTMLPreElement>('.engine-banner__diagnostic');
  if (diagnostic) diagnostic.textContent = failureDiagnostics(failures);
  overlay.querySelector('#chat-engine-retry-btn')?.addEventListener('click', () => {
    void runEngineRetry();
  });
}

/**
 * Suppress the overlay because the surface has real content to show.
 *
 * Chat calls this when a conversation is on screen: an existing thread is worth
 * more than a "pick a model" card, even with nothing loaded. Routed through here
 * rather than having the view toggle classes itself, so the panel's own
 * empty-state suppression stays in step with the overlay's visibility.
 */
export function setOverlaySuppressed(suppressed: boolean): void {
  getStartedOverlay?.classList.toggle('chat-model-overlay--conversation-visible', suppressed);
  refreshOverlayVisibility();
}

/** Catalog entries the surface behind this overlay can actually use. */
function overlayScopedEntries(): CatalogEntry[] {
  const cats = overlayLoadedCategories;
  const all = getCatalog();
  return cats && cats.length > 0
    ? all.filter((entry) => cats.includes(entry.category))
    : [...all];
}

function welcomeOverlayCard(): string {
  return `
    <div class="chat-model-overlay-card">
      <div class="chat-model-overlay-glyph">
        ${icon('sparkles', { size: 32 })}
      </div>
      <h3 class="chat-model-overlay-title">Welcome</h3>
      <p class="chat-model-overlay-description">
        Choose your AI model and start chatting. AI inference runs in your
        browser. Setup and model downloads contact RunAnywhere services, and
        enabled web tools contact their named providers.
      </p>
      <button type="button" id="chat-get-started-btn" class="btn btn-primary btn-lg">
        Choose a Model
      </button>
      <div class="chat-model-overlay-privacy">
        ${icon('lock', { size: 16 })}
        <span>On-device AI inference</span>
      </div>
    </div>
  `;
}

function unavailableOverlayCard(
  failures: readonly EngineFailure[],
  rechecking: boolean,
): string {
  const retry = canRetryEngines()
    ? `<button type="button" id="chat-engine-retry-btn" class="btn btn-primary btn-lg" ${rechecking ? 'disabled' : ''}>
         ${rechecking ? 'Re-checking&hellip;' : 'Try again'}
       </button>`
    : '';
  return `
    <div class="chat-model-overlay-card">
      <div class="chat-model-overlay-glyph chat-model-overlay-glyph--warning">
        ${icon('warning', { size: 32 })}
      </div>
      <h3 class="chat-model-overlay-title">${rechecking ? 'Re-checking the AI engine' : 'AI engine didn&rsquo;t load'}</h3>
      <p class="chat-model-overlay-description">${escapeHtml(
        rechecking
          ? 'Loading the on-device AI engine again…'
          : describeFailures(failures),
      )}</p>
      ${retry}
      ${failures.length > 0
        ? `<details class="engine-banner__details chat-model-overlay-details">
             <summary>Technical details</summary>
             <pre class="engine-banner__diagnostic"></pre>
           </details>`
        : ''}
    </div>
  `;
}

/**
 * Subscribe to state changes for re-rendering consumers (chat toolbar, etc.).
 * Returns an unsubscribe function.
 */
export function onModelStateChange(listener: () => void): () => void {
  listeners.push(listener);
  return () => {
    const idx = listeners.indexOf(listener);
    if (idx >= 0) listeners.splice(idx, 1);
  };
}

/** Reconcile picker/toolbar/overlay state after another app surface performs
 * lifecycle work directly through RunAnywhere (for example Documents RAG).
 * Those loads bypass this component's row-state setters, so tab activation
 * must query the canonical native lifecycle instead of showing stale UI. */
export function refreshModelSelectionState(): void {
  if (catalogRegistered) hydrateRowStatesFromRegistry();
  refreshToolbarLabel();
  refreshOverlayVisibility();
  for (const listener of listeners) {
    try {
      listener();
    } catch (err) {
      appLogger.warning('[model-selection] refresh listener threw', err);
    }
  }
}

/**
 * Find the loaded model for a specific category, or `null` if none. Used by
 * the Transcribe/Speak tabs to surface a "Pick an STT/TTS model" toolbar pill
 * matching the Chat tab's pattern.
 */
export function findLoadedModelForCategory(category: ModelCategory): ModelInfo | null {
  return loadedByCategory.get(category) ?? null;
}

/**
 * Loaded model per catalog category, refreshed on every registry hydrate and
 * after each load/unload. `RunAnywhere.models.state()` is async, so the picker
 * keeps this synchronous mirror for render paths.
 */
const loadedByCategory = new Map<ModelCategory, ModelInfo>();

async function refreshLoadedByCategory(): Promise<void> {
  try {
    const { loaded } = await RunAnywhere.models.state();
    loadedByCategory.clear();
    for (const [category, model] of Object.entries(loaded)) {
      if (model) loadedByCategory.set(Number(category) as ModelCategory, model);
    }
  } catch {
    // A modality without a registered backend must not clear the others.
  }
}

/** Open the model selection bottom sheet programmatically. */
export function openSheet(options: OpenSheetOptions = {}): void {
  if (modalEl) return;
  activeSheetOptions = options;
  renderSheet();
}

// ---------------------------------------------------------------------------
// Programmatic model orchestration — used by multi-model experiences (Voice AI)
// that need to download + load a set of models without opening the picker. All
// SDK verbs stay centralized here; consumers only pass model ids + a progress
// callback and observe the shared row state via `getModelStatus`.
// ---------------------------------------------------------------------------

/** Public snapshot of a model's lifecycle for external consumers. */
export interface ModelStatusSnapshot {
  status: RowStatus;
  progress: number;   // 0..1
  /** Which part of the download is running. Only set while `downloading`. */
  phase?: DownloadPhase;
  /**
   * The one line of detail that belongs under the bar, already worded — the
   * byte/rate/ETA readout while transferring, the phase's name after it.
   *
   * Resolved here rather than by each caller so the pipeline slots on Voice AI
   * and Solutions cannot describe the same transfer differently from the picker
   * that started it.
   */
  detail?: string;
  /** The phase has no measurable position, so `progress` must not be believed. */
  indeterminate?: boolean;
  error?: string;
  /** Only meaningful with `status: 'error'` — see `RowState`. */
  retryable?: boolean;
}

/** Read the current lifecycle status for a model id. */
export function getModelStatus(modelId: string): ModelStatusSnapshot {
  return toSnapshot(rowStates.get(modelId) ?? { status: 'registered' });
}

/** The public view of one row's state. Single site, so the picker's own
 * renderers and an external consumer can never read the state differently. */
function toSnapshot(state: RowState): ModelStatusSnapshot {
  return {
    status: state.status,
    progress: state.status === 'downloading' ? state.progress : 0,
    phase: state.status === 'downloading' ? state.phase : undefined,
    detail: state.status === 'downloading' ? describePhase(state) : undefined,
    indeterminate: state.status === 'downloading' ? state.measured !== true : undefined,
    error: state.status === 'error' ? state.error : undefined,
    retryable: state.status === 'error' ? state.retryable : undefined,
  };
}

/** True once a model is downloaded and successfully loaded. */
export function isModelLoaded(modelId: string): boolean {
  return getModelStatus(modelId).status === 'loaded';
}

/**
 * Ensure a model is downloaded and loaded, reusing the picker's download/load
 * pipeline (progress + toolbar sync included). No-ops when already loaded.
 * Resolves `true` on success, `false` on any failure (the error surfaces via
 * the shared row state + a toast, matching the picker's behavior).
 */
export async function ensureModelReady(modelId: string): Promise<boolean> {
  const status = getModelStatus(modelId).status;
  if (status === 'loaded') return true;

  if (status !== 'downloaded') {
    await startDownload(modelId);
    if (getModelStatus(modelId).status !== 'downloaded') return false;
  }

  await loadModel(modelId);
  return getModelStatus(modelId).status === 'loaded';
}

// ---------------------------------------------------------------------------
// Rendering — bottom sheet
// ---------------------------------------------------------------------------

function renderSheet(): void {
  searchQuery = '';
  expandedOrgs.clear();

  // The shell — backdrop, header, Close, Escape, focus trap, focus restore —
  // belongs to `openModal`; this function owns only the picker's own body.
  // Focus is deliberately left on the sheet rather than the search field: this
  // opens from a tap on a phone, where focusing the input would raise the
  // keyboard over the list the user came to read.
  const modal = openModal({
    title: activeSheetOptions.title ?? 'Select Model',
    titleId: 'model-sheet-title',
    onClose: () => {
      modalEl = null;
      activeSheetOptions = {};
      searchQuery = '';
    },
  });
  modalEl = modal.root;
  closeActiveSheet = modal.close;

  modal.body.innerHTML = `
    <div id="model-sheet-banner"></div>
    <div class="model-search">
      ${icon('search', { size: 16, className: 'model-search__icon' })}
      <input id="model-sheet-search" class="model-search__input" type="search"
        placeholder="Search models, capabilities…" aria-label="Search models"
        autocomplete="off" spellcheck="false" />
    </div>
    <button type="button" class="btn btn-secondary btn-sm model-sheet-hf-btn" id="model-sheet-hf-btn">
      ${icon('plus', { size: 16 })}
      Add from Hugging Face
    </button>
    <div id="model-sheet-list"></div>
  `;

  const searchInput = modalEl.querySelector('#model-sheet-search') as HTMLInputElement;
  searchInput.addEventListener('input', () => {
    searchQuery = searchInput.value;
    renderRows();
  });

  modalEl.querySelector('#model-sheet-hf-btn')!.addEventListener('click', () => {
    openAddFromHuggingFace();
  });

  // Probe hardware once, then re-render the banner + recommended section. The
  // list renders immediately (state-grouped) so the sheet is never blank while
  // the async capability probe resolves.
  void ensureCapabilities().then(() => {
    if (modalEl) {
      if (catalogRegistered) hydrateRowStatesFromRegistry();
      renderBanner();
      renderRows();
    }
  });

  // Always re-read the registry when opening the sheet so OPFS-hydrated
  // downloads (or loads from other tabs) are not stuck on "Download".
  if (catalogRegistered) hydrateRowStatesFromRegistry();
  renderBanner();
  renderRows();
}

/** Detect + cache hardware capabilities and the derived recommendation set. */
async function ensureCapabilities(): Promise<void> {
  if (capabilitiesCache) return;
  try {
    capabilitiesCache = await detectDeviceCapabilities();
    recommendationCache = recommendModels(
      capabilitiesCache.tier,
      capabilitiesCache.memoryBudgetBytes,
      getCatalog(),
    );
  } catch (err) {
    appLogger.warning('[model-selection] capability probe failed', err);
  }
}

function renderBanner(): void {
  const host = modalEl?.querySelector('#model-sheet-banner') as HTMLElement | null;
  if (!host) return;

  // An engine failure outranks the hardware banner. "Recommended for your
  // device / WebGPU · 32 GB · High-performance" above a list where nothing can
  // load is the single most misleading thing this sheet can say, and the reason
  // the picker used to send people into a download that could never succeed.
  const scoped = scopedEntries();
  const failures = failuresForEntries(scoped);
  const rechecking = isRetryingForEntries(scoped);
  if (failures.length > 0 || rechecking) {
    renderEngineFailureBanner(host, failures, rechecking);
    return;
  }

  const caps = capabilitiesCache;
  if (!caps) {
    host.innerHTML = '';
    return;
  }
  host.innerHTML = `
    <div class="device-banner device-banner--${caps.tier}">
      <div class="device-banner__glyph">
        ${icon('chip', { size: 24 })}
      </div>
      <div class="device-banner__text">
        <div class="device-banner__title">Recommended for your device</div>
        <div class="device-banner__meta">${escapeHtml(describeCapabilities(caps))}</div>
      </div>
    </div>
  `;
}

/**
 * The banner shown in place of the device banner when an engine failed.
 *
 * Structure mirrors `.device-banner` so the sheet's layout doesn't shift: same
 * glyph/text arrangement, a warning tone instead of the brand gradient, one
 * Retry action, and the raw diagnostic folded into a `<details>` — useful when
 * a developer is debugging their own build, invisible when a consumer isn't.
 */
function renderEngineFailureBanner(
  host: HTMLElement,
  failures: readonly EngineFailure[],
  rechecking: boolean,
): void {
  const retryBtn = canRetryEngines()
    ? `<button type="button" class="btn btn-secondary btn-sm" id="model-sheet-engine-retry" ${rechecking ? 'disabled' : ''}>
         ${rechecking ? 'Re-checking&hellip;' : 'Retry setup'}
       </button>`
    : '';
  host.innerHTML = `
    <div class="engine-banner" role="status">
      <div class="engine-banner__glyph">
        ${icon('warning', { size: 24 })}
      </div>
      <div class="engine-banner__text">
        <div class="engine-banner__title">${rechecking ? 'Re-checking the AI engine' : 'On-device AI engine unavailable'}</div>
        <div class="engine-banner__meta">${escapeHtml(
          rechecking
            ? 'Loading the on-device AI engine again…'
            : describeFailures(failures),
        )}</div>
        ${failures.length > 0
          ? `<details class="engine-banner__details">
               <summary>Technical details</summary>
               <pre class="engine-banner__diagnostic"></pre>
             </details>`
          : ''}
      </div>
      ${retryBtn}
    </div>
  `;
  // The diagnostic is upstream text (fetch/WASM messages, possibly a URL), so
  // it goes in as textContent and never as markup.
  const diagnostic = host.querySelector<HTMLPreElement>('.engine-banner__diagnostic');
  if (diagnostic) diagnostic.textContent = failureDiagnostics(failures);
  host.querySelector('#model-sheet-engine-retry')?.addEventListener('click', () => {
    void runEngineRetry();
  });
}

/**
 * Re-exported so the views that already import it from here keep working while
 * `engine-notice` owns the single implementation. One retry, one set of
 * outcome messages — a second copy would be free to drift.
 */
export { runEngineRetry };

function closeSheet(): void {
  // State is reset in the modal's `onClose`, so dismissing via Escape, the
  // backdrop, or the Close button cannot leave `activeSheetOptions` pointing at
  // a consumer that is no longer on screen.
  closeActiveSheet?.();
  closeActiveSheet = null;
}

/**
 * The catalog entries this sheet is currently showing.
 *
 * Shared with the banner so a modality-scoped sheet (Transcribe → speech only)
 * cannot warn about an engine none of its visible rows use.
 */
function scopedEntries(): CatalogEntry[] {
  const allEntries = getCatalog();
  const filterCats = activeSheetOptions.filterCategories;
  return filterCats && filterCats.length > 0
    ? allEntries.filter((entry) => filterCats.includes(entry.category))
    : [...allEntries];
}

function renderRows(): void {
  const host = document.getElementById('model-sheet-list');
  if (!host) return;

  const scoped = scopedEntries();
  if (!scoped.length) {
    host.innerHTML = '<p class="text-secondary">No models registered.</p>';
    bindRowActions(host);
    return;
  }

  const query = searchQuery.trim().toLowerCase();
  const matches = (entry: CatalogEntry): boolean => matchesSearch(entry, query);

  const recommendedIds = recommendedIdSet();
  const recommendedHtml = renderRecommendedSection(scoped, recommendedIds, matches);

  // Everything not surfaced as a recommendation is grouped into family cards,
  // filtered by the search query. Recommended entries stay only in the block
  // above so the family list reads as "browse the rest".
  const rest = scoped.filter((entry) => !recommendedIds.has(entry.id) && matches(entry));
  const familiesHtml = renderFamilySection(rest, recommendedHtml.length > 0);

  const body = recommendedHtml + familiesHtml;
  host.innerHTML = body || '<p class="model-empty text-secondary">No models match your search.</p>';

  bindRowActions(host);
  bindFamilyInteractions(host);
}

type ModelAction = 'download' | 'load' | 'unload' | 'select' | 'cancel-download';

function bindRowActions(host: HTMLElement): void {
  host.querySelectorAll('[data-action]').forEach((el) => {
    const btn = el as HTMLButtonElement;
    const action = btn.dataset.action as ModelAction;
    const modelId = btn.dataset.modelId!;
    btn.addEventListener('click', (event) => {
      event.stopPropagation();
      void handleAction(action, modelId);
    });
  });
}

/** Wire org-card expand toggles. */
function bindFamilyInteractions(host: HTMLElement): void {
  host.querySelectorAll('[data-family-toggle]').forEach((el) => {
    el.addEventListener('click', () => {
      const key = (el as HTMLElement).dataset.familyToggle!;
      if (expandedOrgs.has(key)) expandedOrgs.delete(key);
      else expandedOrgs.add(key);
      renderRows();
    });
  });
}

/** Ids surfaced in the recommended block (excluded from the family list). */
function recommendedIdSet(): Set<string> {
  const ids = new Set<string>();
  const rec = recommendationCache;
  if (!rec) return ids;

  const filterCats = activeSheetOptions.filterCategories;
  // Modality-scoped pickers (Vision/Transcribe/Speak/Documents) still get a
  // recommended highlight — just the one entry relevant to that modality —
  // so every single-modality tab opens on its best-for-device default.
  if (filterCats && filterCats.length > 0) {
    for (const category of filterCats) {
      const entry = recommendedForCategory(rec, category);
      if (entry) ids.add(entry.id);
    }
    return ids;
  }

  for (const llm of rec.recommendedLLMs) ids.add(llm.id);
  const { asr, tts, vlm, embedding } = rec.companions;
  for (const companion of [asr, tts, vlm, embedding]) {
    if (companion) ids.add(companion.id);
  }
  return ids;
}

/** The single recommended entry for a modality category, when one exists. */
function recommendedForCategory(
  rec: RecommendedSelection,
  category: ModelCategory,
): CatalogEntry | null {
  switch (category) {
    case ModelCategory.MODEL_CATEGORY_LANGUAGE:
      return rec.defaultModel;
    case ModelCategory.MODEL_CATEGORY_MULTIMODAL:
      return rec.companions.vlm;
    case ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION:
      return rec.companions.asr;
    case ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:
      return rec.companions.tts;
    case ModelCategory.MODEL_CATEGORY_EMBEDDING:
      return rec.companions.embedding;
    default:
      return null;
  }
}

/**
 * Render the "Recommended for your device" block. For the full (Chat) picker
 * this is the default LLM highlighted + the other recommended LLMs, followed by
 * a compact "Also recommended" companion row. For a modality-scoped picker it's
 * simply the single best-for-device model for that modality, highlighted.
 * Returns '' when nothing is recommended in scope.
 */
function renderRecommendedSection(
  scoped: readonly CatalogEntry[],
  recommendedIds: Set<string>,
  matches: (entry: CatalogEntry) => boolean,
): string {
  const rec = recommendationCache;
  if (!rec || recommendedIds.size === 0) return '';

  const scopedById = new Map(scoped.map((entry) => [entry.id, entry]));
  const inScope = (entry: CatalogEntry | null | undefined): entry is CatalogEntry =>
    entry != null && scopedById.has(entry.id) && matches(entry);

  const isScoped = (activeSheetOptions.filterCategories?.length ?? 0) > 0;
  const defaultId = rec.defaultModel?.id;

  if (isScoped) {
    // One highlighted card per recommended-in-scope entry (usually exactly one).
    const cards = [...recommendedIds]
      .map((id) => scopedById.get(id))
      .filter(inScope)
      .map((entry) => renderRecommendedCard(entry, stateOf(entry.id), true))
      .join('');
    if (!cards) return '';
    return recommendedShell(`<div class="reco-grid">${cards}</div>`, '');
  }

  const llms = rec.recommendedLLMs.filter(inScope);
  const companions = [rec.companions.vlm, rec.companions.asr, rec.companions.tts, rec.companions.embedding]
    .filter(inScope);
  if (llms.length === 0 && companions.length === 0) return '';

  const llmCards = llms
    .map((entry) => renderRecommendedCard(entry, stateOf(entry.id), entry.id === defaultId))
    .join('');
  const companionRows = companions.length > 0
    ? `
      <div class="model-subsection__title">Also recommended</div>
      ${companions.map((entry) => renderModelRow(entry, stateOf(entry.id))).join('')}
    `
    : '';

  return recommendedShell(`<div class="reco-grid">${llmCards}</div>`, companionRows);
}

/** Wrap recommended content in the titled section shell. */
function recommendedShell(cardsHtml: string, companionRows: string): string {
  return `
    <div class="model-section model-section--recommended">
      <div class="model-section__title model-section__title--reco">
        ${icon('star', { size: 16 })}
        Recommended
      </div>
      ${cardsHtml}
      ${companionRows}
    </div>
  `;
}

/** Group the remaining catalog into organisation cards. */
function renderFamilySection(entries: readonly CatalogEntry[], hasRecommended: boolean): string {
  if (entries.length === 0) return '';

  const orgs = groupByOrg(entries);
  if (orgs.length === 0) return '';

  const ready = orgs.filter((org) =>
    org.entries.some((entry) => ['downloaded', 'loaded'].includes(stateOf(entry.id).status)));
  const rest = orgs.filter((org) => !ready.includes(org));

  const sections: string[] = [];
  if (ready.length > 0) {
    sections.push(renderOrgSection('On this device', ready));
  }
  if (rest.length > 0) {
    const heading = ready.length === 0
      ? (hasRecommended ? 'All organisations' : 'All organisations')
      : 'More organisations';
    sections.push(renderOrgSection(heading, rest));
  }
  return sections.join('');
}

function renderOrgSection(heading: string, orgs: OrgGroup[]): string {
  const cards = orgs.map((org) => renderOrgCard(org)).join('');
  return `
    <div class="model-section">
      <div class="model-section__title">${escapeHtml(heading)}</div>
      <div class="family-list">${cards}</div>
    </div>
  `;
}

interface OrgGroup {
  key: string;
  name: string;
  entries: CatalogEntry[];
}

/** Bucket entries by organisation, preserving matcher declaration order. */
function groupByOrg(entries: readonly CatalogEntry[]): OrgGroup[] {
  const groups = new Map<string, OrgGroup>();
  const order: string[] = [];
  for (const entry of entries) {
    const org = modelOrg(entry);
    const existing = groups.get(org.key);
    if (existing) {
      existing.entries.push(entry);
    } else {
      groups.set(org.key, {
        key: org.key,
        name: org.name,
        entries: [entry],
      });
      order.push(org.key);
    }
  }
  // Sort models within each org smaller → larger (by advertised bytes).
  for (const group of groups.values()) {
    group.entries.sort((a, b) => modelDisplaySizeBytes(a) - modelDisplaySizeBytes(b));
  }
  return order.map((key) => groups.get(key)!);
}

/**
 * A rounded org card: publisher name, NPU/ready status, and model count.
 * Tapping toggles an expanded list of models.
 */
function renderOrgCard(org: OrgGroup): string {
  const expanded = expandedOrgs.has(org.key) || searchQuery.trim().length > 0;
  const options = org.entries.length;
  const representative = pickRepresentative(org.entries);
  const activeEntry = org.entries.find((entry) => stateOf(entry.id).status === 'loaded');
  const onDevice = org.entries.some((entry) =>
    ['downloaded', 'loaded'].includes(stateOf(entry.id).status));
  const hasNpu = org.entries.some((entry) =>
    formatFramework(entry.framework).toLowerCase().includes('npu')
    || `${entry.id} ${entry.name}`.toLowerCase().includes('hnpu'));

  const statusPill = activeEntry
    ? '<span class="family-card__status family-card__status--active">Active</span>'
    : onDevice
      ? '<span class="family-card__status">On device</span>'
      : '';
  const npuPill = hasNpu
    ? '<span class="tag-pill tag-pill--capability">NPU</span>'
    : '';

  const variants = expanded
    ? `<div class="family-variants">${renderOrgVariants(org)}</div>`
    : '';

  return `
    <div class="family-card${expanded ? ' family-card--expanded' : ''}" data-family-key="${escapeHtml(org.key)}">
      <button type="button" class="family-card__head" data-family-toggle="${escapeHtml(org.key)}" aria-expanded="${expanded}">
        <div class="model-logo family-card__logo">${icon(modalityIcon(representative.category), { size: 20 })}</div>
        <div class="family-card__body">
          <div class="family-card__name-row">
            <span class="family-card__name">${escapeHtml(org.name)}</span>
            ${npuPill}
            ${statusPill}
          </div>
          <div class="family-card__tagline">${options} ${options === 1 ? 'model' : 'models'}</div>
        </div>
        <div class="family-card__aside">
          <span class="family-card__count">${options} ${options === 1 ? 'model' : 'models'}</span>
          ${icon('chevronDown', { size: 16, className: 'family-card__chevron' })}
        </div>
      </button>
      ${variants}
    </div>
  `;
}

/** Render an org's models once expanded. */
function renderOrgVariants(org: OrgGroup): string {
  const best = bestVariantForDevice(org.entries);
  return org.entries
    .map((entry) => renderVariantRow(entry, entry.id === best?.id))
    .join('');
}

/**
 * What this phase is doing, in one line.
 *
 * The post-transfer phases replace the readout outright rather than appending to
 * it: every byte is already on disk by then, so leaving the last measured rate
 * on screen while nothing is moving is the difference between "nearly done" and
 * "frozen at 99%". They keep the total size, though, because "Checking download"
 * alone loses the sense of scale that explains why the wait is long.
 *
 * Wording matches iOS `ModelDownloadPhase.label` and its `byteFragment`.
 */
function describePhase(state: RowState & { status: 'downloading' }): string {
  switch (state.phase) {
    case 'queued':
      return 'Starting…';
    case 'cancelling':
      return 'Cancelling…';
    case 'verifying':
    case 'extracting': {
      const label = state.phase === 'verifying' ? 'Checking download' : 'Unpacking';
      return state.bytesTotal
        ? `${label} · ${formatTransferBytes(state.bytesTotal)}`
        : label;
    }
    default:
      // Blank before the first byte lands — say the job is starting rather than
      // printing "0 B", which reads as a transfer that is already stuck.
      return transferDetailLine(state) || 'Starting…';
  }
}

/**
 * The progress bar plus a line saying what is happening, how fast, and how much
 * of it is done.
 *
 * Was a bare percentage bar in three places, discarding the `bytesDone` /
 * `bytesTotal` the SDK has always emitted. A percentage alone cannot answer the
 * only question a user has while waiting on a multi-gigabyte model — "how long
 * is this going to take" — and the non-transfer phases had no label at all, so
 * verification looked like a hung download stuck at 100%.
 *
 * Exported so the pipeline slots render the identical markup instead of the
 * bare bar they used to draw themselves.
 */
export function renderDownloadProgress(status: ModelStatusSnapshot): string {
  if (status.status !== 'downloading') return '';

  const percent = Math.round(status.progress * 100);
  const detail = status.detail ?? '';
  const indeterminate = status.indeterminate ?? false;

  // The percent sits at the end of the same line as the readout — the order
  // Android reads in, and the placement iOS gives it beside the bar. Both are
  // one glance apart from the bar itself, which is the point.
  return `<div class="progress-bar mt-sm${indeterminate ? ' progress-bar--indeterminate' : ''}"
      role="progressbar" aria-valuemin="0" aria-valuemax="100"
      ${indeterminate ? '' : `aria-valuenow="${percent}"`}
      aria-label="${escapeHtml(detail || 'Download progress')}">
      <div class="progress-fill" style="width:${indeterminate ? 100 : percent}%"></div>
    </div>
    <div class="progress-detail" style="display:flex;justify-content:space-between;gap:var(--space-sm)">
      <span class="progress-detail__text">${escapeHtml(detail)}</span>
      <span class="progress-detail__percent">${indeterminate ? '' : `${percent}%`}</span>
    </div>`;
}

/**
 * The note under a row whose download stopped part-way.
 *
 * The two cases look identical on disk — bytes present, nothing transferring —
 * but they are opposite events: one is a fault, one is the user's own decision.
 * Colouring a deliberate cancel in error red, or offering "Retry" for something
 * that never failed, reads as the app having lost track of what happened.
 *
 * Both variants say the bytes are kept, because the reasonable fear about a
 * half-finished multi-gigabyte download is that continuing means starting from
 * zero. It does not. Wording matches Android `DownloadInterruptionNote`.
 */
function renderInterruptionNote(entryId: string, state: RowState): string {
  if (state.status === 'paused') {
    return '<div class="model-row-error">Paused — resume picks up where it stopped</div>';
  }
  if (state.status !== 'error') return '';
  // A failure that cannot be retried must not imply one: the message says what
  // is wrong, and the row's control is disabled rather than inviting a click
  // into the identical error. The id is what that disabled control points its
  // `aria-describedby` at, so the reason is announced with it.
  const follow = state.retryable && state.stage === 'download'
    ? ' Retry resumes where it stopped.'
    : '';
  return `<div class="model-row-error error" id="download-note-${escapeHtml(entryId)}">${escapeHtml(state.error)}${follow}</div>`;
}

/** A single variant row inside an expanded family. */
function renderVariantRow(entry: CatalogEntry, bestForDevice: boolean): string {
  const state = stateOf(entry.id);
  const isBest = bestForDevice && isRecommendable(entry);
  const progressBar = renderDownloadProgress(toSnapshot(state));
  const errorBar = renderInterruptionNote(entry.id, state);
  const bestBadge = isBest
    ? '<span class="variant-row__best">Best for this device</span>'
    : '';
  const capability = modelCapability(entry);
  const capabilityPill = capability
    ? `<span class="tag-pill tag-pill--capability">${escapeHtml(capability)}</span>`
    : '';
  const compatibilityReason = renderCompatibilityReason(entry);

  return `
    <div class="variant-row variant-row--${state.status}${isBest ? ' variant-row--best' : ''}" data-model-id="${escapeHtml(entry.id)}">
      <div class="variant-row__info">
        <div class="variant-row__name">${escapeHtml(cleanModelName(entry.name))}${bestBadge}</div>
        <div class="variant-row__meta">
          <span class="variant-row__size">${formatModelSize(modelDisplaySizeBytes(entry))}</span>
          ${renderBackendPill(entry)}
          <span class="variant-row__feel">${escapeHtml(variantSizeFeel(entry))}</span>
          ${capabilityPill}
        </div>
        ${compatibilityReason}
        ${progressBar}
        ${errorBar}
      </div>
      ${actionButton(entry, state)}
    </div>
  `;
}

/** Small neutral pill naming the inference backend (llama.cpp / ONNX / Sherpa). */
function renderBackendPill(entry: CatalogEntry): string {
  return `<span class="backend-pill">${escapeHtml(formatFramework(entry.framework))}</span>`;
}

/** Choose the card's representative entry (the best-for-device variant). */
function pickRepresentative(entries: CatalogEntry[]): CatalogEntry {
  return bestVariantForDevice(entries) ?? entries[0];
}

/**
 * Auto-select the best variant for the device: the largest entry that still
 * fits the tier memory budget (smarter is better when it fits), falling back to
 * the smallest entry when none fit. Pure w.r.t. the cached capabilities.
 */
function bestVariantForDevice(entries: CatalogEntry[]): CatalogEntry | undefined {
  if (entries.length === 0) return undefined;
  const budget = capabilitiesCache?.memoryBudgetBytes ?? Number.POSITIVE_INFINITY;
  const fitting = entries.filter((entry) => entry.memoryRequiredBytes <= budget);
  if (fitting.length > 0) {
    // Largest that still fits — smarter is better when it comfortably fits.
    return [...fitting].sort((a, b) => modelDisplaySizeBytes(b) - modelDisplaySizeBytes(a))[0];
  }
  // Nothing fits the budget: fall back to the smallest so it's at least usable.
  return [...entries].sort((a, b) => modelDisplaySizeBytes(a) - modelDisplaySizeBytes(b))[0];
}

/** Read-through row state accessor with a sensible default. */
function stateOf(id: string): RowState {
  return rowStates.get(id) ?? { status: 'registered' };
}

/**
 * Match against friendly, consumer-facing signals only — model name, org
 * name, size feel, and consumer tags. Deliberately excludes quant strings
 * and inference backend names.
 */
function matchesSearch(entry: CatalogEntry, query: string): boolean {
  if (!query) return true;
  const org = modelOrg(entry);
  const normalize = (value: string): string => value.toLowerCase().replace(/[-_./]+/g, ' ');
  const haystack = normalize([
    entry.id,
    entry.name,
    entry.description,
    org.name,
    variantSizeFeel(entry),
    ...consumerTags(entry).map((tag) => tag.label),
  ].join(' '));
  const needle = normalize(query).trim();
  return needle.length === 0 || haystack.includes(needle);
}

/** Render a rich recommended card with a single clean tag row. */
function renderRecommendedCard(entry: CatalogEntry, state: RowState, bestForDevice: boolean): string {
  // "Best for this device" is a recommendation, and recommending a model that
  // cannot run is worse than recommending nothing: it is the row a first-time
  // user reaches for. Strip the badge and the brand highlight when the row is
  // not actionable, and let the disabled button + reason speak instead.
  const isDefault = bestForDevice && isRecommendable(entry);
  const tags = consumerTags(entry).map(renderTagPill).join('');
  const progressBar = renderDownloadProgress(toSnapshot(state));
  const errorBar = renderInterruptionNote(entry.id, state);
  const bestBadge = isDefault
    ? '<span class="reco-card__best">Best for this device</span>'
    : '';
  const compatibilityReason = renderCompatibilityReason(entry);
  return `
    <div class="reco-card${isDefault ? ' reco-card--default' : ''} reco-card--${state.status}" data-model-id="${escapeHtml(entry.id)}">
      <div class="reco-card__head">
        <div class="model-logo reco-card__logo">${icon(modalityIcon(entry.category), { size: 20 })}</div>
        <div class="reco-card__title-wrap">
          <div class="reco-card__name">${escapeHtml(cleanModelName(entry.name))}${bestBadge}</div>
          <div class="reco-card__size">${formatModelSize(modelDisplaySizeBytes(entry))} ${renderBackendPill(entry)}</div>
          <div class="reco-card__tags">${tags}</div>
        </div>
        ${actionButton(entry, state)}
      </div>
      ${compatibilityReason}
      ${progressBar}
      ${errorBar}
    </div>
  `;
}

function renderTagPill(tag: ConsumerTag): string {
  return `<span class="tag-pill tag-pill--${tag.kind}">${escapeHtml(tag.label)}</span>`;
}

/** Compact companion row (ASR/TTS/VLM/embedding): name, size + backend, tag. */
function renderModelRow(entry: CatalogEntry, state: RowState): string {
  const progressBar = renderDownloadProgress(toSnapshot(state));
  const errorBar = renderInterruptionNote(entry.id, state);
  const capability = modelCapability(entry);
  const capabilityPill = capability
    ? `<span class="tag-pill tag-pill--capability">${escapeHtml(capability)}</span>`
    : '';
  const compatibilityReason = renderCompatibilityReason(entry);
  return `
    <div class="model-row model-row--${state.status}" data-model-id="${escapeHtml(entry.id)}">
      <div class="model-logo">${icon(modalityIcon(entry.category), { size: 20 })}</div>
      <div class="model-info">
        <div class="model-name">${escapeHtml(cleanModelName(entry.name))}</div>
        <div class="model-meta">
          <span class="model-size">${formatModelSize(modelDisplaySizeBytes(entry))}</span>
          ${renderBackendPill(entry)}
          ${capabilityPill}
        </div>
        ${compatibilityReason}
        ${progressBar}
        ${errorBar}
      </div>
      ${actionButton(entry, state)}
    </div>
  `;
}

/**
 * Every reason this row might not be actionable, resolved to one.
 *
 * Size first, engine second: the 4 GiB WASM32 ceiling is a permanent property
 * of this model on the Web, while a failed registration is usually transient.
 * Telling someone to retry an engine for a model that could never fit would
 * send them around a loop that cannot end.
 */
function compatibilityFor(entry: CatalogEntry): WebModelCompatibility {
  const size = webModelCompatibility(entry, {
    hasWebGPU: capabilitiesCache?.hasWebGPU,
  });
  if (!size.supported) return size;
  return engineCompatibility(entry);
}

/** Can this row be held up as a recommendation right now? */
function isRecommendable(entry: CatalogEntry): boolean {
  return compatibilityFor(entry).supported;
}

function renderCompatibilityReason(entry: CatalogEntry): string {
  const compatibility = compatibilityFor(entry);
  if (compatibility.supported) return '';
  const reference = compatibility.reference
    ? ` <a href="${escapeHtml(compatibility.reference.url)}" target="_blank" rel="noopener noreferrer">${escapeHtml(compatibility.reference.label)} &nearr;</a>`
    : '';
  return `<div class="model-compatibility-reason" id="model-compatibility-${escapeHtml(entry.id)}" data-compatibility-code="${compatibility.code}">${escapeHtml(compatibility.reason)}${reference}</div>`;
}

function actionButton(entry: CatalogEntry, state: RowState): string {
  const safeModelId = escapeHtml(entry.id);
  const compatibility = compatibilityFor(entry);
  if (!compatibility.supported && state.status !== 'loaded') {
    return `<button type="button" class="model-action-btn model-action-btn--unavailable" data-model-id="${safeModelId}" data-compatibility-code="${compatibility.code}" aria-describedby="model-compatibility-${safeModelId}" disabled>${escapeHtml(compatibility.actionLabel)}</button>`;
  }
  switch (state.status) {
    case 'registered':
      return `<button type="button" class="model-action-btn download" data-action="download" data-model-id="${safeModelId}">Download</button>`;
    case 'paused':
      // "Resume" after a cancelled transfer, because that is what happens: the
      // partial bytes were kept and the next attempt continues from them.
      // Saying "Download" would imply the wait starts over.
      return `<button type="button" class="model-action-btn download" data-action="download" data-model-id="${safeModelId}" title="Continue from where this stopped">Resume</button>`;
    case 'downloading':
      // Cancellable while bytes are still being fetched — including the queued
      // phase, where the wait can be the longest part of a multi-file plan.
      // Verifying and extracting are short, local, and have no transfer left to
      // abandon, so a Cancel there would be a button that misses its own window.
      //
      // The percentage moved to the progress detail line, which frees this slot
      // for the control a waiting user actually wants. It was previously a
      // disabled button showing a number already rendered directly below it.
      if (state.phase === 'queued' && !activeDownloads.has(entry.id)) {
        // The plan/quota preflight runs before there is an iterator to break out
        // of, so there is nothing a Cancel could stop yet. A button that does
        // nothing is worse than no button.
        return '<button type="button" class="model-action-btn model-action-btn--progress" disabled>Starting&hellip;</button>';
      }
      if (state.phase === 'queued' || state.phase === 'transferring') {
        return `<button type="button" class="model-action-btn model-action-btn--cancel" data-action="cancel-download" data-model-id="${safeModelId}" title="Stop this download — the bytes already fetched are kept">Cancel</button>`;
      }
      // Once the stop is under way the control has nothing left to do, and a
      // second tap has nothing to cancel. It says so rather than looking live.
      return `<button type="button" class="model-action-btn model-action-btn--progress" disabled>${
        state.phase === 'cancelling'
          ? 'Cancelling&hellip;'
          : state.phase === 'verifying' ? 'Checking&hellip;' : 'Unpacking&hellip;'
      }</button>`;
    case 'downloaded':
      return `<button type="button" class="model-action-btn load" data-action="load" data-model-id="${safeModelId}">Use</button>`;
    case 'loading':
      return `<button type="button" class="model-action-btn model-action-btn--progress" disabled>Loading&hellip;</button>`;
    case 'loaded':
      if (activeSheetOptions.onModelReady) {
        return `<button type="button" class="model-action-btn loaded" data-action="select" data-model-id="${safeModelId}">&#10003; Use</button>`;
      }
      return `<button type="button" class="model-action-btn loaded" data-action="unload" data-model-id="${safeModelId}" title="Tap to unload">&#10003; Active</button>`;
    case 'error':
      // THE DEAD-END RETRY. Every failure used to render this button, including
      // the download-plan refusals that are decided before a single byte is
      // requested — an unresolvable file list, a partial that no longer matches
      // the server, a backend that never answered the planner. Pressing it
      // replayed the identical plan and produced the identical message, forever.
      // The SDK already publishes the verdict on `SDKError.retryable`; when it
      // says no, the control says no too, and the note above it carries the
      // reason and the actual next step.
      if (!state.retryable) {
        return `<button type="button" class="model-action-btn model-action-btn--unavailable" data-model-id="${safeModelId}" aria-describedby="download-note-${safeModelId}" disabled>Can&rsquo;t download</button>`;
      }
      return `<button type="button" class="model-action-btn model-action-btn--retry" data-action="${state.stage === 'load' ? 'load' : 'download'}" data-model-id="${safeModelId}">Retry</button>`;
  }
}

// ---------------------------------------------------------------------------
// Actions — download / load / unload
// ---------------------------------------------------------------------------

async function handleAction(action: ModelAction, modelId: string): Promise<void> {
  if (action === 'download') await startDownload(modelId);
  else if (action === 'load') {
    // Capture before awaiting: closing/reopening a sheet while a model loads
    // must not redirect the completed selection to a different consumer.
    const onModelReady = activeSheetOptions.onModelReady;
    const sourceModal = modalEl;
    if (await loadModel(modelId)) {
      completeSheetSelection(modelId, onModelReady, sourceModal);
    }
  }
  else if (action === 'unload') await unloadModel(modelId);
  else if (action === 'cancel-download') await cancelModelDownload(modelId);
  else if (action === 'select') {
    completeSheetSelection(modelId, activeSheetOptions.onModelReady, modalEl);
  }
}

/**
 * Stop an in-flight download.
 *
 * `models.download()` cancels the transfer when its iterator is broken out of,
 * and keeps the resume token — so this is also what makes a later Download
 * click continue rather than restart. Without a control there was no way to
 * stop a multi-gigabyte transfer short of closing the tab, which loses the
 * partial file and the token with it.
 *
 * The generator emits `cancelled` on the way out, and that branch is what moves
 * the row to `paused`; doing it here as well would race it.
 *
 * Exported as `cancelModelDownload` for the Downloads tab, which lists the same
 * transfers; a tab named for them that could only watch was the odd one out.
 * Same verb, same preserved bytes, same resulting `paused` row — one call.
 */
export async function cancelModelDownload(modelId: string): Promise<void> {
  const iterator = activeDownloads.get(modelId);
  if (!iterator) return;
  activeDownloads.delete(modelId);
  // Winding a transfer down is not instant — the SDK has to tell the native
  // orchestrator and wait for it to stop. Saying so is what stops a tap that
  // did land from looking exactly like one that was ignored.
  const state = rowStates.get(modelId);
  if (state?.status === 'downloading') {
    setRow(modelId, { ...state, phase: 'cancelling', measured: false });
  }
  try {
    await iterator.return?.(undefined);
  } catch {
    // A generator that already finished rejects here; the row state is
    // whatever its terminal event set, which is correct either way.
  }
}

/**
 * Whether a Cancel offered for this model would actually stop something.
 *
 * Two conditions, both of which a surface outside this module cannot see: an
 * iterator has to exist (the plan/quota preflight runs before there is one, so
 * a `queued` row can still have nothing to break out of), and bytes have to
 * still be arriving — `verifying`, `extracting` and an in-flight `cancelling`
 * are local wind-down phases a Cancel would simply miss.
 *
 * Exported so the Downloads tab and the picker cannot disagree about whether
 * the same transfer can still be stopped; the picker applies the same rule
 * inline because it also has to name the phase on the disabled button.
 */
export function isDownloadCancellable(modelId: string): boolean {
  if (!activeDownloads.has(modelId)) return false;
  const state = rowStates.get(modelId);
  return state?.status === 'downloading'
    && (state.phase === 'queued' || state.phase === 'transferring');
}

/**
 * The size a finished transfer measured, for the phases that follow it.
 *
 * `verifying` / `extracting` / `cancelling` carry no byte counts of their own,
 * so without this the detail line would drop the one number that explains why
 * the wait is long. Mirrors Android's `latest.copy(...)` fold.
 */
function transferCarryOver(modelId: string): { bytesDone?: number; bytesTotal?: number } {
  const state = rowStates.get(modelId);
  return state?.status === 'downloading'
    ? { bytesDone: state.bytesDone, bytesTotal: state.bytesTotal }
    : {};
}

/**
 * Record a failed download and say so once.
 *
 * `retryable` comes from the SDK rather than being assumed: the planner refuses
 * some models permanently (an unresolvable file list, a partial that no longer
 * matches the server) and those refusals must not be dressed up as a transient
 * hiccup with a Retry beside them.
 */
function failDownload(modelId: string, message: string, retryable: boolean): void {
  setRow(modelId, { status: 'error', error: message, stage: 'download', retryable });
  showToast(
    retryable ? `Download failed: ${message}` : `Can’t download this model: ${message}`,
    'warning',
    retryable ? undefined : 8000,
  );
}

/**
 * The SDK's own verdict on whether trying again could end differently.
 *
 * Reads `SDKException.proto.retryable` — set by `throwDownloadFailure` in the
 * Web SDK from the planner's failure reason. Anything that is not a recognisable
 * SDK error is treated as retryable: an unknown fault is more likely a blip than
 * a permanent refusal, and the failure branch above still states what happened.
 */
function isRetryable(err: unknown): boolean {
  const proto = (err as { proto?: { retryable?: unknown } } | null)?.proto;
  return typeof proto?.retryable === 'boolean' ? proto.retryable : true;
}

async function startDownload(modelId: string): Promise<void> {
  const entry = getCatalog().find((candidate) => candidate.id === modelId);
  if (entry) {
    const compatibility = compatibilityFor(entry);
    if (!compatibility.supported) {
      showToast(compatibility.reason, 'warning');
      return;
    }
  }

  // Everything from here to the first byte — re-seeding the registry, asking for
  // persistent storage, planning, opening the connection — is time the user is
  // waiting after their click, and it can run to seconds on a multi-file model.
  // The row says so from the click rather than from the first progress event.
  // Restored on every path that gives up before a transfer starts, so an
  // abandoned attempt never leaves a row claiming to be queued.
  const previousState = stateOf(modelId);
  setRow(modelId, { status: 'downloading', progress: 0, phase: 'queued' });
  const abandon = (): void => setRow(modelId, previousState);

  let model = RunAnywhere.models.get(modelId);
  if (!model && entry) {
    // Catalog UI can outlive a partial registry wipe (backend re-register).
    // Re-seed the declarative entry before failing the Download click.
    try {
      const { registerModelCatalog } = await import('../services/model-catalog');
      registerModelCatalog();
      model = RunAnywhere.models.get(modelId);
    } catch {
      /* fall through */
    }
  }
  if (!model) {
    abandon();
    showToast(`Model ${modelId} not found in registry`, 'warning');
    return;
  }

  const requiredBytes = entry
    ? modelDisplaySizeBytes(entry)
    : (() => {
      const parsed = Number(model.downloadSizeBytes ?? 0);
      return Number.isFinite(parsed) ? Math.max(0, parsed) : 0;
    })();

  // First async step after the Download click — request persist() while the
  // user gesture is still active, then verify origin quota.
  const storage = await ensureDownloadStorageReady({ requiredBytes });
  if (requiredBytes > 0 && !storage.sufficient) {
    const fallbackMessage = RunAnywhere.storage.isSupported
      ? 'Free space or open Storage → Choose Storage Folder.'
      : 'Please free up space in your browser.';
    abandon();
    showToast(
      `Not enough browser storage for this model (need ${formatBytes(requiredBytes)}, `
        + `${formatBytes(storage.availableBytes)} free). ${fallbackMessage}`,
      'warning',
      6000,
    );
    return;
  }

  // Large downloads use browser OPFS by default. Do not open the OS folder
  // picker here — it steals the Download click and is easy to dismiss while
  // the download continues anyway. Only mention Choose Storage Folder when
  // the browser supports that path and no durable folder is already active.
  if (
    requiredBytes >= LARGE_DOWNLOAD_BYTES
    && !storage.persisted
    && !RunAnywhere.storage.isReady
    && RunAnywhere.storage.isSupported
  ) {
    showToast(
      'Storing this model in browser OPFS. For a durable disk folder, open Storage → Choose Storage Folder.',
      'info',
      5000,
    );
  }

  // Rate samples for the speed readout. `performance.now()` rather than
  // Date.now() so a clock adjustment mid-download cannot produce a negative
  // interval and a nonsense speed.
  //
  // Measured here only because the Web `DownloadEvent.progress` carries just the
  // two byte counts. Swift and Kotlin receive `bytesPerSecond`/`etaSeconds`
  // straight from the C++ orchestrator, which knows the whole transfer's
  // history, and both apps say in writing that re-deriving a rate from two UI
  // samples disagrees with it. The honest fix is to widen the Web event to carry
  // the same fields; until then this is the closest approximation available.
  let lastAt = performance.now();
  let lastBytes = 0;
  let smoothed: number | undefined;

  // Iterated explicitly rather than with `for await` so Cancel has a handle to
  // break out of; that break *is* the SDK's cancellation signal.
  const events = RunAnywhere.models.download(modelId);
  const iterator = events[Symbol.asyncIterator]();
  activeDownloads.set(modelId, iterator);

  try {
    for (let step = await iterator.next(); !step.done; step = await iterator.next()) {
      const event = step.value;
      switch (event.type) {
        case 'progress': {
          const now = performance.now();
          const elapsed = (now - lastAt) / 1000;
          // Sampled over at least 400ms: a per-event rate computed across a few
          // milliseconds swings wildly and renders as an unreadable flicker.
          if (elapsed >= 0.4 && event.bytesDone > lastBytes) {
            const instant = (event.bytesDone - lastBytes) / elapsed;
            // Exponential smoothing, weighted toward history, so the number is
            // steady enough to read while still tracking a real slowdown.
            smoothed = smoothed === undefined ? instant : smoothed * 0.7 + instant * 0.3;
            lastAt = now;
            lastBytes = event.bytesDone;
          }
          const bytesTotal = event.bytesTotal > 0 ? event.bytesTotal : undefined;
          setRow(modelId, {
            status: 'downloading',
            phase: 'transferring',
            progress: bytesTotal ? event.bytesDone / bytesTotal : 0,
            // No Content-Length means no position to plot. An honest sweep beats
            // a bar pinned at zero while bytes are visibly arriving.
            measured: bytesTotal !== undefined,
            bytesDone: event.bytesDone,
            bytesTotal,
            bytesPerSecond: smoothed,
            etaSeconds: smoothed && bytesTotal
              ? Math.max(0, bytesTotal - event.bytesDone) / smoothed
              : undefined,
          });
          break;
        }
        case 'verifying':
          // Named rather than shown as a finished transfer: verifying a
          // multi-gigabyte file takes real time, and a full bar with no label
          // looks exactly like a hang. The size carries over — these events
          // repeat none of it, and a line that empties out mid-operation reads
          // as a reset.
          setRow(modelId, {
            ...transferCarryOver(modelId),
            status: 'downloading',
            phase: 'verifying',
            progress: 1,
          });
          break;
        case 'extracting':
          setRow(modelId, {
            ...transferCarryOver(modelId),
            status: 'downloading',
            phase: 'extracting',
            // `percent` is 0..100 when the SDK reports it, and absent otherwise —
            // in which case the bar sweeps rather than claiming to be finished.
            progress: event.percent === undefined ? 1 : Math.min(1, Math.max(0, event.percent / 100)),
            measured: event.percent !== undefined,
          });
          break;
        case 'cancelled':
          // Was falling into the same branch as `completed`, so a cancelled
          // download claimed the model was on disk and the next Load failed
          // with a missing-file error the user had no way to connect to it.
          setRow(modelId, { status: 'paused' });
          return;
        case 'failed':
          failDownload(modelId, event.error.message, event.error.retryable);
          return;
        case 'completed':
          setRow(modelId, { status: 'downloaded' });
          break;
        case 'started':
          break;
      }
    }
  } catch (err) {
    failDownload(modelId, formatError(err), isRetryable(err));
  } finally {
    // Covers every exit — completed, cancelled, failed, and the throw path — so
    // a stale iterator can never be handed to a later Cancel click. Guarded on
    // identity because a fresh download for the same model may already have
    // replaced this entry.
    if (activeDownloads.get(modelId) === iterator) activeDownloads.delete(modelId);
  }
}

async function loadModel(modelId: string): Promise<boolean> {
  const entry = getCatalog().find((candidate) => candidate.id === modelId);
  if (entry) {
    const compatibility = compatibilityFor(entry);
    if (!compatibility.supported) {
      showToast(compatibility.reason, 'warning');
      return false;
    }
  }
  setRow(modelId, { status: 'loading' });
  try {
    await RunAnywhere.models.load(modelId);
    await refreshLoadedByCategory();
    const loadedEntry = getCatalog().find((entry) => entry.id === modelId);
    if (loadedEntry) {
      // A category has one native "current" model. Downgrade the previous
      // choice in that category while preserving loaded rows in other
      // modalities (LLM + STT + TTS must remain simultaneously visible).
      for (const entry of getCatalog()) {
        if (entry.id === modelId || entry.category !== loadedEntry.category) continue;
        if (rowStates.get(entry.id)?.status === 'loaded') {
          rowStates.set(entry.id, { status: 'downloaded' });
        }
      }
    }
    setRow(modelId, { status: 'loaded' });
    showToast(`Loaded ${modelId}`, 'success');
    return true;
  } catch (err) {
    const message = formatError(err);
    // Stage matters for the row's control: a load failure leaves the bytes on
    // disk, so its Retry must load again rather than re-fetch a file that is
    // already there.
    setRow(modelId, { status: 'error', error: message, stage: 'load', retryable: isRetryable(err) });
    showToast(`Load failed: ${message}`, 'warning');
    return false;
  }
}

/** Complete an explicit picker choice after the entry is known to be ready. */
function completeSheetSelection(
  modelId: string,
  onModelReady: OpenSheetOptions['onModelReady'],
  sourceModal: HTMLElement | null,
): void {
  const entry = getCatalog().find((candidate) => candidate.id === modelId);
  if (entry && onModelReady) {
    try {
      onModelReady(entry);
    } catch (err) {
      appLogger.warning('[model-selection] model-ready callback threw', err);
    }
  }
  if (modalEl === sourceModal) closeSheet();
}

async function unloadModel(modelId: string): Promise<void> {
  try {
    await RunAnywhere.models.unload(modelId);
    await refreshLoadedByCategory();
    setRow(modelId, { status: 'downloaded' });
    showToast(`Unloaded ${modelId}`, 'info');
  } catch (err) {
    const message = formatError(err);
    showToast(`Unload failed: ${message}`, 'warning');
  }
}

// ---------------------------------------------------------------------------
// State + toolbar updates
// ---------------------------------------------------------------------------

/**
 * Write a live snapshot into an already-rendered `renderDownloadProgress`
 * fragment, or report that the fragment is not there to write into.
 *
 * The counterpart to the renderer, and exported alongside it, because every
 * surface that shows a transfer has the same problem: progress arrives about
 * four times a second, and rebuilding the markup that often throws away focus —
 * a keyboard user could never reach the Cancel button on a row that keeps being
 * replaced underneath them.
 */
export function patchDownloadProgress(row: ParentNode, status: ModelStatusSnapshot): boolean {
  const bar = row.querySelector('.progress-bar') as HTMLElement | null;
  const fill = row.querySelector('.progress-fill') as HTMLElement | null;
  const detail = row.querySelector('.progress-detail__text');
  const percentEl = row.querySelector('.progress-detail__percent');
  if (!bar || !fill || !detail || !percentEl) return false;

  const pct = Math.round(Math.max(0, Math.min(1, status.progress)) * 100);
  const indeterminate = status.indeterminate ?? false;

  bar.classList.toggle('progress-bar--indeterminate', indeterminate);
  fill.style.width = `${indeterminate ? 100 : pct}%`;
  if (indeterminate) bar.removeAttribute('aria-valuenow');
  else bar.setAttribute('aria-valuenow', String(pct));
  bar.setAttribute('aria-label', status.detail || 'Download progress');
  detail.textContent = status.detail ?? '';
  percentEl.textContent = indeterminate ? '' : `${pct}%`;
  return true;
}

/**
 * Patch the picker's progress UI so download ticks do not rebuild the sheet.
 *
 * Was updating the bar's width and nothing else, which meant the readout it sits
 * under — the byte counter, the rate, the estimate — was painted once at the
 * start of the transfer and then never again. A line reading "0 B of 4.1 GB"
 * beside a bar that visibly advances is worse than no line at all.
 *
 * Returns false on a phase change so the caller re-renders instead: the action
 * button changes with the phase (Cancel becomes "Checking…"), and that lives
 * outside the fragment `patchDownloadProgress` can reach.
 */
function updateDownloadProgressInPlace(
  modelId: string,
  previous: RowState & { status: 'downloading' },
  state: RowState & { status: 'downloading' },
): boolean {
  if (previous.phase !== state.phase) return false;

  const host = document.getElementById('model-sheet-list');
  const row = host?.querySelector(`[data-model-id="${CSS.escape(modelId)}"]`);
  return row ? patchDownloadProgress(row, toSnapshot(state)) : false;
}

function setRow(modelId: string, state: RowState): void {
  const previous = rowStates.get(modelId);
  rowStates.set(modelId, state);
  if (modalEl) {
    const progressOnly = previous?.status === 'downloading'
      && state.status === 'downloading'
      && updateDownloadProgressInPlace(modelId, previous, state);
    if (!progressOnly) renderRows();
  }
  refreshToolbarLabel();
  refreshOverlayVisibility();
  for (const listener of listeners) {
    try {
      listener();
    } catch (err) {
      appLogger.warning('[model-selection] listener threw', err);
    }
  }
}

function refreshToolbarLabel(): void {
  if (!toolbarBtn || !toolbarText) return;

  const loaded = findLoadedModelForScope(toolbarSheetOptions.filterCategories);
  if (loaded) {
    toolbarText.textContent = `${loaded.name || loaded.id} · ${formatFramework(loaded.framework)}`;
  } else {
    toolbarText.textContent = catalogRegistered ? 'Select Model' : 'Loading...';
  }
}

function refreshOverlayVisibility(): void {
  if (!getStartedOverlay) return;
  const shouldShow = !findLoadedModelForScope(overlayLoadedCategories);
  getStartedOverlay.classList.toggle('hidden', !shouldShow);
  // The card replaces the scroll region rather than covering it, so the panel
  // has to know to stand its own empty state down while the card is up —
  // otherwise both "nothing here yet" surfaces render at once.
  getStartedOverlay.parentElement?.classList.toggle(
    'chat-panel--model-blocked',
    shouldShow && !getStartedOverlay.classList.contains('chat-model-overlay--conversation-visible'),
  );
  // Re-render only while visible: rebuilding a hidden overlay would discard a
  // `<details>` the user had expanded for no benefit.
  if (shouldShow) renderOverlayCard();
  if (getStartedBtn) {
    getStartedBtn.disabled = !catalogRegistered;
    if (!getStartedBtn.textContent?.trim()) {
      getStartedBtn.textContent = 'Choose a Model';
    }
  }
}

// Engine registration resolves after the shell is built, and a retry can flip
// it back, so every engine-dependent surface re-renders from one subscription
// rather than each caller remembering to poll.
onEngineStateChange(() => {
  if (modalEl) {
    renderBanner();
    renderRows();
  }
  refreshOverlayVisibility();
  for (const listener of listeners) {
    try {
      listener();
    } catch (err) {
      appLogger.warning('[model-selection] engine listener threw', err);
    }
  }
});

function findLoadedModelForScope(
  categories?: readonly ModelCategory[],
): ModelInfo | null {
  if (categories && categories.length > 0) {
    for (const category of categories) {
      const model = findLoadedModelForCategory(category);
      if (model) return model;
    }
    return null;
  }

  for (const [id, state] of rowStates.entries()) {
    if (state.status === 'loaded') return lookupModelInfo(id);
  }
  return null;
}

function lookupModelInfo(modelId: string): ModelInfo | null {
  return RunAnywhere.models.get(modelId);
}

/**
 * On first catalog registration, query the registry for already-downloaded
 * and currently-loaded models so the UI reflects their real state.
 */
function hydrateRowStatesFromRegistry(): void {
  const catalog = getCatalog();
  const downloadedIds = new Set(
    RunAnywhere.models.list({ downloadedOnly: true }).map((model) => model.id),
  );

  // Refresh every stable row from the registry before overlaying loaded state.
  // In-progress download/load operations remain authoritative until they end.
  for (const entry of catalog) {
    const state = rowStates.get(entry.id);
    if (state?.status === 'downloading' || state?.status === 'loading') continue;
    const isDownloaded = downloadedIds.has(entry.id);
    // An interruption is not something the registry knows about — it reports
    // "not downloaded" for a paused transfer, a failed one, and a model nobody
    // ever touched alike. Keeping the row's memory of *why* it is not downloaded
    // is what stops a hydrate (which runs on every sheet open) from quietly
    // turning "Paused — resume picks up where it stopped" back into a plain
    // Download button. A registry that now says the file is there always wins.
    if (!isDownloaded && (state?.status === 'paused' || state?.status === 'error')) continue;
    rowStates.set(entry.id, { status: isDownloaded ? 'downloaded' : 'registered' });
  }

  // One current model per modality. The async snapshot is mirrored into
  // `loadedByCategory`, so overlay from there and refresh it in the background.
  for (const model of loadedByCategory.values()) {
    rowStates.set(model.id, { status: 'loaded' });
  }
  void refreshLoadedByCategory().then(() => {
    for (const model of loadedByCategory.values()) {
      if (rowStates.get(model.id)?.status === 'downloaded') {
        rowStates.set(model.id, { status: 'loaded' });
      }
    }
    if (modalEl) renderRows();
    refreshToolbarLabel();
  });
}
