/**
 * RunAnywhere AI — desktop app (Electron main process).
 *
 * Everything runs on-device: the main process forks a utility host that owns the
 * native addon, and the renderer talks to it over an isolated MessagePort. No
 * prompt, document, or audio ever leaves the machine.
 *
 *   npm run dev        development, with a renderer dev server
 *   npm start          production bundle
 *   npm run selftest   headless end-to-end run, exits 0/1
 */
import fs from 'node:fs';
import path from 'node:path';

import { app, BrowserWindow, dialog, ipcMain, nativeTheme, shell } from 'electron';

import { RunAnywhereMain } from '@runanywhere/electron/main';
import { LlamaCPP } from '@runanywhere/electron-llamacpp';
import { ONNX } from '@runanywhere/electron-onnx';
import { Sherpa } from '@runanywhere/electron-sherpa';
import { capConversations, EMPTY_CONVERSATIONS, type ConversationsFile } from '../shared/conversation';
import {
  IpcChannel,
  IpcEvent,
  MenuCommand,
  type LogRecord,
  type PickFilesRequest,
  type PlatformInfo,
  type ResolvedTheme,
  type ThemePreference,
} from '../shared/ipc-contract';

import { backendConfig } from './env';
import { DEFAULT_CAPABILITIES, installAppMenu, type MenuCapabilities } from './menu';
import {
  APP_ROOT,
  CATALOG_PATH,
  HOST_PATH,
  IS_E2E,
  IS_SELFTEST,
  isGpuBuild,
  resolveNativePath,
  SDK_ROOT,
} from './paths';
import { installNavigationGuards, installPermissionHandlers } from './security';
import { createStore, STORE_FILES, type JsonStore } from './store';
import { createSelftestHarness } from './selftest';
import { getSettingsWindow, showSettingsWindow } from './settings-window';
import { createMainWindow, loadRenderer } from './window';
import { mergeSettingsPatch, type AppSettings } from '../shared/settings';

// Identity must be set before `app.getPath('userData')` is read, so settings and
// conversations land in "RunAnywhere AI" rather than Electron's default.
app.setName('RunAnywhere AI');

// Playwright sets RA_E2E=1. Redirect userData into a fresh temp dir so the gate
// never reads the developer's conversations/settings or downloaded-model state.
if (IS_E2E) {
  const dir = path.join(app.getPath('temp'), `runanywhere-ai-e2e-${process.pid}`);
  fs.mkdirSync(dir, { recursive: true });
  app.setPath('userData', dir);
}

// Backend registration is main-process only (security): paths flow to the
// utility host via RUNANYWHERE_PLUGIN_PATHS at fork — never over RPC.
// Call before any RunAnywhereMain.connect() so re-forks replay the same queue.
LlamaCPP.register();
ONNX.register();
Sherpa.register();
// Resolve the addon at startup but keep the failure readable: an uncaught throw
// here would close the app with no window and no message.
let nativePath: string | null = null;
let nativeError: Error | null = null;
try {
  nativePath = resolveNativePath();
} catch (error) {
  nativeError = error instanceof Error ? error : new Error(String(error));
}

const selftest = createSelftestHarness();

let store: JsonStore | null = null;
const useStore = (): JsonStore => (store ??= createStore(app.getPath('userData')));

let win: BrowserWindow | null = null;
let capabilities: MenuCapabilities = DEFAULT_CAPABILITIES;
/** Brokers the utility-host MessagePort into a BrowserWindow. Set once ready. */
let connectHost: ((webContents: Electron.WebContents) => void) | null = null;

function openSettings(): void {
  if (connectHost === null) return;
  showSettingsWindow(connectHost);
}

function broadcastSettingsChanged(settings: AppSettings): void {
  for (const target of BrowserWindow.getAllWindows()) {
    if (!target.isDestroyed()) target.webContents.send(IpcEvent.SettingsChanged, settings);
  }
}

function sendMenuCommand(command: MenuCommand): void {
  // Preferences live in their own window (Swift Settings scene), not as a
  // detail-column route — handle here so ⌘, works even if no renderer is focused.
  if (command === MenuCommand.OpenSettings) {
    openSettings();
    return;
  }
  if (win !== null && !win.isDestroyed()) win.webContents.send(IpcEvent.MenuCommand, command);
}

