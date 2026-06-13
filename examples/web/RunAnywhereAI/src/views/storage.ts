/**
 * Storage Tab — storage info header + maintenance actions + a model catalog
 * view that surfaces registry state via proto-byte adapters.
 *
 * Mirrors iOS `StorageViewModel` (StorageViewModel.swift:28-103):
 *   - `RunAnywhere.getStorageInfo(request)` drives the used/free header.
 *   - Clear Cache / Clean Temp delegate to the SDK verbs.
 *   - Per-model Delete goes through `RunAnywhere.deleteModel(modelId)`.
 *
 * The storage-location switcher (OPFS vs local folder) is justified web
 * platform code — browsers expose two storage backends, iOS has one.
 * Downloading + loading lives in `components/model-selection.ts`.
 */

import type { TabLifecycle } from '../app';
import { showToast } from '../components/dialogs';
import {
  RunAnywhere,
  deviceStorageUsagePercentage,
  storageInfoAppStorage,
  storageInfoDeviceStorage,
  storageInfoTotalModelsSize,
} from '@runanywhere/web';
import type { ModelInfo, StorageInfo } from '@runanywhere/web';
import {
  StorageInfoRequest,
} from '@runanywhere/proto-ts/storage_types';
import {
  onModelStateChange,
  openSheet as openModelSheet,
} from '../components/model-selection';
import { getCatalog } from '../services/model-catalog';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';
import {
  formatBytes,
  formatFramework,
  modalityEmoji,
} from '../services/model-display';

let container: HTMLElement;
let unsubscribeState: (() => void) | null = null;
let lastStorageInfo: StorageInfo | null = null;
let storageInfoError: string | null = null;

