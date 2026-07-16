/**
 * Add from Hugging Face — a modal overlay for discovering and downloading an
 * arbitrary GGUF model from the Hugging Face Hub, PocketPal-style.
 *
 * Flow: search repos → pick a repo → see its GGUF quantizations (quant + size)
 * → Download. Discovery is served by the small `hf-hub-client` REST helper; the
 * SDK does all resolve/register/download/persist work
 * (`RunAnywhere.registerModel` + `RunAnywhere.downloadModel`), exactly like the
 * built-in catalog flow in `model-selection.ts`.
 *
 * This is example-app UI only — no SDK/WASM/proto changes. The 4 GiB WASM32
 * address-space gate from `model-catalog.ts` is surfaced as a non-blocking
 * warning so the user is told when a quant is too large for the browser build.
 */

import { RunAnywhere } from '@runanywhere/web';
import { InferenceFramework, ModelFormat } from '@runanywhere/proto-ts/model_types';
import type { DownloadProgress } from '@runanywhere/proto-ts/download_service';
import { DownloadState } from '@runanywhere/proto-ts/download_service';
import {
  searchGgufModels,
  listGgufFiles,
  hfResolveUrl,
  type HfModelSummary,
  type HfRepoFile,
} from '../services/hf-hub-client';
import { webSizeCompatibility } from '../services/model-catalog';
import { refreshModelSelectionState } from './model-selection';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';
import { formatBytes } from '../services/model-display';
import { showToast } from './dialogs';

// ---------------------------------------------------------------------------
// State (module-scope — one HF modal per app, like the model-selection sheet)
// ---------------------------------------------------------------------------

type FileRowState =
  | { status: 'idle' }
  | { status: 'downloading'; progress: number } // 0..1
  | { status: 'downloaded'; modelId: string }
  | { status: 'loading'; modelId: string }
  | { status: 'loaded'; modelId: string }
  | { status: 'error'; error: string };

let modalEl: HTMLElement | null = null;
let searchDebounce: number | null = null;

/** Files are keyed by their repo-relative path within the selected repo. */
const fileStates = new Map<string, FileRowState>();
let selectedRepo: string | null = null;
let selectedFiles: readonly HfRepoFile[] = [];

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/** Open the "Add from Hugging Face" modal. No-op if it is already open. */
export function openAddFromHuggingFace(): void {
  if (modalEl) return;
  resetState();
  renderModal();
}

function resetState(): void {
  fileStates.clear();
  selectedRepo = null;
  selectedFiles = [];
}

// ---------------------------------------------------------------------------
// Modal shell
// ---------------------------------------------------------------------------

function renderModal(): void {
  modalEl = document.createElement('div');
  modalEl.className = 'modal-backdrop';
  modalEl.innerHTML = `
    <div class="modal-sheet" role="dialog" aria-modal="true" aria-labelledby="hf-sheet-title">
      <div class="modal-handle"></div>
      <div class="modal-header">
        <h3 class="text-md font-semibold" id="hf-sheet-title">Add from Hugging Face</h3>
        <button type="button" class="btn-ghost" id="hf-sheet-close" aria-label="Close">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="20" height="20">
            <line x1="18" y1="6" x2="6" y2="18"/>
            <line x1="6" y1="6" x2="18" y2="18"/>
          </svg>
        </button>
      </div>
      <div class="modal-body">
        <div class="model-search">
          <svg class="model-search__icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="11" cy="11" r="7"/>
            <line x1="21" y1="21" x2="16.65" y2="16.65"/>
          </svg>
          <input id="hf-search-input" class="model-search__input" type="search"
            placeholder="Search GGUF models on Hugging Face…" autocomplete="off" spellcheck="false" />
        </div>
        <p class="text-tertiary hf-hint">
          Searches public GGUF repositories. Pick a repo to choose a quantization to download.
        </p>
        <div id="hf-result-list"></div>
      </div>
    </div>
  `;

  document.body.appendChild(modalEl);

  modalEl.querySelector('#hf-sheet-close')!.addEventListener('click', closeModal);
  modalEl.addEventListener('click', (event) => {
    if (event.target === modalEl) closeModal();
  });

  const input = modalEl.querySelector('#hf-search-input') as HTMLInputElement;
  input.addEventListener('input', () => {
    if (searchDebounce !== null) window.clearTimeout(searchDebounce);
    searchDebounce = window.setTimeout(() => void runSearch(input.value), 350);
  });
  input.focus();

  renderResults('<p class="text-tertiary hf-empty">Type to search Hugging Face.</p>');
}

