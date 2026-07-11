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
import { getCatalog, type CatalogEntry } from '../services/model-catalog';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';
import {
  formatBytes,
  formatFramework,
  modelDisplaySizeBytes,
  modalityEmoji,
  cleanModelName,
  consumerTags,
  modelFamily,
  modelCapability,
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
import { showToast } from './dialogs';
import { appLogger } from '../services/app-logger';

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
const expandedFamilies = new Set<string>();

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
            appLogger.warning('[model-selection] hydrated listener threw', err);
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
 * Clear the view's SDK-lifetime state before `RunAnywhere.shutdown()`.
 * Shutdown resets EventBus, so the next catalog registration must subscribe
 * to `models.hydrated` again even though this UI module stays loaded.
 */
export function resetCatalogRegistrationState(): void {
  catalogRegistered = false;
  hydratedSubscribed = false;
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
  try {
    const current = RunAnywhere.currentModel({
      category,
      includeModelMetadata: true,
    });
    if (!current?.found || !current.modelId) return null;
    return current.model ?? RunAnywhere.getModel(current.modelId);
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
// Programmatic model orchestration — used by multi-model experiences (Voice AI)
// that need to download + load a set of models without opening the picker. All
// SDK verbs stay centralized here; consumers only pass model ids + a progress
// callback and observe the shared row state via `getModelStatus`.
// ---------------------------------------------------------------------------

/** Public snapshot of a model's lifecycle for external consumers. */
export interface ModelStatusSnapshot {
  status: RowStatus;
  progress: number;   // 0..1
  error?: string;
}

/** Read the current lifecycle status for a model id. */
export function getModelStatus(modelId: string): ModelStatusSnapshot {
  const state = rowStates.get(modelId) ?? { status: 'registered' as RowStatus };
  return { status: state.status, progress: state.progress ?? 0, error: state.error };
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
  const title = escapeHtml(activeSheetOptions.title ?? 'Select Model');
  searchQuery = '';
  expandedFamilies.clear();
  modalEl = document.createElement('div');
  modalEl.className = 'modal-backdrop';
  modalEl.innerHTML = `
    <div class="modal-sheet" role="dialog" aria-modal="true" aria-labelledby="model-sheet-title">
      <div class="modal-handle"></div>
      <div class="modal-header">
        <h3 class="text-md font-semibold" id="model-sheet-title">${title}</h3>
        <button type="button" class="btn-ghost" id="model-sheet-close" aria-label="Close">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="20" height="20">
            <line x1="18" y1="6" x2="6" y2="18"/>
            <line x1="6" y1="6" x2="18" y2="18"/>
          </svg>
        </button>
      </div>
      <div class="modal-body">
        <div id="model-sheet-banner"></div>
        <div class="model-search">
          <svg class="model-search__icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="11" cy="11" r="7"/>
            <line x1="21" y1="21" x2="16.65" y2="16.65"/>
          </svg>
          <input id="model-sheet-search" class="model-search__input" type="search"
            placeholder="Search models, capabilities…" autocomplete="off" spellcheck="false" />
        </div>
        <div id="model-sheet-list"></div>
      </div>
    </div>
  `;

  document.body.appendChild(modalEl);

  modalEl.querySelector('#model-sheet-close')!.addEventListener('click', closeSheet);
  modalEl.addEventListener('click', (event) => {
    if (event.target === modalEl) closeSheet();
  });

  const searchInput = modalEl.querySelector('#model-sheet-search') as HTMLInputElement;
  searchInput.addEventListener('input', () => {
    searchQuery = searchInput.value;
    renderRows();
  });

  // Probe hardware once, then re-render the banner + recommended section. The
  // list renders immediately (state-grouped) so the sheet is never blank while
  // the async capability probe resolves.
  void ensureCapabilities().then(() => {
    if (modalEl) {
      renderBanner();
      renderRows();
    }
  });

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
  const caps = capabilitiesCache;
  if (!caps) {
    host.innerHTML = '';
    return;
  }
  host.innerHTML = `
    <div class="device-banner device-banner--${caps.tier}">
      <div class="device-banner__glyph">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
          <rect x="4" y="4" width="16" height="16" rx="3"/>
          <rect x="9" y="9" width="6" height="6" rx="1"/>
          <path d="M9 2v2M15 2v2M9 20v2M15 20v2M2 9h2M2 15h2M20 9h2M20 15h2"/>
        </svg>
      </div>
      <div class="device-banner__text">
        <div class="device-banner__title">Recommended for your device</div>
        <div class="device-banner__meta">${escapeHtml(describeCapabilities(caps))}</div>
      </div>
    </div>
  `;
}

function closeSheet(): void {
  if (!modalEl) return;
  modalEl.remove();
  modalEl = null;
  activeSheetOptions = {};
  searchQuery = '';
}

function renderRows(): void {
  const host = document.getElementById('model-sheet-list');
  if (!host) return;

  const allEntries = getCatalog();
  const filterCats = activeSheetOptions.filterCategories;
  const scoped = filterCats && filterCats.length > 0
    ? allEntries.filter((entry) => filterCats.includes(entry.category))
    : allEntries;
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

type ModelAction = 'download' | 'load' | 'unload' | 'select';

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

/** Wire family-card expand toggles. */
function bindFamilyInteractions(host: HTMLElement): void {
  host.querySelectorAll('[data-family-toggle]').forEach((el) => {
    el.addEventListener('click', () => {
      const key = (el as HTMLElement).dataset.familyToggle!;
      if (expandedFamilies.has(key)) expandedFamilies.delete(key);
      else expandedFamilies.add(key);
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
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="14" height="14">
          <path d="M12 3l1.9 5.4L19 10l-5.1 1.6L12 17l-1.9-5.4L5 10l5.1-1.6L12 3z"/>
        </svg>
        Recommended
      </div>
      ${cardsHtml}
      ${companionRows}
    </div>
  `;
}

/** Group the remaining catalog into consumer-facing family cards. */
function renderFamilySection(entries: readonly CatalogEntry[], hasRecommended: boolean): string {
  if (entries.length === 0) return '';

  const families = groupByFamily(entries);
  if (families.length === 0) return '';

  const heading = hasRecommended ? 'Browse all models' : 'All models';
  const cards = families.map((family) => renderFamilyCard(family)).join('');

  return `
    <div class="model-section">
      <div class="model-section__title">${escapeHtml(heading)}</div>
      <div class="family-list">${cards}</div>
    </div>
  `;
}

interface FamilyGroup {
  key: string;
  name: string;
  tagline: string;
  entries: CatalogEntry[];
}

/** Bucket entries by family, preserving catalog order within each family. */
function groupByFamily(entries: readonly CatalogEntry[]): FamilyGroup[] {
  const groups = new Map<string, FamilyGroup>();
  for (const entry of entries) {
    const family = modelFamily(entry);
    const existing = groups.get(family.key);
    if (existing) {
      existing.entries.push(entry);
    } else {
      groups.set(family.key, {
        key: family.key,
        name: family.name,
        tagline: family.tagline,
        entries: [entry],
      });
    }
  }
  return [...groups.values()];
}

/**
 * A rounded family card: name, one-liner, the family's cleanest tag, and the
 * option count. Tapping toggles an expanded list of variants. When a variant is
 * loaded/downloaded the card reflects that with a subtle status dot.
 */
function renderFamilyCard(family: FamilyGroup): string {
  // Searching is a direct lookup, so surface matching variants immediately
  // instead of hiding exact results behind a second family-card click.
  const expanded = expandedFamilies.has(family.key) || searchQuery.trim().length > 0;
  const options = family.entries.length;
  const representative = pickRepresentative(family.entries);
  const tag = consumerTags(representative)[0];
  const activeEntry = family.entries.find((entry) => stateOf(entry.id).status === 'loaded');
  const onDevice = family.entries.some((entry) =>
    ['downloaded', 'loaded'].includes(stateOf(entry.id).status));

  const statusPill = activeEntry
    ? '<span class="family-card__status family-card__status--active">Active</span>'
    : onDevice
      ? '<span class="family-card__status">On device</span>'
      : '';

  const variants = expanded
    ? `<div class="family-variants">${renderFamilyVariants(family)}</div>`
    : '';

  return `
    <div class="family-card${expanded ? ' family-card--expanded' : ''}" data-family-key="${escapeHtml(family.key)}">
      <button type="button" class="family-card__head" data-family-toggle="${escapeHtml(family.key)}" aria-expanded="${expanded}">
        <div class="model-logo family-card__logo">${modalityEmoji(representative.category)}</div>
        <div class="family-card__body">
          <div class="family-card__name-row">
            <span class="family-card__name">${escapeHtml(family.name)}</span>
            ${tag ? renderTagPill(tag) : ''}
            ${statusPill}
          </div>
          <div class="family-card__tagline">${escapeHtml(family.tagline)}</div>
        </div>
        <div class="family-card__aside">
          <span class="family-card__count">${options} ${options === 1 ? 'option' : 'options'}</span>
          <svg class="family-card__chevron" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <polyline points="6 9 12 15 18 9"/>
          </svg>
        </div>
      </button>
      ${variants}
    </div>
  `;
}

/**
 * Render a family's variants once expanded. The best-for-device variant is
 * auto-flagged; each row shows the clean model name, download size, a subtle
 * backend pill, and the friendly size feel — never quant strings.
 */
function renderFamilyVariants(family: FamilyGroup): string {
  const best = bestVariantForDevice(family.entries);
  return family.entries
    .map((entry) => renderVariantRow(entry, entry.id === best?.id))
    .join('');
}

/** A single variant row inside an expanded family. */
function renderVariantRow(entry: CatalogEntry, isBest: boolean): string {
  const state = stateOf(entry.id);
  const progressBar = state.status === 'downloading'
    ? `<div class="progress-bar mt-sm"><div class="progress-fill" style="width:${Math.round((state.progress ?? 0) * 100)}%"></div></div>`
    : '';
  const errorBar = state.error
    ? `<div class="model-row-error error">${escapeHtml(state.error)}</div>`
    : '';
  const bestBadge = isBest
    ? '<span class="variant-row__best">Best for this device</span>'
    : '';
  const capability = modelCapability(entry);
  const capabilityPill = capability
    ? `<span class="tag-pill tag-pill--capability">${escapeHtml(capability)}</span>`
    : '';

  return `
    <div class="variant-row variant-row--${state.status}${isBest ? ' variant-row--best' : ''}" data-model-id="${escapeHtml(entry.id)}">
      <div class="variant-row__info">
        <div class="variant-row__name">${escapeHtml(cleanModelName(entry.name))}${bestBadge}</div>
        <div class="variant-row__meta">
          <span class="variant-row__size">${formatBytes(modelDisplaySizeBytes(entry))}</span>
          ${renderBackendPill(entry)}
          <span class="variant-row__feel">${escapeHtml(variantSizeFeel(entry))}</span>
          ${capabilityPill}
        </div>
        ${progressBar}
        ${errorBar}
      </div>
      ${actionButton(entry.id, state)}
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
  return rowStates.get(id) ?? { status: 'registered' as RowStatus };
}

/**
 * Match against friendly, consumer-facing signals only — model name, family
 * name/tagline, size feel, and consumer tags. Deliberately excludes quant
 * strings and inference backend names.
 */
function matchesSearch(entry: CatalogEntry, query: string): boolean {
  if (!query) return true;
  const family = modelFamily(entry);
  const haystack = [
    entry.name,
    entry.description,
    family.name,
    family.tagline,
    variantSizeFeel(entry),
    ...consumerTags(entry).map((tag) => tag.label),
  ]
    .join(' ')
    .toLowerCase();
  return haystack.includes(query);
}

/** Render a rich recommended card with a single clean tag row. */
function renderRecommendedCard(entry: CatalogEntry, state: RowState, isDefault: boolean): string {
  const tags = consumerTags(entry).map(renderTagPill).join('');
  const progressBar = state.status === 'downloading'
    ? `<div class="progress-bar mt-sm"><div class="progress-fill" style="width:${Math.round((state.progress ?? 0) * 100)}%"></div></div>`
    : '';
  const errorBar = state.error
    ? `<div class="model-row-error error">${escapeHtml(state.error)}</div>`
    : '';
  const bestBadge = isDefault
    ? '<span class="reco-card__best">Best for this device</span>'
    : '';
  return `
    <div class="reco-card${isDefault ? ' reco-card--default' : ''} reco-card--${state.status}" data-model-id="${escapeHtml(entry.id)}">
      <div class="reco-card__head">
        <div class="model-logo reco-card__logo">${modalityEmoji(entry.category)}</div>
        <div class="reco-card__title-wrap">
          <div class="reco-card__name">${escapeHtml(cleanModelName(entry.name))}${bestBadge}</div>
          <div class="reco-card__size">${formatBytes(modelDisplaySizeBytes(entry))} ${renderBackendPill(entry)}</div>
          <div class="reco-card__tags">${tags}</div>
        </div>
        ${actionButton(entry.id, state)}
      </div>
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
  const progressBar = state.status === 'downloading'
    ? `<div class="progress-bar mt-sm"><div class="progress-fill" style="width:${Math.round((state.progress ?? 0) * 100)}%"></div></div>`
    : '';
  const errorBar = state.error
    ? `<div class="model-row-error error">${escapeHtml(state.error)}</div>`
    : '';
  const capability = modelCapability(entry);
  const capabilityPill = capability
    ? `<span class="tag-pill tag-pill--capability">${escapeHtml(capability)}</span>`
    : '';
  return `
    <div class="model-row model-row--${state.status}" data-model-id="${escapeHtml(entry.id)}">
      <div class="model-logo">${modalityEmoji(entry.category)}</div>
      <div class="model-info">
        <div class="model-name">${escapeHtml(cleanModelName(entry.name))}</div>
        <div class="model-meta">
          <span class="model-size">${formatBytes(modelDisplaySizeBytes(entry))}</span>
          ${renderBackendPill(entry)}
          ${capabilityPill}
        </div>
        ${progressBar}
        ${errorBar}
      </div>
      ${actionButton(entry.id, state)}
    </div>
  `;
}

function actionButton(modelId: string, state: RowState): string {
  const safeModelId = escapeHtml(modelId);
  switch (state.status) {
    case 'registered':
      return `<button type="button" class="model-action-btn download" data-action="download" data-model-id="${safeModelId}">Download</button>`;
    case 'downloading':
      return `<button type="button" class="model-action-btn model-action-btn--progress" disabled>${Math.round((state.progress ?? 0) * 100)}%</button>`;
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
      return `<button type="button" class="model-action-btn model-action-btn--retry" data-action="download" data-model-id="${safeModelId}">Retry</button>`;
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
  else if (action === 'select') {
    completeSheetSelection(modelId, activeSheetOptions.onModelReady, modalEl);
  }
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

async function loadModel(modelId: string): Promise<boolean> {
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
    setRow(modelId, { status: 'error', error: message });
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
  if (getStartedBtn) {
    getStartedBtn.disabled = !catalogRegistered;
    if (!getStartedBtn.textContent?.trim()) {
      getStartedBtn.textContent = 'Choose a Model';
    }
  }
}

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
  const catalog = getCatalog();
  const downloadedIds = new Set<string>();
  try {
    const downloaded = RunAnywhere.downloadedModels();
    for (const model of downloaded?.models ?? []) {
      downloadedIds.add(model.id);
    }
  } catch {
    // ignore — listDownloaded may be unavailable in some WASM builds
  }

  // Refresh every stable row from the registry before overlaying loaded state.
  // In-progress download/load operations remain authoritative until they end.
  for (const entry of catalog) {
    const state = rowStates.get(entry.id);
    if (state?.status === 'downloading' || state?.status === 'loading') continue;
    let isDownloaded = downloadedIds.has(entry.id);
    if (!isDownloaded) {
      try {
        isDownloaded = Boolean(RunAnywhere.getModel(entry.id)?.isDownloaded);
      } catch {
        // The catalog entry may not have reached the native registry yet.
      }
    }
    rowStates.set(entry.id, { status: isDownloaded ? 'downloaded' : 'registered' });
  }

  // The native lifecycle tracks a current model per modality. Query every
  // category represented by the catalog so loading STT/TTS/VAD/VLM models does
  // not hide one another behind the legacy unscoped currentModel() result.
  const categories = new Set(catalog.map((entry) => entry.category));
  for (const category of categories) {
    try {
      const current = RunAnywhere.currentModel({
        category,
        includeModelMetadata: false,
      });
      if (current?.modelId) {
        rowStates.set(current.modelId, { status: 'loaded' });
      }
    } catch {
      // One unavailable modality must not prevent the others from hydrating.
    }
  }
}
