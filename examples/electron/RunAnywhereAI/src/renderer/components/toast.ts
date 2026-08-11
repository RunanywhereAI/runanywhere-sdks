/**
 * Transient messages.
 *
 * Mirrors the macOS app's toast: a floating pill, centred at the bottom, that
 * fades up and dismisses itself. Errors get the danger tone and a longer dwell,
 * because a message the user cannot read is not a message.
 */
import { icon, type IconName } from './icons';

export type ToastTone = 'neutral' | 'success' | 'danger';

const DWELL_MS: Readonly<Record<ToastTone, number>> = {
  neutral: 2600,
  success: 2600,
  danger: 5200,
};

const TONE_ICON: Readonly<Record<ToastTone, IconName | null>> = {
  neutral: null,
  success: 'checkmark',
  danger: 'info.circle',
};

function host(): HTMLElement {
  const existing = document.getElementById('toasts');
  if (existing !== null) return existing;
  const created = document.createElement('div');
  created.id = 'toasts';
  created.className = 'ra-toast-host';
  created.setAttribute('aria-live', 'polite');
  document.body.append(created);
  return created;
}

export function showToast(message: string, tone: ToastTone = 'neutral'): void {
  const element = document.createElement('div');
  element.className = 'ra-toast';
  element.dataset.tone = tone;

  const glyph = TONE_ICON[tone];
  element.innerHTML = (glyph === null ? '' : icon(glyph, { size: 14 })) + `<span></span>`;
  const label = element.querySelector('span');
  if (label !== null) label.textContent = message;

  host().append(element);

  window.setTimeout(() => {
    element.style.transition = 'opacity var(--ra-duration-standard) var(--ra-ease-out)';
    element.style.opacity = '0';
    window.setTimeout(() => element.remove(), 260);
  }, DWELL_MS[tone]);
}

/** Report a failure without leaking a stack trace into the UI. */
export function showError(error: unknown, fallback = 'Something went wrong'): void {
  const message = error instanceof Error ? error.message : typeof error === 'string' ? error : fallback;
  showToast(message === '' ? fallback : message, 'danger');
}
