/**
 * The preferences window — a separate BrowserWindow matching Swift's
 * `Settings { }` scene (CombinedSettingsView.swift macOS path): fixed
 * 560×460, five tabs, singleton (⌘, reopens the same window).
 */
import path from 'node:path';

import { BrowserWindow, nativeTheme, type WebContents } from 'electron';

import { APP_ROOT, IS_SELFTEST } from './paths';
import { installNavigationGuards } from './security';
import { loadRenderer } from './window';

const SETTINGS_WIDTH = 560;
const SETTINGS_HEIGHT = 460;

const IS_MAC = process.platform === 'darwin';

let settingsWin: BrowserWindow | null = null;

function backgroundColor(): string {
  return nativeTheme.shouldUseDarkColors ? '#0C0E17' : '#FBFAF8';
}

/**
 * Create (or focus) the preferences window.
 *
 * `connect` is the SDK MessagePort broker — the Models / Advanced panes call
 * storage and `setHfToken`, which need the utility host the same way the main
 * window does.
 */
export function showSettingsWindow(connect: (webContents: WebContents) => void): BrowserWindow {
  if (settingsWin !== null && !settingsWin.isDestroyed()) {
    if (settingsWin.isMinimized()) settingsWin.restore();
    settingsWin.focus();
    return settingsWin;
  }

  const win = new BrowserWindow({
    width: SETTINGS_WIDTH,
    height: SETTINGS_HEIGHT,
    // Swift pins every pane to one frame so the window does not resize under
    // the pointer when a tab is clicked.
    resizable: false,
    minimizable: true,
    maximizable: false,
    fullscreenable: false,
    show: false,
    backgroundColor: backgroundColor(),
    title: 'Settings',
    ...(IS_MAC ? {} : { icon: path.join(APP_ROOT, 'assets', 'icon.ico') }),
    webPreferences: {
      preload: path.join(APP_ROOT, 'out', 'preload', 'index.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });

  installNavigationGuards(win);

  const onThemeUpdated = (): void => {
    if (!win.isDestroyed()) win.setBackgroundColor(backgroundColor());
  };
  nativeTheme.on('updated', onThemeUpdated);

  win.webContents.on('did-finish-load', () => {
    if (!win.isDestroyed()) connect(win.webContents);
  });

  win.once('ready-to-show', () => {
    if (!IS_SELFTEST) win.show();
  });

  win.on('closed', () => {
    nativeTheme.off('updated', onThemeUpdated);
    settingsWin = null;
  });

  loadRenderer(win, {}, 'settings');
  settingsWin = win;
  return win;
}

/** Focus the open preferences window, if any. */
export function focusSettingsWindow(): void {
  if (settingsWin !== null && !settingsWin.isDestroyed()) {
    if (settingsWin.isMinimized()) settingsWin.restore();
    settingsWin.focus();
  }
}

export function getSettingsWindow(): BrowserWindow | null {
  return settingsWin !== null && !settingsWin.isDestroyed() ? settingsWin : null;
}

export function closeSettingsWindow(): void {
  if (settingsWin !== null && !settingsWin.isDestroyed()) settingsWin.close();
}
