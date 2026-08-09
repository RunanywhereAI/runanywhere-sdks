/**
 * Storage Tab — storage info header + maintenance actions + a model catalog
 * view that surfaces registry state via proto-byte adapters.
 *
 * Mirrors iOS `StorageViewModel` (StorageViewModel.swift:28-103):
 *   - `RunAnywhere.models.state()` drives the used/free header.
 *   - Clear Caches delegates to `RunAnywhere.storage.clearCaches()`.
 *   - Per-model Delete goes through `RunAnywhere.models.delete(id)`.
 *
 * The storage-location switcher (OPFS vs local folder) is justified web
 * platform code — browsers expose two storage backends, iOS has one.
 * Downloading + loading lives in `components/model-selection.ts`.
 */

import type { TabLifecycle } from '../app';
import { showToast } from '../components/dialogs';
import { RunAnywhere } from '@runanywhere/web';
import type { ModelsState } from '@runanywhere/web';
import {
  cancelModelDownload,
  getModelStatus,
  isDownloadCancellable,
  onModelStateChange,
  openSheet as openModelSheet,
  patchDownloadProgress,
  refreshModelSelectionState,
  renderDownloadProgress,
  resetModelRowState,
  type ModelStatusSnapshot,
} from '../components/model-selection';
import { getCatalog } from '../services/model-catalog';
import { icon } from '../components/icons';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';
import {
  formatBytes,
  formatFramework,
  formatModelSize,
  modelDisplaySizeBytes,
  modalityIcon,
} from '../services/model-display';

let container: HTMLElement;
let unsubscribeState: (() => void) | null = null;
let lastStorageInfo: ModelsState | null = null;
let storageInfoError: string | null = null;

/**
 * The structure each rendered row was built for, keyed by model id.
 *
 * Only the parts that decide what the row *is* — its badge, its buttons, its
 * note — never the numbers inside a transfer. That split is what lets a progress
 * tick be patched instead of re-rendered.
 */
const renderedRowShapes = new Map<string, string>();

export function initStorageTab(el: HTMLElement): TabLifecycle {
  container = el;
  container.innerHTML = `
    <div class="toolbar">
      <!-- "Downloads": the one name the nav row, the Advanced-hub row and the tab
           registry all use for this panel. It used to be the fourth name for it. -->
      <div class="toolbar-title">Downloads</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="storage-clear-cache-btn" style="font-size: 0.8rem;">Clear Caches</button>
      </div>
    </div>
    <div class="scroll-area" id="storage-scroll">
      <div id="storage-info-header" style="padding: 12px 16px; margin-bottom: 12px; border-radius: 8px; background: var(--bg-secondary);"></div>

      <div
        class="storage-location"
        id="storage-location"
        style="padding: 12px 16px; margin-bottom: 12px; border-radius: 8px; background: var(--bg-secondary); display: flex; align-items: center; gap: 12px; flex-wrap: wrap;"
      >
        <div style="flex: 1; min-width: 200px;">
          <div style="font-size: 0.75rem; opacity: 0.6; margin-bottom: 2px;">Storage Location</div>
          <div id="storage-location-label" style="font-size: 0.9rem; font-weight: 500;">Checking&hellip;</div>
        </div>
        <button class="btn btn-secondary" id="storage-choose-dir-btn" style="font-size: 0.8rem; padding: 6px 14px;">
          Choose Storage Folder
        </button>
        <button class="btn btn-secondary" id="storage-reauth-btn" style="font-size: 0.8rem; padding: 6px 14px; display: none;">
          Re-authorize Access
        </button>
      </div>

      <div style="margin: 16px 0 8px; display: flex; align-items: center; justify-content: space-between; gap: 8px;">
        <h3 style="font-size: 0.95rem; font-weight: 600; margin: 0;">Registered Models</h3>
        <button class="btn btn-primary btn-sm" id="storage-open-selection-btn">Manage Models</button>
      </div>
      <div id="storage-model-list" class="storage-model-list"></div>
    </div>
  `;

  container.querySelector('#storage-clear-cache-btn')!.addEventListener('click', () => {
    void (async () => {
    try {
      await RunAnywhere.storage.clearCaches();
      showToast('Caches cleared', 'success');
    } catch (err) {
      showToast(`Failed to clear caches: ${formatError(err)}`, 'warning');
    }
      void refreshStorageInfo();
    })();
  });

  container.querySelector('#storage-choose-dir-btn')!.addEventListener('click', () => {
    void (async () => {
    try {
      const ok = await RunAnywhere.storage.chooseDirectory();
      if (ok) {
        refreshModelSelectionState();
        showToast(`Using folder: ${RunAnywhere.storage.directoryName ?? 'selected'}`, 'success');
      } else {
        showToast('Folder selection cancelled or unsupported', 'info');
      }
    } catch (err) {
      showToast(formatError(err), 'warning');
    }
      updateStorageLocationUI();
    })();
  });

  container.querySelector('#storage-reauth-btn')!.addEventListener('click', () => {
    void (async () => {
      const ok = await RunAnywhere.storage.requestAccess();
      if (ok) refreshModelSelectionState();
      showToast(ok ? 'Access re-authorized' : 'Access not granted', ok ? 'success' : 'warning');
      updateStorageLocationUI();
    })();
  });

  container.querySelector('#storage-open-selection-btn')!.addEventListener('click', () => {
    openModelSheet();
  });
  void refreshStorageInfo();
  updateStorageLocationUI();
  renderModelList();

  unsubscribeState = onModelStateChange(() => {
    void refreshStorageInfo();
    syncModelList();
  });

  return {
    onActivate(): void {
      void refreshStorageInfo();
      updateStorageLocationUI();
      renderModelList();
    },
    onDeactivate(): void {
      // Keep the subscription live across tab activation toggles; clean up
      // only if the panel itself gets torn down.
      if (!container.isConnected && unsubscribeState) {
        unsubscribeState();
        unsubscribeState = null;
      }
    },
  };
}

