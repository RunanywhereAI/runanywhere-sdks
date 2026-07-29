// RunAnywhere demo app (Electron main). Forks the utility host (native addon) and
// opens a tabbed window that exercises the SDK: Chat, Structured output, Tool
// calling, Vision, Embeddings, and Voice — all over the isolated MessagePort.
//
//   RUNANYWHERE_NATIVE_PATH=<...>.node npx electron examples/electron/RunAnywhereAI
//
// Headless self-test (loads models + runs Chat/Structured/Tools/Embeddings through
// the app's real code paths, then exits 0/1):
//   RA_SELFTEST=1 RUNANYWHERE_NATIVE_PATH=<...>.node npx electron examples/electron/RunAnywhereAI
const path = require('path');
const fs = require('fs');
const { app, BrowserWindow, ipcMain } = require('electron');
const { RunAnywhereMain } = require('../../../sdk/runanywhere-electron/dist/process/main');

// This example lives at the repo root (examples/electron/RunAnywhereAI) and loads
// the SDK from its built output under sdk/runanywhere-electron/dist.
const SDK_ROOT = path.join(__dirname, '..', '..', '..', 'sdk', 'runanywhere-electron');
const SELFTEST = process.env.RA_SELFTEST === '1';
const APP_ICON = path.join(__dirname, 'runanywhere-logo.png');
// Self-test output goes to a file too (Electron's GUI-subsystem stdout is not
// reliably captured when launched from a shell).
const RESULT_LOG = path.join(__dirname, 'selftest-result.log');
// Electron can outlive the shell that launched it (notably Start-Process and
// GUI-subsystem launches). A later console.log/process.stdout.write then emits
// EPIPE and Electron turns every log line into a main-process error dialog.
// Treat a closed output pipe as "logging unavailable", never as an app failure.
let outputAvailable = true;
for (const stream of [process.stdout, process.stderr]) {
  stream?.on('error', (error) => {
    if (error && (error.code === 'EPIPE' || error.code === 'ERR_STREAM_DESTROYED')) outputAvailable = false;
  });
}
const writeOutput = (line) => {
  if (!outputAvailable || !process.stdout || process.stdout.destroyed || !process.stdout.writable) return;
  try {
    process.stdout.write(line, (error) => {
      if (error && (error.code === 'EPIPE' || error.code === 'ERR_STREAM_DESTROYED')) outputAvailable = false;
    });
  } catch (error) {
    if (error && (error.code === 'EPIPE' || error.code === 'ERR_STREAM_DESTROYED')) outputAvailable = false;
  }
};
const record = (line) => {
  if (SELFTEST) try { fs.appendFileSync(RESULT_LOG, line); } catch { /* ignore */ }
};
if (SELFTEST) try { fs.writeFileSync(RESULT_LOG, ''); } catch { /* ignore */ }

// Keep the automated run deterministic while leaving the visible demo's normal
// Chromium rendering behavior unchanged.
if (SELFTEST) app.disableHardwareAcceleration();

let done = false;
function finish(code, msg) {
  if (done) return;
  done = true;
  if (msg) writeOutput('[main] ' + msg + '\n');
  // Keep the Node process status in sync with Electron's shutdown status.
  // On Windows the packaged Electron launcher can otherwise report success even
  // when the headless self-test calls app.exit(1).
  process.exitCode = code;
  app.exit(code);
}

// Tiny JSON store in userData for conversation history + settings (demo-owned).
const storePath = (name) => path.join(app.getPath('userData'), name);
const readJson = (name, fallback) => {
  try { return JSON.parse(fs.readFileSync(storePath(name), 'utf8')); } catch { return fallback; }
};
const writeJson = (name, data) => {
  try {
    fs.mkdirSync(app.getPath('userData'), { recursive: true });
    fs.writeFileSync(storePath(name), JSON.stringify(data));
    return true;
  } catch { return false; }
};

app.whenReady().then(() => {
  ipcMain.handle('demo:conversations:load', () => readJson('conversations.json', []));
  ipcMain.handle('demo:conversations:save', (_e, data) => writeJson('conversations.json', data));
  ipcMain.handle('demo:settings:load', () => readJson('settings.json', {}));
  ipcMain.handle('demo:settings:save', (_e, data) => writeJson('settings.json', data));
  ipcMain.handle('demo:models:load', () => readJson('custom-models.json', []));
  ipcMain.handle('demo:models:save', (_e, data) => writeJson('custom-models.json', data));
  ipcMain.handle('demo:camera:save', (_e, bytes) => {
    const data = Buffer.from(bytes || []);
    const pngSignature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    if (data.length < pngSignature.length || data.length > 20 * 1024 * 1024 ||
        !data.subarray(0, pngSignature.length).equals(pngSignature)) {
      throw new Error('Camera capture must be a PNG smaller than 20 MB.');
    }
    const dir = path.join(app.getPath('temp'), 'runanywhere-electron-camera');
    fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, 'latest-capture.png');
    fs.writeFileSync(file, data);
    return file;
  });

  const ra = new RunAnywhereMain({
    hostPath: path.join(SDK_ROOT, 'dist', 'process', 'host.js'),
    nativePath: process.env.RUNANYWHERE_NATIVE_PATH,
    // On a host crash the preload has already failed the in-flight calls; re-fork
    // + reconnect so the app recovers on the next action (skip during self-test).
    onExit: (c) => {
      writeOutput('[main] utility exited: ' + c + '\n');
      if (!SELFTEST && win && !win.isDestroyed()) ra.connect(win.webContents);
    },
  });

  const win = new BrowserWindow({
    width: 1080,
    height: 720,
    show: !SELFTEST,
    icon: APP_ICON,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });

  win.webContents.on('console-message', (_e, level, message) => {
    if (level >= 2) writeOutput('[renderer] ' + message + '\n'); // surface warnings/errors when a terminal is attached
  });
  ipcMain.on('runanywhere-test-log', (_e, line) => { writeOutput(line); record(line); });
  ipcMain.on('runanywhere-test-done', (_e, ok) => { record(`[main] DONE ok=${ok}\n`); finish(ok ? 0 : 1, 'self-test ok=' + ok); });

  win.webContents.on('did-finish-load', () => ra.connect(win.webContents));
  const query = SELFTEST
    ? { selftest: '1', image: process.env.RA_TEST_IMAGE || '' }
    : {};
  win.loadFile(path.join(__dirname, 'index.html'), { query });

  if (SELFTEST) setTimeout(() => finish(3, 'TIMEOUT'), 240000);
});

app.on('window-all-closed', () => app.quit());
