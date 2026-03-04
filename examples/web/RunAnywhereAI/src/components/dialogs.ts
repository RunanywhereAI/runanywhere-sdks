/**
 * Shared Dialog & Toast System
 *
 * Provides reusable UI primitives for user notifications and confirmations:
 *   - showToast()          — transient success/warning/info messages
 *   - showConfirmDialog()  — generic yes/no modal
 *   - showEvictionDialog() — storage-specific dialog listing models to remove
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type ToastVariant = 'success' | 'warning' | 'info';

export interface EvictionCandidate {
  id: string;
  name: string;
  sizeBytes: number;
}

// ---------------------------------------------------------------------------
// Toast
// ---------------------------------------------------------------------------

const TOAST_ICONS: Record<ToastVariant, string> = {
  success: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="var(--color-green)" stroke-width="2" width="18" height="18"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>`,
  warning: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="var(--color-orange, orange)" stroke-width="2" width="18" height="18"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>`,
  info: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2" width="18" height="18"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>`,
};

/**
 * Show a transient toast notification at the top of the viewport.
 * Auto-dismisses after `durationMs` (default 3 s).
 */
export function showToast(
  message: string,
  variant: ToastVariant = 'success',
  durationMs = 3000,
): void {
  const existing = document.querySelector('.toast');
  existing?.remove();

  const toast = document.createElement('div');
  toast.className = 'toast';
  toast.innerHTML = `${TOAST_ICONS[variant]}<span>${message}</span>`;
  document.body.appendChild(toast);

  requestAnimationFrame(() => {
    requestAnimationFrame(() => toast.classList.add('show'));
  });

  setTimeout(() => {
    toast.classList.remove('show');
    setTimeout(() => toast.remove(), 300);
  }, durationMs);
}

// ---------------------------------------------------------------------------
// Confirm Dialog
// ---------------------------------------------------------------------------

/**
 * Show a generic confirmation dialog.
 * Returns `true` if the user confirms, `false` on cancel.
 */
export function showConfirmDialog(
  title: string,
  message: string,
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  confirmDanger = false,
): Promise<boolean> {
  return new Promise((resolve) => {
    const backdrop = document.createElement('div');
    backdrop.className = 'dialog-backdrop';

    const confirmClass = confirmDanger ? 'dialog-btn dialog-btn--danger' : 'dialog-btn dialog-btn--primary';

    backdrop.innerHTML = `
      <div class="dialog-box">
        <h3 class="dialog-title">${title}</h3>
        <p class="dialog-message">${message}</p>
        <div class="dialog-actions">
          <button class="dialog-btn dialog-btn--cancel" data-role="cancel">${cancelLabel}</button>
          <button class="${confirmClass}" data-role="confirm">${confirmLabel}</button>
        </div>
      </div>
    `;

    const close = (result: boolean) => {
      backdrop.remove();
      resolve(result);
    };

    backdrop.querySelector('[data-role="cancel"]')!.addEventListener('click', () => close(false));
    backdrop.querySelector('[data-role="confirm"]')!.addEventListener('click', () => close(true));
    backdrop.addEventListener('click', (e) => {
      if (e.target === backdrop) close(false);
    });

    document.body.appendChild(backdrop);
  });
}

// ---------------------------------------------------------------------------
// Eviction Dialog
// ---------------------------------------------------------------------------

/**
 * Show a storage-eviction dialog listing models the user can remove
 * to make room for a new download.
 *
 * Returns the list of model IDs the user chose to remove, or `null` on cancel.
 */
export function showEvictionDialog(
  newModelName: string,
  newModelSizeBytes: number,
  availableBytes: number,
  candidates: EvictionCandidate[],
): Promise<string[] | null> {
  return new Promise((resolve) => {
    const backdrop = document.createElement('div');
    backdrop.className = 'dialog-backdrop';

    const neededBytes = newModelSizeBytes - availableBytes;

    const candidateRows = candidates
      .map(
        (c) => `
        <label class="eviction-row">
          <input type="checkbox" checked data-model-id="${c.id}" data-size="${c.sizeBytes}" />
          <span class="eviction-model-name">${c.name}</span>
          <span class="eviction-model-size">${formatBytes(c.sizeBytes)}</span>
        </label>`,
      )
      .join('');

    backdrop.innerHTML = `
      <div class="dialog-box dialog-box--wide">
        <h3 class="dialog-title">Not Enough Storage</h3>
        <p class="dialog-message">
          <strong>${newModelName}</strong> needs ${formatBytes(newModelSizeBytes)}, but only
          ${formatBytes(availableBytes)} is available.
          Select models to remove to free up space.
        </p>
        <div class="eviction-meter">
          <span class="eviction-meter-label">Need to free:</span>
          <span class="eviction-meter-value" id="eviction-needed">${formatBytes(neededBytes)}</span>
        </div>
        <div class="eviction-candidates">${candidateRows}</div>
        <div class="dialog-actions">
          <button class="dialog-btn dialog-btn--cancel" data-role="cancel">Cancel</button>
          <button class="dialog-btn dialog-btn--danger" data-role="confirm" id="eviction-confirm">Remove &amp; Download</button>
        </div>
      </div>
    `;

    const confirmBtn = backdrop.querySelector('#eviction-confirm') as HTMLButtonElement;
    const neededEl = backdrop.querySelector('#eviction-needed')!;

    // Update the "need to free" meter when checkboxes change
    const updateMeter = () => {
      let selected = 0;
      backdrop.querySelectorAll<HTMLInputElement>('input[type="checkbox"]').forEach((cb) => {
        if (cb.checked) selected += Number(cb.dataset.size ?? 0);
      });
      const remaining = neededBytes - selected;
      if (remaining > 0) {
        neededEl.textContent = `${formatBytes(remaining)} more needed`;
        confirmBtn.disabled = true;
      } else {
        neededEl.textContent = `Ready (${formatBytes(selected)} freed)`;
        confirmBtn.disabled = false;
      }
    };

    backdrop.querySelectorAll('input[type="checkbox"]').forEach((cb) => {
      cb.addEventListener('change', updateMeter);
    });
    updateMeter();

    const close = (result: string[] | null) => {
      backdrop.remove();
      resolve(result);
    };

    backdrop.querySelector('[data-role="cancel"]')!.addEventListener('click', () => close(null));
    confirmBtn.addEventListener('click', () => {
      const selected: string[] = [];
      backdrop.querySelectorAll<HTMLInputElement>('input[type="checkbox"]:checked').forEach((cb) => {
        const id = cb.dataset.modelId;
        if (id) selected.push(id);
      });
      close(selected);
    });
    backdrop.addEventListener('click', (e) => {
      if (e.target === backdrop) close(null);
    });

    document.body.appendChild(backdrop);
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function formatBytes(bytes: number): string {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return (bytes / Math.pow(1024, i)).toFixed(1) + ' ' + units[Math.min(i, units.length - 1)];
}