// ---------------------------------------------------------------------------
// Storage info header (iOS parity: StorageViewModel.swift:28-62 loadData)
// ---------------------------------------------------------------------------

async function refreshStorageInfo(): Promise<void> {
  storageInfoError = null;
  lastStorageInfo = null;
  try {
    lastStorageInfo = await RunAnywhere.models.state();
  } catch (err) {
    storageInfoError = formatError(err);
  }
  renderStorageInfoHeader();
}

function renderStorageInfoHeader(): void {
  const host = container.querySelector<HTMLElement>('#storage-info-header');
  if (!host) return;

  if (storageInfoError) {
    host.innerHTML = `<div class="docs-status">Storage info unavailable: ${escapeHtml(storageInfoError)}</div>`;
    return;
  }
  if (!lastStorageInfo) {
    host.innerHTML = '<div class="docs-status">Loading storage info...</div>';
    return;
  }

  const { storageUsedBytes, storageFreeBytes } = lastStorageInfo;
  const modelsSize = RunAnywhere.models
    .list({ downloadedOnly: true })
    .reduce((total, model) => total + Number(model.downloadSizeBytes ?? 0), 0);
  const quota = storageUsedBytes + storageFreeBytes;
  const usedPct = quota > 0 ? (storageUsedBytes / quota) * 100 : 0;

  // "Origin used" / "Origin free" is the storage API's vocabulary, not a word a
  // user of this app has any reason to know. The quota is per-site, so say that.
  host.innerHTML = `
    <div style="font-size: 0.75rem; opacity: 0.6; margin-bottom: 6px;">Storage</div>
    <div style="display: flex; gap: 24px; flex-wrap: wrap; font-size: 0.85rem;">
      <div><strong>Used by this site:</strong> ${formatBytes(storageUsedBytes)}</div>
      <div><strong>Models:</strong> ${formatBytes(modelsSize)}</div>
      <div><strong>Still available:</strong> ${formatBytes(storageFreeBytes)}</div>
    </div>
    ${quota > 0
      ? `<div class="progress-bar" style="margin-top: 8px;">
          <div class="progress-fill" style="width:${Math.min(100, Math.round(usedPct))}%"></div>
        </div>`
      : ''}
  `;
}

// ---------------------------------------------------------------------------
// Storage location switcher (web platform code)
// ---------------------------------------------------------------------------

/**
 * Describe where downloaded models are being kept.
 *
 * The four states used to be written in the storage layer's own vocabulary —
 * "OPFS", "the split-WASM SDK", "not visible in Finder" — which names an API, a
 * build topology, and one operating system's file manager. None of the three
 * tells a user what is true of their models, and the middle one is not even a
 * thing that exists outside this repository. Each branch now says where the
 * files are and what that means for them.
 */
