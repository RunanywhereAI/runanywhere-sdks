/**
 * Shell smoke + visual-parity capture.
 *
 * Proves the three processes come up and the shell renders, then captures each
 * screen in both themes for comparison against the macOS SwiftUI app.
 *
 * Screenshots land in `test/e2e/__screenshots__/` and are the input to the
 * parity gate — they are compared against
 * `thoughts/shared/research/electron-parity/macos-reference-screenshots/`.
 */
import { _electron as electron, expect, test, type ElectronApplication, type Page } from '@playwright/test';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const appRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const shots = path.join(appRoot, 'test', 'e2e', '__screenshots__');

/** The macOS reference window size, so a diff compares like with like. */
const VIEWPORT = { width: 1500, height: 1000 };

let app: ElectronApplication;
let page: Page;

test.beforeAll(async () => {
  app = await electron.launch({
    args: [appRoot],
    env: {
      ...process.env,
      // Keep the run off the user's real conversation/settings store.
      RA_E2E: '1',
    },
  });
  page = await app.firstWindow();
  await page.setViewportSize(VIEWPORT);
  await page.waitForLoadState('domcontentloaded');
});

test.afterAll(async () => {
  await app?.close();
});

test('the shell renders with its three destinations', async () => {
  // The sidebar is the shell's backbone: three destinations, always present, or
  // there is no way back from Models/Advanced.
  await expect(page.locator('.ra-nav-row')).toHaveCount(3);
  await expect(page.locator('.ra-nav-row').nth(0)).toContainText('Chat');
  await expect(page.locator('.ra-nav-row').nth(1)).toContainText('Models');
  await expect(page.locator('.ra-nav-row').nth(2)).toContainText('Advanced');

  // Exactly one row is selected — a split view with nothing highlighted reads as
  // "not loaded yet".
  await expect(page.locator('.ra-nav-row[aria-current="page"]')).toHaveCount(1);
});

test('the sidebar list is scoped to the open destination', async () => {
  // MacSidebar.swift:5-21 — a sidebar offering "Search chats" and twelve
  // conversation rows while the detail column shows Models is describing a screen
  // the user is not looking at. The search field and the Chats section appear
  // under Chat and nowhere else; the three destinations are always present.
  await page.evaluate(() => {
    location.hash = '#/chat';
  });
  await page.waitForTimeout(200);
  await expect(page.locator('.ra-sidebar-search')).toBeVisible();
  await expect(page.locator('.ra-sidebar-chats')).toBeVisible();

  await page.evaluate(() => {
    location.hash = '#/models';
  });
  await page.waitForTimeout(200);
  await expect(page.locator('.ra-sidebar-search')).toBeHidden();
  await expect(page.locator('.ra-sidebar-chats')).toBeHidden();
  await expect(page.locator('.ra-nav-row')).toHaveCount(3);

  await page.evaluate(() => {
    location.hash = '#/chat';
  });
  await page.waitForTimeout(200);
});

test('every capability the app needs reaches the renderer', async () => {
  // A facade method that cannot cross contextBridge does not exist for this app.
  // These are the 11 hard blockers from the Swift-parity audit plus the four
  // "free wins"; each screen below is gated on one of them, so this test is what
  // stops an SDK change from silently un-shipping a feature.
  const surface = await page.evaluate(() => {
    const ra = window.runanywhere as unknown as Record<string, unknown>;
    const models = ra.models as Record<string, unknown> | undefined;
    const lora = ra.lora as Record<string, unknown> | undefined;
    return {
      namespaces: [
        'llm', 'vlm', 'stt', 'tts', 'vad', 'embeddings', 'rerank', 'diarization',
        'segmentation', 'voice', 'rag', 'models', 'lora', 'storage', 'logging',
        'secure', 'auth', 'telemetry', 'events',
      ].filter((k) => ra[k] === undefined),
      facade: ['isReady', 'deviceId', 'environment', 'setHfToken', 'capabilities', 'version'].filter(
        (k) => ra[k] === undefined,
      ),
      models: ['list', 'download', 'load', 'delete', 'isResumable', 'import', 'compatibility', 'state'].filter(
        (k) => models?.[k] === undefined,
      ),
      lora: ['register', 'download', 'listCatalog', 'adaptersForModel', 'state'].filter(
        (k) => lora?.[k] === undefined,
      ),
    };
  });

  expect(surface.namespaces, 'namespaces missing from window.runanywhere').toEqual([]);
  expect(surface.facade, 'facade members missing from window.runanywhere').toEqual([]);
  expect(surface.models, 'models verbs missing').toEqual([]);
  expect(surface.lora, 'lora catalog verbs missing').toEqual([]);
});

