/**
 * Shell smoke + motion contract.
 *
 * Visual baselines live in `visual.spec.ts` (compared against
 * `test/e2e/__screenshots__/`). This file keeps the structural and motion
 * assertions that do not need pixel diffs.
 */
import { _electron as electron, expect, test, type ElectronApplication, type Page } from '@playwright/test';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { goRoute, setTheme, VIEWPORT, waitForShell } from './helpers';

const appRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

let app: ElectronApplication;
let page: Page;

test.beforeAll(async () => {
  app = await electron.launch({
    args: [appRoot],
    env: {
      ...process.env,
      // Isolate userData + pin SDK model dirs (see main IS_E2E).
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
  await goRoute(page, 'chat');
  await expect(page.locator('.ra-sidebar-search')).toBeVisible();
  await expect(page.locator('.ra-sidebar-chats')).toBeVisible();

  await goRoute(page, 'models');
  await expect(page.locator('.ra-sidebar-search')).toBeHidden();
  await expect(page.locator('.ra-sidebar-chats')).toBeHidden();
  await expect(page.locator('.ra-nav-row')).toHaveCount(3);

  await goRoute(page, 'chat');
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
  await goRoute(page, 'chat');
  await expect(page.locator('.ra-toolbar-title')).toContainText('Chat');
  await expect(page.locator('.ra-toolbar-subtitle')).not.toBeEmpty();
});

test('design tokens resolve to the Swift ladder, not the web warm neutrals', async () => {
  // Chromium may serialize #ffffff as #fff — compare via resolved rgb().
  const readColor = async (varName: string): Promise<string> =>
    page.evaluate((name) => {
      const probe = document.createElement('div');
      probe.style.color = `var(${name})`;
      document.body.append(probe);
      const value = getComputedStyle(probe).color;
      probe.remove();
      return value;
    }, varName);

  await setTheme(page, 'light');
  const lightMeta = await page.evaluate(() => {
    const style = getComputedStyle(document.documentElement);
    return {
      composerRadius: style.getPropertyValue('--ra-radius-xl').trim(),
      hitTarget: style.getPropertyValue('--ra-hit-target').trim(),
    };
  });

  expect(await readColor('--ra-brand')).toBe('rgb(255, 105, 0)');
  // Ink on orange (6.1:1), never white body copy on the brand fill.
  expect(await readColor('--ra-on-brand')).toBe('rgb(16, 24, 43)');
  // macOS column: the composer is 16, not the iOS 28.
  expect(lightMeta.composerRadius).toBe('16px');
  // macOS pointer-fine hit target, not the 44 touch target.
  expect(lightMeta.hitTarget).toBe('28px');
  expect(await readColor('--ra-background')).toBe('rgb(251, 250, 248)');
  expect(await readColor('--ra-surface')).toBe('rgb(255, 255, 255)');

  await setTheme(page, 'dark');
  expect(await readColor('--ra-background')).toBe('rgb(12, 14, 23)');
  expect(await readColor('--ra-surface')).toBe('rgb(19, 22, 32)');
});

test('motion tokens match the Motion.swift ladder', async () => {
  // Assert from computed styles — Chromium may serialize 120ms as .12s, so
  // resolve through a transitionDuration probe rather than the raw custom prop.
  const readMs = async (varName: string): Promise<number> =>
    page.evaluate((name) => {
      const probe = document.createElement('div');
      probe.style.transitionDuration = `var(${name})`;
      document.body.append(probe);
      const raw = getComputedStyle(probe).transitionDuration; // e.g. "0.12s"
      probe.remove();
      return Math.round(parseFloat(raw) * 1000);
    }, varName);

  expect(await readMs('--ra-duration-micro')).toBe(120);
  expect(await readMs('--ra-duration-standard')).toBe(240);
  expect(await readMs('--ra-duration-emphasis')).toBe(400);
  expect(await readMs('--ra-duration-hero')).toBe(700);
  expect(await readMs('--ra-reduced-fallback')).toBe(150);
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

test('reduced motion stops ambient loops', async () => {
  // tokens.css sets `animation: none !important` under prefers-reduced-motion —
  // ambient breathe/shimmer/spin must not keep running at a shortened duration.
  await page.emulateMedia({ reducedMotion: 'reduce' });
  const animation = await page.evaluate(() => {
    const probe = document.createElement('div');
    probe.style.animation = 'ra-spin var(--ra-ambient-spin) linear infinite';
    document.body.append(probe);
    const styles = getComputedStyle(probe);
    const result = {
      name: styles.animationName,
      duration: styles.animationDuration,
    };
    probe.remove();
    return result;
  });
  expect(animation.name).toBe('none');
  await page.emulateMedia({ reducedMotion: null });
});
