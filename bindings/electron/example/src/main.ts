/**
 * Electron MAIN process.
 *
 * Three jobs and nothing else:
 *   1. Record the backend plugin. Registration is main-process only (security):
 *      `RunAnywhereMain` copies the recorded paths into RUNANYWHERE_PLUGIN_PATHS
 *      when it forks the utility host — never over renderer RPC.
 *   2. Fork that host and broker its MessagePort into the window. Inference runs
 *      there, so neither this process nor the renderer ever loads the addon.
 *   3. Open one window.
 */
import * as path from 'node:path';

import { app, BrowserWindow } from 'electron';

import { RunAnywhereMain } from '@runanywhere/electron/main';
import { LlamaCPP } from '@runanywhere/electron-llamacpp';

// Before any connect(): the fork reads the queue this fills.
LlamaCPP.register();

// The host is what turns a catalog id into files on disk, and catalog
// registration is per process — so it needs this app's table as a CommonJS
// module on disk. `catalog.js` is what tsc emits from `src/catalog.ts`.
const runAnywhere = new RunAnywhereMain({
  catalogPath: path.join(__dirname, 'catalog.js'),
});

function createWindow(): void {
  const win = new BrowserWindow({
    width: 720,
    height: 560,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      // The preload requires SDK modules, which a sandboxed preload cannot do.
      // contextIsolation stays on (the default), so the page still gets only
      // what contextBridge publishes.
      sandbox: false,
    },
  });
  // Connect after the page exists, so the port lands in a live renderer. This
  // fires again on reload, which is exactly when a fresh port is needed.
  win.webContents.on('did-finish-load', () => runAnywhere.connect(win.webContents));
  void win.loadFile(path.join(__dirname, '..', 'index.html'));
}

void app.whenReady().then(createWindow);

app.on('window-all-closed', () => app.quit());
