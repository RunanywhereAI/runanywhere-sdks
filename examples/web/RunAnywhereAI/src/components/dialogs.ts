/**
 * Shared Dialog & Toast System
 *
 * Provides reusable UI primitives for user notifications:
 *   - showToast() — transient success/warning/info messages
 *   - openModal() — a modal sheet with real focus management
 *
 * WHY THE MODAL SHELL LIVES HERE. Both dialogs in this app (the model picker
 * and Add-from-Hugging-Face) had hand-rolled the identical backdrop → sheet →
 * handle → header → body markup, and both had the identical set of gaps: no
 * focus trap, no Escape, no `inert` on the background, and no focus restore. A
 * keyboard user could Tab straight out of an open sheet into the page behind it
 * and operate controls they could not see; a screen-reader user was read the
 * whole obscured page as if it were still available. Two copies of one shell is
 * also two places for that to be fixed and one place for it to be forgotten, so
 * the shell is centralized and the callers supply only a title and a body.
 */

import { icon, type IconName } from './icons';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type ToastVariant = 'success' | 'warning' | 'info';

// ---------------------------------------------------------------------------
// Toast
// ---------------------------------------------------------------------------

/**
 * The glyph for each variant.
 *
 * Colour is deliberately NOT set here. These used to carry
 * `stroke="var(--color-green)"` / `"var(--color-primary)"` and, for warning,
 * `stroke="var(--color-orange, orange)"` — a token this app never defines, so
 * every warning toast was painting the CSS keyword `orange` (#FFA500), an
 * off-brand hue sitting next to #FF6900 in the same corner of the screen. The
 * icons now inherit `currentColor` from `.toast--<variant>`, which reads the
 * token layer, so a palette change reaches them and no hex or fallback keyword
 * lives in a template string.
 */
