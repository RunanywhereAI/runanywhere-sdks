/**
 * Shared Dialog & Toast System
 *
 * Provides reusable UI primitives for user notifications:
 *   - showToast() — transient success/warning/info messages
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type ToastVariant = 'success' | 'warning' | 'info';

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