function platformInfo(): PlatformInfo {
  const platform = process.platform === 'darwin' || process.platform === 'win32' ? process.platform : 'linux';
  // Keep this honest per platform: the SDK's secure store is the macOS Keychain
  // on darwin and DPAPI on Win32. The previous app showed "Windows DPAPI" copy on
  // every platform.
  const secureStorageLabel =
    platform === 'darwin' ? 'macOS Keychain' : platform === 'win32' ? 'Windows DPAPI' : 'a local key file';
  return {
    platform,
    arch: process.arch,
    secureStorageAvailable: platform === 'darwin' || platform === 'win32',
    secureStorageLabel,
    modelsDirectory: path.join(app.getPath('userData'), 'models'),
    userDataDirectory: app.getPath('userData'),
    appVersion: app.getVersion(),
  };
}

function registerIpc(): void {
  ipcMain.handle(IpcChannel.ConversationsLoad, (): ConversationsFile => {
    const raw = useStore().readJson<ConversationsFile>(STORE_FILES.conversations, EMPTY_CONVERSATIONS);
    return { version: 1, conversations: capConversations(raw.conversations) };
  });
  ipcMain.handle(IpcChannel.ConversationsSave, (_event, data: ConversationsFile): boolean =>
    useStore().writeJson(STORE_FILES.conversations, {
      version: 1,
      conversations: capConversations(data.conversations),
    }),
  );

  ipcMain.handle(IpcChannel.SettingsLoad, (): unknown => useStore().readJson<unknown>(STORE_FILES.settings, {}));
  ipcMain.handle(IpcChannel.SettingsSave, (_event, data: unknown): boolean => {
    // Merge-not-replace: a pane that only writes temperature must not wipe
    // per-modality model choices living in the same object.
    const patch =
      data !== null && typeof data === 'object' ? (data as Partial<AppSettings>) : ({} as Partial<AppSettings>);
    const merged = mergeSettingsPatch(useStore().readJson<unknown>(STORE_FILES.settings, {}), patch);
    const ok = useStore().writeJson(STORE_FILES.settings, merged);
    if (ok) broadcastSettingsChanged(merged);
    return ok;
  });

  ipcMain.handle(IpcChannel.OpenSettingsWindow, (): void => {
    openSettings();
  });

  ipcMain.handle(IpcChannel.CustomModelsLoad, (): unknown =>
    useStore().readJson<unknown[]>(STORE_FILES.customModels, []),
  );
  ipcMain.handle(IpcChannel.CustomModelsSave, (_event, data: unknown): boolean =>
    useStore().writeJson(STORE_FILES.customModels, data),
  );

  ipcMain.handle(IpcChannel.BackendConfig, () => backendConfig());
  ipcMain.handle(IpcChannel.PlatformInfo, () => platformInfo());

  ipcMain.handle(IpcChannel.ThemeGet, (): ResolvedTheme =>
    nativeTheme.shouldUseDarkColors ? 'dark' : 'light',
  );
  ipcMain.handle(IpcChannel.ThemeSet, (_event, preference: ThemePreference): ResolvedTheme => {
    nativeTheme.themeSource = preference;
    return nativeTheme.shouldUseDarkColors ? 'dark' : 'light';
  });

  ipcMain.handle(IpcChannel.RevealPath, (_event, target: string): void => {
    if (fs.existsSync(target)) shell.showItemInFolder(target);
  });
  ipcMain.handle(IpcChannel.OpenExternal, async (_event, url: string): Promise<void> => {
    if (/^https?:/i.test(url)) await shell.openExternal(url);
  });

  ipcMain.handle(IpcChannel.PickFiles, async (_event, request: PickFilesRequest): Promise<string[]> => {
    if (win === null || win.isDestroyed()) return [];
    const result = await dialog.showOpenDialog(win, {
      title: request.title,
      filters: request.filters?.map((f) => ({ name: f.name, extensions: [...f.extensions] })),
      properties: request.multiple === true ? ['openFile', 'multiSelections'] : ['openFile'],
    });
    return result.canceled ? [] : result.filePaths;
  });

  // Renderer logs are forwarded here so they survive in a packaged build, where
  // a console.log goes nowhere a user can reach.
  ipcMain.on(IpcChannel.LogWrite, (_event, record: LogRecord): void => {
    selftest.log(`[${record.level}] ${record.scope}: ${record.message}\n`);
  });

  ipcMain.on(IpcChannel.MenuCapabilities, (_event, next: MenuCapabilities): void => {
    capabilities = next;
    installAppMenu(sendMenuCommand, capabilities);
  });
}

