/**
 * Storage Tab - Manage downloaded models and disk usage.
 * Mirrors iOS StorageView with enhanced quota bar, LRU timestamps,
 * delete confirmations, and toast notifications.
 */

import type { TabLifecycle } from '../app';
import { ModelManager } from '../services/model-manager';
import { showToast, showConfirmDialog } from '../components/dialogs';

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
      <div id="storage-models" class="storage-models-list"></div>
      <div class="storage-actions">
        <button class="btn btn-danger" id="storage-clear-btn">Clear All Models</button>
      </div>
    </div>
  `;

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
