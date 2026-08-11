/**
 * Headless end-to-end self-test plumbing (`RA_SELFTEST=1`).
 *
 * This is the only automated coverage of the SDK from an app's perspective, so it
 * is preserved exactly: same channels, same exit-code contract, same watchdog.
 *
 * Exit codes: 0 pass · 1 fail (or no native addon) · 3 timeout · 4 renderer gone
 * · 5 uncaught exception.
 *
 * Output also goes to a file because Electron is a GUI-subsystem binary on
 * Windows and its stdout is not reliably captured when launched from a shell.
 */
import fs from 'node:fs';
import path from 'node:path';

import { app, type BrowserWindow, ipcMain } from 'electron';

import { APP_ROOT, IS_SELFTEST } from './paths';

const RESULT_LOG = path.join(APP_ROOT, 'selftest-result.log');
const TIMEOUT_MS = 240_000;

export interface SelftestHarness {
  /** Append a line to the result log (and stdout) when self-testing. */
  log(line: string): void;
  /** Exit once, with a code. A no-op after the first call. */
  finish(code: number, message?: string): void;
  /** Wire the renderer-death and test IPC channels. */
  attach(win: BrowserWindow): void;
  /** Arm the watchdog. */
  start(): void;
}

export function createSelftestHarness(): SelftestHarness {
  let done = false;

  if (IS_SELFTEST) {
    try {
      fs.writeFileSync(RESULT_LOG, '');
    } catch {
      /* ignore */
    }
  }

  const log = (line: string): void => {
    if (!IS_SELFTEST) return;
    process.stdout.write(line);
    try {
      fs.appendFileSync(RESULT_LOG, line);
    } catch {
      /* ignore */
    }
  };

  const finish = (code: number, message?: string): void => {
    if (!IS_SELFTEST || done) return;
    done = true;
    if (message !== undefined) log(`[main] ${message}\n`);
    app.exit(code);
  };

  const attach = (win: BrowserWindow): void => {
    // A dead renderer must not leave a blank window with no way back.
    win.webContents.on('render-process-gone', (_event, details) => {
      log(`[main] renderer gone: ${details.reason}\n`);
      if (IS_SELFTEST) {
        finish(4, `renderer gone: ${details.reason}`);
        return;
      }
      if (!win.isDestroyed()) win.reload();
    });

    // On webContents the details object is the FIRST argument; reading the second
    // gets the deprecated numeric level, whose `.level` is undefined — which is
    // why renderer warnings and errors were never printed in the previous app.
    win.webContents.on('console-message', (details) => {
      if (details.level === 'warning' || details.level === 'error') {
        log(`[renderer] ${details.level}: ${details.message}\n`);
      }
    });

    // Self-test plumbing ONLY. `runanywhere-test-done` calls app.exit(), so it
    // must never be reachable in a shipped build.
    if (!IS_SELFTEST) return;
    ipcMain.on('runanywhere-test-log', (_event, line: string) => log(String(line)));
    ipcMain.on('runanywhere-test-done', (_event, ok: boolean) => {
      log(`[main] DONE ok=${ok}\n`);
      finish(ok ? 0 : 1, `self-test ok=${ok}`);
    });
  };

  const start = (): void => {
    if (IS_SELFTEST) setTimeout(() => finish(3, 'TIMEOUT'), TIMEOUT_MS);
  };

  return { log, finish, attach, start };
}