export function initStorageTab(el: HTMLElement): TabLifecycle {
  container = el;
  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Storage</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="storage-clear-cache-btn" style="font-size: 0.8rem;">Clear Cache</button>
        <button class="btn btn-secondary" id="storage-clean-temp-btn" style="font-size: 0.8rem;">Clean Temp</button>
      </div>
    </div>
    <div class="scroll-area" id="storage-scroll">
      <div id="storage-info-header" style="padding: 12px 16px; margin-bottom: 12px; border-radius: 8px; background: var(--surface-secondary, #1a1a2e);"></div>

      <div
        class="storage-location"
        id="storage-location"
        style="padding: 12px 16px; margin-bottom: 12px; border-radius: 8px; background: var(--surface-secondary, #1a1a2e); display: flex; align-items: center; gap: 12px; flex-wrap: wrap;"
      >
        <div style="flex: 1; min-width: 200px;">
          <div style="font-size: 0.75rem; opacity: 0.6; margin-bottom: 2px;">Storage Location</div>
          <div id="storage-location-label" style="font-size: 0.9rem; font-weight: 500;">Browser Storage (OPFS)</div>
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

  container.querySelector('#storage-clear-cache-btn')!.addEventListener('click', async () => {
    // iOS parity: StorageViewModel.swift:68-75 `clearCache()`.
    try {
      await RunAnywhere.clearCache();
      showToast('Cache cleared', 'success');
    } catch (err) {
      showToast(`Failed to clear cache: ${formatError(err)}`, 'warning');
    }
    refreshStorageInfo();
  });

  container.querySelector('#storage-clean-temp-btn')!.addEventListener('click', async () => {
    // iOS parity: StorageViewModel.swift:77-84 `cleanTempFiles()`.
    try {
      await RunAnywhere.cleanTempFiles();
      showToast('Temporary files cleaned', 'success');
    } catch (err) {
      showToast(`Failed to clean temporary files: ${formatError(err)}`, 'warning');
    }
    refreshStorageInfo();
  });

  container.querySelector('#storage-choose-dir-btn')!.addEventListener('click', async () => {
    try {
      const ok = await RunAnywhere.storage.chooseLocalStorageDirectory();
      if (ok) {
        showToast(`Using folder: ${RunAnywhere.storage.localStorageDirectoryName ?? 'selected'}`, 'success');
      } else {
        showToast('Folder selection cancelled or unsupported', 'info');
      }
    } catch (err) {
      showToast(formatError(err), 'warning');
    }
    updateStorageLocationUI();
  });

  container.querySelector('#storage-reauth-btn')!.addEventListener('click', async () => {
    const ok = await RunAnywhere.storage.requestLocalStorageAccess();
    showToast(ok ? 'Access re-authorized' : 'Access not granted', ok ? 'success' : 'warning');
    updateStorageLocationUI();
  });

  container.querySelector('#storage-open-selection-btn')!.addEventListener('click', () => {
    openModelSheet();
  });
  refreshStorageInfo();
  updateStorageLocationUI();
  renderModelList();

  unsubscribeState = onModelStateChange(() => {
    refreshStorageInfo();
    renderModelList();
  });

  return {
    onActivate(): void {
      refreshStorageInfo();
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

function refreshStorageInfo(): void {
  storageInfoError = null;
  lastStorageInfo = null;
  try {
    const result = RunAnywhere.getStorageInfo(StorageInfoRequest.fromPartial({
      includeDevice: true,
      includeApp: true,
      includeModels: true,
      includeCache: true,
    }));
    if (!result.success) {
      storageInfoError = result.errorMessage || 'Failed to load storage data';
    } else {
      lastStorageInfo = result.info ?? null;
    }
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

  const app = storageInfoAppStorage(lastStorageInfo);
  const device = storageInfoDeviceStorage(lastStorageInfo);
  const modelsSize = storageInfoTotalModelsSize(lastStorageInfo);
  const usedPct = deviceStorageUsagePercentage(device);

  host.innerHTML = `
    <div style="font-size: 0.75rem; opacity: 0.6; margin-bottom: 6px;">Storage</div>
    <div style="display: flex; gap: 24px; flex-wrap: wrap; font-size: 0.85rem;">
      <div><strong>App used:</strong> ${formatBytes(app.totalBytes)}</div>
      <div><strong>Models:</strong> ${formatBytes(modelsSize)}</div>
      <div><strong>Device free:</strong> ${formatBytes(device.freeBytes)}</div>
    </div>
    ${device.totalBytes > 0
      ? `<div class="progress-bar" style="margin-top: 8px;">
          <div class="progress-fill" style="width:${Math.min(100, Math.round(usedPct))}%"></div>
        </div>`
      : ''}
  `;
}

// ---------------------------------------------------------------------------
// Storage location switcher (web platform code)
// ---------------------------------------------------------------------------

function updateStorageLocationUI(): void {
  const label = container.querySelector('#storage-location-label') as HTMLElement;
  const chooseDirBtn = container.querySelector('#storage-choose-dir-btn') as HTMLElement;
  const reauthBtn = container.querySelector('#storage-reauth-btn') as HTMLElement;

  if (RunAnywhere.storage.isLocalStorageReady) {
    const safeName = escapeHtml(RunAnywhere.storage.localStorageDirectoryName ?? 'Unknown');
    label.innerHTML = `<strong>Local Folder:</strong> ~/${safeName}/`
      + `<br><span style="font-size:0.75rem;opacity:0.5">Models saved as real files &mdash; visible in Finder, persists forever</span>`;
    label.style.color = 'var(--color-success, #4caf50)';
    chooseDirBtn.textContent = 'Change Folder';
    reauthBtn.style.display = 'none';
  } else if (RunAnywhere.storage.hasLocalStorageHandle) {
    label.innerHTML = 'Local folder configured &mdash; needs re-authorization'
      + `<br><span style="font-size:0.75rem;opacity:0.5">Click "Re-authorize" to reconnect</span>`;
    label.style.color = 'var(--color-warning, #ff9800)';
    reauthBtn.style.display = '';
  } else {
    label.innerHTML = '<strong>Browser Storage (OPFS)</strong>'
      + `<br><span style="font-size:0.75rem;opacity:0.5">Sandboxed browser storage &mdash; not visible in Finder. Use "Choose Storage Folder" for a real path.</span>`;
    label.style.color = '';
    reauthBtn.style.display = 'none';
  }
}

// ---------------------------------------------------------------------------
// Model list (read-only registry view + per-model Delete)
// ---------------------------------------------------------------------------

function renderModelList(): void {
  const host = container.querySelector('#storage-model-list') as HTMLElement | null;
  if (!host) return;

  const catalog = getCatalog();
  if (!catalog.length) {
    host.innerHTML = '<p class="text-secondary" style="padding: 12px 0;">Catalog not registered yet.</p>';
    return;
  }

  const downloadedIds = new Set<string>();
  try {
    const downloaded = RunAnywhere.downloadedModels();
    for (const m of downloaded?.models ?? []) downloadedIds.add(m.id);
  } catch {
    // tolerate — adapter may not be installed
  }

  let loadedId: string | null = null;
  try {
    loadedId = RunAnywhere.currentModel()?.modelId || null;
  } catch {
    loadedId = null;
  }

  host.innerHTML = catalog.map((entry) => {
    const registryInfo = lookupModelInfo(entry.id);
    const isDownloaded = downloadedIds.has(entry.id) || Boolean(registryInfo?.isDownloaded);
    const isLoaded = entry.id === loadedId;
    const statusLabel = isLoaded
      ? '<span class="badge badge-green">Loaded</span>'
      : isDownloaded
        ? '<span class="badge badge-blue">Downloaded</span>'
        : '<span class="badge badge-grey">Not downloaded</span>';
    return `
      <div class="model-row" style="cursor: default;">
        <div class="model-logo">${modalityEmoji(entry.category)}</div>
        <div class="model-info">
          <div class="model-name">${escapeHtml(entry.name)}</div>
          <div class="model-meta">
            <span class="model-framework-badge">${formatFramework(entry.framework)}</span>
            <span class="model-size">${formatBytes(entry.memoryRequiredBytes)}</span>
            ${statusLabel}
          </div>
        </div>
        ${isDownloaded
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
}

/** iOS parity: StorageViewModel.swift:86-103 `deleteModel(_:)`. */
async function deleteModel(modelId: string): Promise<void> {
  try {
    const result = RunAnywhere.deleteModel(modelId);
    if (!result.success) {
      showToast(result.errorMessage || 'Failed to delete model', 'warning');
      return;
    }
    showToast(`Deleted ${modelId}`, 'success');
  } catch (err) {
    showToast(`Failed to delete model: ${formatError(err)}`, 'warning');
  }
  refreshStorageInfo();
  renderModelList();
}

function lookupModelInfo(modelId: string): ModelInfo | null {
  try {
    return RunAnywhere.getModel(modelId);
  } catch {
    return null;
  }
}
