/**
 * Model picker shell.
 *
 * Opens as a sheet with search + a scrollable list. Feature views (C2) supply
 * rows via `setRows` / `renderListRow`; this module owns chrome only — no
 * catalog fetch, no download orchestration.
 */
import { icon } from './icons';
import { openSheet, type SheetHandle } from './sheet';
import { escapeHtml } from '../services/format';

export interface ModelPickerRow {
  readonly id: string;
  readonly title: string;
  readonly meta: string;
  readonly selected?: boolean;
  readonly badge?: string;
  readonly disabled?: boolean;
}

export interface ModelPickerOptions {
  readonly title: string;
  readonly titleId?: string;
  readonly searchPlaceholder?: string;
  readonly rows: readonly ModelPickerRow[];
  readonly onSelect: (id: string) => void;
  readonly onClose?: () => void;
  readonly footer?: HTMLElement;
}

export interface ModelPickerHandle {
  readonly close: () => void;
  setRows(rows: readonly ModelPickerRow[]): void;
  setQuery(query: string): void;
}

function renderRow(row: ModelPickerRow): HTMLElement {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'ra-list-row';
  button.dataset.modelId = row.id;
  button.disabled = row.disabled === true;
  if (row.selected === true) button.setAttribute('aria-selected', 'true');

  button.innerHTML =
    `<div class="ra-list-row-body">` +
    `<div class="ra-list-row-title">${escapeHtml(row.title)}</div>` +
    `<div class="ra-list-row-meta">${escapeHtml(row.meta)}</div>` +
    `</div>` +
    (row.badge !== undefined
      ? `<div class="ra-list-row-aside"><span class="ra-badge">${escapeHtml(row.badge)}</span></div>`
      : row.selected === true
        ? `<div class="ra-list-row-aside">${icon('checkmark', { size: 16 })}</div>`
        : '');

  return button;
}

/** Open the model picker shell. */
export function openModelPicker(options: ModelPickerOptions): ModelPickerHandle {
  const sheet: SheetHandle = openSheet({
    title: options.title,
    titleId: options.titleId ?? 'ra-model-picker-title',
    onClose: options.onClose,
    footer: options.footer,
  });

  const shell = document.createElement('div');
  shell.className = 'ra-model-picker';

  const searchWrap = document.createElement('div');
  searchWrap.className = 'ra-model-picker-search';
  searchWrap.innerHTML = icon('magnifyingglass', { size: 14, className: 'ra-search-icon' });

  const search = document.createElement('input');
  search.type = 'search';
  search.className = 'ra-search-input';
  search.placeholder = options.searchPlaceholder ?? 'Search models';
  search.setAttribute('aria-label', 'Search models');
  searchWrap.append(search);

  const list = document.createElement('div');
  list.className = 'ra-model-picker-list ra-scroll';
  list.setAttribute('role', 'listbox');
  list.setAttribute('aria-label', options.title);

  shell.append(searchWrap, list);
  sheet.body.append(shell);

  let rows = options.rows;
  let query = '';

  const paint = (): void => {
    const needle = query.trim().toLowerCase();
    const matches =
      needle === ''
        ? rows
        : rows.filter(
            (row) =>
              row.title.toLowerCase().includes(needle) || row.meta.toLowerCase().includes(needle),
          );

    list.replaceChildren();
    if (matches.length === 0) {
      const empty = document.createElement('p');
      empty.className = 'ra-type-meta';
      empty.textContent = needle === '' ? 'No models in this category.' : 'No matches.';
      list.append(empty);
      return;
    }

    for (const row of matches) {
      const el = renderRow(row);
      el.addEventListener('click', () => {
        if (row.disabled === true) return;
        options.onSelect(row.id);
        sheet.close();
      });
      list.append(el);
    }
  };

  search.addEventListener('input', () => {
    query = search.value;
    paint();
  });

  paint();

  return {
    close: sheet.close,
    setRows(next: readonly ModelPickerRow[]): void {
      rows = next;
      paint();
    },
    setQuery(next: string): void {
      query = next;
      search.value = next;
      paint();
    },
  };
}
