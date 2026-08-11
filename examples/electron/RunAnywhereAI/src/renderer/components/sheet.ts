/**
 * Modal sheet shell.
 *
 * Mirrors the Web dialogs.ts contract and the macOS sheet presentation: one
 * shared backdrop → sheet → header → body, with Escape, a focus trap, inert
 * background, and focus restore. Callers fill `body` and own their content;
 * everything about being a dialog lives here.
 */
import { icon } from './icons';

export interface SheetHandle {
  readonly root: HTMLElement;
  readonly body: HTMLElement;
  readonly close: () => void;
}

export interface SheetOptions {
  readonly title: string;
  readonly titleId: string;
  readonly onClose?: () => void;
  /** Optional footer node (actions). Appended below the scroll body. */
  readonly footer?: HTMLElement;
}

interface SheetRecord {
  readonly backdrop: HTMLElement;
  readonly sheet: HTMLElement;
  readonly restoreFocus: HTMLElement | null;
  readonly inerted: HTMLElement[];
  readonly onClose?: () => void;
}

const sheetStack: SheetRecord[] = [];

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
  return Array.from(root.querySelectorAll<HTMLElement>(FOCUSABLE)).filter(
    (el) => el.offsetParent !== null || el === root,
  );
}

function setBackgroundInert(el: HTMLElement, inert: boolean): void {
  if (inert) {
    el.setAttribute('inert', '');
    el.setAttribute('aria-hidden', 'true');
  } else {
    el.removeAttribute('inert');
    el.removeAttribute('aria-hidden');
  }
}

function backgroundLayers(): HTMLElement[] {
  return Array.from(document.body.children).filter(
    (el): el is HTMLElement =>
      el instanceof HTMLElement &&
      el.tagName !== 'SCRIPT' &&
      !el.classList.contains('ra-toast-host') &&
      !el.hasAttribute('inert'),
  );
}

function closeSheetRecord(record: SheetRecord): void {
  const index = sheetStack.indexOf(record);
  if (index < 0) return;
  sheetStack.splice(index, 1);

  for (const el of record.inerted) setBackgroundInert(el, false);
  record.backdrop.remove();
  record.onClose?.();

  if (sheetStack.length === 0) {
    record.restoreFocus?.focus();
    return;
  }

  const top = sheetStack[sheetStack.length - 1];
  const focusable = focusableWithin(top.sheet);
  (focusable[0] ?? top.sheet).focus();
}

function onDocumentKeyDown(event: KeyboardEvent): void {
  if (sheetStack.length === 0) return;
  const top = sheetStack[sheetStack.length - 1];

  if (event.key === 'Escape') {
    event.preventDefault();
    closeSheetRecord(top);
    return;
  }

  if (event.key !== 'Tab') return;

  const focusable = focusableWithin(top.sheet);
  if (focusable.length === 0) {
    event.preventDefault();
    top.sheet.focus();
    return;
  }

  const first = focusable[0];
  const last = focusable[focusable.length - 1];
  const active = document.activeElement;

  if (!(active instanceof HTMLElement) || !top.sheet.contains(active)) {
    event.preventDefault();
    first.focus();
    return;
  }

  if (event.shiftKey && (active === first || active === top.sheet)) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && active === last) {
    event.preventDefault();
    first.focus();
  }
}

let keyListenerInstalled = false;

function ensureKeyListener(): void {
  if (keyListenerInstalled) return;
  document.addEventListener('keydown', onDocumentKeyDown);
  keyListenerInstalled = true;
}

/** Open a centred modal sheet. Nested opens stack; Escape closes the top one. */
export function openSheet(options: SheetOptions): SheetHandle {
  ensureKeyListener();

  const backdrop = document.createElement('div');
  backdrop.className = 'ra-sheet-backdrop';

  const sheet = document.createElement('div');
  sheet.className = 'ra-sheet';
  sheet.setAttribute('role', 'dialog');
  sheet.setAttribute('aria-modal', 'true');
  sheet.setAttribute('aria-labelledby', options.titleId);
  sheet.tabIndex = -1;

  const header = document.createElement('div');
  header.className = 'ra-sheet-header';

  const heading = document.createElement('h2');
  heading.className = 'ra-sheet-title';
  heading.id = options.titleId;
  heading.textContent = options.title;

  const closeBtn = document.createElement('button');
  closeBtn.type = 'button';
  closeBtn.className = 'ra-icon-button';
  closeBtn.setAttribute('aria-label', 'Close');
  closeBtn.innerHTML = icon('xmark', { size: 18 });
  header.append(heading, closeBtn);

  const body = document.createElement('div');
  body.className = 'ra-sheet-body ra-scroll';

  sheet.append(header, body);
  if (options.footer !== undefined) {
    options.footer.classList.add('ra-sheet-footer');
    sheet.append(options.footer);
  }
  backdrop.append(sheet);

  const inerted = backgroundLayers();
  const record: SheetRecord = {
    backdrop,
    sheet,
    restoreFocus: document.activeElement instanceof HTMLElement ? document.activeElement : null,
    inerted,
    onClose: options.onClose,
  };

  const close = (): void => closeSheetRecord(record);
  closeBtn.addEventListener('click', close);
  backdrop.addEventListener('click', (event) => {
    if (event.target === backdrop) close();
  });

  for (const el of inerted) setBackgroundInert(el, true);
  sheetStack.push(record);
  document.body.append(backdrop);

  requestAnimationFrame(() => {
    const focusable = focusableWithin(sheet);
    (focusable[0] ?? sheet).focus();
  });

  return { root: backdrop, body, close };
}

/** True when any sheet is open — useful for shell shortcuts that must yield. */
export function isSheetOpen(): boolean {
  return sheetStack.length > 0;
}
