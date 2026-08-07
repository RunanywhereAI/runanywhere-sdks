// RunAnywhere AI — desktop app (Electron main process).
//
// Everything runs on-device: the main process forks a utility host that owns the
// native addon, and the renderer talks to it over an isolated MessagePort. No
// prompt, document, or audio ever leaves the machine.
//
// Launch (dev):   npm start        (from examples/electron/RunAnywhereAI)
// Launch (GPU):   npm run start:gpu
// Headless self-test (runs the real code paths, exits 0/1):
//   RA_SELFTEST=1 npx electron examples/electron/RunAnywhereAI
const path = require('path');
const { createStore, capConversations } = require('./store');
const fs = require('fs');
const { app, BrowserWindow, Menu, dialog, ipcMain, session, shell } = require('electron');

// Identity must be set before `app.getPath('userData')` is read so settings and
// conversations land in %APPDATA%\RunAnywhere AI (not Electron's default).
app.setName('RunAnywhere AI');

const { RunAnywhereMain } = require('../../../sdk/runanywhere-electron/dist/rpc/main');

// The app ships alongside the SDK in this repo; a packaged build resolves the
// same layout inside resources/ (see electron-builder config when packaging).
const SDK_ROOT = path.join(__dirname, '..', '..', '..', 'sdk', 'runanywhere-electron');
const PREBUILDS = path.join(SDK_ROOT, 'prebuilds');
const SELFTEST = process.env.RA_SELFTEST === '1';

