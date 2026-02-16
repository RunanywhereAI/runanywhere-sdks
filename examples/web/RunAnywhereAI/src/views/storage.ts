/**
 * Storage Tab - Manage downloaded models and disk usage.
 * Mirrors iOS StorageView with enhanced quota bar, LRU timestamps,
 * delete confirmations, and toast notifications.
 */

import type { TabLifecycle } from '../app';
import { ModelManager } from '../services/model-manager';
import { showToast, showConfirmDialog } from '../components/dialogs';
import { RunAnywhere } from '../../../../../sdk/runanywhere-web/packages/core/src/index';

let container: HTMLElement;

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

export function initStorageTab(el: HTMLElement): TabLifecycle {
  container = el;
  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Storage</div>
      <div class="toolbar-actions"></div>
    </div>
    <div class="scroll-area">
      <div class="storage-location" id="storage-location" style="padding: 12px 16px; margin-bottom: 8px; border-radius: 8px; background: var(--surface-secondary, #1a1a2e); display: flex; align-items: center; gap: 12px; flex-wrap: wrap;">
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
      <div class="storage-overview" id="storage-overview">
        <div class="storage-stat"><div class="value" id="storage-count">0</div><div class="label">Models</div></div>
        <div class="storage-stat"><div class="value" id="storage-size">0 MB</div><div class="label">Total Size</div></div>
        <div class="storage-stat"><div class="value" id="storage-available">-- GB</div><div class="label">Available</div></div>
      </div>
      <div class="quota-bar-container" id="quota-bar-container">
        <div class="quota-bar">
          <div class="quota-bar-fill" id="quota-bar-fill"></div>
        </div>
        <div class="quota-bar-label">
          <span id="quota-bar-used">0 MB used</span>
          <span id="quota-bar-total">-- quota</span>
        </div>
      </div>
      <div style="display: flex; gap: 8px; margin-bottom: 12px; flex-wrap: wrap;">
        <button class="btn btn-secondary" id="storage-import-btn" style="flex: 1; min-width: 140px; font-size: 0.85rem; padding: 10px 16px;">
          Import Model File
        </button>
      </div>
      <div id="storage-drop-zone" style="display: none; border: 2px dashed var(--color-primary, #ff6b35); border-radius: 12px; padding: 32px 16px; text-align: center; margin-bottom: 12px; opacity: 0.8; transition: opacity 0.2s;">
        <div style="font-size: 1.1rem; font-weight: 600; margin-bottom: 4px;">Drop model file here</div>
        <div style="font-size: 0.8rem; opacity: 0.6;">Supports .gguf, .onnx, .bin files</div>
      </div>
      <div id="storage-models" class="storage-models-list"></div>
      <div class="storage-actions">
        <button class="btn btn-danger" id="storage-clear-btn">Clear All Models</button>
      </div>
    </div>
  `;

  // Local storage folder picker
  const chooseDirBtn = container.querySelector('#storage-choose-dir-btn') as HTMLButtonElement;
  const reauthBtn = container.querySelector('#storage-reauth-btn') as HTMLButtonElement;

  if (!RunAnywhere.isLocalStorageSupported) {
    chooseDirBtn.disabled = true;
    chooseDirBtn.title = 'Requires Chrome or Edge browser';
    chooseDirBtn.style.opacity = '0.5';
  }

  chooseDirBtn.addEventListener('click', async () => {
    const success = await RunAnywhere.chooseLocalStorageDirectory();
    if (success) {
      showToast(`Local storage: ${RunAnywhere.localStorageDirectoryName}`, 'info');
      updateStorageLocationUI();
    }
  });

  reauthBtn.addEventListener('click', async () => {
    const success = await RunAnywhere.requestLocalStorageAccess();
    if (success) {
      showToast(`Storage access restored: ${RunAnywhere.localStorageDirectoryName}`, 'info');
      updateStorageLocationUI();
    } else {
      showToast('Access denied — try choosing a new folder', 'error');
    }
  });

  updateStorageLocationUI();

  // --- Import Model button (works on ALL browsers via SDK progressive enhancement) ---
  container.querySelector('#storage-import-btn')!.addEventListener('click', async () => {
    const modelId = await RunAnywhere.importModelFromPicker();
    if (modelId) {
      showToast(`Model imported: ${modelId}`, 'info');
      refreshStorage();
    }
  });

  // --- Drag-and-drop zone (desktop only — mobile doesn't support file drag) ---
  const dropZone = container.querySelector('#storage-drop-zone') as HTMLElement;
  const scrollArea = container.querySelector('.scroll-area') as HTMLElement;

  if (window.matchMedia('(hover: hover)').matches) {
    // Desktop: show drop zone when dragging files over the storage tab
    let dragCounter = 0;

    scrollArea.addEventListener('dragenter', (e) => {
      e.preventDefault();
      dragCounter++;
      dropZone.style.display = 'block';
    });

    scrollArea.addEventListener('dragleave', () => {
      dragCounter--;
      if (dragCounter <= 0) {
        dragCounter = 0;
        dropZone.style.display = 'none';
      }
    });

    scrollArea.addEventListener('dragover', (e) => {
      e.preventDefault();
      dropZone.style.opacity = '1';
    });

    scrollArea.addEventListener('drop', async (e) => {
      e.preventDefault();
      dragCounter = 0;
      dropZone.style.display = 'none';

      const file = e.dataTransfer?.files[0];
      if (!file) return;

      const modelId = await RunAnywhere.importModelFromFile(file);
      showToast(`Model imported: ${modelId}`, 'info');
      refreshStorage();
    });
  }

  container.querySelector('#storage-clear-btn')!.addEventListener('click', async () => {
    const confirmed = await showConfirmDialog(
      'Clear All Models',
      'This will remove all downloaded models from storage. You will need to re-download them to use again.',
      'Clear All',
      'Cancel',
      true,
    );
    if (!confirmed) return;

    await ModelManager.clearAll();
    showToast('All models cleared', 'info');
    refreshStorage();
  });

  refreshStorage();

  return {
    onActivate(): void {
      refreshStorage();
    },
  };
}

// ---------------------------------------------------------------------------
// Storage Location UI
// ---------------------------------------------------------------------------

function updateStorageLocationUI(): void {
  const label = container.querySelector('#storage-location-label') as HTMLElement;
  const chooseDirBtn = container.querySelector('#storage-choose-dir-btn') as HTMLElement;
  const reauthBtn = container.querySelector('#storage-reauth-btn') as HTMLElement;

  if (RunAnywhere.isLocalStorageReady) {
    label.innerHTML = `<strong>Local Folder:</strong> ~/${RunAnywhere.localStorageDirectoryName ?? 'Unknown'}/`
      + `<br><span style="font-size:0.75rem;opacity:0.5">Models saved as real files — visible in Finder, persists forever</span>`;
    label.style.color = 'var(--color-success, #4caf50)';
    chooseDirBtn.textContent = 'Change Folder';
    reauthBtn.style.display = 'none';
  } else if (RunAnywhere.hasLocalStorageHandle) {
    label.innerHTML = 'Local folder configured — needs re-authorization'
      + `<br><span style="font-size:0.75rem;opacity:0.5">Click "Re-authorize" to reconnect</span>`;
    label.style.color = 'var(--color-warning, #ff9800)';
    reauthBtn.style.display = '';
  } else {
    label.innerHTML = '<strong>Browser Storage (OPFS)</strong>'
      + `<br><span style="font-size:0.75rem;opacity:0.5">Sandboxed browser storage — not visible in Finder. Use "Choose Storage Folder" for a real path.</span>`;
    label.style.color = '';
    reauthBtn.style.display = 'none';
  }
}

// ---------------------------------------------------------------------------
// Refresh Storage Info
// ---------------------------------------------------------------------------

async function refreshStorage(): Promise<void> {
  const info = await ModelManager.getStorageInfo();
  container.querySelector('#storage-count')!.textContent = String(info.modelCount);
  container.querySelector('#storage-size')!.textContent = formatBytes(info.totalSize);
  container.querySelector('#storage-available')!.textContent = formatBytes(info.available);

  // Quota bar
  const totalQuota = info.totalSize + info.available;
  const usedPercent = totalQuota > 0 ? (info.totalSize / totalQuota) * 100 : 0;
  const fillEl = container.querySelector('#quota-bar-fill') as HTMLElement;
  fillEl.style.width = `${Math.min(usedPercent, 100)}%`;

  // Color coding: green < 70%, orange 70-90%, red > 90%
  fillEl.classList.remove('quota-bar-fill--warning', 'quota-bar-fill--critical');
  if (usedPercent > 90) {
    fillEl.classList.add('quota-bar-fill--critical');
  } else if (usedPercent > 70) {
    fillEl.classList.add('quota-bar-fill--warning');
  }

  container.querySelector('#quota-bar-used')!.textContent = `${formatBytes(info.totalSize)} used`;
  container.querySelector('#quota-bar-total')!.textContent = `${formatBytes(totalQuota)} quota`;

  // Model list
  const modelsEl = container.querySelector('#storage-models')!;
  const downloaded = ModelManager.getModels().filter(
    (m) => m.status === 'downloaded' || m.status === 'loaded',
  );

  if (downloaded.length === 0) {
    modelsEl.innerHTML = '<p class="muted-text">No downloaded models</p>';
  } else {
    // Sort by last used (most recent first)
    const sorted = [...downloaded].sort((a, b) => {
      const aTime = ModelManager.getModelLastUsedAt(a.id);
      const bTime = ModelManager.getModelLastUsedAt(b.id);
      return bTime - aTime;
    });

    modelsEl.innerHTML = sorted
      .map((m) => {
        const lastUsedAt = ModelManager.getModelLastUsedAt(m.id);
        const lastUsedText = lastUsedAt > 0 ? timeAgo(lastUsedAt) : 'Never used';

        return `
        <div class="model-row">
          <div class="model-logo">&#129302;</div>
          <div class="model-info">
            <div class="model-name">${m.name}</div>
            <div class="model-meta">
              <span class="model-framework-badge">${m.framework}</span>
              ${m.sizeBytes ? `<span class="model-size">${formatBytes(m.sizeBytes)}</span>` : ''}
            </div>
            <div class="model-last-used">Last used: ${lastUsedText}</div>
          </div>
          <button class="btn btn-sm text-red" data-delete="${m.id}" data-name="${m.name}" data-size="${m.sizeBytes ?? 0}">Delete</button>
        </div>
      `;
      })
      .join('');

    modelsEl.querySelectorAll('[data-delete]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        const el = btn as HTMLElement;
        const modelId = el.dataset.delete!;
        const modelName = el.dataset.name ?? modelId;
        const modelSize = Number(el.dataset.size ?? 0);

        const confirmed = await showConfirmDialog(
          'Delete Model',
          `Remove <strong>${modelName}</strong> (${formatBytes(modelSize)}) from storage? You will need to re-download it to use again.`,
          'Delete',
          'Cancel',
          true,
        );
        if (!confirmed) return;

        await ModelManager.deleteModel(modelId);
        showToast(`${modelName} removed (freed ${formatBytes(modelSize)})`, 'info');
        refreshStorage();
      });
    });
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return (bytes / Math.pow(1024, i)).toFixed(1) + ' ' + units[Math.min(i, units.length - 1)];
}

/**
 * Convert a timestamp to a human-readable "time ago" string.
 */
function timeAgo(timestamp: number): string {
  const seconds = Math.floor((Date.now() - timestamp) / 1000);
  if (seconds < 60) return 'Just now';

  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;

  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;

  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d ago`;

  return new Date(timestamp).toLocaleDateString();
}
