/**
 * Add from Hugging Face — a modal overlay for discovering and downloading an
 * arbitrary GGUF model from the Hugging Face Hub, PocketPal-style.
 *
 * Flow: pick a suggestion or search repos → pick a repo → see its GGUF
 * quantizations (quant + size) → Download. Both entry points converge on the
 * same `openRepo()` call, so there is exactly one download path.
 *
 * Discovery is served by the small `hf-hub-client` REST helper; the
 * SDK does all resolve/register/download/persist work
 * (`RunAnywhere.models.register` + `RunAnywhere.models.download`), exactly like the
 * built-in catalog flow in `model-selection.ts`.
 *
 * This is example-app UI only — no SDK/WASM/proto changes. The 4 GiB WASM32
 * address-space gate from `model-catalog.ts` is surfaced as a non-blocking
 * warning so the user is told when a quant is too large for the browser build.
 */

import { RunAnywhere } from '@runanywhere/web';
import { InferenceFramework, ModelFormat } from '@runanywhere/proto-ts/model_types';
import {
  searchGgufModels,
  listGgufFiles,
  hfResolveUrl,
  formatParameterCount,
  HF_SUGGESTED_GGUF_MODELS,
  type HfModelSummary,
  type HfRepoFile,
} from '../services/hf-hub-client';
import { webSizeCompatibility } from '../services/model-catalog';
import { refreshModelSelectionState } from './model-selection';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';
import { formatBytes } from '../services/model-display';
import { openModal, showToast } from './dialogs';
import { icon } from './icons';

// ---------------------------------------------------------------------------
// State (module-scope — one HF modal per app, like the model-selection sheet)
// ---------------------------------------------------------------------------

/**
 * The phase a transfer is actually in. `downloading` alone was not enough: the
 * SDK keeps working after the last byte arrives — it checksums, then unpacks —
 * and a row that only knows a 0..1 fraction renders both of those as a bar
 * frozen at 100%, which on a multi-gigabyte model looks like a hang for minutes.
 */
type TransferPhase = 'downloading' | 'verifying' | 'extracting';

type FileRowState =
  | { status: 'idle' }
  | { status: 'transferring'; phase: TransferPhase; progress: number } // 0..1
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
  // Opens on top of the model picker, which stays open underneath — the shared
  // modal keeps a stack so Escape and Tab apply to this one, and closing it
  // returns focus and interactivity to the picker rather than to the page.
  const modal = openModal({
    title: 'Add from Hugging Face',
    titleId: 'hf-sheet-title',
    onClose: () => {
      if (searchDebounce !== null) {
        window.clearTimeout(searchDebounce);
        searchDebounce = null;
      }
      modalEl = null;
      resetState();
    },
  });
  modalEl = modal.root;

  modal.body.innerHTML = `
    <div class="model-search">
      ${icon('search', { size: 16, className: 'model-search__icon' })}
      <input id="hf-search-input" class="model-search__input" type="search"
        placeholder="Search Hugging Face for chat models…" aria-label="Search Hugging Face for chat models"
        autocomplete="off" spellcheck="false" />
    </div>
    <!-- The format constraint is stated as a consequence of searching, not as the
         promise on the row that opens this sheet: "GGUF" names a container format
         nobody outside the field has heard of, and it used to be the first thing a
         hesitant reader saw. Android and iOS word their entry rows the same way. -->
    <p class="text-tertiary hf-hint">
      Only models this app can run are shown. Pick a repo to choose a size to download.
    </p>
    <div id="hf-result-list"></div>
  `;

  const input = modal.body.querySelector('#hf-search-input') as HTMLInputElement;
  input.addEventListener('input', () => {
    if (searchDebounce !== null) window.clearTimeout(searchDebounce);
    searchDebounce = window.setTimeout(() => void runSearch(input.value), 350);
  });
  // Overrides the shared modal's default of focusing the sheet, and `dialogs.ts`
  // names this dialog as the one caller that does so. Search stays the primary
  // act — a user who already knows the repo they want types it without a click
  // — and the suggestions below are not lost to assistive tech either: they sit
  // under a real heading, and the very next Tab stop from this field is the
  // first suggestion.
  input.focus();

  renderSuggestions();
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
// Idle state — the curated sub-1B suggestions
// ---------------------------------------------------------------------------

