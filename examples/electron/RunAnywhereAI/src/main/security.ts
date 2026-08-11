/**
 * The four security handlers, carried over verbatim from the pre-TypeScript app.
 * Each one closes a hole Electron leaves open by default; none is optional.
 */
import type { BrowserWindow } from 'electron';
import { session, shell } from 'electron';

/**
 * Electron auto-grants every permission a page asks for. This app legitimately
 * needs the microphone (voice, VAD) and nothing else — deny the rest outright so
 * a compromised page cannot reach geolocation, notifications or the camera.
 */
export function installPermissionHandlers(): void {
  const allowed = (permission: string): boolean => permission === 'media' || permission === 'audioCapture';

  session.defaultSession.setPermissionRequestHandler((_wc, permission, callback) => {
    callback(allowed(permission));
  });
  session.defaultSession.setPermissionCheckHandler((_wc, permission) => allowed(permission));
}

export function installNavigationGuards(win: BrowserWindow): void {
  // External links open in the real browser, never in an app window.
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:/i.test(url)) void shell.openExternal(url);
    return { action: 'deny' };
  });

  // setWindowOpenHandler only covers window.open/target=_blank. A TOP-LEVEL
  // navigation (an injected link, a stray location assignment) would replace the
  // app with remote content that still has the preload attached. The app is a
  // single local page, so nothing may navigate away from it.
  win.webContents.on('will-navigate', (event, url) => {
    if (url !== win.webContents.getURL()) {
      event.preventDefault();
      if (/^https?:/i.test(url)) void shell.openExternal(url);
    }
  });

  // Nothing in this app embeds a webview.
  win.webContents.on('will-attach-webview', (event) => {
    event.preventDefault();
  });
}