// Backend credentials for telemetry/auth, read from a gitignored .env (or the
// environment). Mirrors the Android example's local.properties contract: with
// both a base URL and an API key set, the SDK initializes in PRODUCTION
// (org-scoped, authed telemetry); with neither, DEVELOPMENT (keyless).
function backendConfig() {
  const env = { ...process.env };
  try {
    const raw = fs.readFileSync(path.join(__dirname, '.env'), 'utf8');
    for (const line of raw.split(/\r?\n/)) {
      const t = line.trim();
      if (!t || t.startsWith('#') || !t.includes('=')) continue;
      const i = t.indexOf('=');
      const key = t.slice(0, i).trim();
      const val = t.slice(i + 1).trim().replace(/^['"]|['"]$/g, '');
      if (key && env[key] === undefined) env[key] = val;
    }
  } catch {
    // No .env is fine — fall back to process.env / keyless development.
  }
  const apiKey = (env.RUNANYWHERE_API_KEY || '').trim();
  const baseUrl = (env.RUNANYWHERE_BASE_URL || '').trim();
  return {
    apiKey,
    baseUrl,
    environment: apiKey && baseUrl ? 'production' : 'development',
  };
}

// Compute device: CPU by default. The CUDA prebuild is only used when explicitly
// requested (RA_GPU=1 / --gpu) AND present — loading it without an NVIDIA driver
// stack fails, so it must never be the silent default.
function resolveNativePath() {
  if (process.env.RUNANYWHERE_NATIVE_PATH) return process.env.RUNANYWHERE_NATIVE_PATH;
  const wantGpu = process.env.RA_GPU === '1' || process.argv.includes('--gpu');
  const base = `${process.platform}-${process.arch}`;
  const candidates = wantGpu ? [`${base}-cuda`, base] : [base];
  for (const variant of candidates) {
    const candidate = path.join(PREBUILDS, variant, 'runanywhere_native.node');
    if (fs.existsSync(candidate)) return candidate;
  }
  // Say so HERE rather than letting `undefined` travel into the utility host and
  // fail there with a message that points at the wrong layer.
  throw new Error(
    `no native addon for ${base}. This build ships prebuilds for: ` +
    `${(fs.existsSync(PREBUILDS) ? fs.readdirSync(PREBUILDS) : []).join(', ') || '(none)'}. ` +
    'Set RUNANYWHERE_NATIVE_PATH to a runanywhere_native.node built for this platform.'
  );
}

// Resolve at startup, but keep the failure readable: an uncaught throw here would
// close the app with no window and no message.
let NATIVE_PATH = null;
let NATIVE_ERROR = null;
try { NATIVE_PATH = resolveNativePath(); } catch (e) { NATIVE_ERROR = e; }
const DEVICE = /cuda|gpu/i.test(NATIVE_PATH || '') ? 'gpu' : 'cpu';

// Self-test output also goes to a file — Electron is a GUI-subsystem binary, so
// its stdout isn't reliably captured when launched from a shell.
const RESULT_LOG = path.join(__dirname, 'selftest-result.log');
const record = (line) => {
  if (SELFTEST) try { fs.appendFileSync(RESULT_LOG, line); } catch { /* ignore */ }
};
if (SELFTEST) try { fs.writeFileSync(RESULT_LOG, ''); } catch { /* ignore */ }

app.disableHardwareAcceleration();

let done = false;
function finish(code, msg) {
  if (done) return;
  done = true;
  if (msg) console.log('[main]', msg);
  app.exit(code);
}

// Local JSON store in userData for conversations / settings / custom models.
// The implementation lives in store.js so it can be unit-tested without Electron
// (atomic temp+fsync+rename writes; a corrupt file is backed up, not discarded).
let store = null;
const useStore = () => (store ||= createStore(app.getPath('userData')));
const readJson = (name, fallback) => useStore().readJson(name, fallback);
const writeJson = (name, data) => useStore().writeJson(name, data);

// One instance only: a second launch focuses the existing window instead of
// forking a second utility host (which would load the models twice).
if (!SELFTEST && !app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.whenReady().then(() => {
    // Nothing below can work without the addon; say which platform is missing a
    // prebuild rather than failing later inside the utility host.
    if (NATIVE_ERROR) {
      console.error('[main]', NATIVE_ERROR.message);
      record('[main] ' + NATIVE_ERROR.message + '\n');
      if (!SELFTEST) dialog.showErrorBox('RunAnywhere AI cannot start', NATIVE_ERROR.message);
      finish(1, 'no native addon');
      return;
    }
    ipcMain.handle('store:conversations:load', () => readJson('conversations.json', []));
    ipcMain.handle('store:conversations:save', (_e, data) => writeJson('conversations.json',
      data && Array.isArray(data.conversations)
        ? { ...data, conversations: capConversations(data.conversations) }
        : data));
    ipcMain.handle('store:settings:load', () => readJson('settings.json', {}));
    ipcMain.handle('store:settings:save', (_e, data) => writeJson('settings.json', data));
    ipcMain.handle('store:models:load', () => readJson('custom-models.json', []));
    ipcMain.handle('store:models:save', (_e, data) => writeJson('custom-models.json', data));
    // Backend creds for telemetry/auth (read from .env in the main process — the
    // sandboxed renderer has no filesystem access).
    ipcMain.handle('app:backend-config', () => backendConfig());

    const ra = new RunAnywhereMain({
      hostPath: path.join(SDK_ROOT, 'dist', 'rpc', 'host.js'),
      nativePath: NATIVE_PATH,
      // On a host crash the preload has already failed the in-flight calls;
      // re-fork + reconnect so the app recovers on the next action.
      onExit: (c) => {
        console.log('[main] utility exited:', c);
        if (!SELFTEST && win && !win.isDestroyed()) ra.connect(win.webContents);
      },
    });

    const win = new BrowserWindow({
      width: 1180,
      height: 780,
      minWidth: 900,
      minHeight: 620,
      show: !SELFTEST,
      // Paint the app's own background immediately so launch doesn't flash white.
      backgroundColor: '#0a0e1a',
      title: 'RunAnywhere AI',
      icon: path.join(__dirname, 'assets', 'icon.ico'),
      webPreferences: {
        preload: path.join(__dirname, 'preload.js'),
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: false,
      },
    });
    // setMenuBarVisibility only HIDES the stock menu — its accelerators still work,
    // so Ctrl+Shift+I would open DevTools in a shipped build and hand anyone who can
    // talk a user through a keystroke full access to the contextBridge. Replace the
    // menu instead of hiding it, keeping the shortcuts users legitimately expect.
    Menu.setApplicationMenu(Menu.buildFromTemplate([
      { role: 'editMenu' },
      {
        label: 'View',
        submenu: [
          { role: 'resetZoom' }, { role: 'zoomIn' }, { role: 'zoomOut' },
          { type: 'separator' }, { role: 'togglefullscreen' },
        ],
      },
      { role: 'windowMenu' },
    ]));
    win.setMenuBarVisibility(false);

    // Electron auto-grants every permission a page asks for. This app legitimately
    // needs the microphone (voice, VAD) and nothing else — deny the rest outright
    // so a compromised page cannot reach geolocation, notifications or the camera.
    session.defaultSession.setPermissionRequestHandler((_wc, permission, callback) => {
      callback(permission === 'media' || permission === 'audioCapture');
    });
    session.defaultSession.setPermissionCheckHandler((_wc, permission) =>
      permission === 'media' || permission === 'audioCapture');

    app.on('second-instance', () => {
      if (win && !win.isDestroyed()) {
        if (win.isMinimized()) win.restore();
        win.focus();
      }
    });

    // External links open in the real browser, never in an app window.
    win.webContents.setWindowOpenHandler(({ url }) => {
      if (/^https?:/i.test(url)) shell.openExternal(url);
      return { action: 'deny' };
    });

    // setWindowOpenHandler only covers window.open/target=_blank. A TOP-LEVEL
    // navigation (an injected link, a stray location assignment) would replace
    // the app with remote content that still has the preload attached. The app
    // is a single local page, so nothing may navigate away from it.
    win.webContents.on('will-navigate', (e, url) => {
      if (url !== win.webContents.getURL()) {
        e.preventDefault();
        if (/^https?:/i.test(url)) shell.openExternal(url);
      }
    });
    // Nothing in this app embeds a webview.
    win.webContents.on('will-attach-webview', (e) => e.preventDefault());

    // A dead renderer must not leave a blank window with no way back.
    win.webContents.on('render-process-gone', (_e, details) => {
      console.error('[main] renderer gone:', details && details.reason);
      if (SELFTEST) { finish(4, 'renderer gone: ' + (details && details.reason)); return; }
      if (win && !win.isDestroyed()) win.reload();
    });
    win.webContents.on('unresponsive', () => console.error('[main] renderer unresponsive'));

    // On webContents the details object is the FIRST argument (the remaining
    // positional args are the deprecated pre-Electron-34 form). Reading the second
    // argument gets the deprecated numeric level, whose `.level` is undefined — so
    // renderer warnings and errors, the ones worth seeing, were never printed.
    win.webContents.on('console-message', (details) => {
      const level = details && details.level;
      if (level === 'warning' || level === 'error') {
        console.log('[renderer]', level + ':', details.message);
      }
    });
    // Self-test plumbing ONLY. runanywhere-test-done calls app.exit(), so it must
    // never be reachable in a shipped build.
    if (SELFTEST) {
      ipcMain.on('runanywhere-test-log', (_e, line) => { process.stdout.write(String(line)); record(String(line)); });
      ipcMain.on('runanywhere-test-done', (_e, ok) => { record(`[main] DONE ok=${ok}\n`); finish(ok ? 0 : 1, 'self-test ok=' + ok); });
    }

    win.webContents.on('did-finish-load', () => ra.connect(win.webContents));
    const query = SELFTEST
      ? { selftest: '1', device: DEVICE, image: process.env.RA_TEST_IMAGE || '' }
      : { device: DEVICE };
    win.loadFile(path.join(__dirname, 'index.html'), { query });

    if (SELFTEST) setTimeout(() => finish(3, 'TIMEOUT'), 240000);
  });
}

// Without these a throw anywhere in the main process kills the app with no
// diagnostic, and an unhandled rejection is silent. Log, and keep running: a
// background failure should not take the window down with it.
process.on('uncaughtException', (err) => {
  console.error('[main] uncaught exception:', (err && err.stack) || err);
  if (SELFTEST) finish(5, 'uncaught exception');
});
process.on('unhandledRejection', (reason) => {
  console.error('[main] unhandled rejection:', reason);
});

app.on('window-all-closed', () => app.quit());