/**
 * The dialog's idle state.
 *
 * It used to be the sentence "Type to search Hugging Face.", which asks the
 * user to already know the name of a repo that is small enough to run in a
 * browser tab — the Hub's most-downloaded GGUF repos are 27B-284B models, so
 * the obvious searches all end in something that cannot load. The curated list
 * in `hf-hub-client` answers that question up front; every tile is a repo whose
 * parameter count was measured and is under 1B.
 *
 * This runs on open and again whenever the query is cleared, so browsing and
 * searching are the same surface rather than two modes.
 */
function renderSuggestions(): void {
  // Carries `hf-repo-row` as well as its own class so the shortlist and the
  // search results share one frame, hover and focus treatment — they are two
  // states of the same list and must not look like two components. `--hf-i` is
  // the row's index, which the stylesheet turns into the reveal stagger.
  const tiles = HF_SUGGESTED_GGUF_MODELS.map((model, index) => `
    <button type="button" class="hf-repo-row hf-suggestion" style="--hf-i:${index}"
      data-repo-id="${escapeHtml(model.repoId)}">
      <div class="hf-suggestion__info">
        <div class="hf-suggestion__head">
          <span class="hf-suggestion__title">${escapeHtml(model.title)}</span>
          <span class="tag-pill tag-pill--params">${escapeHtml(formatParameterCount(model.params))}</span>
        </div>
        <div class="hf-suggestion__repo">${escapeHtml(model.repoId)}</div>
        <div class="hf-suggestion__blurb">${escapeHtml(model.blurb)}</div>
      </div>
      ${icon('chevronRight', { size: 16, className: 'hf-repo-row__chevron' })}
    </button>
  `).join('');

  // A real heading rather than a styled div: this is the one landmark a screen
  // reader can jump to from the focused search field, and it is what tells the
  // user the tiles below are a shortlist and not search results.
  renderResults(`
    <section class="hf-suggestions" aria-labelledby="hf-suggestions-title">
      <h4 class="hf-suggestions__title" id="hf-suggestions-title">Suggested small models</h4>
      <p class="hf-suggestions__subtext">All under 1B parameters.</p>
      <div class="hf-suggestion-list">${tiles}</div>
    </section>
  `);
  bindRepoOpeners('.hf-suggestion');
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
    // Clearing the field is a return to browsing, not an empty result set.
    renderSuggestions();
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
    renderResults('<p class="text-tertiary hf-empty">No runnable models match your search.</p>');
    return;
  }
  const rows = results.map((repo) => {
    // The Hub only reports `gguf.total` for repos whose header it could parse.
    // Absent means absent: no badge, rather than a placeholder that would read
    // as a real (and wrong) size. Same pill as the suggestion tiles, so the two
    // states of this list read as one screen.
    const params = repo.params === undefined
      ? ''
      : `<span class="tag-pill tag-pill--params">${escapeHtml(formatParameterCount(repo.params))}</span>`;
    return `
    <button type="button" class="hf-repo-row" data-repo-id="${escapeHtml(repo.id)}">
      <div class="hf-repo-row__info">
        <div class="hf-repo-row__name">${escapeHtml(repo.id)}</div>
        <div class="hf-repo-row__meta">
          ${params}
          <span>&#8595; ${formatCount(repo.downloads)} downloads</span>
          <span>&#9829; ${formatCount(repo.likes)}</span>
        </div>
      </div>
      ${icon('chevronRight', { size: 16, className: 'hf-repo-row__chevron' })}
    </button>
  `;
  }).join('');
  renderResults(`<div class="hf-repo-list">${rows}</div>`);

  bindRepoOpeners('.hf-repo-row');
}

/**
 * Wire every control matching `selector` to open the repo named in its dataset.
 *
 * Shared by the suggestion tiles and the search rows so a suggestion is not a
 * second download path — it is the identical `openRepo()` entry the search
 * results use.
 */
