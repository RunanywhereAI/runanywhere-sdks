/**
 * Appearance.
 *
 * Three-state preference (`light` / `dark` / `system`) resolved to a rendered
 * theme. The OS is followed **live**: the previous app read the preference once
 * at startup, so changing appearance while it ran did nothing.
 *
 * Two sources have to agree — `nativeTheme` in the main process (which also paints
 * the window background before the first frame) and `matchMedia` in the page —
 * so main is treated as authoritative and the media query is only a fallback for
 * the pre-paint script in `index.html`.
 */
import type { ResolvedTheme, ThemePreference } from '@shared/ipc-contract';

const STORAGE_KEY = 'ra.theme';

function apply(theme: ResolvedTheme): void {
  document.documentElement.dataset.theme = theme;
}

/** The stored preference, or `system` when nothing has been chosen. */
export function storedPreference(): ThemePreference {
  const saved = localStorage.getItem(STORAGE_KEY);
  return saved === 'light' || saved === 'dark' ? saved : 'system';
}

/**
 * Wire appearance up. Returns a setter for the preference and an unsubscribe.
 *
 * The pre-paint script in `index.html` has already stamped a theme, so this only
 * corrects it once main reports the authoritative value.
 */
export async function installTheme(): Promise<{
  setPreference(preference: ThemePreference): Promise<void>;
  dispose(): void;
}> {
  const preference = storedPreference();

  // Tell main the preference so `nativeTheme.themeSource` drives the window
  // background too — otherwise a light-theme user still gets a dark frame.
  const resolved = await window.appStore.setTheme(preference);
  apply(resolved);

  const unsubscribe = window.appStore.onThemeChanged(apply);

  return {
    async setPreference(next: ThemePreference): Promise<void> {
      if (next === 'system') localStorage.removeItem(STORAGE_KEY);
      else localStorage.setItem(STORAGE_KEY, next);
      apply(await window.appStore.setTheme(next));
    },
    dispose: unsubscribe,
  };
}