test('streams survive contextBridge (own-property Symbol.asyncIterator)', async () => {
  // VadStream's Symbol.asyncIterator used to live on the PROTOTYPE, which
  // contextBridge does not carry into the page — which is why the old app had a
  // polling loop instead of a stream.
  const iterable = await page.evaluate(() => {
    const ra = window.runanywhere as unknown as { models: { download(id: string): unknown } };
    const stream = ra.models.download('__does-not-exist__') as object;
    const own = Object.prototype.hasOwnProperty.call(stream, Symbol.asyncIterator);
    // Release it so the rejected transfer does not leak into later tests.
    void (stream as { return?: () => unknown }).return?.();
    return own;
  });
  expect(iterable, 'Symbol.asyncIterator must be an OWN property').toBe(true);
});

test('the toolbar shows a title and subtitle', async () => {
  await expect(page.locator('.ra-toolbar-title')).toContainText('Chat');
  await expect(page.locator('.ra-toolbar-subtitle')).not.toBeEmpty();
});

test('design tokens resolve to the Swift ladder, not the web warm neutrals', async () => {
  const tokens = await page.evaluate(() => {
    const style = getComputedStyle(document.documentElement);
    return {
      theme: document.documentElement.dataset.theme,
      background: style.getPropertyValue('--ra-background').trim(),
      surface: style.getPropertyValue('--ra-surface').trim(),
      brand: style.getPropertyValue('--ra-brand').trim(),
      onBrand: style.getPropertyValue('--ra-on-brand').trim(),
      composerRadius: style.getPropertyValue('--ra-radius-xl').trim(),
      hitTarget: style.getPropertyValue('--ra-hit-target').trim(),
    };
  });

  expect(tokens.brand.toLowerCase()).toBe('#ff6900');
  // Ink on orange (6.1:1), never white body copy on the brand fill.
  expect(tokens.onBrand.toLowerCase()).toBe('#10182b');
  // macOS column: the composer is 16, not the iOS 28.
  expect(tokens.composerRadius).toBe('16px');
  // macOS pointer-fine hit target, not the 44 touch target.
  expect(tokens.hitTarget).toBe('28px');

  if (tokens.theme === 'dark') {
    expect(tokens.background.toLowerCase()).toBe('#0c0e17');
    expect(tokens.surface.toLowerCase()).toBe('#131620');
  } else {
    expect(tokens.background.toLowerCase()).toBe('#fbfaf8');
    expect(tokens.surface.toLowerCase()).toBe('#ffffff');
  }
});

test('reduced motion crossfades rather than blinking', async () => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  const duration = await page.evaluate(() => {
    const probe = document.createElement('div');
    probe.style.transition = 'opacity var(--ra-duration-standard) var(--ra-ease-out)';
    document.body.append(probe);
    const value = getComputedStyle(probe).transitionDuration;
    probe.remove();
    return value;
  });
  // Motion.swift is explicit that the change must be perceived, not blinked past.
  // 0s (what the web app ships) is a blink; 150ms is the specified fallback.
  expect(duration).toBe('0.15s');
  await page.emulateMedia({ reducedMotion: null });
});

for (const theme of ['dark', 'light'] as const) {
  test(`captures every screen — ${theme}`, async () => {
    await page.evaluate((next) => {
      document.documentElement.dataset.theme = next;
    }, theme);

    const routes = ['chat', 'models', 'advanced'] as const;
    for (const route of routes) {
      await page.evaluate((r) => {
        location.hash = `#/${r}`;
      }, route);
      // Let the view mount and its entrance animation settle.
      await page.waitForTimeout(500);
      await page.screenshot({ path: path.join(shots, `${route}-${theme}.png`) });
    }
  });
}
