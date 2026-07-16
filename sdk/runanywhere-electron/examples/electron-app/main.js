// Minimal headless Electron app exercising the RunAnywhere utility-process
// architecture: main forks the utility (native addon), a hidden renderer talks to
// it over a brokered MessagePort, and streamed tokens flow back to the page.
//
//   RUNANYWHERE_NATIVE_PATH=<...>.node npx electron examples/electron-app
const path = require('path');
const { app, BrowserWindow, ipcMain } = require('electron');
const { RunAnywhereMain } = require('../../dist/process/main');

app.disableHardwareAcceleration(); // headless / CI-friendly

const SDK_ROOT = path.join(__dirname, '..', '..');
const MODEL = process.env.RA_LLM_MODEL || 'e:\\codes\\qual\\models\\smollm2-135m.gguf';

let finished = false;
function finish(code, msg) {
  if (finished) return;
  finished = true;
  console.log('[main]', msg);
  app.exit(code);
}

app.whenReady().then(() => {
  const ra = new RunAnywhereMain({
    hostPath: path.join(SDK_ROOT, 'dist', 'process', 'host.js'),
    nativePath: process.env.RUNANYWHERE_NATIVE_PATH,
    onExit: (c) => console.log('[main] utility process exited:', c),
  });

  const win = new BrowserWindow({
    show: false,
    webPreferences: {
      preload: path.join(SDK_ROOT, 'dist', 'process', 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });

  ipcMain.on('runanywhere-test-log', (_e, line) => process.stdout.write(line));
  ipcMain.on('runanywhere-test-done', (_e, ok) => finish(ok ? 0 : 1, 'renderer reported ok=' + ok));

  win.webContents.on('did-finish-load', () => ra.connect(win.webContents));
  win.loadFile(path.join(__dirname, 'index.html'), { query: { model: MODEL } });

  setTimeout(() => finish(3, 'TIMEOUT (120s)'), 120000);
});

app.on('window-all-closed', () => {
  /* keep running until finish() */
});