function updateStorageLocationUI(): void {
  const label = container.querySelector('#storage-location-label') as HTMLElement;
  const chooseDirBtn = container.querySelector('#storage-choose-dir-btn') as HTMLElement;
  const reauthBtn = container.querySelector('#storage-reauth-btn') as HTMLElement;

  if (RunAnywhere.storage.isReady) {
    const safeName = escapeHtml(RunAnywhere.storage.directoryName ?? 'Unknown');
    label.innerHTML = `<strong>Your folder:</strong> ~/${safeName}/`
      + `<br><span style="font-size:0.75rem;opacity:0.5">Models are saved as ordinary files you can open, move, and delete yourself.</span>`;
    label.style.color = 'var(--color-success, #4caf50)';
    chooseDirBtn.textContent = 'Change Folder';
    chooseDirBtn.style.display = '';
    reauthBtn.style.display = 'none';
  } else if (RunAnywhere.storage.directoryName !== null) {
    label.innerHTML = '<strong>Your folder needs permission again</strong>'
      + `<br><span style="font-size:0.75rem;opacity:0.5">Browsers drop folder access between visits. Re-authorize to reconnect it.</span>`;
    label.style.color = 'var(--color-warning, #ff9800)';
    chooseDirBtn.style.display = '';
    reauthBtn.style.display = '';
  } else if (RunAnywhere.storage.backend === 'memory') {
    label.innerHTML = '<strong>Nothing can be saved here</strong>'
      + '<br><span style="font-size:0.75rem;opacity:0.5">This browser is offering neither its own storage nor a folder to write to, so downloads cannot be kept.</span>';
    label.style.color = 'var(--color-warning, #ff9800)';
    chooseDirBtn.style.display = RunAnywhere.storage.isSupported ? '' : 'none';
    reauthBtn.style.display = 'none';
  } else {
    label.innerHTML = '<strong>Private browser storage</strong>'
      + `<br><span style="font-size:0.75rem;opacity:0.5">The browser keeps these files for this site; they don&rsquo;t appear in your file manager. Choose a folder to keep them somewhere you can see.</span>`;
    label.style.color = '';
    chooseDirBtn.style.display = '';
    reauthBtn.style.display = 'none';
  }
}

// ---------------------------------------------------------------------------
// Model list (registry view + live transfers + per-model Delete)
// ---------------------------------------------------------------------------

/**
 * The badge naming a model's state, in the words the picker and the pipeline
 * slots already use.
 *
 * This list read from the registry alone, so it knew only three states —
 * "Loaded", "Downloaded", "Not downloaded" — and a transfer running right now
 * appeared under a tab called *Downloads* as "Not downloaded". The state comes
 * from the same snapshot the picker renders from, so the two cannot disagree
 * about what a model is doing.
 */
function storageStatusBadge(status: ModelStatusSnapshot): string {
  switch (status.status) {
    case 'loaded':
      // "Active" everywhere in this app, and "On device" for merely downloaded —
      // the split iOS draws between `activeIndicator` and a model that is only
      // on disk. This badge used to be the app's fourth word for the same state.
      return '<span class="badge badge-green">Active</span>';
    case 'downloaded':
      return '<span class="badge badge-blue">On device</span>';
    case 'downloading':
      return `<span class="badge badge-blue">${escapeHtml(downloadingBadgeLabel(status))}</span>`;
    case 'loading':
      return '<span class="badge badge-blue">Loading…</span>';
    case 'paused':
      return '<span class="badge badge-yellow">Paused</span>';
    case 'error':
      return '<span class="badge badge-red">Failed</span>';
    default:
      return '<span class="badge badge-grey">Not downloaded</span>';
  }
}

/** The phase's own name, so a checksum is not reported as a stalled transfer. */
function downloadingBadgeLabel(status: ModelStatusSnapshot): string {
  switch (status.phase) {
    case 'queued':
      return 'Starting…';
    case 'cancelling':
      return 'Cancelling…';
    case 'verifying':
      return 'Checking…';
    case 'extracting':
      return 'Unpacking…';
    default:
      return 'Downloading';
  }
}

/** What a row is, as opposed to what its numbers currently read. */
function rowShape(status: ModelStatusSnapshot): string {
  return `${status.status}|${status.phase ?? ''}|${status.error ?? ''}`;
}

/**
 * Apply a model-state change to the list, rebuilding only when it changed shape.
 *
 * A running transfer emits about four progress events a second. Rebuilding the
 * whole list on each of them would take the focus ring with it every time, so a
 * keyboard user could never reach the Cancel button on the row they are watching
 * — and the bar would restart its width transition on each rebuild, stuttering
 * rather than gliding. A tick that only moves numbers is written into the
 * existing markup instead.
 */
