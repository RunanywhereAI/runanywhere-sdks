// RunAnywhere demo app (Electron main). Forks the utility host (native addon) and
// opens a tabbed window that exercises the SDK: Chat, Structured output, Tool
// calling, Vision, Embeddings, and Voice — all over the isolated MessagePort.
//
//   RUNANYWHERE_NATIVE_PATH=<...>.node npx electron examples/demo-app
//
// Headless self-test (loads models + runs Chat/Structured/Tools/Embeddings through
// the app's real code paths, then exits 0/1):
//   RA_SELFTEST=1 RUNANYWHERE_NATIVE_PATH=<...>.node npx electron examples/demo-app
const path = require('path');
const fs = require('fs');
const { app, BrowserWindow, ipcMain } = require('electron');
const { RunAnywhereMain } = require('../../dist/process/main');

const SDK_ROOT = path.join(__dirname, '..', '..');
const SELFTEST = process.env.RA_SELFTEST === '1';
// Self-test output goes to a file too (Electron's GUI-subsystem stdout is not
// reliably captured when launched from a shell).
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

  const ra = new RunAnywhereMain({
    hostPath: path.join(SDK_ROOT, 'dist', 'process', 'host.js'),
    nativePath: process.env.RUNANYWHERE_NATIVE_PATH,
    onExit: (c) => console.log('[main] utility exited:', c),
  });

  const win = new BrowserWindow({
    width: 1080,
    height: 720,
    show: !SELFTEST,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });

  win.webContents.on('console-message', (_e, level, message) => {
    if (level >= 2) console.log('[renderer]', message); // surface warnings/errors
  });
  ipcMain.on('runanywhere-test-log', (_e, line) => { process.stdout.write(line); record(line); });
  ipcMain.on('runanywhere-test-done', (_e, ok) => { record(`[main] DONE ok=${ok}\n`); finish(ok ? 0 : 1, 'self-test ok=' + ok); });

  win.webContents.on('did-finish-load', () => ra.connect(win.webContents));
  const query = SELFTEST
    ? { selftest: '1', image: process.env.RA_TEST_IMAGE || 'e:\\codes\\qual\\models\\test_red_circle.jpg' }
    : {};
  win.loadFile(path.join(__dirname, 'index.html'), { query });

  if (SELFTEST) setTimeout(() => finish(3, 'TIMEOUT'), 240000);
});

app.on('window-all-closed', () => app.quit());
