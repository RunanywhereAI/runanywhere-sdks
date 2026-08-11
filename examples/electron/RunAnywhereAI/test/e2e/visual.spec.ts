/**
 * Visual-parity gate — per screen, light and dark, 1500×1000.
 *
 * Baselines: `test/e2e/__screenshots__/{route}-{theme}.png` (+ settings).
 * Update intentionally after C1/C2 chrome changes:
 *   npx playwright test test/e2e/visual.spec.ts --update-snapshots
 *
 * Determinism: RA_E2E isolates userData and pins the SDK model dir empty, so CI
 * never triggers real downloads. Chat greeting is pinned; Models storage card
 * is masked (disk free space varies).
 */
import { _electron as electron, expect, test, type ElectronApplication, type Page } from '@playwright/test';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  goRoute,
  openSettingsWindow,
  setTheme,
  SHELL_ROUTES,
  stabilizeChat,
  THEMES,
  VIEWPORT,
  waitForModelsList,
  waitForShell,
  type Theme,
} from './helpers';

const appRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

let app: ElectronApplication;
let page: Page;

test.beforeAll(async () => {
  app = await electron.launch({
    args: [appRoot],
    env: {
      ...process.env,
      RA_E2E: '1',
    },
  });
  page = await app.firstWindow();
  await page.setViewportSize(VIEWPORT);
  await waitForShell(page);
});

test.afterAll(async () => {
  await app?.close();
});

async function prepareRoute(route: (typeof SHELL_ROUTES)[number], theme: Theme): Promise<void> {
  await setTheme(page, theme);
  await goRoute(page, route);
  // Let the view mount and its entrance animation settle before Playwright
  // disables animations for the snapshot.
  await page.waitForTimeout(400);

  if (route === 'chat') {
    await expect(page.locator('.ra-composer')).toBeVisible();
    await stabilizeChat(page);
  } else if (route === 'models') {
    await waitForModelsList(page);
  } else {
    await expect(page.locator('.ra-toolbar-title')).toContainText('Advanced');
  }
}

for (const theme of THEMES) {
  test(`shell screens — ${theme}`, async () => {
    for (const route of SHELL_ROUTES) {
      await prepareRoute(route, theme);
      const mask =
        route === 'models' ? [page.locator('.ra-models-device')] : undefined;
      await expect(page).toHaveScreenshot(`${route}-${theme}.png`, {
        mask,
      });
    }
  });
}

test('settings window — light and dark', async () => {
  const settingsPage = await openSettingsWindow(app, page);

  for (const theme of THEMES) {
    await setTheme(settingsPage, theme);
    await expect(settingsPage.locator('.ra-prefs-tab[aria-selected="true"]')).toContainText('General');
    // Storage / HF status can still settle after open — wait for the general pane.
    await expect(settingsPage.locator('.ra-prefs-panel')).toBeVisible();
    await expect(settingsPage).toHaveScreenshot(`settings-general-${theme}.png`, {
      // Version string and storage rows can differ; mask the About-adjacent footers
      // if present on General. Keep the chrome + tabs in the gate.
      mask: [
        settingsPage.locator('.ra-prefs-mono'),
        settingsPage.locator('.ra-prefs-status-ok, .ra-prefs-status-warn'),
      ],
    });
  }

  await settingsPage.close();
});

test('hub child route paints without leaving Advanced scope', async () => {
  // Smoke that Advanced hub navigation works — full hub matrix is optional; one
  // stable child proves the router beyond the three sidebar destinations.
  await setTheme(page, 'light');
  await goRoute(page, 'embeddings');
  await expect(page.locator('.ra-toolbar-title')).toContainText('Embeddings');
  await expect(page.locator('.ra-nav-row[aria-current="page"]')).toContainText('Advanced');
  await page.waitForTimeout(400);
  await expect(page).toHaveScreenshot('embeddings-light.png');
});
