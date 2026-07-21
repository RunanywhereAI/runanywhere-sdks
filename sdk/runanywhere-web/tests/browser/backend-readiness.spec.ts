/**
 * Backend readiness browser gate.
 *
 * Proves the example app reaches an interactive shell with backends either
 * registered or explicitly unavailable — never stuck in `backend=pending`.
 * Also records the active inference execution context (main vs worker).
 */
import { test, expect } from '@playwright/test';

interface AppReadinessSnapshot {
  ready: boolean;
  state: string;
  backend: 'pending' | 'registered' | 'unavailable';
  step: string;
  reason: string;
  error?: string;
}

declare global {
  interface Window {
    __RUNANYWHERE_AI_READY__?: AppReadinessSnapshot;
    __RUNANYWHERE_SDK__?: {
      isInitialized: boolean;
      runtime?: {
        executionContext?: 'main' | 'worker';
        queueDepth?: number;
        streamingMode?: string;
      };
      diffusion?: { availability(): { available: boolean; reason?: string } };
    };
  }
}

test.describe('Backend readiness', () => {
  test('interactive shell settles backend registration and reports runtime context', async ({ page }) => {
    await page.goto('/');

    await page.waitForFunction(
      () => {
        const snap = window.__RUNANYWHERE_AI_READY__;
        return Boolean(snap && (snap.ready || snap.state === 'error'));
      },
      null,
      { timeout: 60_000 },
    );

    const readiness = await page.evaluate(() => window.__RUNANYWHERE_AI_READY__);
    expect(readiness?.state).not.toBe('error');
    expect(readiness?.ready).toBe(true);
    expect(readiness?.backend, `backend stuck: ${readiness?.reason}`).not.toBe('pending');

    const runtime = await page.evaluate(() => {
      const sdk = window.__RUNANYWHERE_SDK__;
      return {
        initialized: sdk?.isInitialized ?? false,
        executionContext: sdk?.runtime?.executionContext ?? 'main',
        streamingMode: sdk?.runtime?.streamingMode ?? null,
        diffusion: sdk?.diffusion?.availability() ?? null,
      };
    });

    expect(runtime.initialized).toBe(true);
    expect(['main', 'worker']).toContain(runtime.executionContext);
    expect(runtime.diffusion).toMatchObject({
      available: expect.any(Boolean),
    });
  });
});