function closeModal(): void {
  if (searchDebounce !== null) {
    window.clearTimeout(searchDebounce);
    searchDebounce = null;
  }
  if (!modalEl) return;
  modalEl.remove();
  modalEl = null;
  resetState();
}

function renderResults(html: string): void {
  const host = modalEl?.querySelector('#hf-result-list') as HTMLElement | null;
  if (host) host.innerHTML = html;
}

function currentQuery(): string {
  const input = modalEl?.querySelector('#hf-search-input') as HTMLInputElement | null;
  return input ? input.value.trim() : '';
}

// ---------------------------------------------------------------------------
// Search → repo list
// ---------------------------------------------------------------------------

async function runSearch(query: string): Promise<void> {
  const trimmed = query.trim();
  selectedRepo = null;
  selectedFiles = [];
  fileStates.clear();
  if (!trimmed) {
    renderResults('<p class="text-tertiary hf-empty">Type to search Hugging Face.</p>');
    return;
  }
  renderResults('<p class="text-tertiary hf-empty">Searching…</p>');
  try {
    const results = await searchGgufModels(trimmed);
    // A newer search may have started while this awaited; ignore stale results.
    if (currentQuery() !== trimmed || selectedRepo !== null) return;
    renderRepoList(results);
  } catch (err) {
    renderResults(`<p class="hf-error error">${escapeHtml(formatError(err))}</p>`);
  }
}

function renderRepoList(results: readonly HfModelSummary[]): void {
  if (results.length === 0) {
    renderResults('<p class="text-tertiary hf-empty">No GGUF repositories match your search.</p>');
    return;
  }
  const rows = results.map((repo) => `
    <button type="button" class="hf-repo-row" data-repo-id="${escapeHtml(repo.id)}">
      <div class="hf-repo-row__info">
        <div class="hf-repo-row__name">${escapeHtml(repo.id)}</div>
        <div class="hf-repo-row__meta">
          <span>&#8595; ${formatCount(repo.downloads)} downloads</span>
          <span>&#9829; ${formatCount(repo.likes)}</span>
        </div>
      </div>
      <svg class="hf-repo-row__chevron" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <polyline points="9 18 15 12 9 6"/>
      </svg>
    </button>
  `).join('');
  renderResults(`<div class="hf-repo-list">${rows}</div>`);

  modalEl?.querySelectorAll<HTMLButtonElement>('.hf-repo-row').forEach((btn) => {
    btn.addEventListener('click', () => {
      const repoId = btn.dataset.repoId;
      if (repoId) void openRepo(repoId);
    });
  });
}

// ---------------------------------------------------------------------------
// Repo → file list
// ---------------------------------------------------------------------------

async function openRepo(repoId: string): Promise<void> {
  selectedRepo = repoId;
  selectedFiles = [];
  fileStates.clear();
  renderResults(`
    ${backButtonHtml()}
    <div class="hf-repo-title">${escapeHtml(repoId)}</div>
    <p class="text-tertiary hf-empty">Loading files…</p>
  `);
  bindBackButton();
  try {
    const files = await listGgufFiles(repoId);
    if (selectedRepo !== repoId) return; // user navigated away
    selectedFiles = files;
    renderFileList();
  } catch (err) {
    renderResults(`
      ${backButtonHtml()}
      <div class="hf-repo-title">${escapeHtml(repoId)}</div>
      <p class="hf-error error">${escapeHtml(formatError(err))}</p>
    `);
    bindBackButton();
  }
}