function syncModelList(): void {
  if (!patchLiveTransfers()) renderModelList();
}

/** True when every row is still the shape it was rendered as and at least one
 * live transfer was updated in place. */
function patchLiveTransfers(): boolean {
  const host = container.querySelector('#storage-model-list');
  if (!host || renderedRowShapes.size === 0) return false;

  const live: Array<[Element, ModelStatusSnapshot]> = [];
  for (const entry of getCatalog()) {
    const status = getModelStatus(entry.id);
    if (renderedRowShapes.get(entry.id) !== rowShape(status)) return false;
    if (status.status !== 'downloading') continue;
    const row = host.querySelector(`[data-model-id="${CSS.escape(entry.id)}"]`);
    if (!row) return false;
    live.push([row, status]);
  }
  if (live.length === 0) return false;
  return live.every(([row, status]) => patchDownloadProgress(row, status));
}

function renderModelList(): void {
  const host = container.querySelector('#storage-model-list') as HTMLElement | null;
  if (!host) return;

  const catalog = getCatalog();
  renderedRowShapes.clear();
  if (!catalog.length) {
    host.innerHTML = '<p class="text-secondary" style="padding: 12px 0;">No models yet — still loading the list.</p>';
    return;
  }

  host.innerHTML = catalog.map((entry) => {
    const status = getModelStatus(entry.id);
    // Not "is downloading": the wind-down phases are still `downloading`, and a
    // Cancel there is a live-looking button with nothing left to stop — the row
    // rendered one throughout the cancel it had just started. The picker decides
    // this from the same predicate, so one transfer cannot be offered a Cancel
    // on one screen and refused it on the other.
    const canCancel = isDownloadCancellable(entry.id);
    const hasArtifacts = status.status === 'downloaded' || status.status === 'loaded';
    // A paused or failed transfer left partial bytes on disk. Delete is the only
    // way to reclaim them, so the row that says they exist also offers it.
    const hasPartials = status.status === 'paused' || status.status === 'error';
    renderedRowShapes.set(entry.id, rowShape(status));
    return `
      <div class="model-row" style="cursor: default;" data-model-id="${escapeHtml(entry.id)}">
        <div class="model-logo">${icon(modalityIcon(entry.category), { size: 20 })}</div>
        <div class="model-info">
          <div class="model-name">${escapeHtml(entry.name)}</div>
          <div class="model-meta">
            <span class="model-framework-badge">${formatFramework(entry.framework)}</span>
            <span class="model-size">${formatModelSize(modelDisplaySizeBytes(entry))}</span>
            ${storageStatusBadge(status)}
          </div>
          ${renderDownloadProgress(status)}
          ${status.status === 'paused'
            ? '<div class="model-row-error">Paused — resume from Manage Models picks up where it stopped</div>'
            : ''}
          ${status.status === 'error'
            ? `<div class="model-row-error error">${escapeHtml(status.error ?? 'Download failed')}</div>`
            : ''}
        </div>
        ${canCancel
          ? `<button class="btn btn-secondary btn-sm storage-cancel-btn" data-model-id="${escapeHtml(entry.id)}" style="font-size: 0.75rem;">Cancel</button>`
          : ''}
        ${hasArtifacts || hasPartials
          ? `<button class="btn btn-secondary btn-sm storage-delete-btn" data-model-id="${escapeHtml(entry.id)}" style="font-size: 0.75rem;">Delete</button>`
          : ''}
      </div>
    `;
  }).join('');

  host.querySelectorAll<HTMLButtonElement>('.storage-delete-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const modelId = btn.dataset.modelId;
      if (modelId) void deleteModel(modelId);
    });
  });
  host.querySelectorAll<HTMLButtonElement>('.storage-cancel-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const modelId = btn.dataset.modelId;
      if (modelId) void cancelModelDownload(modelId);
    });
  });
}

async function deleteModel(modelId: string): Promise<void> {
  try {
    await RunAnywhere.models.delete(modelId);
    // Clears the row's memory of a paused or failed attempt too: the partial
    // bytes are gone, so an offer to resume them would be a lie.
    resetModelRowState(modelId);
    showToast(`Deleted ${modelId}`, 'success');
  } catch (err) {
    showToast(`Failed to delete model: ${formatError(err)}`, 'warning');
  }
  await refreshStorageInfo();
  renderModelList();
}
