/**
 * Shared helpers for the Electron visual-parity gate.
 */
import { expect, type ElectronApplication, type Page } from '@playwright/test';

/** The macOS reference window size, so a diff compares like with like. */
export const VIEWPORT = { width: 1500, height: 1000 } as const;

/** Primary shell destinations + preferences (not a detail-column route). */
export const SHELL_ROUTES = ['chat', 'models', 'advanced'] as const;
export type ShellRoute = (typeof SHELL_ROUTES)[number];

export const THEMES = ['dark', 'light'] as const;
export type Theme = (typeof THEMES)[number];

/** Wait until the shell has painted its three destinations. */
export async function waitForShell(page: Page): Promise<void> {
  await page.waitForLoadState('domcontentloaded');
  await expect(page.locator('.ra-nav-row')).toHaveCount(3);
}

/** Apply a theme without going through the preferences window. */
export async function setTheme(page: Page, theme: Theme): Promise<void> {
  await page.evaluate((next) => {
    document.documentElement.dataset.theme = next;
  }, theme);
}

/** Navigate the detail column by hash (mirrors the shell router). */
export async function goRoute(page: Page, route: ShellRoute | string): Promise<void> {
  await page.evaluate((r) => {
    location.hash = `#/${r}`;
  }, route);
  await page.waitForTimeout(200);
}

/**
 * Pin time-of-day greeting so Chat baselines do not flip at noon/evening.
 * No-op when a conversation is open (empty state is gone).
 */
export async function stabilizeChat(page: Page): Promise<void> {
  const title = page.locator('.ra-chat-empty .ra-empty-title');
  if ((await title.count()) === 0) return;
  await title.evaluate((el) => {
    el.textContent = 'Good afternoon';
  });
}

/** Wait for Models to finish its first catalog refresh (no downloads started). */
export async function waitForModelsList(page: Page): Promise<void> {
  await expect(page.locator('.ra-models-list')).toBeVisible();
  await expect(
    page.locator('.ra-models-list .ra-model-row, .ra-models-list .ra-type-secondary').first(),
  ).toBeVisible({ timeout: 60_000 });
}

/**
 * Open the preferences BrowserWindow via the typed bridge.
 * Returns the settings page (560×460 — do not force the shell viewport).
 */
export async function openSettingsWindow(app: ElectronApplication, page: Page): Promise<Page> {
  const [settingsPage] = await Promise.all([
    app.waitForEvent('window'),
    page.evaluate(async () => {
      await window.appStore.openSettings();
    }),
  ]);
  await settingsPage.waitForLoadState('domcontentloaded');
  await expect(settingsPage.locator('.ra-prefs-tabs [role="tab"]')).toHaveCount(5);
  return settingsPage;
}
