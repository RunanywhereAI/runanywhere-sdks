// Voice demo (Electron main): forks the utility host (native addon) and wires a
// renderer that captures the mic, runs STT -> LLM -> TTS over the isolated
// MessagePort, and plays the reply. Run with a microphone present:
//   RUNANYWHERE_NATIVE_PATH=<...>.node npx electron examples/voice-app
const path = require('path');
const { app, BrowserWindow } = require('electron');
const { RunAnywhereMain } = require('../../dist/process/main');

const SDK_ROOT = path.join(__dirname, '..', '..');

app.whenReady().then(() => {
  const ra = new RunAnywhereMain({
    hostPath: path.join(SDK_ROOT, 'dist', 'process', 'host.js'),
    nativePath: process.env.RUNANYWHERE_NATIVE_PATH,
    onExit: (c) => console.log('[main] utility exited:', c),
  });

  const win = new BrowserWindow({
    width: 720,
    height: 520,
    webPreferences: {
      preload: path.join(SDK_ROOT, 'dist', 'process', 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });

  win.webContents.on('did-finish-load', () => ra.connect(win.webContents));
  win.loadFile(path.join(__dirname, 'index.html'));
});

app.on('window-all-closed', () => app.quit());
