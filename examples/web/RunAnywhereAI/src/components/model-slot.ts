/**
 * Model slot — one "this surface needs this model" row.
 *
 * A slot names a role (chat model, speech-to-text, …), the catalog entry that
 * fills it, and that entry's live download/load state read from the shared
 * model registry. Voice AI renders four of them for its pipeline; Solutions
 * renders one per model id its YAML names.
 *
 * Extracted so those surfaces cannot drift: before this existed, the label /
 * progress / "✓ Ready" vocabulary lived inside `views/voice.ts`, so a second
 * surface needing the same row had to either reach into that view or reinvent
 * the state vocabulary — and two surfaces describing the same registry state
 * with different words is exactly the untruthful-UI failure the app's rules
 * forbid.
 */

import type { ModelCategory } from '@runanywhere/web';
import { escapeHtml } from '../services/escape-html';
import type { CatalogEntry } from '../services/model-catalog';
import {
  cleanModelName,
  formatFramework,
  formatModelSize,
  modalityIcon,
  modelDisplaySizeBytes,
} from '../services/model-display';
import { engineCompatibility } from '../services/engine-availability';
import { icon } from './icons';
import {
  getModelStatus,
  renderDownloadProgress,
  type ModelStatusSnapshot,
} from './model-selection';

/** One role a surface needs filled, plus the entry currently filling it. */
export interface ModelSlotView {
  /** Stable key; surfaces through `data-slot` and on the Change button. */
  key: string;
  /** Role name shown to the user ("Chat model"), never the model's own name. */
  label: string;
  category: ModelCategory;
  /** `null` when nothing in the catalog can fill this role on this device. */
  entry: CatalogEntry | null;
  /** Marks the role as not gating the surface's primary action. */
  optional?: boolean;
  /** Renders a Change affordance carrying `data-change="<key>"`. */
  changeable?: boolean;
  /** Shown in place of the model line when `entry` is null. */
  missingHint?: string;
}

/**
 * Render the status pill for a model's lifecycle state.
 *
 * Every branch of `ModelStatusSnapshot` is named, in the user's terms rather
 * than the registry's: "On device" for downloaded-but-not-loaded is the
 * distinction that decides whether the next action costs bandwidth or seconds.
 *
 * The download branches name the phase the picker names — a slot that said "99%"
 * through a two-minute checksum was describing the same event by a different,
 * and by then untrue, number.
 *
 * The loaded branch says "Active", not "Ready". iOS spends "Ready" on a model
 * that is merely on disk (`consumerStatusLabel`) and "Active" on the one that is
 * loaded (`activeIndicator`), so a slot reading "Ready" for a loaded model made
 * one word mean two different states across the two apps — the worst kind of
 * divergence, because both readings are plausible.
 */
export function renderModelSlotState(status: ModelStatusSnapshot): string {
  switch (status.status) {
    case 'loaded':
      return '<span class="model-slot__state model-slot__state--ready">&#10003; Active</span>';
    case 'downloaded':
      return '<span class="model-slot__state">On device</span>';
    case 'downloading':
      return `<span class="model-slot__state">${escapeHtml(downloadPhaseLabel(status))}</span>`;
    case 'loading':
      return '<span class="model-slot__state">Loading…</span>';
    case 'paused':
      return '<span class="model-slot__state model-slot__state--pending">Paused</span>';
    case 'error':
      return '<span class="model-slot__state model-slot__state--error">Failed</span>';
    default:
      return '<span class="model-slot__state model-slot__state--pending">Not set up</span>';
  }
}

/** The short form of a download phase, for the one-line aside. */
function downloadPhaseLabel(status: ModelStatusSnapshot): string {
  switch (status.phase) {
    case 'queued':
      return 'Starting…';
    case 'cancelling':
      return 'Cancelling…';
    case 'verifying':
      return 'Checking…';
    case 'extracting':
      return 'Unpacking…';
    default:
      return status.indeterminate ? 'Downloading' : `${Math.round(status.progress * 100)}%`;
  }
}

/** Render one slot row. Returns HTML; the caller owns event wiring. */
export function renderModelSlot(slot: ModelSlotView): string {
  const entry = slot.entry;
  if (!entry) {
    return `
      <div class="model-slot model-slot--missing" data-slot="${escapeHtml(slot.key)}">
        <div class="model-slot__icon">${icon(modalityIcon(slot.category), { size: 20 })}</div>
        <div class="model-slot__body">
          <div class="model-slot__label">${escapeHtml(slot.label)}</div>
          <div class="model-slot__hint">${escapeHtml(slot.missingHint ?? 'No model available for this device.')}</div>
        </div>
      </div>
    `;
  }

  const status = getModelStatus(entry.id);
  const optionalTag = slot.optional
    ? ' <span class="model-slot__opt">optional</span>'
    : '';
  const changeBtn = slot.changeable
    ? `<button type="button" class="model-slot__change" data-change="${escapeHtml(slot.key)}">Change</button>`
    : '';

  // A slot whose engine never registered would otherwise read "Not set up" —
  // an invitation to press a Set up button that cannot succeed. Say why
  // instead, using the same reason string the picker shows for the same model.
  // The card these rows sit in states the cause and the retry once, above, so
  // the row itself stays to a single line.
  const engine = engineCompatibility(entry);
  const engineReason = engine.supported ? '' : engine.reason;

  return `
    <div class="model-slot model-slot--${engineReason ? 'blocked' : status.status}" data-slot="${escapeHtml(slot.key)}">
      <div class="model-slot__icon">${icon(modalityIcon(slot.category), { size: 20 })}</div>
      <div class="model-slot__body">
        <div class="model-slot__label">${escapeHtml(slot.label)}${optionalTag}</div>
        <div class="model-slot__hint">
          ${escapeHtml(cleanModelName(entry.name))}
          · ${formatModelSize(modelDisplaySizeBytes(entry))}
          <span class="backend-pill">${escapeHtml(formatFramework(entry.framework))}</span>
        </div>
        ${engineReason
          ? `<div class="model-slot__blocked">${escapeHtml(engineReason)}</div>`
          : ''}
        ${engineReason
          ? ''
          // The picker's own markup, not a second bar: this used to be a bare
          // width with no readout, so the same transfer showed bytes, a rate and
          // an estimate in the picker and a silent stripe here.
          : renderDownloadProgress(status)}
        ${!engineReason && status.status === 'paused'
          ? '<div class="model-slot__blocked">Paused — resume picks up where it stopped</div>'
          : ''}
        ${!engineReason && status.status === 'error'
          ? `<div class="model-slot__blocked">${escapeHtml(status.error ?? 'Download failed')}</div>`
          : ''}
      </div>
      <div class="model-slot__aside">
        ${engineReason
          ? '<span class="model-slot__state model-slot__state--blocked">Unavailable</span>'
          : renderModelSlotState(status)}
        ${changeBtn}
      </div>
    </div>
  `;
}
