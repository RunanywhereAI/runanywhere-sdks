/**
 * Storage Tab - Manage downloaded models and disk usage.
 * Mirrors iOS StorageView.
 */

import type { TabLifecycle } from '../app';
import { ModelManager } from '../services/model-manager';

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
      <div id="storage-models" class="storage-models-list"></div>
      <div class="storage-actions">
        <button class="btn btn-danger" id="storage-clear-btn">Clear All Models</button>
      </div>
    </div>
  `;

  container.querySelector('#storage-clear-btn')!.addEventListener('click', async () => {
    await ModelManager.clearAll();
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

  const modelsEl = container.querySelector('#storage-models')!;
  const downloaded = ModelManager.getModels().filter(
    (m) => m.status === 'downloaded' || m.status === 'loaded',
  );

  if (downloaded.length === 0) {
    modelsEl.innerHTML = '<p class="muted-text">No downloaded models</p>';
  } else {
    modelsEl.innerHTML = downloaded
      .map(
        (m) => `
        <div class="model-row">
          <div class="model-logo">&#129302;</div>
          <div class="model-info">
            <div class="model-name">${m.name}</div>
            <div class="model-meta">
              <span class="model-framework-badge">${m.framework}</span>
              ${m.sizeBytes ? `<span class="model-size">${formatBytes(m.sizeBytes)}</span>` : ''}
            </div>
          </div>
          <button class="btn btn-sm text-red" data-delete="${m.id}">Delete</button>
        </div>
      `,
      )
      .join('');

    modelsEl.querySelectorAll('[data-delete]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        await ModelManager.deleteModel((btn as HTMLElement).dataset.delete!);
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
  return (bytes / Math.pow(1024, i)).toFixed(1) + ' ' + units[i];
}
