/**
 * Storage Tab — storage location switcher plus a minimal model catalog view
 * that surfaces registry state via proto-byte adapters.
 *
 * The model browser half is intentionally read-only: it lists everything
 * the app has registered via `services/model-catalog.ts` plus anything the
 * SDK reports as downloaded/loaded. Downloading + loading lives in
 * `components/model-selection.ts` — the chat toolbar pill is the single
 * canonical entry point for that.
 */

import type { TabLifecycle } from '../app';
import { showToast } from '../components/dialogs';
import {
  RunAnywhere,
  InferenceFramework,
  ModelCategory,
} from '@runanywhere/web';
import type { ModelInfo } from '@runanywhere/web';
import {
  ensureCatalogRegistered,
  onModelStateChange,
  openSheet as openModelSheet,
} from '../components/model-selection';
import { getCatalog } from '../services/model-catalog';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';

let container: HTMLElement;
let unsubscribeState: (() => void) | null = null;

export function initStorageTab(el: HTMLElement): TabLifecycle {
  container = el;
  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Storage</div>
      <div class="toolbar-actions"></div>
    </div>
    <div class="scroll-area" id="storage-scroll">
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

  ensureCatalogRegistered();
  updateStorageLocationUI();
  renderModelList();

  unsubscribeState = onModelStateChange(() => renderModelList());

  return {
    onActivate(): void {
      ensureCatalogRegistered();
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
      </div>
    `;
  }).join('');
}

function lookupModelInfo(modelId: string): ModelInfo | null {
  try {
    return RunAnywhere.getModel(modelId);
  } catch {
    return null;
  }
}

function modalityEmoji(category: ModelCategory): string {
  switch (category) {
    case ModelCategory.MODEL_CATEGORY_LANGUAGE: return '&#129302;';
    case ModelCategory.MODEL_CATEGORY_MULTIMODAL: return '&#128065;';
    case ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION: return '&#127908;';
    case ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS: return '&#128266;';
    case ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION: return '&#128483;';
    case ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION: return '&#127912;';
    case ModelCategory.MODEL_CATEGORY_EMBEDDING: return '&#128279;';
    default: return '&#9881;&#65039;';
  }
}

function formatFramework(framework: InferenceFramework): string {
  switch (framework) {
    case InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP: return 'llama.cpp';
    case InferenceFramework.INFERENCE_FRAMEWORK_ONNX: return 'ONNX';
    case InferenceFramework.INFERENCE_FRAMEWORK_COREML: return 'CoreML';
    case InferenceFramework.INFERENCE_FRAMEWORK_MLX: return 'MLX';
    default: return 'Unknown';
  }
}

function formatBytes(bytes: number): string {
  if (bytes >= 1_000_000_000) return `${(bytes / 1_000_000_000).toFixed(1)} GB`;
  if (bytes >= 1_000_000) return `${Math.round(bytes / 1_000_000)} MB`;
  return `${Math.round(bytes / 1_000)} KB`;
}
