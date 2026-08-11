/**
 * Renderer logging.
 *
 * `no-console` is an error in this app: a bare `console.log` goes nowhere a user
 * can reach in a packaged build. Everything routes through here, which forwards to
 * a main-side file log.
 */
import type { LogLevel } from '@shared/ipc-contract';

/**
 * Strip anything that should not survive into a log file.
 *
 * Signed download URLs carry credentials in their query string, and a log file
 * persists — so the query is dropped from anything URL-shaped.
 */
function sanitize(message: string): string {
  return message.replace(/(https?:\/\/[^\s?]+)\?[^\s]*/gi, '$1?<redacted>');
}

function emit(level: LogLevel, scope: string, parts: readonly unknown[]): void {
  const message = sanitize(
    parts
      .map((part) => {
        if (typeof part === 'string') return part;
        if (part instanceof Error) return part.stack ?? part.message;
        try {
          return JSON.stringify(part);
        } catch {
          return String(part);
        }
      })
      .join(' '),
  );
  window.appStore.log(level, scope, message);
}

export interface Logger {
  debug(...parts: readonly unknown[]): void;
  info(...parts: readonly unknown[]): void;
  warn(...parts: readonly unknown[]): void;
  error(...parts: readonly unknown[]): void;
}

/** A logger scoped to one subsystem, so a log line says where it came from. */
export function logger(scope: string): Logger {
  return {
    debug: (...parts) => emit('debug', scope, parts),
    info: (...parts) => emit('info', scope, parts),
    warn: (...parts) => emit('warn', scope, parts),
    error: (...parts) => emit('error', scope, parts),
  };
}
