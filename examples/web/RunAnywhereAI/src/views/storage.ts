/**
 * Storage Tab — minimal storage location switcher.
 *
 * The previous storage tab depended on `ModelManager.getModels()` /
 * `ModelManager.getStorageInfo()` for downloaded model accounting; both
 * were deleted in the V2 cleanup. Until the proto-byte storage adapter is
 * wired into the example, the storage tab only exposes the persistent
 * directory chooser (`RunAnywhere.chooseLocalStorageDirectory`) which is
 * still backed by `LocalFileStorage` in the core SDK.
 */

import type { TabLifecycle } from '../app';
import { showToast } from '../components/dialogs';
import { RunAnywhere } from '@runanywhere/web';

let container: HTMLElement;

export function initStorageTab(el: HTMLElement): TabLifecycle {
  container = el;
  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Storage</div>
      <div class="toolbar-actions"></div>
    </div>
    <div class="scroll-area">
      <div class="storage-location" id="storage-location" style="padding: 12px 16px; margin-bottom: 12px; border-radius: 8px; background: var(--surface-secondary, #1a1a2e); display: flex; align-items: center; gap: 12px; flex-wrap: wrap;">
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
      <div class="feature-unavailable" style="margin-top: 8px;">
        <h2>Model storage browser is offline</h2>
        <p class="feature-unavailable__description">
          Listing downloaded models, quota, and per-model deletion previously
          flowed through the legacy <code>ModelManager</code> service that
          was deleted in the V2 cleanup. The replacement is a proto-byte
          storage adapter (<code>StorageAdapter</code> / <code>ModelRegistry</code>
          extensions) installed by the backend WASM modules.
        </p>
        <p class="feature-unavailable__hint">
          The <strong>storage location</strong> control above still works
          today — it talks to <code>RunAnywhere.chooseLocalStorageDirectory</code>
          in the pure-TypeScript core.
        </p>
      </div>
    </div>
  `;

  container.querySelector('#storage-choose-dir-btn')!.addEventListener('click', async () => {
    try {
      const ok = await RunAnywhere.chooseLocalStorageDirectory();
      if (ok) {
        showToast(`Using folder: ${RunAnywhere.localStorageDirectoryName ?? 'selected'}`, 'success');
      } else {
        showToast('Folder selection cancelled or unsupported', 'info');
      }
    } catch (err) {
      showToast(err instanceof Error ? err.message : String(err), 'warning');
    }
    updateStorageLocationUI();
  });

  container.querySelector('#storage-reauth-btn')!.addEventListener('click', async () => {
    const ok = await RunAnywhere.requestLocalStorageAccess();
    showToast(ok ? 'Access re-authorized' : 'Access not granted', ok ? 'success' : 'warning');
    updateStorageLocationUI();
  });

  updateStorageLocationUI();

  return {
    onActivate(): void {
      updateStorageLocationUI();
    },
  };
}

function updateStorageLocationUI(): void {
  const label = container.querySelector('#storage-location-label') as HTMLElement;
  const chooseDirBtn = container.querySelector('#storage-choose-dir-btn') as HTMLElement;
  const reauthBtn = container.querySelector('#storage-reauth-btn') as HTMLElement;

  if (RunAnywhere.isLocalStorageReady) {
    const safeName = escapeHtml(RunAnywhere.localStorageDirectoryName ?? 'Unknown');
    label.innerHTML = `<strong>Local Folder:</strong> ~/${safeName}/`
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

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
