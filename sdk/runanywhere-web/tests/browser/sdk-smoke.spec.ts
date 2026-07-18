/**
 * SDK smoke test — MVP harness.
 *
 * Loads the RunAnywhereAI example app in a real browser, waits for the
 * SDK initialization flow to hit the "interactive" readiness state, and
 * asserts the public API surfaces exist on `window.RunAnywhere`.
 *
 * Scope is intentionally tight: we do not download models or run actual
 * inference here. End-to-end LLM/STT/TTS testing comes after ONNX WASM is
 * unblocked on Emscripten.
 */
import { test, expect } from '@playwright/test';

interface AppReadinessSnapshot {
  ready: boolean;
  state: 'booting' | 'initializing-sdk' | 'building-shell' | 'interactive' | 'error';
  sdk: 'initializing' | 'ready' | 'unavailable';
  backend: 'pending' | 'registered' | 'unavailable';
  identity: 'not-required' | 'pending' | 'ready' | 'unavailable';
  step:
    | 'booting'
    | 'initializing-sdk'
    | 'registering-llamacpp'
    | 'registering-onnx'
    | 'phase2-services'
    | 'catalog'
    | 'identity'
    | 'building-shell'
    | 'interactive'
    | 'error';
  shellReady: boolean;
  modelUiReady: boolean;
  modelUiTarget: 'get-started' | 'toolbar' | null;
  activeTab: string | null;
  reason: string;
  error?: string;
}

declare global {
  interface Window {
    __RUNANYWHERE_AI_READY__?: AppReadinessSnapshot;
    // Example app attaches the imported RunAnywhere singleton here so the
    // browser harness can probe it without re-importing through Vite.
    __RUNANYWHERE_SDK__?: {
      version: string;
      isInitialized: boolean;
      isAuthenticated: boolean;
      textGeneration: Record<string, unknown>;
      modelRegistry: Record<string, unknown>;
      // Model lifecycle is exposed via flat top-level verbs
      // (loadModel/unloadModel/currentModel) mirroring the Swift source-of-truth
      // facade — there is intentionally no `modelLifecycle` namespace.
      loadModel: (...args: unknown[]) => unknown;
      stt: Record<string, unknown>;
      tts: Record<string, unknown>;
      vad: Record<string, unknown>;
    };
  }
}

test.describe('Web SDK smoke test', () => {
  test('example app initializes and exposes RunAnywhere public surface', async ({ page }, testInfo) => {
    const consoleErrors: string[] = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        // Append the source URL: the browser's generic "Failed to load
        // resource" text omits the file, which the missing-WASM filter
        // below needs to recognize (e.g. racommons-onnx-sherpa.js 404 in a
        // checkout without the ONNX artifact staged).
        const url = msg.location().url;
        consoleErrors.push(url ? `${msg.text()} (${url})` : msg.text());
      }
    });

    await page.goto('/');

    // Wait for the app to finish its boot sequence. SDK readiness may be
    // `ready` (WASM loaded) or `unavailable` (WASM missing in dev cold-start),
    // but the app shell must reach `interactive` either way.
    try {
      await page.waitForFunction(
        () => {
          const snap = window.__RUNANYWHERE_AI_READY__;
          // Production identity intentionally completes in the background;
          // local interactive readiness must not wait for it.
          return snap && (snap.ready || snap.state === 'error');
        },
        null,
        { timeout: 60_000 },
      );
    } catch {
      const snapshot = await page.evaluate(() => window.__RUNANYWHERE_AI_READY__);
      await testInfo.attach('readiness-at-timeout', {
        body: JSON.stringify(snapshot ?? { state: 'not-published' }, null, 2),
        contentType: 'application/json',
      });
      throw new Error(
        `readiness stayed pending after 60s at step=${snapshot?.step ?? 'not-published'}: `
        + `${snapshot?.reason ?? 'no readiness snapshot'}`,
      );
    }

    const readiness = await page.evaluate(() => window.__RUNANYWHERE_AI_READY__);
    expect(readiness, 'readiness snapshot should be published').toBeTruthy();
    expect(readiness?.state, `app reached error state: ${readiness?.error ?? ''}`).not.toBe('error');
    expect(readiness?.ready, `app was interactive but not ready at step=${readiness?.step}`).toBe(true);
    expect(readiness?.shellReady).toBe(true);

    // The example app publishes the imported singleton on window so the
    // harness can probe the public API surface without re-bundling.
    await page.waitForFunction(() => !!window.__RUNANYWHERE_SDK__, null, { timeout: 10_000 });

    const surface = await page.evaluate(() => {
      const ra = window.__RUNANYWHERE_SDK__!;
      return {
        version: ra.version,
        isInitialized: ra.isInitialized,
        isAuthenticated: ra.isAuthenticated,
        hasTextGenerationStream:
          typeof ra.textGeneration === 'object' &&
          ra.textGeneration !== null &&
          typeof ra.textGeneration.generateStream === 'function',
        hasModelRegistry: typeof ra.modelRegistry === 'object' && ra.modelRegistry !== null,
        hasLoadModel: typeof ra.loadModel === 'function',
        hasStt: typeof ra.stt === 'object' && ra.stt !== null,
        hasTts: typeof ra.tts === 'object' && ra.tts !== null,
        hasVad: typeof ra.vad === 'object' && ra.vad !== null,
      };
    });

    // Version must be a real semver, not the hardcoded placeholder.
    expect(surface.version).toMatch(/^\d+\.\d+\.\d+/);
    expect(surface.version).not.toBe('0.1.0');

    // Phase 1 (initialize) should have completed by the time the app shell
    // is interactive.
    expect(surface.isInitialized).toBe(true);

    // No auth flow is wired from the browser today; commons
    // rac_auth_is_authenticated returns false until tokens are stored.
    expect(surface.isAuthenticated).toBe(false);

    // Public namespace facades must be present.
    expect(surface.hasTextGenerationStream).toBe(true);
    expect(surface.hasModelRegistry).toBe(true);
    // Model lifecycle is the flat `loadModel` verb (Swift-parity facade shape),
    // not a `modelLifecycle` namespace.
    expect(surface.hasLoadModel).toBe(true);
    expect(surface.hasStt).toBe(true);
    expect(surface.hasTts).toBe(true);
    expect(surface.hasVad).toBe(true);

    // No fatal console errors escaped the initialization flow. Warnings
    // about missing WASM are tolerated — those happen in fresh dev checkouts
    // before `npm run build:wasm -- --llamacpp` runs.
    const fatalErrors = consoleErrors.filter((err) =>
      !err.includes('WASM') &&
      !err.includes('wasm') &&
      !err.includes('sherpa-onnx') &&
      !err.includes('racommons-llamacpp') &&
      !err.includes('racommons-onnx-sherpa') &&
      // Credential-less dev init: commons logs the model-assignment fetch
      // at ERROR ("base URL is not configured"); the SDK's Phase 2 already
      // downgrades it to a deferred-fetch warning, so it is expected noise
      // in development — same on iOS, where commons emits the same line.
      !err.includes('model assignment base URL is not configured') &&
      // Device registration follows the same credential-less development
      // path and deliberately reports that its configuration is incomplete.
      !err.includes('Device registration requires a matching base URL and API key'),
    );
    expect(fatalErrors, `unexpected console errors:\n${fatalErrors.join('\n')}`).toHaveLength(0);
  });
});
