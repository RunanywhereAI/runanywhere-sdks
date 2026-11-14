import { test, expect } from '@playwright/test';
import { resolve } from 'node:path';
import type * as LoggingHarness from './support/worker-logging-harness';

test('propagates logging into both real worker WASM heaps', async ({ page }) => {
  test.skip(process.env.RA_RUN_WORKER_LOGGING_E2E !== '1', 'Requires current CPU WASM builds for both backends.');
  test.setTimeout(5 * 60_000);
  await page.goto('/');
  await expect(page.locator('#generate')).toBeEnabled({ timeout: 120_000 });
  const harnessURL = `/@fs/${resolve(__dirname, 'support/worker-logging-harness.ts')}`;
  const result = await page.evaluate(async (url) => {
    const harness = await import(/* @vite-ignore */ url) as typeof LoggingHarness;
    return harness.exerciseWorkerLogging();
  }, harnessURL);
  expect(result.initial).toEqual({ native: 1, javascript: 1 });
  expect(result.afterInit).toEqual([{ native: 4, javascript: 4 }, { native: 4, javascript: 4 }]);
  expect(result.live).toEqual([{ native: 0, javascript: 0 }, { native: 0, javascript: 0 }]);
  expect(result.recreated).toEqual({ native: 3, javascript: 3 });
});

test('changes native output after an in-flight worker logging update', async ({ page }) => {
  test.skip(process.env.RA_RUN_WORKER_LOGGING_E2E !== '1', 'Downloads the real SmolLM2 model.');
  test.setTimeout(15 * 60_000);
  const nativeLogs: string[] = [];
  page.on('console', (message) => {
    if (message.text().includes('[PARAMS] LLM C-API')) nativeLogs.push(message.text());
  });
  await page.goto('/');
  await expect(page.locator('#generate')).toBeEnabled({ timeout: 120_000 });
  const harnessURL = `/@fs/${resolve(__dirname, 'support/worker-logging-harness.ts')}`;
  for (const phase of [0, 1]) {
    nativeLogs.length = 0;
    const result = await page.evaluate(async ({ url, phase }) => {
      const harness = await import(/* @vite-ignore */ url) as typeof LoggingHarness;
      return phase === 0
        ? harness.generateWithLogLevel(1, 4)
        : harness.generateWithLogLevel();
    }, { url: harnessURL, phase });
    expect(result.text.trim().length).toBeGreaterThan(0);
    expect(result.executionContext).toBe('worker');
    expect(result.acceleration).toBe('cpu');
    if (phase === 0) {
      expect(result.changedDuringStream).toBe(true);
      expect(nativeLogs.length).toBeGreaterThan(0);
    } else {
      expect(nativeLogs).toEqual([]);
    }
  }
});