/** Re-render the current repo's file list from `selectedFiles` + `fileStates`. */
function renderFileList(): void {
  const repoId = selectedRepo;
  if (!repoId) return;

  if (selectedFiles.length === 0) {
    renderResults(`
      ${backButtonHtml()}
      <div class="hf-repo-title">${escapeHtml(repoId)}</div>
      <p class="text-tertiary hf-empty">No GGUF files found in this repository.</p>
    `);
    bindBackButton();
    return;
  }

  const rows = selectedFiles.map((file) => renderFileRow(file)).join('');
  renderResults(`
    ${backButtonHtml()}
    <div class="hf-repo-title">${escapeHtml(repoId)}</div>
    <div class="hf-file-list">${rows}</div>
  `);
  bindBackButton();
  bindFileActions(repoId);
}

function renderFileRow(file: HfRepoFile): string {
  const state = fileStates.get(file.path) ?? { status: 'idle' };
  const compatibility = webSizeCompatibility(file.sizeBytes, file.sizeBytes);
  const warning = !compatibility.supported
    ? `<div class="hf-file-row__warning">&#9888;&#65039; ${escapeHtml(compatibility.reason)}</div>`
    : '';
  const progressBar = state.status === 'downloading'
    ? `<div class="progress-bar mt-sm"><div class="progress-fill" style="width:${Math.round(state.progress * 100)}%"></div></div>`
    : '';
  const errorBar = state.status === 'error'
    ? `<div class="model-row-error error">${escapeHtml(state.error)}</div>`
    : '';

  return `
    <div class="hf-file-row" data-file-path="${escapeHtml(file.path)}">
      <div class="hf-file-row__info">
        <div class="hf-file-row__name">${escapeHtml(file.path.split('/').pop() ?? file.path)}</div>
        <div class="hf-file-row__meta">
          <span class="tag-pill tag-pill--capability">${escapeHtml(file.quantLabel)}</span>
          <span class="hf-file-row__size">${formatBytes(file.sizeBytes)}</span>
        </div>
        ${warning}
        ${progressBar}
        ${errorBar}
      </div>
      ${renderFileAction(state)}
    </div>
  `;
}

function renderFileAction(state: FileRowState): string {
  switch (state.status) {
    case 'idle':
      return '<button type="button" class="model-action-btn download" data-hf-action="download">Download</button>';
    case 'downloading':
      return `<button type="button" class="model-action-btn model-action-btn--progress" disabled>${Math.round(state.progress * 100)}%</button>`;
    case 'downloaded':
      return '<button type="button" class="model-action-btn load" data-hf-action="load">Use</button>';
    case 'loading':
      return '<button type="button" class="model-action-btn model-action-btn--progress" disabled>Loading&hellip;</button>';
    case 'loaded':
      return '<button type="button" class="model-action-btn loaded" disabled>&#10003; Active</button>';
    case 'error':
      return '<button type="button" class="model-action-btn model-action-btn--retry" data-hf-action="download">Retry</button>';
  }
}

function bindFileActions(repoId: string): void {
  const byPath = new Map(selectedFiles.map((file) => [file.path, file]));
  modalEl?.querySelectorAll<HTMLElement>('.hf-file-row').forEach((row) => {
    const path = row.dataset.filePath;
    const file = path ? byPath.get(path) : undefined;
    if (!file) return;
    row.querySelector<HTMLButtonElement>('[data-hf-action="download"]')
      ?.addEventListener('click', () => void downloadFile(repoId, file));
    row.querySelector<HTMLButtonElement>('[data-hf-action="load"]')
      ?.addEventListener('click', () => void loadFile(file));
  });
}

// ---------------------------------------------------------------------------
// Register + download (delegated entirely to the SDK — mirror model-selection)
// ---------------------------------------------------------------------------

