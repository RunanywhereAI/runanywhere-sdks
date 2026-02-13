/**
 * Model Selection Sheet - Modal with device info + model list
 * Matches iOS ModelSelectionSheet.
 */

import { ModelManager, ModelCategory, type ModelInfo } from '../services/model-manager';

let modalEl: HTMLElement | null = null;

// ---------------------------------------------------------------------------
// Show Modal
// ---------------------------------------------------------------------------

export function showModelSelectionSheet(modality?: ModelCategory): void {
  if (modalEl) return; // Already open

  const models = modality
    ? ModelManager.getModels().filter((m) => m.modality === modality)
    : ModelManager.getModels();

  // Device info
  const memory = (navigator as any).deviceMemory ?? '--';
  const cores = navigator.hardwareConcurrency ?? '--';
  const browser = detectBrowser();

  modalEl = document.createElement('div');
  modalEl.className = 'modal-backdrop';
  modalEl.innerHTML = `
    <div class="modal-sheet">
      <div class="modal-handle"></div>
      <div class="modal-header">
        <h3 class="text-md font-semibold">Select Model</h3>
        <button class="btn-ghost" id="model-sheet-close">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="20" height="20"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
        </button>
      </div>
      <div class="modal-body">
        <!-- Device Info -->
        <div class="device-info">
          <div class="device-info-item">
            <div class="value">${browser}</div>
            <div class="label">Browser</div>
          </div>
          <div class="device-info-item">
            <div class="value">${memory} GB</div>
            <div class="label">Memory</div>
          </div>
          <div class="device-info-item">
            <div class="value">${cores}</div>
            <div class="label">CPU Cores</div>
          </div>
        </div>

        <!-- Model List -->
        <div id="model-sheet-list"></div>
      </div>
    </div>
  `;

  document.body.appendChild(modalEl);

  // Close handlers
  modalEl.querySelector('#model-sheet-close')!.addEventListener('click', closeSheet);
  modalEl.addEventListener('click', (e) => {
    if (e.target === modalEl) closeSheet();
  });

  // Render model list
  renderModelList(models);

  // Subscribe to updates
  const unsub = ModelManager.onChange(() => {
    const updated = modality
      ? ModelManager.getModels().filter((m) => m.modality === modality)
      : ModelManager.getModels();
    renderModelList(updated);
  });

  // Store unsub for cleanup
  (modalEl as any).__unsub = unsub;
}

// ---------------------------------------------------------------------------
// Close Modal
// ---------------------------------------------------------------------------

function closeSheet(): void {
  if (!modalEl) return;
  const unsub = (modalEl as any).__unsub;
  if (typeof unsub === 'function') unsub();
  modalEl.remove();
  modalEl = null;
}

// ---------------------------------------------------------------------------
// Render Model List
// ---------------------------------------------------------------------------

function renderModelList(models: ModelInfo[]): void {
  const listEl = document.getElementById('model-sheet-list');
  if (!listEl) return;

  listEl.innerHTML = models
    .map((m) => {
      const actionBtn = getActionButton(m);
      const progressBar = m.status === 'downloading'
        ? `<div class="progress-bar mt-sm"><div class="progress-fill" style="width:${(m.downloadProgress ?? 0) * 100}%;"></div></div>`
        : '';

      return `
        <div class="model-row" data-model-id="${m.id}">
          <div class="model-logo">${getModelEmoji(m)}</div>
          <div class="model-info">
            <div class="model-name">${m.name}</div>
            <div class="model-meta">
              <span class="model-framework-badge">${m.framework}</span>
              ${m.memoryRequirement ? `<span class="model-size">${formatMB(m.memoryRequirement)}</span>` : ''}
            </div>
            ${progressBar}
          </div>
          ${actionBtn}
        </div>
      `;
    })
    .join('');

  // Attach action handlers
  listEl.querySelectorAll('[data-action]').forEach((btn) => {
    const action = (btn as HTMLElement).dataset.action!;
    const modelId = (btn as HTMLElement).dataset.modelId!;

    btn.addEventListener('click', async (e) => {
      e.stopPropagation();
      if (action === 'download') {
        await ModelManager.downloadModel(modelId);
      } else if (action === 'load') {
        const success = await ModelManager.loadModel(modelId);
        if (success) {
          showToast(`${ModelManager.getModels().find((m) => m.id === modelId)?.name ?? 'Model'} Ready`);
          closeSheet();
        }
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Action Button
// ---------------------------------------------------------------------------

function getActionButton(model: ModelInfo): string {
  switch (model.status) {
    case 'registered':
      return `<button class="model-action-btn download" data-action="download" data-model-id="${model.id}">Download</button>`;
    case 'downloading':
      return `<button class="model-action-btn" disabled>${Math.round((model.downloadProgress ?? 0) * 100)}%</button>`;
    case 'downloaded':
      return `<button class="model-action-btn load" data-action="load" data-model-id="${model.id}">Load</button>`;
    case 'loading':
      return `<button class="model-action-btn" disabled>Loading...</button>`;
    case 'loaded':
      return `<button class="model-action-btn loaded">Loaded</button>`;
    case 'error':
      return `<button class="model-action-btn model-action-btn--retry" data-action="download" data-model-id="${model.id}">Retry</button>`;
    default:
      return '';
  }
}

// ---------------------------------------------------------------------------
// Toast
// ---------------------------------------------------------------------------

function showToast(message: string): void {
  const existing = document.querySelector('.toast');
  existing?.remove();

  const toast = document.createElement('div');
  toast.className = 'toast';
  toast.innerHTML = `
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="var(--color-green)" stroke-width="2" width="18" height="18"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>
    <span>${message}</span>
  `;
  document.body.appendChild(toast);

  requestAnimationFrame(() => {
    requestAnimationFrame(() => toast.classList.add('show'));
  });

  setTimeout(() => {
    toast.classList.remove('show');
    setTimeout(() => toast.remove(), 300);
  }, 3000);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function getModelEmoji(model: ModelInfo): string {
  switch (model.modality) {
    case ModelCategory.Language: return '&#129302;';
    case ModelCategory.Multimodal: return '&#128065;';
    case ModelCategory.SpeechRecognition: return '&#127908;';
    case ModelCategory.SpeechSynthesis: return '&#128266;';
    case ModelCategory.ImageGeneration: return '&#127912;';
    default: return '&#129302;';
  }
}

function formatMB(bytes: number): string {
  if (bytes >= 1_000_000_000) return (bytes / 1_000_000_000).toFixed(1) + ' GB';
  return (bytes / 1_000_000).toFixed(0) + ' MB';
}

function detectBrowser(): string {
  const ua = navigator.userAgent;
  if (ua.includes('Chrome')) return 'Chrome';
  if (ua.includes('Firefox')) return 'Firefox';
  if (ua.includes('Safari')) return 'Safari';
  if (ua.includes('Edge')) return 'Edge';
  return 'Browser';
}
