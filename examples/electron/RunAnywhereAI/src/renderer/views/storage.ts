/**
 * Storage — what is on disk, and how to free it.
 *
 * Thin SDK calls: `storage.info` / `clearCache` / `cleanTempFiles` when present,
 * plus `models.list` / `models.delete` for the per-model rows (Swift
 * `StorageViewModel`). Reveal uses `appStore.revealPath`.
 */
import { escapeHtml, formatSize } from '../services/format';
import { showError, showToast } from '../components/toast';
import type { ViewFactory } from '../shell/app';

interface StoredModelRow {
  readonly id: string;
  readonly name: string;
  readonly sizeBytes: number;
  readonly localPath?: string;
}

interface StorageSnapshot {
  readonly usedBytes: number;
  readonly freeBytes: number;
  readonly cacheBytes: number;
  readonly models: readonly StoredModelRow[];
}

async function loadSnapshot(): Promise<StorageSnapshot> {
  const ra = window.runanywhere;
  let usedBytes = 0;
  let freeBytes = 0;
  let cacheBytes = 0;

  try {
    const info = await ra.storage.info();
    const device = info.info?.device;
    const app = info.info?.app;
    usedBytes = device?.usedBytes ?? info.info?.totalModelsBytes ?? 0;
    freeBytes = device?.freeBytes ?? 0;
    cacheBytes = app?.cacheBytes ?? 0;
  } catch {
    // Fall back to the aggregate numbers Swift still uses when the analyzer
    // surface is unavailable.
    const state = await ra.models.state();
    usedBytes = state.storageUsedBytes;
    freeBytes = state.storageFreeBytes;
  }

  const listed = await ra.models.list({ downloadedOnly: true });
  const models = listed
    .filter((model) => model.sizeBytes > 0)
    .map(
      (model): StoredModelRow => ({
        id: model.id,
        name: model.name,
        sizeBytes: model.sizeBytes,
        localPath: model.localPath,
      }),
    );

  return { usedBytes, freeBytes, cacheBytes, models };
}

function renderSummary(host: HTMLElement, snap: StorageSnapshot): void {
  host.innerHTML =
    `<div class="ra-card ra-stack">` +
    `<div class="ra-row" style="justify-content:space-between">` +
    `<div><div class="ra-muted-label">Models on disk</div><div class="ra-stat">${escapeHtml(formatSize(snap.usedBytes))}</div></div>` +
    `<div><div class="ra-muted-label">Free space</div><div class="ra-stat">${escapeHtml(formatSize(snap.freeBytes))}</div></div>` +
    `<div><div class="ra-muted-label">Cache</div><div class="ra-stat">${escapeHtml(formatSize(snap.cacheBytes))}</div></div>` +
    `</div>` +
    `<div class="ra-row">` +
    `<button type="button" class="ra-btn-secondary" data-action="reveal">Reveal folder</button>` +
    `<button type="button" class="ra-btn-secondary" data-action="clear-cache">Clear cache</button>` +
    `<button type="button" class="ra-btn-secondary" data-action="clean-temp">Clean temp</button>` +
    `<button type="button" class="ra-btn-quiet" data-action="refresh">Refresh</button>` +
    `</div>` +
    `</div>`;
}

function renderModels(host: HTMLElement, models: readonly StoredModelRow[]): void {
  if (models.length === 0) {
    host.innerHTML = `<p class="ra-muted">No downloaded models yet. Download one from Models.</p>`;
    return;
  }
  host.innerHTML =
    `<div class="ra-dense-list">` +
    models
      .map(
        (model) =>
          `<div class="ra-dense-row" data-model-id="${escapeHtml(model.id)}">` +
          `<div class="ra-dense-copy">` +
          `<strong>${escapeHtml(model.name)}</strong>` +
          `<small>${escapeHtml(formatSize(model.sizeBytes))}` +
          (model.localPath === undefined ? '' : ` · ${escapeHtml(model.localPath)}`) +
          `</small>` +
          `</div>` +
          `<div class="ra-row">` +
          (model.localPath === undefined
            ? ''
            : `<button type="button" class="ra-btn-quiet" data-action="reveal-model">Reveal</button>`) +
          `<button type="button" class="ra-btn-quiet" data-action="delete-model">Delete</button>` +
          `</div>` +
          `</div>`,
      )
      .join('') +
    `</div>`;
}

export const createStorageView: ViewFactory = ({ root }) => {
  let disposed = false;
  let snapshot: StorageSnapshot | null = null;

  const scroll = document.createElement('div');
  scroll.className = 'ra-view-scroll ra-stack';
  scroll.innerHTML =
    `<div id="storage-summary"><p class="ra-muted">Loading storage…</p></div>` +
    `<section class="ra-stack">` +
    `<h2 class="ra-section-title">Downloaded models</h2>` +
    `<div id="storage-models"></div>` +
    `</section>`;
  root.append(scroll);

  const summaryHost = scroll.querySelector<HTMLElement>('#storage-summary');
  const modelsHost = scroll.querySelector<HTMLElement>('#storage-models');
  if (summaryHost === null || modelsHost === null) return {};

  const refresh = async (): Promise<void> => {
    try {
      snapshot = await loadSnapshot();
      if (disposed) return;
      renderSummary(summaryHost, snapshot);
      renderModels(modelsHost, snapshot.models);
    } catch (error) {
      if (disposed) return;
      showError(error, 'Could not load storage');
      summaryHost.innerHTML = `<p class="ra-muted">Storage info unavailable.</p>`;
    }
  };

  scroll.addEventListener('click', (event) => {
    const button = (event.target as HTMLElement).closest<HTMLButtonElement>('[data-action]');
    if (button === null) return;
    const action = button.dataset.action;
    const row = button.closest<HTMLElement>('[data-model-id]');
    const modelId = row?.dataset.modelId;

    void (async () => {
      try {
        switch (action) {
          case 'refresh':
            await refresh();
            return;
          case 'reveal': {
            const platform = await window.appStore.platformInfo();
            await window.appStore.revealPath(platform.modelsDirectory);
            return;
          }
          case 'clear-cache':
            await window.runanywhere.storage.clearCache();
            showToast('Cache cleared', 'success');
            await refresh();
            return;
          case 'clean-temp':
            await window.runanywhere.storage.cleanTempFiles();
            showToast('Temp files cleaned', 'success');
            await refresh();
            return;
          case 'reveal-model': {
            const path = snapshot?.models.find((m) => m.id === modelId)?.localPath;
            if (path !== undefined) await window.appStore.revealPath(path);
            return;
          }
          case 'delete-model': {
            if (modelId === undefined) return;
            if (!window.confirm(`Delete ${modelId} from disk?`)) return;
            await window.runanywhere.models.delete(modelId);
            showToast('Model deleted', 'success');
            await refresh();
            return;
          }
          case undefined:
            return;
          default:
            return;
        }
      } catch (error) {
        showError(error);
      }
    })();
  });

  void refresh();

  return {
    dispose() {
      disposed = true;
    },
  };
};
