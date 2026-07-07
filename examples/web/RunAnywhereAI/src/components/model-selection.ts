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
 * Model actions flow through the flat Swift-named facade verbs:
 *
 *   - `RunAnywhere.listModels()` / `getModel(...)` — catalog list / get
 *   - `RunAnywhere.downloadModel(...)` — download with progress callback
 *   - `RunAnywhere.loadModel(...)`     — load through the C++ lifecycle ABI
 *
 * No legacy app-side registries or extension-point routing.
 */

import type { ModelInfo } from '@runanywhere/web';
import {
  RunAnywhere,
  ModelCategory,
} from '@runanywhere/web';
import type { DownloadProgress } from '@runanywhere/proto-ts/download_service';
import {
  DownloadState,
} from '@runanywhere/proto-ts/download_service';
import { getCatalog } from '../services/model-catalog';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';
import {
  formatBytes,
  formatFramework,
  modalityEmoji,
} from '../services/model-display';
import { showToast } from './dialogs';

// ---------------------------------------------------------------------------
// State (module-scope, one selection sheet per app)
// ---------------------------------------------------------------------------

type RowStatus =
  | 'registered'       // not downloaded yet
  | 'downloading'
  | 'downloaded'       // on disk but not loaded
  | 'loading'
  | 'loaded'
  | 'error';

interface RowState {
  status: RowStatus;
  progress?: number;   // 0..1
  error?: string;
}

const rowStates = new Map<string, RowState>();

let modalEl: HTMLElement | null = null;
let toolbarBtn: HTMLElement | null = null;
let toolbarText: HTMLElement | null = null;
let getStartedOverlay: HTMLElement | null = null;
let getStartedBtn: HTMLButtonElement | null = null;
let catalogRegistered = false;
let hydratedSubscribed = false;
const listeners: Array<() => void> = [];

/**
 * Sheet open options — used by tabs that want to restrict the visible catalog
 * to a single modality (Vision → MULTIMODAL, Transcribe → SPEECH_RECOGNITION,
 * Speak → SPEECH_SYNTHESIS). When omitted, the whole catalog is shown.
 */
export interface OpenSheetOptions {
  filterCategories?: readonly ModelCategory[];
  title?: string;
}

