/**
 * One "this surface needs this model" row — presentation shell.
 *
 * Feature views supply the label, entry display strings, and live status.
 * Download chrome reuses `createDownloadProgress` so the Models list and a
 * modality slot never invent two progress readouts for the same transfer.
 */
import { icon, type IconName } from './icons';
import { createDownloadProgress, type DownloadProgressView } from './download-progress';
import { escapeHtml } from '../services/format';

export type ModelSlotStatus =
  | 'missing'
  | 'remote'
  | 'downloaded'
  | 'downloading'
  | 'loading'
  | 'loaded'
  | 'paused'
  | 'error'
  | 'blocked';

export interface ModelSlotView {
  readonly key: string;
  readonly label: string;
  readonly icon?: IconName;
  readonly title?: string;
  readonly meta?: string;
  readonly status: ModelSlotStatus;
  readonly statusLabel?: string;
  readonly optional?: boolean;
  readonly changeable?: boolean;
  readonly blockedReason?: string;
  readonly download?: DownloadProgressView;
  readonly errorMessage?: string;
}

function defaultStatusLabel(status: ModelSlotStatus): string {
  switch (status) {
    case 'loaded':
      return '✓ Active';
    case 'downloaded':
      return 'On device';
    case 'downloading':
      return 'Downloading';
    case 'loading':
      return 'Loading…';
    case 'paused':
      return 'Paused';
    case 'error':
      return 'Failed';
    case 'blocked':
      return 'Unavailable';
    case 'missing':
      return 'Not set up';
    case 'remote':
      return 'Not set up';
    default: {
      const _exhaustive: never = status;
      return _exhaustive;
    }
  }
}

/** Render one slot row as HTML. Caller wires `[data-change]` clicks. */
export function renderModelSlot(slot: ModelSlotView): string {
  const glyph = icon(slot.icon ?? 'square.stack.3d.up', { size: 20 });
  const optional =
    slot.optional === true ? ' <span class="ra-type-caption">optional</span>' : '';
  const change =
    slot.changeable === true
      ? `<button type="button" class="ra-btn-quiet" data-change="${escapeHtml(slot.key)}">Change</button>`
      : '';

  if (slot.status === 'missing') {
    return (
      `<div class="ra-model-slot" data-slot="${escapeHtml(slot.key)}" data-status="missing">` +
      `<div class="ra-model-slot-icon">${glyph}</div>` +
      `<div class="ra-model-slot-body">` +
      `<div class="ra-model-slot-label">${escapeHtml(slot.label)}${optional}</div>` +
      `<div class="ra-model-slot-hint">${escapeHtml(slot.meta ?? 'No model available.')}</div>` +
      `</div></div>`
    );
  }

  const statusText = escapeHtml(slot.statusLabel ?? defaultStatusLabel(slot.status));
  const blocked =
    slot.blockedReason !== undefined
      ? `<div class="ra-model-slot-hint">${escapeHtml(slot.blockedReason)}</div>`
      : '';
  const error =
    slot.errorMessage !== undefined
      ? `<div class="ra-model-slot-hint" data-tone="danger">${escapeHtml(slot.errorMessage)}</div>`
      : '';

  return (
    `<div class="ra-model-slot" data-slot="${escapeHtml(slot.key)}" data-status="${slot.status}">` +
    `<div class="ra-model-slot-icon">${glyph}</div>` +
    `<div class="ra-model-slot-body">` +
    `<div class="ra-model-slot-label">${escapeHtml(slot.label)}${optional}</div>` +
    `<div class="ra-model-slot-hint">${escapeHtml(slot.title ?? '')}${slot.meta !== undefined ? ` · ${escapeHtml(slot.meta)}` : ''}</div>` +
    `${blocked}${error}` +
    `<div data-download-host></div>` +
    `</div>` +
    `<div class="ra-model-slot-aside"><span class="ra-badge">${statusText}</span>${change}</div>` +
    `</div>`
  );
}

/**
 * Hydrate download bars inside a tree that used `renderModelSlot`.
 * Returns false when a phase change needs a full re-render.
 */
export function hydrateModelSlotDownloads(
  root: ParentNode,
  downloads: Readonly<Record<string, DownloadProgressView>>,
): void {
  for (const [key, view] of Object.entries(downloads)) {
    const slot = root.querySelector(`[data-slot="${CSS.escape(key)}"]`);
    if (!(slot instanceof HTMLElement)) continue;
    const host = slot.querySelector('[data-download-host]');
    if (!(host instanceof HTMLElement)) continue;
    host.replaceChildren();
    if (slot.dataset.status !== 'downloading' && slot.dataset.status !== 'paused') continue;
    const progress = createDownloadProgress(view);
    host.append(progress.element);
  }
}
