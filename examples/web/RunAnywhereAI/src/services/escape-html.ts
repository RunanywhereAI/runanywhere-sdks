/**
 * HTML escape helper shared by all view-side render code.
 *
 * Escapes the five XML-significant characters: & < > " '. This is the
 * superset of the variants previously inlined in each view file, so every
 * call site is safe to migrate without behavior change.
 */
export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
