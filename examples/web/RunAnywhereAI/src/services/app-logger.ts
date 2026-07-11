const URL_PATTERN = /https?:\/\/[^\s"')]+/gi;

export function sanitizeDiagnosticText(value: string): string {
  return value
    .replace(/\bBearer\s+[^\s"']+/gi, 'Bearer [REDACTED]')
    .replace(/\bsk-[A-Za-z0-9_-]{8,}\b/g, '[REDACTED-KEY]')
    .replace(
      /((?:api[-_ ]?key|authorization|credential|token|password)["']?\s*[:=]\s*["']?)[^\s,"'}]+/gi,
      '$1[REDACTED]',
    )
    .replace(URL_PATTERN, (raw) => {
      try {
        const url = new URL(raw);
        url.username = '';
        url.password = '';
        url.search = '';
        url.hash = '';
        return url.toString();
      } catch {
        return '[REDACTED-URL]';
      }
    });
}

function safeDetail(value: unknown): unknown {
  if (value instanceof Error) return { errorType: value.name };
  if (typeof value === 'string') return sanitizeDiagnosticText(value);
  if (typeof value === 'number' || typeof value === 'boolean' || value == null) return value;
  return { valueType: Array.isArray(value) ? 'array' : typeof value };
}

/** Central, credential-safe diagnostics for the browser example. */
export const appLogger = {
  info(message: string, ...details: readonly unknown[]): void {
    // eslint-disable-next-line no-console -- sole audited console destination
    console.info(sanitizeDiagnosticText(message), ...details.map(safeDetail));
  },
  warning(message: string, ...details: readonly unknown[]): void {
    // eslint-disable-next-line no-console -- sole audited console destination
    console.warn(sanitizeDiagnosticText(message), ...details.map(safeDetail));
  },
  error(message: string, ...details: readonly unknown[]): void {
    // eslint-disable-next-line no-console -- sole audited console destination
    console.error(sanitizeDiagnosticText(message), ...details.map(safeDetail));
  },
};
