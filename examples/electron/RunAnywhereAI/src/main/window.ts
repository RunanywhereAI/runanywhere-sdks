/**
 * The main window.
 *
 * Geometry and chrome mirror the macOS SwiftUI app's `WindowGroup`
 * (RunAnywhereAIApp.swift:111-118): `.windowStyle(.titleBar)`,
 * `.windowToolbarStyle(.unified)`, `.defaultSize(1180 × 780)`,
 * `.windowResizability(.contentMinSize)`.
 *
 * Electron cannot draw an AppKit unified toolbar, so on macOS we use
 * `titleBarStyle: 'hiddenInset'` and the renderer draws a toolbar strip of the
 * same height with `-webkit-app-region: drag`. Windows keeps a standard frame.
 */
import path from 'node:path';

import { BrowserWindow, nativeTheme } from 'electron';

import { APP_ROOT, IS_DEV, IS_SELFTEST } from './paths';

const IS_MAC = process.platform === 'darwin';

/**
 * Window background, painted before the renderer's first frame.
 *
 * Must follow the OS appearance: a hardcoded dark value gives a light-theme user
 * a dark flash on every launch (a real bug in the previous app). These are
 * `--ra-background` from the design tokens.
 */
function backgroundColor(): string {
  return nativeTheme.shouldUseDarkColors ? '#0C0E17' : '#FBFAF8';
}

/** Which HTML entry to load — main shell or the preferences window. */
export type RendererPage = 'index' | 'settings';

/** The renderer entry: a dev server in development, the bundle otherwise. */
function rendererTarget(page: RendererPage = 'index'): { url?: string; file?: string } {
  const fileName = page === 'settings' ? 'settings.html' : 'index.html';
  if (IS_DEV) return { url: `http://localhost:5173/${fileName}` };
  return { file: path.join(APP_ROOT, 'out', 'renderer', fileName) };
}

export function createMainWindow(): BrowserWindow {
  const win = new BrowserWindow({
    width: 1180,
    height: 780,
    // Sidebar min 220 (ContentView.swift:45) + the chat column's composer and
    // transcript floor. `.contentMinSize` in SwiftUI means "no maximum".
    minWidth: 860,
    minHeight: 560,
    show: false, // revealed on ready-to-show so there is no unpainted frame
    backgroundColor: backgroundColor(),
    title: 'RunAnywhere AI',
    // macOS takes its icon from the bundle; Windows needs the .ico here.
    ...(IS_MAC ? {} : { icon: path.join(APP_ROOT, 'assets', 'icon.ico') }),
    // The unified title bar: traffic lights float over the renderer's toolbar
    // strip, which supplies the drag region.
    ...(IS_MAC
      ? {
          titleBarStyle: 'hiddenInset' as const,
          trafficLightPosition: { x: 18, y: 18 },
          vibrancy: 'sidebar' as const,
          visualEffectState: 'followWindow' as const,
        }
      : {}),
    webPreferences: {
      preload: path.join(APP_ROOT, 'out', 'preload', 'index.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      // The preload requires SDK modules, which a sandboxed preload cannot do.
      sandbox: false,
    },
  });

  win.once('ready-to-show', () => {
    if (!IS_SELFTEST) win.show();
  });

  // Follow the OS appearance at runtime. The previous app read the preference
  // once at startup, so changing appearance while it ran did nothing.
  const onThemeUpdated = (): void => {
    if (!win.isDestroyed()) win.setBackgroundColor(backgroundColor());
  };
  nativeTheme.on('updated', onThemeUpdated);
  win.on('closed', () => nativeTheme.off('updated', onThemeUpdated));

  return win;
}

export function loadRenderer(
  win: BrowserWindow,
  query: Record<string, string> = {},
  page: RendererPage = 'index',
): void {
  const target = rendererTarget(page);
  if (target.url !== undefined) {
    const url = new URL(target.url);
    for (const [key, value] of Object.entries(query)) url.searchParams.set(key, value);
    void win.loadURL(url.toString());
    return;
  }
  if (target.file !== undefined) void win.loadFile(target.file, { query });
}