let activeSheetOptions: OpenSheetOptions = {};

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
  // Cold-start hydration (RunAnywhere.hydrateModelRegistry) runs asynchronously
  // after phase-2 and may mark models downloaded *after* this initial seed.
  // Subscribe once so the picker, toolbar pill, and per-view consumers refresh
  // to Downloaded/Load instead of showing Download for already-present models.
  if (!hydratedSubscribed) {
    hydratedSubscribed = true;
    try {
      RunAnywhere.events.on('models.hydrated', () => {
        hydrateRowStatesFromRegistry();
        if (modalEl) renderRows();
        refreshToolbarLabel();
        refreshOverlayVisibility();
        for (const listener of listeners) {
          try {
            listener();
          } catch (err) {
            console.warn('[model-selection] hydrated listener threw', err);
          }
        }
      });
    } catch {
      hydratedSubscribed = false; // EventBus unavailable; retry on next call
    }
  }
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
  const btn = document.createElement('button');
  btn.id = 'chat-toolbar-model';
  btn.className = 'toolbar-model-btn';
  btn.type = 'button';
  btn.innerHTML = `
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" class="model-icon">
      <circle cx="12" cy="12" r="9"/>
      <path d="M12 3c2.5 3 2.5 15 0 18M3 12h18"/>
    </svg>
    <span id="chat-toolbar-model-text">Select Model</span>
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="chevron">
      <polyline points="6 9 12 15 18 9"/>
    </svg>
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
 * `buildToolbarModelButton`).
 */
export function buildGetStartedOverlay(sheetOptions: OpenSheetOptions = {}): HTMLElement {
  const overlay = document.createElement('div');
  overlay.id = 'chat-model-overlay';
  overlay.className = 'chat-model-overlay';
  overlay.innerHTML = `
    <div class="chat-model-overlay-card">
      <div class="chat-model-overlay-glyph">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
          <path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8L12 3z"/>
          <path d="M5 3l.8 2.2L8 6l-2.2.8L5 9l-.8-2.2L2 6l2.2-.8L5 3z"/>
          <path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8L19 15z"/>
        </svg>
      </div>
      <h3 class="chat-model-overlay-title">Welcome</h3>
      <p class="chat-model-overlay-description">
        Choose your AI model and start chatting. Everything runs privately
        in your browser &mdash; nothing leaves this device.
      </p>
      <button type="button" id="chat-get-started-btn" class="btn btn-primary btn-lg">
        Choose a Model
      </button>
      <div class="chat-model-overlay-privacy">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <rect x="3" y="11" width="18" height="11" rx="2"/>
          <path d="M7 11V7a5 5 0 0 1 10 0v4"/>
        </svg>
        <span>100% private &middot; Runs on your device</span>
      </div>
    </div>
  `;

  getStartedOverlay = overlay;
  getStartedBtn = overlay.querySelector('#chat-get-started-btn') as HTMLButtonElement;
  getStartedBtn.addEventListener('click', () => openSheet(sheetOptions));

  refreshOverlayVisibility();
  return overlay;
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

/**
 * Find the loaded model for a specific category, or `null` if none. Used by
 * the Transcribe/Speak tabs to surface a "Pick an STT/TTS model" toolbar pill
 * matching the Chat tab's pattern.
 */
export function findLoadedModelForCategory(category: ModelCategory): ModelInfo | null {
  try {
    const current = RunAnywhere.currentModel();
    if (!current?.modelId) return null;
    const info = RunAnywhere.getModel(current.modelId);
    if (info?.category === category) return info;
    return null;
  } catch {
    return null;
  }
}

/** Open the model selection bottom sheet programmatically. */
export function openSheet(options: OpenSheetOptions = {}): void {
  if (modalEl) return;
  activeSheetOptions = options;
  renderSheet();
}

// ---------------------------------------------------------------------------
// Rendering — bottom sheet
// ---------------------------------------------------------------------------

function renderSheet(): void {
  const title = escapeHtml(activeSheetOptions.title ?? 'Select Model');
  modalEl = document.createElement('div');
  modalEl.className = 'modal-backdrop';
  modalEl.innerHTML = `
    <div class="modal-sheet" role="dialog" aria-modal="true">
      <div class="modal-handle"></div>
      <div class="modal-header">
        <h3 class="text-md font-semibold">${title}</h3>
        <button type="button" class="btn-ghost" id="model-sheet-close" aria-label="Close">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="20" height="20">
            <line x1="18" y1="6" x2="6" y2="18"/>
            <line x1="6" y1="6" x2="18" y2="18"/>
          </svg>
        </button>
      </div>
      <div class="modal-body">
        <div id="model-sheet-list"></div>
      </div>
    </div>
  `;

  document.body.appendChild(modalEl);

  modalEl.querySelector('#model-sheet-close')!.addEventListener('click', closeSheet);
  modalEl.addEventListener('click', (event) => {
    if (event.target === modalEl) closeSheet();
  });

  renderRows();
}

function closeSheet(): void {
  if (!modalEl) return;
  modalEl.remove();
  modalEl = null;
  activeSheetOptions = {};
}

function renderRows(): void {
  const host = document.getElementById('model-sheet-list');
  if (!host) return;

  const allEntries = getCatalog();
  // Filter by category when the caller scoped the picker to a modality
  // (e.g. Vision shows only VLM, Transcribe shows only STT). Without
  // filtering, a user opening the picker from Vision could load an LLM
  // and the modality call would then fail (BackendNotAvailable from the
  // VLM provider).
  const filterCats = activeSheetOptions.filterCategories;
  const entries = filterCats && filterCats.length > 0
    ? allEntries.filter((entry) => filterCats.includes(entry.category))
    : allEntries;
  if (!entries.length) {
    host.innerHTML = '<p class="text-secondary">No models registered.</p>';
    return;
  }

  // Consumer catalog sections by state: what's running, what's on the
  // device, what can be downloaded — matches the iOS picker grouping.
  const stateOf = (id: string): RowState => rowStates.get(id) ?? { status: 'registered' as RowStatus };
  const sections: Array<{ title: string; hint?: string; rows: typeof entries }> = [
    {
      title: 'Active',
      rows: entries.filter((entry) => ['loaded', 'loading'].includes(stateOf(entry.id).status)),
    },
    {
      title: 'On this device',
      hint: 'Ready to use — no download needed',
      rows: entries.filter((entry) => stateOf(entry.id).status === 'downloaded'),
    },
    {
      title: 'Available to download',
      hint: 'Stored in your browser, runs fully offline',
      rows: entries.filter((entry) => ['registered', 'downloading', 'error'].includes(stateOf(entry.id).status)),
    },
  ];

  host.innerHTML = sections
    .filter((section) => section.rows.length > 0)
    .map((section) => `
      <div class="model-section">
        <div class="model-section__title">${section.title}${section.hint ? `<small>${section.hint}</small>` : ''}</div>
        ${section.rows.map((entry) => renderModelRow(entry, stateOf(entry.id))).join('')}
      </div>
    `).join('');

  host.querySelectorAll('[data-action]').forEach((el) => {
    const btn = el as HTMLButtonElement;
    const action = btn.dataset.action as 'download' | 'load' | 'unload';
    const modelId = btn.dataset.modelId!;
    btn.addEventListener('click', (event) => {
      event.stopPropagation();
      void handleAction(action, modelId);
    });
  });
}

function renderModelRow(entry: ReturnType<typeof getCatalog>[number], state: RowState): string {
  const progressBar = state.status === 'downloading'
    ? `<div class="progress-bar mt-sm"><div class="progress-fill" style="width:${Math.round((state.progress ?? 0) * 100)}%"></div></div>`
    : '';
  const errorBar = state.error
    ? `<div class="model-row-error error">${escapeHtml(state.error)}</div>`
    : '';
  const badges = [
    `<span class="model-framework-badge">${formatFramework(entry.framework)}</span>`,
    entry.supportsThinking ? '<span class="model-capability-badge model-capability-badge--thinking">Thinking</span>' : '',
    `<span class="model-size">${formatBytes(entry.memoryRequiredBytes)}</span>`,
  ].filter(Boolean).join('');
  return `
    <div class="model-row model-row--${state.status}" data-model-id="${entry.id}">
      <div class="model-logo">${modalityEmoji(entry.category)}</div>
      <div class="model-info">
        <div class="model-name">${escapeHtml(entry.name)}</div>
        <div class="model-description">${escapeHtml(entry.description)}</div>
        <div class="model-meta">${badges}</div>
        ${progressBar}
        ${errorBar}
      </div>
      ${actionButton(entry.id, state)}
    </div>
  `;
}

function actionButton(modelId: string, state: RowState): string {
  switch (state.status) {
    case 'registered':
      return `<button type="button" class="model-action-btn download" data-action="download" data-model-id="${modelId}">Download</button>`;
    case 'downloading':
      return `<button type="button" class="model-action-btn model-action-btn--progress" disabled>${Math.round((state.progress ?? 0) * 100)}%</button>`;
    case 'downloaded':
      return `<button type="button" class="model-action-btn load" data-action="load" data-model-id="${modelId}">Use</button>`;
    case 'loading':
      return `<button type="button" class="model-action-btn model-action-btn--progress" disabled>Loading&hellip;</button>`;
    case 'loaded':
      return `<button type="button" class="model-action-btn loaded" data-action="unload" data-model-id="${modelId}" title="Tap to unload">&#10003; Active</button>`;
    case 'error':
      return `<button type="button" class="model-action-btn model-action-btn--retry" data-action="download" data-model-id="${modelId}">Retry</button>`;
  }
}

