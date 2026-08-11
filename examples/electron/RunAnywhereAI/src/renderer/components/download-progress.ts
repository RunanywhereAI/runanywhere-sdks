/**
 * Download progress chrome.
 *
 * Presentational only. Prefers `fraction` from the SDK's `DownloadProgressSnapshot`
 * (overall progress) so a multi-file transfer does not fill-and-reset per file.
 * Absent fraction → indeterminate shimmer — never a zero standing in for unknown.
 */
import { formatEta, formatRate, formatSize } from '../services/format';

export interface DownloadProgressView {
  /** 0…1 overall fraction when known. */
  readonly fraction?: number;
  readonly bytesDone?: number;
  readonly bytesTotal?: number;
  readonly bytesPerSecond?: number;
  readonly etaSeconds?: number;
  readonly label?: string;
  readonly currentFileIndex?: number;
  readonly totalFiles?: number;
  readonly phase?: 'queued' | 'downloading' | 'verifying' | 'extracting' | 'cancelling';
}

export interface DownloadProgressControl {
  readonly element: HTMLElement;
  update(view: DownloadProgressView): void;
}

function phaseLabel(phase: DownloadProgressView['phase'] | undefined, indeterminate: boolean): string {
  switch (phase) {
    case 'queued':
      return 'Starting…';
    case 'cancelling':
      return 'Cancelling…';
    case 'verifying':
      return 'Checking…';
    case 'extracting':
      return 'Unpacking…';
    case 'downloading':
    case undefined:
      return indeterminate ? 'Downloading' : 'Downloading';
  }
}

export function createDownloadProgress(initial: DownloadProgressView = {}): DownloadProgressControl {
  const root = document.createElement('div');
  root.className = 'ra-download';
  root.setAttribute('role', 'progressbar');
  root.setAttribute('aria-valuemin', '0');
  root.setAttribute('aria-valuemax', '100');

  const detail = document.createElement('div');
  detail.className = 'ra-download-detail';
  const left = document.createElement('span');
  const right = document.createElement('strong');
  detail.append(left, right);

  const track = document.createElement('div');
  track.className = 'ra-progress-track';
  const fill = document.createElement('div');
  fill.className = 'ra-progress-fill';
  track.append(fill);

  root.append(detail, track);

  const update = (view: DownloadProgressView): void => {
    const hasFraction = typeof view.fraction === 'number' && Number.isFinite(view.fraction);
    const indeterminate = !hasFraction;
    const fraction = hasFraction ? Math.max(0, Math.min(1, view.fraction as number)) : 0;

    fill.dataset.indeterminate = indeterminate ? 'true' : 'false';
    if (indeterminate) {
      fill.style.width = '';
      root.removeAttribute('aria-valuenow');
      root.setAttribute('aria-label', view.label ?? phaseLabel(view.phase, true));
    } else {
      fill.style.width = `${Math.round(fraction * 100)}%`;
      root.setAttribute('aria-valuenow', String(Math.round(fraction * 100)));
      root.setAttribute('aria-label', view.label ?? `${Math.round(fraction * 100)} percent`);
    }

    const parts: string[] = [];
    if (view.label !== undefined) parts.push(view.label);
    else parts.push(phaseLabel(view.phase, indeterminate));

    if (typeof view.bytesDone === 'number' && typeof view.bytesTotal === 'number' && view.bytesTotal > 0) {
      parts.push(`${formatSize(view.bytesDone)} / ${formatSize(view.bytesTotal)}`);
    } else if (typeof view.bytesDone === 'number' && view.bytesDone > 0) {
      parts.push(formatSize(view.bytesDone));
    }

    if (typeof view.currentFileIndex === 'number' && typeof view.totalFiles === 'number' && view.totalFiles > 1) {
      parts.push(`file ${view.currentFileIndex}/${view.totalFiles}`);
    }

    left.textContent = parts.join(' · ');

    const trailing: string[] = [];
    if (typeof view.bytesPerSecond === 'number' && view.bytesPerSecond > 0) {
      trailing.push(formatRate(view.bytesPerSecond));
    }
    if (typeof view.etaSeconds === 'number' && view.etaSeconds > 0) {
      trailing.push(formatEta(view.etaSeconds));
    }
    if (!indeterminate) trailing.push(`${Math.round(fraction * 100)}%`);
    right.textContent = trailing.join(' · ');
  };

  update(initial);
  return { element: root, update };
}