function bindRepoOpeners(selector: string): void {
  modalEl?.querySelectorAll<HTMLButtonElement>(selector).forEach((btn) => {
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
  const progressBar = state.status === 'transferring'
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
    case 'transferring':
      return `<button type="button" class="model-action-btn model-action-btn--progress" disabled>${escapeHtml(transferLabel(state.phase, state.progress))}</button>`;
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

/**
 * What the disabled action button says mid-transfer.
 *
 * A percentage is only meaningful while bytes are moving. Checksumming and
 * unpacking both happen at 100% of the *download*, so showing "100%" for them
 * reads as a stall on exactly the models where those steps take longest. Naming
 * the step instead costs nothing and is the truth.
 */
function transferLabel(phase: TransferPhase, progress: number): string {
  switch (phase) {
    case 'downloading':
      return `${Math.round(progress * 100)}%`;
    case 'verifying':
      return 'Checking…';
    case 'extracting':
      return 'Unpacking…';
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

  setFileState(file.path, { status: 'transferring', phase: 'downloading', progress: 0 });

  try {
    const url = hfResolveUrl(repoId, file.path);
    const basename = repoId.split('/').pop() ?? repoId;
    const name = `${basename} (${file.quantLabel})`;

    // The SDK builds the canonical ModelInfo, persists it, and returns it with a
    // derived id. Example apps never hand-assemble proto model metadata.
    const model = RunAnywhere.models.register({
      name,
      url,
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      format: ModelFormat.MODEL_FORMAT_GGUF,
      description: `Added from Hugging Face: ${repoId}`,
      sizeBytes: file.sizeBytes,
      memoryRequiredBytes: file.sizeBytes,
    });

    // Every arm is named. This loop used to be two `if`s and an `else`, and that
    // `else` swallowed `failed` and `cancelled` along with `completed` — so a
    // download that died mid-transfer set the row to "downloaded" and toasted
    // "Downloaded <name>" for a model that was not on disk. `models.download()`
    // reports failure as a terminal `failed` event and then ends the iteration
    // normally; it does NOT throw, so the `catch` below never saw it either.
    // The same bug was proven on Android by killing the network mid-transfer.
    let outcome: 'completed' | 'failed' | 'cancelled' | 'ended' = 'ended';
    for await (const event of RunAnywhere.models.download(model.id)) {
      switch (event.type) {
        case 'progress':
          setFileState(file.path, {
            status: 'transferring',
            phase: 'downloading',
            progress: event.bytesTotal > 0 ? event.bytesDone / event.bytesTotal : 0,
          });
          break;
        case 'verifying':
          setFileState(file.path, { status: 'transferring', phase: 'verifying', progress: 1 });
          break;
        case 'extracting':
          setFileState(file.path, {
            status: 'transferring',
            phase: 'extracting',
            // `percent` is the unpack's own progress and is optional; without it
            // hold the bar full rather than snapping back to zero.
            progress: event.percent !== undefined ? event.percent / 100 : 1,
          });
          break;
        case 'completed':
          outcome = 'completed';
          setFileState(file.path, { status: 'downloaded', modelId: event.modelId });
          break;
        case 'failed':
          outcome = 'failed';
          setFileState(file.path, { status: 'error', error: event.error.message });
          break;
        case 'cancelled':
          outcome = 'cancelled';
          // Back to idle, not to an error: the user asked for this, so the row
          // should offer Download again rather than accuse them of a failure.
          setFileState(file.path, { status: 'idle' });
          break;
        case 'started':
          break;
      }
    }

    if (outcome === 'completed') {
      showToast(`Downloaded ${name}`, 'success');
      refreshModelSelectionState();
    } else if (outcome === 'failed') {
      const state = fileStates.get(file.path);
      showToast(
        `Download failed: ${state?.status === 'error' ? state.error : 'unknown error'}`,
        'warning',
      );
    } else if (outcome === 'ended') {
      // The stream finished without a terminal event. Nothing can be claimed
      // about the file, so say exactly that instead of guessing either way.
      setFileState(file.path, {
        status: 'error',
        error: 'The download ended without reporting a result. Try again.',
      });
      showToast('Download ended without a result', 'warning');
    }
  } catch (err) {
    const message = formatError(err);
    setFileState(file.path, { status: 'error', error: message });
    showToast(`Download failed: ${message}`, 'warning');
  }
}

async function loadFile(file: HfRepoFile): Promise<void> {
  const state = fileStates.get(file.path);
  if (!state || state.status !== 'downloaded') return;
  const modelId = state.modelId;

  setFileState(file.path, { status: 'loading', modelId });
  try {
    await RunAnywhere.models.load(modelId);
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
  // Names the list it actually returns to. With the field empty there are no
  // results behind this repo — `runSearch('')` re-renders the shortlist — and
  // "Back to results" would promise a screen the user never saw.
  const label = currentQuery() ? 'Back to results' : 'Back to suggestions';
  return `
    <button type="button" class="hf-back-btn" id="hf-back-btn">
      ${icon('back', { size: 16 })}
      ${label}
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