// ---------------------------------------------------------------------------
// Actions — download / load / unload
// ---------------------------------------------------------------------------

async function handleAction(action: 'download' | 'load' | 'unload', modelId: string): Promise<void> {
  if (action === 'download') await startDownload(modelId);
  else if (action === 'load') await loadModel(modelId);
  else if (action === 'unload') await unloadModel(modelId);
}

async function startDownload(modelId: string): Promise<void> {
  setRow(modelId, { status: 'downloading', progress: 0 });

  try {
    const model = RunAnywhere.getModel(modelId);
    if (!model) {
      throw new Error(`Model ${modelId} not found in registry`);
    }

    const progress = await RunAnywhere.downloadModel({
      modelId,
      model,
      allowMeteredNetwork: true,
      resumeExisting: false,
      verifyChecksums: false,
      validateExistingBytes: false,
      updateRegistryOnCompletion: true,
      storageNamespace: '',
      availableStorageBytes: 0,
      requiredFreeBytesAfterDownload: 0,
      pollIntervalMs: 500,
      onProgress: (next) => applyProgress(modelId, next),
    });
    applyProgress(modelId, progress);
  } catch (err) {
    const message = formatError(err);
    setRow(modelId, { status: 'error', error: message });
    showToast(`Download failed: ${message}`, 'warning');
  }
}

