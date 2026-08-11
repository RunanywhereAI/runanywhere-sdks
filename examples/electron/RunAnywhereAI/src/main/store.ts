/**
 * The app's small JSON store (conversations / settings / custom models).
 *
 * Ported from the pre-TypeScript `store.js`, algorithm unchanged. Two properties
 * matter here, because losing this data is silent and total:
 *   * writes are ATOMIC — temp file + fsync + rename, so an interrupted write can
 *     never leave truncated JSON that parses as "no conversations".
 *   * an unreadable file is BACKED UP rather than discarded, so a user can get
 *     their history back instead of finding an empty app.
 *
 * Electron-free on purpose, so it stays unit-testable.
 */
import fs from 'node:fs';
import path from 'node:path';

export interface JsonStore {
  readJson<T>(name: string, fallback: T): T;
  writeJson(name: string, data: unknown): boolean;
  path(name: string): string;
}

/** Create a store rooted at `dir` (created on demand). */
export function createStore(dir: string): JsonStore {
  const target = (name: string): string => path.join(dir, name);

  function readJson<T>(name: string, fallback: T): T {
    const file = target(name);
    let text: string;
    try {
      text = fs.readFileSync(file, 'utf8');
    } catch {
      return fallback; // missing file is the normal first-run case
    }
    try {
      return JSON.parse(text) as T;
    } catch {
      // Keep the bytes: a parse failure is recoverable by hand, a delete is not.
      try {
        fs.copyFileSync(file, `${file}.corrupt-${Date.now()}`);
      } catch {
        /* best effort */
      }
      return fallback;
    }
  }

  function writeJson(name: string, data: unknown): boolean {
    const file = target(name);
    const tmp = `${file}.${process.pid}.tmp`;
    try {
      fs.mkdirSync(dir, { recursive: true });
      const json = JSON.stringify(data);
      const fd = fs.openSync(tmp, 'w');
      try {
        fs.writeFileSync(fd, json);
        fs.fsyncSync(fd); // durable on disk before it becomes the live file
      } finally {
        fs.closeSync(fd);
      }
      // Rename within one directory is atomic: a reader sees the old file or the
      // new one, never a half-written one.
      fs.renameSync(tmp, file);
      return true;
    } catch {
      try {
        fs.rmSync(tmp, { force: true });
      } catch {
        /* ignore */
      }
      return false;
    }
  }

  return { readJson, writeJson, path: target };
}

/** The three files this app persists, all under `app.getPath('userData')`. */
export const STORE_FILES = {
  conversations: 'conversations.json',
  settings: 'settings.json',
  customModels: 'custom-models.json',
} as const;
