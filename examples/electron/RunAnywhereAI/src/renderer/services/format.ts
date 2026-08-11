/**
 * Presentation helpers.
 *
 * Pure formatting, no SDK knowledge — the one category of "logic" that genuinely
 * belongs in an example app.
 */

/** Byte count as the model rows show it. */
export function formatSize(bytes: number): string {
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(1)} GB`;
  if (bytes >= 1e6) return `${(bytes / 1e6).toFixed(0)} MB`;
  return `${(bytes / 1e3).toFixed(0)} KB`;
}

/** Catalog sizes are declared in MB. */
export function formatMegabytes(megabytes: number): string {
  return megabytes >= 1000 ? `${(megabytes / 1000).toFixed(1)} GB` : `${megabytes} MB`;
}

export function formatSeconds(milliseconds: number): string {
  return `${(milliseconds / 1000).toFixed(1)}s`;
}

/** Transfer rate for the download progress block. */
export function formatRate(bytesPerSecond: number): string {
  if (bytesPerSecond <= 0) return '—';
  return `${formatSize(bytesPerSecond)}/s`;
}

/** Remaining time, in the shape the macOS download block uses. */
export function formatEta(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds <= 0) return '—';
  if (seconds < 60) return `${Math.round(seconds)}s left`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m left`;
  const hours = Math.floor(minutes / 60);
  return `${hours}h ${minutes % 60}m left`;
}

/**
 * The greeting the chat empty state opens with, matching the macOS app's
 * time-of-day copy.
 */
export function greeting(now: Date = new Date()): string {
  const hour = now.getHours();
  if (hour < 5) return 'Still up?';
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

/** Generation metrics as the analytics footer prints them. */
export function formatMetrics(metrics: {
  readonly outputTokens: number;
  readonly tokensPerSecond: number;
  readonly timeToFirstTokenMs: number;
}): string {
  const parts = [`${metrics.outputTokens} tokens`];
  if (metrics.tokensPerSecond > 0) parts.push(`${metrics.tokensPerSecond.toFixed(1)} tok/s`);
  if (metrics.timeToFirstTokenMs > 0) parts.push(`TTFT ${Math.round(metrics.timeToFirstTokenMs)}ms`);
  return parts.join(' · ');
}

/** Escape text destined for an innerHTML template. */
export function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (char) => {
    switch (char) {
      case '&':
        return '&amp;';
      case '<':
        return '&lt;';
      case '>':
        return '&gt;';
      case '"':
        return '&quot;';
      default:
        return '&#39;';
    }
  });
}