async function loadModel(modelId: string): Promise<void> {
  setRow(modelId, { status: 'loading' });
  try {
    const result = await RunAnywhere.loadModel({
      modelId,
      forceReload: false,
      validateAvailability: true,
    });
    if (!result || !result.success) {
      throw new Error(result?.errorMessage || 'Model load failed');
    }
    setRow(modelId, { status: 'loaded' });
    showToast(`Loaded ${modelId}`, 'success');
    closeSheet();
  } catch (err) {
    const message = formatError(err);
    setRow(modelId, { status: 'error', error: message });
    showToast(`Load failed: ${message}`, 'warning');
  }
}

async function unloadModel(modelId: string): Promise<void> {
  try {
    const result = await RunAnywhere.unloadModel({
      modelId,
      unloadAll: false,
    });
    if (!result || !result.success) {
      throw new Error(result?.errorMessage || 'Unload failed');
    }
    setRow(modelId, { status: 'downloaded' });
    showToast(`Unloaded ${modelId}`, 'info');
  } catch (err) {
    const message = formatError(err);
    showToast(`Unload failed: ${message}`, 'warning');
  }
}

function applyProgress(modelId: string, progress: DownloadProgress): void {
  const fraction = Math.max(0, Math.min(1, progress.overallProgress));
  if (progress.state === DownloadState.DOWNLOAD_STATE_COMPLETED) {
    setRow(modelId, { status: 'downloaded', progress: 1 });
    return;
  }
  if (progress.state === DownloadState.DOWNLOAD_STATE_FAILED) {
    setRow(modelId, { status: 'error', error: progress.errorMessage || 'Download failed' });
    return;
  }
  if (progress.state === DownloadState.DOWNLOAD_STATE_CANCELLED) {
    setRow(modelId, { status: 'registered' });
    return;
  }
  setRow(modelId, {
    status: 'downloading',
    progress: fraction,
  });
}

// ---------------------------------------------------------------------------
// State + toolbar updates
// ---------------------------------------------------------------------------

function setRow(modelId: string, patch: Partial<RowState>): void {
  const previous = rowStates.get(modelId) ?? { status: 'registered' as RowStatus };
  rowStates.set(modelId, { ...previous, ...patch });
  if (modalEl) renderRows();
  refreshToolbarLabel();
  refreshOverlayVisibility();
  for (const listener of listeners) {
    try {
      listener();
    } catch (err) {
      console.warn('[model-selection] listener threw', err);
    }
  }
}

function refreshToolbarLabel(): void {
  if (!toolbarBtn || !toolbarText) return;

  const loaded = findLoadedModelId();
  if (loaded) {
    const info = lookupModelInfo(loaded);
    toolbarText.textContent = info
      ? `${info.name || loaded} · ${formatFramework(info.framework)}`
      : loaded;
  } else {
    toolbarText.textContent = catalogRegistered ? 'Select Model' : 'Loading...';
  }
}

function refreshOverlayVisibility(): void {
  if (!getStartedOverlay) return;
  const shouldShow = !findLoadedModelId();
  getStartedOverlay.classList.toggle('hidden', !shouldShow);
  if (getStartedBtn) {
    getStartedBtn.disabled = !catalogRegistered;
    if (!getStartedBtn.textContent?.trim()) {
      getStartedBtn.textContent = 'Choose a Model';
    }
  }
}

function findLoadedModelId(): string | null {
  for (const [id, state] of rowStates.entries()) {
    if (state.status === 'loaded') return id;
  }
  return null;
}

function lookupModelInfo(modelId: string): ModelInfo | null {
  try {
    return RunAnywhere.getModel(modelId);
  } catch {
    return null;
  }
}

/**
 * On first catalog registration, query the registry for already-downloaded
 * and currently-loaded models so the UI reflects their real state.
 */
function hydrateRowStatesFromRegistry(): void {
  try {
    const downloaded = RunAnywhere.downloadedModels();
    for (const model of downloaded?.models ?? []) {
      rowStates.set(model.id, { status: 'downloaded' });
    }
  } catch {
    // ignore — listDownloaded may be unavailable in some WASM builds
  }

  try {
    const current = RunAnywhere.currentModel();
    if (current?.modelId) {
      rowStates.set(current.modelId, { status: 'loaded' });
    }
  } catch {
    // ignore — lifecycle may be unavailable
  }
}