// One instance only: a second launch focuses the existing window instead of
// forking a second utility host (which would load the models twice).
// E2E / selftest use isolated userData (and their own lock key) so a developer
// can keep the real app open while the gate runs.
if (!IS_SELFTEST && !IS_E2E && !app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (win !== null && !win.isDestroyed()) {
      if (win.isMinimized()) win.restore();
      win.focus();
    }
  });

  void app.whenReady().then(() => {
    // Nothing below can work without the addon; say which platform is missing a
    // prebuild rather than failing later inside the utility host.
    if (nativeError !== null || nativePath === null) {
      const message = nativeError?.message ?? 'no native addon';
      selftest.log(`[main] ${message}\n`);
      if (!IS_SELFTEST) dialog.showErrorBox('RunAnywhere AI cannot start', message);
      selftest.finish(1, 'no native addon');
      return;
    }

    registerIpc();
    installAppMenu(sendMenuCommand, capabilities);
    installPermissionHandlers();

    const ra = new RunAnywhereMain({
      hostPath: HOST_PATH,
      nativePath,
      // The host downloads and resolves models, so it needs this app's catalog
      // too — registration is per-process. It resolves the path with require(),
      // which is why the TypeScript table is also emitted as CommonJS.
      catalogPath: CATALOG_PATH,
      // On a host crash the preload has already failed the in-flight calls;
      // re-fork + reconnect so the app recovers on the next action.
      onExit: () => {
        if (!IS_SELFTEST && win !== null && !win.isDestroyed()) ra.connect(win.webContents);
        const settings = getSettingsWindow();
        if (!IS_SELFTEST && settings !== null) ra.connect(settings.webContents);
      },
    });
    connectHost = (webContents) => ra.connect(webContents);

    win = createMainWindow();
    installNavigationGuards(win);
    selftest.attach(win);

    nativeTheme.on('updated', () => {
      const theme = nativeTheme.shouldUseDarkColors ? 'dark' : 'light';
      for (const target of BrowserWindow.getAllWindows()) {
        if (!target.isDestroyed()) target.webContents.send(IpcEvent.ThemeChanged, theme);
      }
    });

    win.webContents.on('did-finish-load', () => {
      if (win !== null && !win.isDestroyed()) ra.connect(win.webContents);
    });

    win.on('closed', () => {
      win = null;
    });

    loadRenderer(win, {
      device: isGpuBuild(nativePath) ? 'gpu' : 'cpu',
      ...(IS_E2E ? { e2e: '1' } : {}),
      ...(IS_SELFTEST ? { selftest: '1', image: process.env.RA_TEST_IMAGE ?? '' } : {}),
    });

    selftest.start();
  });
}

// macOS keeps the app alive with no windows; every other platform quits.
app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('activate', () => {
  if (
    BrowserWindow.getAllWindows().length === 0 &&
    nativeError === null &&
    nativePath !== null &&
    connectHost !== null
  ) {
    win = createMainWindow();
    installNavigationGuards(win);
    win.webContents.on('did-finish-load', () => {
      if (win !== null && !win.isDestroyed() && connectHost !== null) connectHost(win.webContents);
    });
    loadRenderer(win, { device: isGpuBuild(nativePath) ? 'gpu' : 'cpu' });
  }
});

// Without these a throw anywhere in the main process kills the app with no
// diagnostic, and an unhandled rejection is silent. Log, and keep running: a
// background failure should not take the window down with it.
process.on('uncaughtException', (error) => {
  selftest.log(`[main] uncaught exception: ${error.stack ?? String(error)}\n`);
  selftest.finish(5, 'uncaught exception');
});
process.on('unhandledRejection', (reason) => {
  selftest.log(`[main] unhandled rejection: ${String(reason)}\n`);
});

// Referenced so the bundler keeps the constant; also documents where the SDK is.
void SDK_ROOT;
void APP_ROOT;