async function downloadFile(repoId: string, file: HfRepoFile): Promise<void> {
  const compatibility = webSizeCompatibility(file.sizeBytes, file.sizeBytes);
  if (!compatibility.supported) {
    // Non-blocking gate: warn, but let the user proceed (plan requires
    // "warn (not necessarily block)").
    showToast(compatibility.reason, 'warning');
  }

  setFileState(file.path, { status: 'downloading', progress: 0 });

  try {
    const url = hfResolveUrl(repoId, file.path);
    const basename = repoId.split('/').pop() ?? repoId;
    const name = `${basename} (${file.quantLabel})`;

    // The SDK builds the canonical ModelInfo, persists it, and returns it with a
    // derived id. Example apps never hand-assemble proto model metadata.
    const model = RunAnywhere.registerModel(
      url,
      name,
      InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      {
        description: `Added from Hugging Face: ${repoId}`,
        format: ModelFormat.MODEL_FORMAT_GGUF,
        downloadSizeBytes: file.sizeBytes,
        memoryRequirement: file.sizeBytes,
      },
    );

    const progress = await RunAnywhere.downloadModel({
      modelId: model.id,
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
      onProgress: (next) => applyProgress(file.path, model.id, next),
    });
    applyProgress(file.path, model.id, progress);

    if ((fileStates.get(file.path) ?? { status: 'idle' }).status === 'downloaded') {
      showToast(`Downloaded ${name}`, 'success');
      refreshModelSelectionState();
    }
  } catch (err) {
    const message = formatError(err);
    setFileState(file.path, { status: 'error', error: message });
    showToast(`Download failed: ${message}`, 'warning');
  }
}

function applyProgress(path: string, modelId: string, progress: DownloadProgress): void {
  if (progress.state === DownloadState.DOWNLOAD_STATE_COMPLETED) {
    setFileState(path, { status: 'downloaded', modelId });
    return;
  }
  if (progress.state === DownloadState.DOWNLOAD_STATE_FAILED) {
    setFileState(path, { status: 'error', error: progress.errorMessage || 'Download failed' });
    return;
  }
  if (progress.state === DownloadState.DOWNLOAD_STATE_CANCELLED) {
    setFileState(path, { status: 'idle' });
    return;
  }
  const fraction = Math.max(0, Math.min(1, progress.overallProgress));
  setFileState(path, { status: 'downloading', progress: fraction });
}

async function loadFile(file: HfRepoFile): Promise<void> {
  const state = fileStates.get(file.path);
  if (!state || state.status !== 'downloaded') return;
  const modelId = state.modelId;

  setFileState(file.path, { status: 'loading', modelId });
  try {
    const result = await RunAnywhere.loadModel({
      modelId,
      forceReload: false,
      validateAvailability: true,
    });
    if (!result || !result.success) {
      throw new Error(result?.errorMessage || 'Model load failed');
    }
    setFileState(file.path, { status: 'loaded', modelId });
    refreshModelSelectionState();
    showToast(`Loaded ${modelId}`, 'success');
  } catch (err) {
    const message = formatError(err);
    setFileState(file.path, { status: 'error', error: message });
    showToast(`Load failed: ${message}`, 'warning');
  }
}

/** Update one file's state and re-render the (small) repo file list. */
function setFileState(path: string, state: FileRowState): void {
  fileStates.set(path, state);
  renderFileList();
}

// ---------------------------------------------------------------------------
// Back navigation + small helpers
// ---------------------------------------------------------------------------

function backButtonHtml(): string {
  return `
    <button type="button" class="hf-back-btn" id="hf-back-btn">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="16" height="16">
        <polyline points="15 18 9 12 15 6"/>
      </svg>
      Back to results
    </button>
  `;
}

function bindBackButton(): void {
  modalEl?.querySelector('#hf-back-btn')?.addEventListener('click', () => {
    selectedRepo = null;
    selectedFiles = [];
    fileStates.clear();
    void runSearch(currentQuery());
  });
}

function formatCount(value: number): string {
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`;
  if (value >= 1_000) return `${(value / 1_000).toFixed(1)}K`;
  return String(value);
}