const TOAST_ICONS: Record<ToastVariant, IconName> = {
  success: 'check',
  warning: 'warning',
  info: 'info',
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
  toast.className = `toast toast--${variant}`;
  // The icon is a closed, source-controlled SVG. Toast messages frequently
  // contain backend/model/download errors, so keep them out of an HTML sink —
  // the message goes in via textContent below.
  toast.innerHTML = icon(TOAST_ICONS[variant], { size: 20 });
  const label = document.createElement('span');
  label.textContent = message;
  toast.appendChild(label);
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
// Modal
// ---------------------------------------------------------------------------

/** What a caller needs back to fill and later dismiss its dialog. */
export interface ModalHandle {
  /** The backdrop. Compare against it to tell one dialog instance from another. */
  root: HTMLElement;
  /** The `.modal-body` scroll container — the caller owns everything inside. */
  body: HTMLElement;
  /** Dismiss. Idempotent, and safe to call after the dialog is already gone. */
  close: () => void;
}

export interface ModalOptions {
  /** Heading text. Set as `textContent`, so it is never an HTML sink. */
  title: string;
  /** Unique id for the heading, referenced by the sheet's `aria-labelledby`. */
  titleId: string;
  /** Called after the dialog is removed, however it was dismissed. */
  onClose?: () => void;
}

interface ModalRecord {
  backdrop: HTMLElement;
  sheet: HTMLElement;
  /** Where focus was before this dialog opened, so it can be given back. */
  restoreFocus: HTMLElement | null;
  /**
   * Exactly what this dialog made inert, so closing it un-inerts that and
   * nothing else. Captured rather than recomputed because the page may have
   * gained or lost top-level elements while the dialog was open.
   */
  inerted: HTMLElement[];
  onClose?: () => void;
}

/**
 * Open dialogs, innermost last.
 *
 * A stack rather than a single active dialog because the picker's "Add from
 * Hugging Face" button opens a second dialog on top of the first. Escape and
 * Tab must apply to the top one only, and closing it has to hand focus and
 * interactivity back to the one underneath — not to the page.
 */
const modalStack: ModalRecord[] = [];

/** Rejects hidden and disabled candidates, which cannot take focus. */
const FOCUSABLE = [
  'a[href]',
  'button:not([disabled])',
  'input:not([disabled])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  'summary',
  '[tabindex]:not([tabindex="-1"])',
].join(',');

function focusableWithin(root: HTMLElement): HTMLElement[] {
  return Array.from(root.querySelectorAll<HTMLElement>(FOCUSABLE))
    // `offsetParent` is null for `display:none` subtrees — e.g. the drag handle
    // and other affordances this app hides at desktop widths.
    .filter((el) => el.offsetParent !== null || el === root);
}

/**
 * Take the background out of play for pointer and assistive tech alike.
 *
 * `inert` does both in browsers that have it; `aria-hidden` covers the older end
 * of this app's supported range (the documented floor predates `inert`), where
 * the unknown attribute is simply ignored. Keyboard is handled by the trap
 * regardless, and the backdrop already covers the viewport against clicks — so
 * each layer of this is a fallback for a different input method, not
 * redundancy.
 */
function setBackgroundInert(el: HTMLElement, inert: boolean): void {
  if (inert) {
    el.setAttribute('inert', '');
    el.setAttribute('aria-hidden', 'true');
  } else {
    el.removeAttribute('inert');
    el.removeAttribute('aria-hidden');
  }
}

/**
 * Everything a newly-opened dialog must suppress behind it.
 *
 * Not just `#app`: the acceleration badge is a sibling of it, so inerting only
 * the app shell would leave an element outside the dialog exposed to assistive
 * tech on the `aria-hidden` fallback path. Toasts are excluded deliberately — a
 * toast is an announcement rather than a control, and one raised by the dialog
 * itself (a failed download) still has to be readable.
 *
 * Already-inert elements are skipped so each dialog owns exactly what it
 * changed: when a second dialog opens over the first, only the first's backdrop
 * is new, and closing it must not hand the page back while the first is still up.
 * Call before appending the new backdrop, which is therefore never in the list.
 */
function backgroundLayers(): HTMLElement[] {
  return Array.from(document.body.children).filter((el): el is HTMLElement => (
    el instanceof HTMLElement
    && el.tagName !== 'SCRIPT'
    && !el.classList.contains('toast')
    && !el.hasAttribute('inert')
  ));
}

/**
 * Build the shared sheet shell and open it as the topmost dialog.
 *
 * The caller fills `handle.body` and wires its own controls; everything about
 * being a *dialog* — the shell, Escape, the focus trap, background inertness,
 * focus restore, and the Close button — belongs to this function.
 */
export function openModal(options: ModalOptions): ModalHandle {
  const backdrop = document.createElement('div');
  backdrop.className = 'modal-backdrop';

  const sheet = document.createElement('div');
  sheet.className = 'modal-sheet';
  sheet.setAttribute('role', 'dialog');
  sheet.setAttribute('aria-modal', 'true');
  sheet.setAttribute('aria-labelledby', options.titleId);
  // Focusable but not tabbable: the open handler focuses this so the dialog and
  // its title are announced, without adding a stop to the Tab order.
  sheet.tabIndex = -1;

  const handle = document.createElement('div');
  handle.className = 'modal-handle';
  // Decorative: it is not a drag affordance here, so it is not announced.
  handle.setAttribute('aria-hidden', 'true');

  const header = document.createElement('div');
  header.className = 'modal-header';
  const heading = document.createElement('h3');
  heading.className = 'text-md font-semibold';
  heading.id = options.titleId;
  heading.textContent = options.title;
  const closeBtn = document.createElement('button');
  closeBtn.type = 'button';
  closeBtn.className = 'btn-ghost';
  closeBtn.setAttribute('aria-label', 'Close');
  closeBtn.innerHTML = icon('close', { size: 20 });
  header.append(heading, closeBtn);

  const body = document.createElement('div');
  body.className = 'modal-body';

  sheet.append(handle, header, body);
  backdrop.appendChild(sheet);

  // Captured before this dialog's own backdrop is in the DOM, so the list is
  // exactly "what was interactive a moment ago".
  const inerted = backgroundLayers();

  const record: ModalRecord = {
    backdrop,
    sheet,
    restoreFocus: document.activeElement instanceof HTMLElement ? document.activeElement : null,
    inerted,
    onClose: options.onClose,
  };

  const close = (): void => closeModalRecord(record);
  closeBtn.addEventListener('click', close);
  backdrop.addEventListener('click', (event) => {
    if (event.target === backdrop) close();
  });

  for (const layer of inerted) setBackgroundInert(layer, true);

  modalStack.push(record);
  document.body.appendChild(backdrop);
  if (modalStack.length === 1) document.addEventListener('keydown', onModalKeydown, true);

  // Focus the sheet, not its first control. The body is still empty here — the
  // caller fills it after this returns — and the first focusable child is the
  // Close button either way, so this announces the dialog and its title rather
  // than the word "Close", and leaves Tab to land on Close first. A caller that
  // wants a field focused instead (Add-from-Hugging-Face) focuses it once its
  // own body exists.
  sheet.focus();

  return { root: backdrop, body, close };
}

function closeModalRecord(record: ModalRecord): void {
  const index = modalStack.indexOf(record);
  if (index < 0) return; // already closed
  modalStack.splice(index, 1);

  for (const layer of record.inerted) setBackgroundInert(layer, false);

  record.backdrop.remove();
  if (modalStack.length === 0) document.removeEventListener('keydown', onModalKeydown, true);

  // Give focus back to whatever opened this, so dismissing a dialog returns the
  // user to where they were rather than to the top of the document.
  const target = record.restoreFocus;
  if (target?.isConnected) target.focus();
  else if (modalStack.length > 0) modalStack[modalStack.length - 1].sheet.focus();

  record.onClose?.();
}

/**
 * Escape closes the top dialog; Tab cycles within it.
 *
 * Captured at the document so a stopPropagation inside a dialog's own body — a
 * search field swallowing keys, say — cannot disable Escape.
 */
function onModalKeydown(event: KeyboardEvent): void {
  const top = modalStack[modalStack.length - 1];
  if (!top) return;

  if (event.key === 'Escape') {
    event.preventDefault();
    closeModalRecord(top);
    return;
  }
  if (event.key !== 'Tab') return;

  const focusable = focusableWithin(top.sheet);
  if (focusable.length === 0) {
    // Nothing to move to; keep focus in the dialog rather than letting Tab
    // escape into the inert page behind it.
    event.preventDefault();
    top.sheet.focus();
    return;
  }

  const active = document.activeElement;
  // These dialogs re-render whole regions of their body with `innerHTML`, which
  // silently drops focus to <body> if the focused control was inside. Without
  // this, the very next Tab would walk the page behind the dialog.
  if (!(active instanceof HTMLElement) || !top.sheet.contains(active)) {
    event.preventDefault();
    (event.shiftKey ? focusable[focusable.length - 1] : focusable[0]).focus();
    return;
  }

  const first = focusable[0];
  const last = focusable[focusable.length - 1];
  if (!event.shiftKey && active === last) {
    event.preventDefault();
    first.focus();
  } else if (event.shiftKey && (active === first || active === top.sheet)) {
    event.preventDefault();
    last.focus();
  }
}
