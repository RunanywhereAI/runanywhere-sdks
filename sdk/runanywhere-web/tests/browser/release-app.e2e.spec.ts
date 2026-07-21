/**
 * Full Web example release journey.
 *
 * This suite is intentionally opt-in: its clean first run downloads about
 * 1.37 GB across eight real public model artifacts (archive extraction needs
 * additional temporary headroom), loads every native WASM modality, and
 * performs real local inference. CPU-only first runs can take multiple hours;
 * each named checkpoint has a 45-minute cap. Tests are serial and use the
 * worker-scoped `appPage` fixture so OPFS, loaded component state, and browser
 * permissions survive between checkpoints.
 *
 * Run:
 *   RA_RUN_FULL_E2E=1 npx playwright test tests/browser/release-app.e2e.spec.ts
 */
import type { Page } from '@playwright/test';
import {
  AUDIO_FIXTURE,
  IMAGE_FIXTURE,
  RAG_FIXTURE,
  RELEASE_E2E_ENABLED,
  RELEASE_MODELS,
  assertFixtureFiles,
  ensureModelReady,
  expect,
  expectSubstantiveText,
  isModelDownloaded,
  isModelLoaded,
  navigateTo,
  observeBrowserDiagnostics,
  test,
  unexpectedBrowserDiagnostics,
  waitForInteractive,
  withExpectedNetworkFailure,
} from './support/release-harness';

const EXPECTED_ORIGIN = new URL(
  process.env.RA_E2E_BASE_URL ?? 'http://127.0.0.1:43173',
).origin;
const RELEASE_LOCAL_DIRECTORY = 'runanywhere-release-e2e';
const RELEASE_LOCAL_PERMISSION_KEY = 'runanywhere-release-e2e-permission';
const WEATHER_TRANSCRIPT_PATTERN = /\bweather\b/i;

const CANONICAL_RUNTIME_ASSETS = [
  'racommons.js',
  'racommons.wasm',
  'racommons-llamacpp.js',
  'racommons-llamacpp.wasm',
  'racommons-llamacpp-webgpu.js',
  'racommons-llamacpp-webgpu.wasm',
  'racommons-onnx-sherpa.js',
  'racommons-onnx-sherpa.wasm',
] as const;

const ALL_TABS = [
  'chat',
  'advanced',
  'storage',
  'settings',
  'voice',
  'vision',
  'documents',
  'transcribe',
  'speak',
  'vad',
  'solutions',
  'benchmarks',
] as const;

test.describe('RunAnywhere Web example — full Chromium release gate', () => {
  test.describe.configure({ mode: 'serial' });
  test.skip(
    !RELEASE_E2E_ENABLED,
    'Set RA_RUN_FULL_E2E=1 to download real models and run the release journey.',
  );

  test('01 — boots all native backends in a cross-origin-isolated shell', async ({ appPage }) => {
    assertFixtureFiles();
    await appPage.goto('/', { waitUntil: 'domcontentloaded' });

    // Production bundlers may hash the main-thread Emscripten imports, while
    // pthread pools still request canonical self-names. Fully consume these
    // responses (HEAD requests can be reported as ERR_ABORTED by Chrome) so a
    // missing worker companion is diagnosed before the SDK readiness wait.
    const runtimeAssets = await appPage.evaluate(async (assetNames) => (
      Promise.all(assetNames.map(async (assetName) => {
        const response = await fetch(`/assets/${assetName}`, { cache: 'no-store' });
        const bytes = await response.arrayBuffer();
        return {
          assetName,
          status: response.status,
          contentType: response.headers.get('content-type') ?? '',
          byteLength: bytes.byteLength,
        };
      }))
    ), CANONICAL_RUNTIME_ASSETS);
    for (const asset of runtimeAssets) {
      expect(asset.status, `${asset.assetName} must return HTTP 200`).toBe(200);
      expect(asset.byteLength, `${asset.assetName} must be non-empty`).toBeGreaterThan(0);
      expect(
        asset.contentType,
        `${asset.assetName} must not fall through to the SPA document`,
      ).toMatch(asset.assetName.endsWith('.wasm') ? /application\/wasm/i : /javascript/i);
    }

    await waitForInteractive(appPage);

    await expect(appPage.locator('#app')).toBeVisible();
    await expect(appPage.locator('#consumer-nav')).toBeAttached();
    await expect(appPage.locator('#tab-chat')).toHaveClass(/\bactive\b/);
    await expect(appPage.locator('#chat-toolbar-model')).toBeVisible();

    const runtime = await appPage.evaluate(async () => {
      const sdk = (window as Window & {
        __RUNANYWHERE_SDK__?: { isInitialized?: boolean };
      }).__RUNANYWHERE_SDK__;
      const gpu = (navigator as Navigator & {
        gpu?: { requestAdapter: () => Promise<unknown> };
      }).gpu;
      const resources = performance.getEntriesByType('resource').map((entry) => entry.name);
      return {
        initialized: sdk?.isInitialized === true,
        backend: document.documentElement.dataset.runanywhereAiBackend,
        state: document.documentElement.dataset.runanywhereAiState,
        crossOriginIsolated: window.crossOriginIsolated,
        webgpuAdapter: Boolean(await gpu?.requestAdapter()),
        acceleration: document.querySelector('#accel-badge')?.textContent?.trim(),
        accelerationBadgeCount: document.querySelectorAll('#accel-badge').length,
        origin: window.location.origin,
        webgpuJSLoaded: resources.some((url) => (
          /racommons-llamacpp-webgpu(?:-[A-Za-z0-9_-]+)?\.js(?:$|\?)/.test(url)
        )),
        webgpuWasmLoaded: resources.some((url) => (
          /racommons-llamacpp-webgpu(?:-[A-Za-z0-9_-]+)?\.wasm(?:$|\?)/.test(url)
        )),
      };
    });
    expect(runtime).toEqual({
      initialized: true,
      backend: 'registered',
      state: 'interactive',
      crossOriginIsolated: true,
      webgpuAdapter: true,
      acceleration: 'WebGPU',
      accelerationBadgeCount: 1,
      origin: EXPECTED_ORIGIN,
      webgpuJSLoaded: true,
      webgpuWasmLoaded: true,
    });
  });

  test('02 — navigates every primary and advanced surface through real controls', async ({ appPage }) => {
    // The drawer trigger is intentionally hidden on desktop, so exercise its
    // real responsive surface at a mobile viewport before returning to the
    // desktop layout for the remaining navigation matrix.
    await appPage.setViewportSize({ width: 390, height: 844 });
    try {
      await appPage.locator('#consumer-menu-btn').click();
      await expect(appPage.locator('body')).toHaveClass(/consumer-drawer-open/);
      await appPage.keyboard.press('Escape');
      await expect(appPage.locator('body')).not.toHaveClass(/consumer-drawer-open/);
      await appPage.locator('#consumer-menu-btn').click();
      // Click the uncovered right edge of the viewport; the drawer itself
      // overlays the scrim on the left and should intercept clicks there.
      await appPage.locator('#consumer-drawer-scrim').click({ position: { x: 386, y: 420 } });
      await expect(appPage.locator('body')).not.toHaveClass(/consumer-drawer-open/);
      await appPage.locator('#consumer-menu-btn').click();
      await appPage.locator('[data-nav-id="advanced"]').click();
      await expect(appPage.locator('#tab-advanced')).toHaveClass(/\bactive\b/);
    } finally {
      await appPage.keyboard.press('Escape').catch(() => undefined);
      await appPage.setViewportSize({ width: 1440, height: 1000 });
    }

    for (const target of [
      'voice',
      'documents',
      'transcribe',
      'speak',
      'vad',
      'storage',
      'benchmarks',
      'solutions',
    ] as const) {
      await navigateTo(appPage, 'advanced');
      await appPage.locator(`[data-advanced-target="${target}"]`).click();
      await expect(appPage.locator(`#tab-${target}`)).toHaveClass(/\bactive\b/);
    }

    // Before an LLM is selected, the welcome surface must route into the real
    // model picker while the composer remains intentionally gated.
    await navigateTo(appPage, 'chat');
    await expect(appPage.locator('#chat-model-overlay')).toBeVisible();
    await appPage.locator('#chat-get-started-btn').click();
    await expect(appPage.locator('.modal-sheet')).toBeVisible();
    await appPage.locator('#model-sheet-close').click();
    await expect(appPage.locator('.modal-sheet')).toBeHidden();

    // Exercise the public app navigation event and prove every initialized
    // panel can activate without a lifecycle exception.
    for (const tab of ALL_TABS) await navigateTo(appPage, tab);

    // The persistent desktop sidebar is already visible at this viewport.
    await appPage.locator('[data-nav-id="downloads"]').click();
    await expect(appPage.locator('#tab-storage')).toHaveClass(/\bactive\b/);
    await appPage.locator('#consumer-settings-btn').click();
    await expect(appPage.locator('#tab-settings')).toHaveClass(/\bactive\b/);

    // Browse controls must manually expand and collapse a family when search
    // is empty; search auto-expansion is covered by every model-ready helper.
    await navigateTo(appPage, 'chat');
    await appPage.locator('#chat-toolbar-model').click();
    const familyToggle = appPage.locator('#model-sheet-list [data-family-toggle]').first();
    await expect(familyToggle).toBeVisible();
    await familyToggle.click();
    await expect(familyToggle).toHaveAttribute('aria-expanded', 'true');
    await expect(appPage.locator('#model-sheet-list .family-variants').first()).toBeVisible();
    await familyToggle.click();
    await expect(familyToggle).toHaveAttribute('aria-expanded', 'false');
    await appPage.locator('#model-sheet-close').click();
  });

  test('03 — persists generation, theme, and safe settings without storing API keys', async ({ appPage }) => {
    await navigateTo(appPage, 'settings');

    await appPage.locator('#settings-temp').fill('0.2');
    await expect(appPage.locator('#settings-temp-val')).toHaveText('0.2');

    for (let attempt = 0; attempt < 25; attempt += 1) {
      if ((await appPage.locator('#settings-tokens-val').textContent()) === '500') break;
      await appPage.locator('#settings-tokens-minus').click();
    }
    await expect(appPage.locator('#settings-tokens-val')).toHaveText('500');
    await appPage.locator('#settings-tokens-plus').click();
    await expect(appPage.locator('#settings-tokens-val')).toHaveText('1000');
    await appPage.locator('#settings-tokens-minus').click();
    await expect(appPage.locator('#settings-tokens-val')).toHaveText('500');

    await appPage.locator('#settings-system-prompt').fill(
      'Answer concisely and directly for automated release verification.',
    );
    const thinkingToggle = appPage.locator('#settings-thinking-toggle');
    const thinkingInitiallyOn = await thinkingToggle.evaluate((node) => node.classList.contains('on'));
    expect(thinkingInitiallyOn, 'fresh installs should show reasoning by default').toBe(true);
    await thinkingToggle.click();
    await expect(thinkingToggle).toHaveClass(thinkingInitiallyOn ? /^(?!.*\bon\b)/ : /\bon\b/);
    await thinkingToggle.click();
    await expect(thinkingToggle).toHaveClass(thinkingInitiallyOn ? /\bon\b/ : /^(?!.*\bon\b)/);

    const originalTheme = await appPage.locator('html').getAttribute('data-theme');
    await appPage.locator('#consumer-theme-btn').click();
    await expect.poll(() => appPage.locator('html').getAttribute('data-theme'))
      .not.toBe(originalTheme);

    // Validation and session-only key handling are exercised with known
    // non-secret values. Real credentials never enter DOM snapshots or
    // Playwright traces.
    await appPage.locator('#settings-api-key').fill('');
    await appPage.locator('#settings-apply-api').click();
    await expect(appPage.locator('#settings-api-status')).toHaveText('Enter an API key.');
    const placeholder = 'PLACEHOLDER_E2E_KEY';
    await appPage.locator('#settings-api-key').fill(placeholder);
    await appPage.locator('#settings-apply-api').click();
    await expect(appPage.locator('#settings-api-status')).toHaveText('Replace the placeholder API key.');

    const validationKey = 'e2e-validation-key-not-a-secret';
    const baseURLInput = appPage.locator('#settings-base-url');
    const originalBaseURL = await baseURLInput.inputValue();
    const runtimeBeforeInvalidURL = await readRuntimeLifecycle(appPage);
    await appPage.locator('#settings-api-key').fill(validationKey);
    await baseURLInput.fill('https://');
    await appPage.locator('#settings-apply-api').click();
    await expect(appPage.locator('#settings-api-status')).toHaveText(/valid HTTPS base URL/i);
    await expect(appPage.locator('#settings-api-status')).toHaveClass(/text-error/);
    await expect(appPage.locator('#settings-apply-api')).toBeEnabled();
    expect(
      await readRuntimeLifecycle(appPage),
      'client-side URL validation must reject the form before runtime teardown begins',
    ).toEqual(runtimeBeforeInvalidURL);

    await appPage.locator('#settings-api-key').fill('');
    await appPage.locator('#settings-api-key').blur();
    await baseURLInput.fill(originalBaseURL);
    await baseURLInput.blur();

    const persisted = await appPage.evaluate((forbiddenValues) => ({
      settings: localStorage.getItem('runanywhere-settings') ?? '',
      allValues: Object.values(localStorage),
      containsForbidden: Object.values(localStorage).some((value) => (
        forbiddenValues.some((forbidden) => value.includes(forbidden))
      )),
    }), [placeholder, validationKey]);
    expect(persisted.settings).not.toContain('apiKey');
    expect(persisted.containsForbidden).toBe(false);
    expect(persisted.allValues.join('\n')).not.toContain(placeholder);
    await expect(appPage.locator('#settings-analytics-state')).toHaveText(/Enabled|Disabled|Unavailable/);
    await expect(appPage.locator('#settings-analytics-hint')).not.toBeEmpty();
  });

  test('04 — verifies About/docs wiring and the responsive mobile drawer', async ({ appPage }, testInfo) => {
    await navigateTo(appPage, 'settings');
    const versionRow = appPage.locator('#tab-settings .setting-row').filter({
      hasText: 'SDK Version',
    });
    await expect(versionRow).toContainText('SDK Version');
    await expect(versionRow.locator('.setting-value')).toHaveText(/^\d+\.\d+\.\d+/);
    await expect(appPage.locator('#tab-settings')).toContainText('Web (Emscripten WASM)');

    await appPage.evaluate(() => {
      const target = window as Window & {
        __RA_RELEASE_OPEN__?: { url: string; target?: string };
        __RA_RELEASE_ORIGINAL_OPEN__?: typeof window.open;
      };
      target.__RA_RELEASE_ORIGINAL_OPEN__ = window.open;
      window.open = (url?: string | URL, popupTarget?: string) => {
        target.__RA_RELEASE_OPEN__ = {
          url: String(url ?? ''),
          ...(popupTarget ? { target: popupTarget } : {}),
        };
        return null;
      };
    });
    try {
      await appPage.locator('#settings-docs-link').click();
      const opened = await appPage.evaluate(() => (
        (window as Window & {
          __RA_RELEASE_OPEN__?: { url: string; target?: string };
        }).__RA_RELEASE_OPEN__
      ));
      expect(opened).toEqual({ url: 'https://docs.runanywhere.ai', target: '_blank' });
    } finally {
      await appPage.evaluate(() => {
        const target = window as Window & {
          __RA_RELEASE_OPEN__?: { url: string; target?: string };
          __RA_RELEASE_ORIGINAL_OPEN__?: typeof window.open;
        };
        if (target.__RA_RELEASE_ORIGINAL_OPEN__) window.open = target.__RA_RELEASE_ORIGINAL_OPEN__;
        delete target.__RA_RELEASE_OPEN__;
        delete target.__RA_RELEASE_ORIGINAL_OPEN__;
      });
    }

    await appPage.setViewportSize({ width: 390, height: 844 });
    try {
      await navigateTo(appPage, 'chat');
      await appPage.locator('#consumer-menu-btn').click();
      await expect(appPage.locator('#consumer-drawer')).toHaveAttribute('aria-hidden', 'false');
      await expect(appPage.locator('body')).toHaveClass(/consumer-drawer-open/);
      await expect.poll(async () => (
        (await appPage.locator('#consumer-drawer').boundingBox())?.x ?? Number.NEGATIVE_INFINITY
      )).toBeGreaterThanOrEqual(0);
      const drawer = await appPage.locator('#consumer-drawer').boundingBox();
      expect(drawer).not.toBeNull();
      expect(drawer!.x).toBeGreaterThanOrEqual(0);
      expect(drawer!.width).toBeLessThanOrEqual(390);
      await testInfo.attach('mobile-drawer', {
        body: await appPage.screenshot({ animations: 'disabled' }),
        contentType: 'image/png',
      });
      await appPage.locator('#consumer-close-drawer-btn').click();
      await expect(appPage.locator('#consumer-drawer')).toHaveAttribute('aria-hidden', 'true');
      await expect(appPage.locator('body')).not.toHaveClass(/consumer-drawer-open/);

      for (const tab of ALL_TABS) {
        await navigateTo(appPage, tab);
        const panel = appPage.locator(`#tab-${tab}`);
        await expect(panel).toHaveClass(/\bactive\b/);
        const layout = await appPage.evaluate((panelId) => {
          const activePanel = document.querySelector<HTMLElement>(`#${panelId}`);
          const actionable = activePanel
            ? Array.from(activePanel.querySelectorAll<HTMLElement>(
              'button, input:not([type="hidden"]), select, textarea, a[href]',
            )).filter((element) => {
              const style = getComputedStyle(element);
              const rect = element.getBoundingClientRect();
              return style.display !== 'none'
                && style.visibility !== 'hidden'
                && rect.width > 0
                && rect.height > 0;
            }).length
            : 0;
          return {
            documentOverflow: document.documentElement.scrollWidth
              - document.documentElement.clientWidth,
            panelOverflow: activePanel
              ? activePanel.scrollWidth - activePanel.clientWidth
              : Number.POSITIVE_INFINITY,
            actionable,
          };
        }, `tab-${tab}`);
        expect(layout.documentOverflow, `${tab} must not overflow the mobile viewport`)
          .toBeLessThanOrEqual(1);
        expect(layout.panelOverflow, `${tab} panel must not overflow horizontally`)
          .toBeLessThanOrEqual(1);
        expect(layout.actionable, `${tab} must expose a visible actionable control`)
          .toBeGreaterThan(0);
      }
    } finally {
      await appPage.setViewportSize({ width: 1440, height: 1000 });
    }
  });

  test('04b — renders a fatal boot error and recovers through the visible Retry control', async ({
    releaseSession,
  }) => {
    const browser = releaseSession.context.browser();
    expect(browser, 'the release context must retain its owning browser').not.toBeNull();
    const retryContext = await browser!.newContext({
      baseURL: EXPECTED_ORIGIN,
      viewport: { width: 1440, height: 1000 },
    });
    await retryContext.addInitScript(() => {
      const target = globalThis as typeof globalThis & {
        __RA_RELEASE_FAIL_WASM_BOOT__?: boolean;
      };
      target.__RA_RELEASE_FAIL_WASM_BOOT__ = true;
      const originalInstantiate = WebAssembly.instantiate;
      const originalInstantiateStreaming = WebAssembly.instantiateStreaming;
      const forcedFailure = (): Promise<never> => Promise.reject(
        new Error('Release E2E forced one recoverable WASM boot failure'),
      );
      Object.defineProperty(WebAssembly, 'instantiate', {
        configurable: true,
        value: (...args: unknown[]): unknown => (
          target.__RA_RELEASE_FAIL_WASM_BOOT__
            ? forcedFailure()
            : Reflect.apply(originalInstantiate, WebAssembly, args)
        ),
      });
      Object.defineProperty(WebAssembly, 'instantiateStreaming', {
        configurable: true,
        value: (...args: unknown[]): unknown => (
          target.__RA_RELEASE_FAIL_WASM_BOOT__
            ? forcedFailure()
            : Reflect.apply(originalInstantiateStreaming, WebAssembly, args)
        ),
      });
    });

    const retryPage = await retryContext.newPage();
    const retryDiagnostics = observeBrowserDiagnostics(retryPage);
    try {
      await retryPage.goto('/', { waitUntil: 'domcontentloaded' });
      await expect(retryPage.locator('#retry-btn')).toBeVisible({ timeout: 180_000 });
      await expect(retryPage.locator('#initialization-error-message')).toContainText(
        'forced one recoverable WASM boot failure',
      );
      await retryPage.evaluate(() => {
        (globalThis as typeof globalThis & { __RA_RELEASE_FAIL_WASM_BOOT__?: boolean })
          .__RA_RELEASE_FAIL_WASM_BOOT__ = false;
      });
      await retryPage.locator('#retry-btn').click();
      await waitForInteractive(retryPage);
      await expect(retryPage.locator('#app')).toBeVisible();
      await expect(retryPage.locator('#retry-btn')).toHaveCount(0);
      expect(await readRuntimeLifecycle(retryPage)).toMatchObject({
        backend: 'registered',
        initialized: true,
        servicesReady: true,
        shellState: 'interactive',
      });
      const expectedBootFailureDiagnostics = [
        /forced one recoverable WASM boot failure/i,
        /^\[RunAnywhere:CommonsModule\] Failed to load Commons WASM$/,
        /^\[RunAnywhere:RunAnywhere\] Initialization failed$/,
      ];
      const unexpected = unexpectedBrowserDiagnostics(retryDiagnostics).filter((event) => (
        !expectedBootFailureDiagnostics.some((pattern) => pattern.test(event.message))
      ));
      expect(unexpected).toEqual([]);
    } finally {
      await retryContext.close();
    }
  });

  test('05 — keeps Bonsai 27B visible but explains why WebGPU cannot run it here', async ({ appPage }) => {
    await appPage.goto('/', { waitUntil: 'domcontentloaded' });
    await waitForInteractive(appPage);
    await navigateTo(appPage, 'chat');
    // Explicit precondition: the incompatible Bonsai model must not be downloaded
    // before proving the blocked runtime path. Asserting it up front keeps the
    // negative-state check order-independent even though the release suite reuses
    // a single worker-scoped page/context in serial mode.
    expect(await isModelDownloaded(appPage, 'bonsai-27b-q1_0')).toBe(false);
    await appPage.locator('#chat-toolbar-model').click();
    await appPage.locator('#model-sheet-search').fill('Bonsai-27B');

    const row = appPage.locator('[data-model-id="bonsai-27b-q1_0"]').first();
    await expect(row).toBeVisible();
    const unavailable = row.locator('button[data-model-id="bonsai-27b-q1_0"]');
    await expect(unavailable).toBeDisabled();
    await expect(unavailable).toHaveText('Too large for Web WASM');
    await expect(unavailable).toHaveAttribute(
      'data-compatibility-code',
      'wasm32-address-space',
    );
    await expect(row.locator('.model-compatibility-reason')).toContainText('3.803 GB GGUF');
    await expect(row.locator('.model-compatibility-reason')).toContainText(
      'llama.cpp path must stage the full',
    );
    await expect(row.locator('.model-compatibility-reason')).toContainText(
      '4 GiB WASM32 heap',
    );
    await expect(row.locator('.model-compatibility-reason')).toContainText('281 MiB');
    await expect(row.locator('.model-compatibility-reason')).toContainText(
      /WebGPU|webgpu/i,
    );
    const reference = row.locator('.model-compatibility-reason a');
    await expect(reference).toHaveText(/PrismML direct-WebGPU demo/);
    await expect(reference).toHaveAttribute(
      'href',
      'https://huggingface.co/spaces/webml-community/bonsai-webgpu-kernels',
    );
    await expect(reference).toHaveAttribute('rel', 'noopener noreferrer');
    await expect(row.locator('[data-action]')).toHaveCount(0);
    expect(await isModelDownloaded(appPage, 'bonsai-27b-q1_0')).toBe(false);

    await appPage.locator('#model-sheet-close').click();
    await expect(appPage.locator('.modal-sheet')).toBeHidden();
  });

  test('10 — downloads one canonical LLM and proves streamed chat inference', async ({ appPage }) => {
    await appPage.goto('/', { waitUntil: 'domcontentloaded' });
    await waitForInteractive(appPage);
    await navigateTo(appPage, 'chat');
    await ensureModelReady(appPage, '#chat-toolbar-model', RELEASE_MODELS.llm);
    // Regression: a successful load auto-selects the model and closes the
    // picker. The release gate must accept that completion path instead of
    // waiting for a loaded button that is now intentionally hidden.
    await expect(appPage.locator('.modal-sheet')).toBeHidden();
    await expect(appPage.locator('#chat-toolbar-model')).toContainText(/SmolLM2 360M/i);

    // Once chat is genuinely ready, prove that its visible composer routes to
    // both Live camera and Talk Mode through user-facing controls.
    await appPage.locator('#chat-attach-btn').click();
    await appPage.locator('#chat-attach-menu [data-action="live"]').click();
    await expect(appPage.locator('#tab-vision')).toHaveClass(/\bactive\b/);
    await navigateTo(appPage, 'chat');
    await appPage.locator('#chat-talk-btn').click();
    await expect(appPage.locator('#tab-voice')).toHaveClass(/\bactive\b/);
    await navigateTo(appPage, 'chat');

    await startFreshChat(appPage);
    const starter = appPage.locator('.suggestion-chip', { hasText: 'Explain a topic' });
    await expect(starter).toBeVisible();
    await starter.click();
    await expect(appPage.locator('#chat-input')).toHaveValue(/on-device AI keeps my data private/i);

    // Exercise the visible composer menu, browser file chooser, attachment
    // preview, and remove action without depending on the hidden input.
    await chooseFileVia(appPage, async () => {
      await appPage.locator('#chat-attach-btn').click();
      await appPage.locator('#chat-attach-menu [data-action="image"]').click();
    }, IMAGE_FIXTURE);
    await expect(appPage.locator('#chat-attachment-pill')).toContainText('test.jpg');
    await appPage.locator('#chat-clear-attachment').click();
    await expect(appPage.locator('#chat-attachment-pill')).toBeHidden();

    const prompt = 'In one concise sentence, explain why local inference improves privacy.';
    await appPage.locator('#chat-input').fill(prompt);
    await appPage.locator('#chat-send-btn').click();
    await expectSubstantiveText(
      appPage.locator('.chat-message--assistant .chat-bubble').last(),
      { minLength: 24, timeout: 8 * 60_000 },
    );
    await expect(appPage.locator('#chat-send-btn')).toHaveAttribute('aria-label', 'Send message', {
      timeout: 8 * 60_000,
    });
    const answer = (
      await appPage.locator('.chat-message--assistant .chat-bubble').last().innerText()
    ).trim();
    expect(answer.length).toBeGreaterThanOrEqual(24);
    expect(answer).not.toMatch(/no llm backend|check the console|generation failed/i);
    expect(answer).not.toMatch(/(.{1,16})\1{8,}/s);
    expect(answer.startsWith(prompt), 'echoPrompt=false must not include the user prompt').toBe(false);
    await expect(appPage.locator('.chat-message--user')).toContainText('local inference');
    const acceleration = await appPage.evaluate(() => {
      const sdk = (window as Window & {
        __RUNANYWHERE_SDK__?: { runtime?: { active?: string | null } };
      }).__RUNANYWHERE_SDK__;
      return {
        active: sdk?.runtime?.active,
        badge: document.querySelector('#accel-badge')?.textContent?.trim(),
      };
    });
    expect(acceleration).toEqual({ active: 'webgpu', badge: 'WebGPU' });

    const copyButton = appPage.locator('.chat-message--assistant [data-copy-idx]').last();
    await copyButton.click();
    await expect(copyButton.locator('span')).toHaveText('Copied');
    const clipboard = await appPage.evaluate(() => navigator.clipboard.readText());
    expect(clipboard.trim()).toBe(answer.trim());

    const currentChat = appPage.locator(
      '#consumer-conversation-list .consumer-recent-entry.active .consumer-recent-row',
      { hasText: 'local inference' },
    );
    await expect(currentChat.locator('.consumer-recent-row__title')).toContainText('local inference');
    await expect(currentChat.locator('.consumer-recent-row__meta')).toContainText('2 messages');

    const keyboardPrompt = 'Confirm in one short sentence that the Enter key sent this message.';
    const composer = appPage.locator('#chat-input');
    await composer.fill('Keep this line');
    await composer.press('Shift+Enter');
    await expect(composer).toHaveValue('Keep this line\n');
    await composer.fill(keyboardPrompt);
    await composer.press('Enter');
    await expect(appPage.locator('.chat-message--user').last()).toContainText('Enter key sent');
    await expectSubstantiveText(
      appPage.locator('.chat-message--assistant .chat-bubble').last(),
      { minLength: 12, timeout: 8 * 60_000 },
    );
    await expect(appPage.locator('#chat-send-btn')).toHaveAttribute('aria-label', 'Send message');

    const tools = appPage.locator('#chat-tools-btn');
    await tools.click();
    await expect(tools).toHaveClass(/\bactive\b/);
    await expect(appPage.locator('#chat-tools-status')).toBeVisible();
    await tools.click();
    await expect(appPage.locator('#chat-tools-status')).toBeHidden();
  });

  test('10b — forces the CPU fallback artifact and performs real inference', async ({ releaseSession }) => {
    const cpuPage = await releaseSession.context.newPage();
    const requestedAssets: string[] = [];
    const diagnostics = observeBrowserDiagnostics(cpuPage);
    cpuPage.on('request', (request) => requestedAssets.push(request.url()));

    try {
      // Shadow Navigator.prototype.gpu before any application code runs. Auto
      // registration must then choose the separately built CPU artifact.
      await cpuPage.addInitScript(() => {
        Object.defineProperty(navigator, 'gpu', {
          configurable: true,
          value: undefined,
        });
      });
      await cpuPage.goto('/', { waitUntil: 'domcontentloaded' });
      await waitForInteractive(cpuPage);
      await expect(cpuPage.locator('#accel-badge')).toHaveText('CPU');
      await expect(cpuPage.locator('#accel-badge')).toHaveCount(1);
      const cpuJS = /racommons-llamacpp(?!-webgpu)(?:-[A-Za-z0-9_-]+)?\.js(?:$|\?)/;
      const cpuWasm = /racommons-llamacpp(?!-webgpu)(?:-[A-Za-z0-9_-]+)?\.wasm(?:$|\?)/;
      const webgpuAsset = /racommons-llamacpp-webgpu(?:-[A-Za-z0-9_-]+)?\.(?:js|wasm)(?:$|\?)/;
      expect(requestedAssets.some((url) => cpuJS.test(url))).toBe(true);
      expect(requestedAssets.some((url) => cpuWasm.test(url))).toBe(true);
      expect(requestedAssets.some((url) => webgpuAsset.test(url))).toBe(false);

      await navigateTo(cpuPage, 'chat');
      await ensureModelReady(cpuPage, '#chat-toolbar-model', RELEASE_MODELS.llm);
      await cpuPage.locator('#chat-input').fill(
        'Reply with one sentence confirming that this inference used the CPU fallback.',
      );
      await cpuPage.locator('#chat-send-btn').click();
      await expectSubstantiveText(
        cpuPage.locator('.chat-message--assistant .chat-bubble').last(),
        { minLength: 16, timeout: 12 * 60_000 },
      );
      await expect(cpuPage.locator('#chat-send-btn')).toHaveAttribute('aria-label', 'Send message', {
        timeout: 12 * 60_000,
      });
      expect(unexpectedBrowserDiagnostics(diagnostics)).toEqual([]);
    } finally {
      await cpuPage.close().catch(() => undefined);
    }
  });

  test('11 — runs all real LLM benchmarks and preserves OPFS/settings across reload', async ({ appPage }) => {
    await navigateTo(appPage, 'benchmarks');
    await appPage.locator('#bench-model-btn').click();
    await expect(appPage.locator('.modal-sheet')).toBeVisible();
    await expect(appPage.locator('#model-sheet-title')).toHaveText('Select LLM Model');
    await appPage.locator('#model-sheet-search').fill(RELEASE_MODELS.llm.query);
    const benchmarkModelRow = appPage.locator(
      `#model-sheet-list [data-model-id="${RELEASE_MODELS.llm.id}"]`,
    ).first();
    await expect(benchmarkModelRow).toBeVisible();
    await benchmarkModelRow.locator(
      `[data-action="unload"][data-model-id="${RELEASE_MODELS.llm.id}"]`,
    ).click();
    await expect.poll(() => isModelLoaded(appPage, RELEASE_MODELS.llm.id), {
      message: 'the benchmark-specific picker must unload its active language model',
      timeout: 120_000,
    }).toBe(false);
    await benchmarkModelRow.locator(
      `[data-action="load"][data-model-id="${RELEASE_MODELS.llm.id}"]`,
    ).click();
    await expect.poll(() => isModelLoaded(appPage, RELEASE_MODELS.llm.id), {
      message: 'the benchmark-specific picker must load the selected language model',
      timeout: 8 * 60_000,
    }).toBe(true);
    await expect(appPage.locator('.modal-sheet')).toBeHidden();
    for (const scenario of ['Short', 'Medium', 'Long'] as const) {
      const run = appPage.locator(`.bench-run-btn[data-name="${scenario}"]`);
      await expect(run).toBeEnabled();
      await run.click();
      await expect(appPage.locator('#bench-status')).toContainText(`Running ${scenario}`);
      await expect(appPage.locator('#bench-status')).toHaveText('Done.', {
        timeout: 30 * 60_000,
      });
    }
    const benchmark = await appPage.locator('#tab-benchmarks .docs-list').innerText();
    expect(benchmark).toMatch(/SmolLM2|smollm2/i);
    expect(benchmark).toMatch(/Short/);
    expect(benchmark).toMatch(/Medium/);
    expect(benchmark).toMatch(/Long/);
    expect(benchmark).toMatch(/tokens|tok\/s/i);
    expect(benchmark).not.toMatch(/Failed:/i);
    await expect(appPage.locator('#tab-benchmarks .docs-list .docs-item')).toHaveCount(3);
    for (const scenario of ['Short', 'Medium', 'Long'] as const) {
      const rowText = await appPage.locator('#tab-benchmarks .docs-list .docs-item', {
        hasText: scenario,
      }).innerText();
      const ttftMs = Number(/TTFT\s+([0-9.]+)\s*ms/i.exec(rowText)?.[1] ?? 0);
      const tokensPerSecond = Number(/([0-9.]+)\s*tok\/s/i.exec(rowText)?.[1] ?? 0);
      const outputTokens = Number(/([0-9]+)\s*tokens/i.exec(rowText)?.[1] ?? 0);
      const totalSeconds = Number(/([0-9.]+)\s*s total/i.exec(rowText)?.[1] ?? 0);
      expect(ttftMs, `${scenario} TTFT must be positive`).toBeGreaterThan(0);
      expect(tokensPerSecond, `${scenario} throughput must be positive`).toBeGreaterThan(0);
      expect(outputTokens, `${scenario} output token count must be positive`).toBeGreaterThan(0);
      expect(totalSeconds, `${scenario} total duration must be positive`).toBeGreaterThan(0);
    }

    await navigateTo(appPage, 'storage');
    await expect(appPage.locator('#storage-location-label')).toContainText('Browser Storage (OPFS)');
    await expect(appPage.locator('#storage-info-header')).toContainText('Models:');
    await expect(appPage.locator('#storage-model-list')).toContainText('SmolLM2');
    await expect(
      appPage.locator(`.storage-delete-btn[data-model-id="${RELEASE_MODELS.llm.id}"]`),
    ).toBeVisible();

    await appPage.locator('#storage-clear-cache-btn').click();
    await expect(appPage.locator('.toast')).toContainText('Cache cleared');
    await appPage.locator('#storage-clean-temp-btn').click();
    await expect(appPage.locator('.toast')).toContainText('Temporary files cleaned');
    await appPage.locator('#storage-open-selection-btn').click();
    await expect(appPage.locator('.modal-sheet')).toBeVisible();
    await appPage.locator('#model-sheet-close').click();

    await appPage.reload({ waitUntil: 'domcontentloaded' });
    await waitForInteractive(appPage);
    await expect.poll(() => isModelDownloaded(appPage, RELEASE_MODELS.llm.id), {
      message: 'LLM must hydrate from OPFS after a hard reload',
      timeout: 180_000,
    }).toBe(true);

    await navigateTo(appPage, 'settings');
    await expect(appPage.locator('#settings-temp-val')).toHaveText('0.2');
    await expect(appPage.locator('#settings-tokens-val')).toHaveText('500');
    await expect(appPage.locator('#settings-system-prompt')).toHaveValue(
      'Answer concisely and directly for automated release verification.',
    );
    const themePersisted = await appPage.evaluate(() => (
      document.documentElement.dataset.theme === localStorage.getItem('runanywhere-theme')
    ));
    expect(themePersisted).toBe(true);

    await navigateTo(appPage, 'chat');
    await expect(
      appPage.locator('.chat-message--user', { hasText: 'local inference' }).first(),
    ).toContainText('local inference');
    await expectSubstantiveText(appPage.locator('.chat-message--assistant .chat-bubble').last(), {
      minLength: 24,
      timeout: 60_000,
    });
    const savedChat = appPage.locator('#consumer-conversation-list .consumer-recent-row', {
      hasText: 'local inference',
    }).first();
    await expect(savedChat).toBeVisible();
    const persistedUserMessages = appPage.locator('.chat-message--user');
    await expect(persistedUserMessages).toHaveCount(3);
    await expect(persistedUserMessages.nth(1)).toContainText('Enter key sent');
    await expect(persistedUserMessages.nth(2)).toContainText('CPU fallback');
    await appPage.locator('#consumer-drawer-new-chat-btn').click();
    await expect(appPage.locator('.chat-message--user')).toHaveCount(0);
    await expect(appPage.locator('.chat-message--assistant')).toHaveCount(0);
    await expect(savedChat).toBeVisible();
    await savedChat.click();
    await expect(persistedUserMessages).toHaveCount(3);

    // A reload intentionally unloads native components. This must be a cheap
    // OPFS load, not another network download.
    await navigateTo(appPage, 'chat');
    await ensureModelReady(appPage, '#chat-toolbar-model', RELEASE_MODELS.llm);
  });

  test('12 — unloads/reloads the LLM and cancels active generation via Stop', async ({ appPage }) => {
    await navigateTo(appPage, 'chat');
    await appPage.locator('#chat-toolbar-model').click();
    await appPage.locator('#model-sheet-search').fill(RELEASE_MODELS.llm.query);
    const row = appPage.locator(
      `#model-sheet-list [data-model-id="${RELEASE_MODELS.llm.id}"]`,
    ).first();
    await expect(row).toBeVisible();
    await row.locator(`[data-action="unload"][data-model-id="${RELEASE_MODELS.llm.id}"]`).click();
    await expect.poll(() => isModelLoaded(appPage, RELEASE_MODELS.llm.id), {
      timeout: 120_000,
    }).toBe(false);
    const reload = row.locator(`[data-action="load"][data-model-id="${RELEASE_MODELS.llm.id}"]`);
    await expect(reload).toBeVisible({ timeout: 120_000 });
    await reload.click();
    await expect.poll(() => isModelLoaded(appPage, RELEASE_MODELS.llm.id), {
      timeout: 8 * 60_000,
    }).toBe(true);
    await expect(appPage.locator('.modal-sheet')).toBeHidden();

    await startFreshChat(appPage);
    await appPage.locator('#chat-input').fill(
      'Write a very long technical report with at least fifty detailed sections about local AI runtimes, model formats, memory allocation, scheduling, and browser isolation.',
    );
    const send = appPage.locator('#chat-send-btn');
    await send.click();
    await expect(send).toHaveAttribute('aria-label', 'Stop generation');
    const assistant = appPage.locator('.chat-message--assistant').last();
    await expect(assistant.locator('.chat-cursor')).toBeVisible({ timeout: 120_000 });
    const normalizeRenderedText = (value: string): string => value.replace(/\s+/g, ' ').trim();
    let beforeStop = '';
    await expect.poll(async () => {
      beforeStop = normalizeRenderedText(await assistant.locator('.chat-bubble').innerText());
      return beforeStop.length;
    }, {
      message: 'generation must stream at least one visible token before Stop',
      timeout: 120_000,
    }).toBeGreaterThan(0);
    expect(beforeStop).not.toMatch(/^Error:/i);
    await expect(send).toHaveAttribute('aria-label', 'Stop generation');
    await send.click();
    await expect(send).toHaveAttribute('aria-label', 'Send message', { timeout: 120_000 });
    const stoppedText = normalizeRenderedText(
      await assistant.locator('.chat-bubble').innerText(),
    );
    expect(stoppedText.length).toBeGreaterThan(0);
    expect(stoppedText).not.toMatch(/^Error:/i);
    await appPage.waitForTimeout(2_000);
    const settledText = normalizeRenderedText(
      await assistant.locator('.chat-bubble').innerText(),
    );
    expect(settledText).toBe(stoppedText);
    await startFreshChat(appPage);
  });

  test('13 — proves Qwen thinking controls and structured JSON generation', async ({ appPage }) => {
    await navigateTo(appPage, 'chat');
    await ensureModelReady(appPage, '#chat-toolbar-model', RELEASE_MODELS.thinkingLlm, {
      downloadTimeout: 30 * 60_000,
      loadTimeout: 12 * 60_000,
    });

    // Test 03 deliberately persists the minimum 500-token budget and test 11
    // verifies it survives a hard reload. Give this reasoning checkpoint a
    // bounded but sufficient budget, then restore the persisted test value.
    await setGenerationTokenBudget(appPage, 2_000);
    await setThinkingMode(appPage, true);
    await navigateTo(appPage, 'chat');
    const thinkingAnswer = await runThinkingEnabledTurn(
      appPage,
      'Reason carefully about which is larger, 17 multiplied by 23 or 19 multiplied by 20, then give the final comparison.',
    );
    expect(thinkingAnswer).toMatch(/17.*23/);
    expect(thinkingAnswer).toMatch(/19.*20/);
    expect(thinkingAnswer).toMatch(/(?:larger|greater|>)/i);

    await setThinkingMode(appPage, false);
    await navigateTo(appPage, 'chat');
    await startFreshChat(appPage);
    await appPage.locator('#chat-input').fill(
      'Answer directly in one sentence: which is larger, 17 multiplied by 23 or 19 multiplied by 20?',
    );
    await appPage.locator('#chat-send-btn').click();
    await expect(appPage.locator('#chat-send-btn')).toHaveAttribute('aria-label', 'Send message', {
      timeout: 12 * 60_000,
    });
    const directReply = appPage.locator('.chat-message--assistant').last();
    await expectSubstantiveText(directReply.locator('.chat-bubble'), {
      minLength: 8,
      timeout: 12 * 60_000,
    });
    await expect(directReply.locator('.chat-thinking')).toHaveCount(0);

    const structured = await appPage.evaluate(async () => {
      interface StructuredResult {
        parsedJson: Uint8Array;
        rawText?: string;
        errorCode: number;
        errorMessage?: string;
        validation?: {
          isValid: boolean;
          containsJson: boolean;
          validationErrors: string[];
        };
      }
      interface StructuredSDK {
        generateStructured?: (
          prompt: string,
          schema: { jsonSchema: string },
          options: { maxTokens: number; temperature: number; disableThinking: boolean },
        ) => Promise<StructuredResult>;
      }
      const sdk = (window as Window & { __RUNANYWHERE_SDK__?: StructuredSDK })
        .__RUNANYWHERE_SDK__;
      if (!sdk?.generateStructured) throw new Error('generateStructured is not exposed');
      const schema = {
        jsonSchema: JSON.stringify({
          type: 'object',
          properties: {
            project: { type: 'string' },
            count: { type: 'integer' },
          },
          required: ['project', 'count'],
          additionalProperties: false,
        }),
      };
      const result = await sdk.generateStructured(
        'Return only a JSON object whose project is RunAnywhere and whose count is the integer 7.',
        schema,
        { maxTokens: 128, temperature: 0, disableThinking: true },
      );
      const decoded = new TextDecoder().decode(result.parsedJson);
      return {
        parsed: JSON.parse(decoded) as unknown,
        rawLength: result.rawText?.length ?? 0,
        errorCode: result.errorCode,
        errorMessage: result.errorMessage ?? '',
        valid: result.validation?.isValid ?? false,
        containsJson: result.validation?.containsJson ?? false,
        validationErrors: result.validation?.validationErrors ?? [],
      };
    });
    expect(structured.errorCode, structured.errorMessage).toBe(0);
    expect(structured.valid, structured.validationErrors.join('; ')).toBe(true);
    expect(structured.containsJson).toBe(true);
    expect(structured.rawLength).toBeGreaterThan(0);
    expect(structured.parsed).toEqual({ project: 'RunAnywhere', count: 7 });
    await setGenerationTokenBudget(appPage, 500);
  });

  test('14 — executes calculator, time, and deterministic weather tools in chat', async ({ appPage }) => {
    await navigateTo(appPage, 'chat');
    await startFreshChat(appPage);
    const tools = appPage.locator('#chat-tools-btn');
    if (!(await tools.evaluate((node) => node.classList.contains('active')))) await tools.click();
    await expect(tools).toHaveClass(/\bactive\b/);

    await runToolTurn(
      appPage,
      'You must call the calculate tool exactly once with the expression (37 * 19) + 5, then report its result.',
      'calculate',
      /708/,
    );
    await runToolTurn(
      appPage,
      'You must call get_current_time exactly once and summarize the returned time and timezone.',
      'get_current_time',
      /timezone|timestamp/i,
    );

    let geocodingRequests = 0;
    let forecastRequests = 0;
    await appPage.route('https://geocoding-api.open-meteo.com/**', async (route) => {
      geocodingRequests += 1;
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        headers: { 'access-control-allow-origin': '*' },
        body: JSON.stringify({
          results: [{ latitude: 37.7749, longitude: -122.4194, name: 'Release City' }],
        }),
      });
    });
    await appPage.route('https://api.open-meteo.com/**', async (route) => {
      forecastRequests += 1;
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        headers: { 'access-control-allow-origin': '*' },
        body: JSON.stringify({
          current: {
            temperature_2m: 72,
            relative_humidity_2m: 40,
            weather_code: 0,
            wind_speed_10m: 5,
          },
        }),
      });
    });
    try {
      await runToolTurn(
        appPage,
        'You must call get_weather exactly once for Release City, then report the returned condition and temperature.',
        'get_weather',
        /Release City|72|Clear sky/i,
        {
          maxAttempts: 3,
          executionCount: () => geocodingRequests + forecastRequests,
        },
      );
      expect(geocodingRequests).toBe(1);
      expect(forecastRequests).toBe(1);
    } finally {
      await appPage.unroute('https://geocoding-api.open-meteo.com/**');
      await appPage.unroute('https://api.open-meteo.com/**');
    }
    await tools.click();
    await expect(tools).not.toHaveClass(/\bactive\b/);
  });

  test('20 — performs batch and live STT from files and the fake microphone', async ({ appPage }) => {
    await navigateTo(appPage, 'transcribe');
    await ensureModelReady(appPage, '#transcribe-model-btn', RELEASE_MODELS.stt);

    await appPage.locator('#mode-batch-btn').click();
    await appPage.locator('#file-input').setInputFiles(AUDIO_FIXTURE);
    const batchTranscript = await expectSubstantiveText(appPage.locator('#transcribe-output'), {
      minLength: 6,
      timeout: 8 * 60_000,
    });
    expect(batchTranscript).toMatch(WEATHER_TRANSCRIPT_PATTERN);

    await appPage.locator('#clear-btn').click();
    await appPage.locator('#mic-toggle-btn').click();
    await expect(appPage.locator('#mic-toggle-btn')).toHaveText('Stop & transcribe');
    await appPage.waitForTimeout(8_000);
    await appPage.locator('#mic-toggle-btn').click();
    const batchMicrophoneTranscript = await expectSubstantiveText(
      appPage.locator('#transcribe-output'),
      {
        minLength: 6,
        timeout: 8 * 60_000,
      },
    );
    expect(batchMicrophoneTranscript).toMatch(WEATHER_TRANSCRIPT_PATTERN);

    await installSTTStreamRecorder(appPage);
    try {
      await appPage.locator('#clear-btn').click();
      await appPage.locator('#mode-live-btn').click();
      await appPage.locator('#file-input').setInputFiles(AUDIO_FIXTURE);
      const streamingTranscript = await expectSubstantiveText(
        appPage.locator('#transcribe-output'),
        {
          minLength: 6,
          timeout: 8 * 60_000,
        },
      );
      expect(streamingTranscript).toMatch(WEATHER_TRANSCRIPT_PATTERN);
      // The offline Whisper backend intentionally starts synthetic partial
      // decodes at three seconds. This 2.1-second file therefore proves the
      // streaming envelope and final result without requiring a partial that
      // the backend cannot emit for such a short utterance.
      await expectFinalSTTStream(appPage, WEATHER_TRANSCRIPT_PATTERN);

      await resetSTTStreamRecorder(appPage);
      await appPage.locator('#clear-btn').click();
      await appPage.locator('#mic-toggle-btn').click();
      await expect(appPage.locator('#mic-toggle-btn')).toHaveText('Stop & transcribe');
      await appPage.waitForTimeout(8_000);
      await appPage.locator('#mic-toggle-btn').click();
      const liveMicrophoneTranscript = await expectSubstantiveText(
        appPage.locator('#transcribe-output'),
        {
          minLength: 6,
          timeout: 8 * 60_000,
        },
      );
      expect(liveMicrophoneTranscript).toMatch(WEATHER_TRANSCRIPT_PATTERN);
      await expectRenderedSTTPartial(appPage, WEATHER_TRANSCRIPT_PATTERN);
    } finally {
      await uninstallSTTStreamRecorder(appPage);
    }
  });

  test('21 — performs real TTS and fake-microphone VAD transitions', async ({ appPage }) => {
    await navigateTo(appPage, 'speak');
    await ensureModelReady(appPage, '#speak-model-btn', RELEASE_MODELS.tts);
    await appPage.locator('#speak-text').fill(
      'RunAnywhere generated this release verification audio entirely on device. ' +
      'The stop control must interrupt this deliberately longer playback promptly ' +
      'while preserving the completed synthesis metadata for inspection.',
    );
    await appPage.locator('#speak-rate').fill('1.2');
    await expect(appPage.locator('#speak-rate-label')).toHaveText('1.2x');
    await installTTSPlaybackRecorder(appPage);
    await appPage.locator('#speak-btn').click();
    await expect.poll(() => recordedTTSPlayback(appPage), {
      message: 'TTS playback.started must be emitted before exercising Stop',
      timeout: 8 * 60_000,
      intervals: [250, 500, 1_000],
    }).toMatchObject({ startedAt: expect.any(Number), durationMs: expect.any(Number) });
    const playbackStarted = await recordedTTSPlayback(appPage);
    expect(playbackStarted.durationMs ?? 0).toBeGreaterThan(2_000);
    await expect(appPage.locator('#stop-btn')).toBeEnabled();
    await appPage.evaluate(() => {
      const target = window as Window & {
        __RA_RELEASE_TTS_PLAYBACK__?: { stopRequestedAt?: number };
      };
      if (target.__RA_RELEASE_TTS_PLAYBACK__) {
        target.__RA_RELEASE_TTS_PLAYBACK__.stopRequestedAt = Date.now();
      }
    });
    await appPage.locator('#stop-btn').click();
    await expect(appPage.locator('#speak-status')).toContainText('Last synthesis:', {
      timeout: 8 * 60_000,
    });
    const stoppedPlayback = await recordedTTSPlayback(appPage);
    expect(stoppedPlayback.completedAt ?? 0).toBeGreaterThanOrEqual(
      stoppedPlayback.stopRequestedAt ?? Number.MAX_SAFE_INTEGER,
    );
    expect((stoppedPlayback.completedAt ?? 0) - (stoppedPlayback.startedAt ?? 0))
      .toBeLessThan((stoppedPlayback.durationMs ?? 0) * 0.75);
    await uninstallTTSPlaybackRecorder(appPage);
    const synthesisStatus = await appPage.locator('#speak-status').innerText();
    expect(synthesisStatus).not.toMatch(/Error:/i);
    const duration = Number(/Last synthesis:\s*([0-9.]+)s/i.exec(synthesisStatus)?.[1] ?? 0);
    expect(duration).toBeGreaterThan(0);

    await navigateTo(appPage, 'vad');
    await ensureModelReady(appPage, '#vad-model-btn', RELEASE_MODELS.vad);
    await appPage.locator('#vad-toggle-btn').click();
    await expect(appPage.locator('#vad-toggle-btn')).toHaveText('Stop listening');
    await expect(appPage.locator('#vad-log')).toContainText('Speech Started', {
      timeout: 120_000,
    });
    await expect(appPage.locator('#vad-log')).toContainText('Speech Ended', {
      timeout: 120_000,
    });
    await expect(appPage.locator('#vad-confidence')).not.toHaveText('-');
    await expect(appPage.locator('#vad-energy')).not.toHaveText('-');
    await appPage.locator('#vad-toggle-btn').click();
    await expect(appPage.locator('#vad-speech-pill')).toHaveText('Idle');
    await appPage.locator('#vad-clear-btn').click();
    await expect(appPage.locator('#vad-log')).toContainText('No speech activity yet');
  });

  test('21b — surfaces failed download Retry, recovers, synthesizes, and switches TTS', async ({ appPage }) => {
    const failedURL = /vits-piper-en_GB-alba-medium\.tar\.gz/i;
    const routePattern = '**/vits-piper-en_GB-alba-medium.tar.gz*';
    await appPage.route(routePattern, async (route) => route.abort('failed'));
    try {
      await withExpectedNetworkFailure(appPage, failedURL, async () => {
        await navigateTo(appPage, 'speak');
        await appPage.locator('#speak-model-btn').click();
        await appPage.locator('#model-sheet-search').fill(RELEASE_MODELS.alternateTts.query);
        const row = appPage.locator(
          `#model-sheet-list [data-model-id="${RELEASE_MODELS.alternateTts.id}"]`,
        ).first();
        await expect(row).toBeVisible();
        await row.locator(
          `[data-action="download"][data-model-id="${RELEASE_MODELS.alternateTts.id}"]`,
        ).click();
        const retry = row.locator(
          `[data-action="download"][data-model-id="${RELEASE_MODELS.alternateTts.id}"]`,
        );
        await expect(retry).toHaveText('Retry', { timeout: 120_000 });
        await expect(appPage.locator('.toast')).toContainText('Download failed');
        expect(await isModelDownloaded(appPage, RELEASE_MODELS.alternateTts.id)).toBe(false);
      });
    } finally {
      await appPage.unroute(routePattern);
    }

    await navigateTo(appPage, 'speak');
    await ensureModelReady(appPage, '#speak-model-btn', RELEASE_MODELS.alternateTts, {
      downloadTimeout: 15 * 60_000,
      loadTimeout: 8 * 60_000,
    });
    await expect(appPage.locator('#speak-model-btn')).toContainText('British English');
    await appPage.locator('#speak-text').fill(
      'The British voice recovered after the deliberate network failure.',
    );
    await installTTSPlaybackRecorder(appPage);
    try {
      await appPage.locator('#speak-btn').click();
      await expect(appPage.locator('#speak-btn')).toHaveText('Speaking...');
      await expectNaturalPlaybackCompleted(appPage, { minDurationMs: 750 });
      await expect(appPage.locator('#speak-status')).toContainText('Last synthesis:', {
        timeout: 8 * 60_000,
      });
    } finally {
      await uninstallTTSPlaybackRecorder(appPage);
    }
    const recoveredStatus = await appPage.locator('#speak-status').innerText();
    expect(recoveredStatus).not.toMatch(/Error:/i);
    expect(Number(/Last synthesis:\s*([0-9.]+)s/i.exec(recoveredStatus)?.[1] ?? 0))
      .toBeGreaterThan(0);

    await ensureModelReady(appPage, '#speak-model-btn', RELEASE_MODELS.tts);
    await expect(appPage.locator('#speak-model-btn')).toContainText('US English');
    expect(await isModelLoaded(appPage, RELEASE_MODELS.tts.id)).toBe(true);
    expect(await isModelLoaded(appPage, RELEASE_MODELS.alternateTts.id)).toBe(false);
  });

  test('22 — completes a fake-microphone voice-agent turn through STT, LLM, and TTS', async ({ appPage }) => {
    await navigateTo(appPage, 'voice');
    await expect(appPage.locator('[data-slot="stt"]')).toBeVisible({ timeout: 60_000 });

    // Pin every slot to the already-verified release models. This exercises
    // each Change picker and prevents a hardware recommendation from pulling
    // a second large LLM into OPFS.
    await chooseVoiceSlot(appPage, 'stt', RELEASE_MODELS.stt);
    await chooseVoiceSlot(appPage, 'llm', RELEASE_MODELS.llm);
    await chooseVoiceSlot(appPage, 'tts', RELEASE_MODELS.tts);
    await chooseVoiceSlot(appPage, 'vad', RELEASE_MODELS.vad);

    // Make every required slot genuinely need setup, while retaining its
    // already-downloaded OPFS artifact. The following setup button must load
    // all three components through the same visible one-click path a user
    // sees after returning to the app.
    await navigateTo(appPage, 'chat');
    await unloadModelThroughPicker(appPage, '#chat-toolbar-model', RELEASE_MODELS.llm);
    await navigateTo(appPage, 'transcribe');
    await unloadModelThroughPicker(appPage, '#transcribe-model-btn', RELEASE_MODELS.stt);
    await navigateTo(appPage, 'speak');
    await unloadModelThroughPicker(appPage, '#speak-model-btn', RELEASE_MODELS.tts);

    await navigateTo(appPage, 'voice');
    await expect(appPage.locator('#voice-setup-btn')).toHaveText('Set up Voice AI');
    for (const slot of ['stt', 'llm', 'tts'] as const) {
      await expect(appPage.locator(`[data-slot="${slot}"]`)).toContainText('On device');
    }
    await appPage.locator('#voice-refresh-btn').click();
    await expect(appPage.locator('#voice-setup-btn')).toHaveText('Set up Voice AI');
    await appPage.locator('#voice-setup-btn').click();
    await expect(appPage.locator('#voice-setup-btn')).toHaveText('Setting up…');
    await expect(appPage.locator('.voice-setup__ready')).toContainText(
      'Your voice assistant is set up.',
      { timeout: 15 * 60_000 },
    );
    for (const slot of ['stt', 'llm', 'tts', 'vad'] as const) {
      await expect(appPage.locator(`[data-slot="${slot}"]`)).toContainText('Ready', {
        timeout: 8 * 60_000,
      });
    }
    await expect(appPage.locator('#voice-start-btn')).toBeEnabled();

    await installVoiceStateRecorder(appPage);
    await installTTSPlaybackRecorder(appPage);
    try {
      await appPage.locator('#voice-start-btn').click();
      await expect(appPage.locator('#voice-state-pill')).toHaveText('Listening', {
        timeout: 180_000,
      });
      const transcript = await expectSubstantiveText(appPage.locator('#voice-user-transcript'), {
        minLength: 6,
        timeout: 12 * 60_000,
      });
      expect(transcript).toMatch(WEATHER_TRANSCRIPT_PATTERN);
      await expectSubstantiveText(appPage.locator('#voice-assistant-response'), {
        // A small local model can answer a wake phrase tersely. The helper
        // still rejects placeholders/errors, while the playback and state
        // assertions below independently prove the complete LLM -> TTS turn.
        minLength: 1,
        timeout: 12 * 60_000,
      });
      await expectNaturalPlaybackCompleted(appPage, { minDurationMs: 250 });

      await expect.poll(() => recordedVoiceStates(appPage), {
        timeout: 12 * 60_000,
        intervals: [500, 1_000, 2_000],
      }).toEqual(expect.arrayContaining(['Listening', 'Thinking', 'Speaking']));
      await expect(appPage.locator('#voice-state-pill')).toHaveText('Listening', {
        timeout: 180_000,
      });
      await expect(appPage.locator('#tab-voice .docs-status.error')).toHaveCount(0);
      await expect(appPage.locator('#voice-stop-btn')).toBeEnabled();
      await appPage.locator('#voice-stop-btn').click();
      await expect(appPage.locator('#voice-state-pill')).toHaveText('Ready');
    } finally {
      await uninstallTTSPlaybackRecorder(appPage);
    }

    // A second real turn verifies Stop while generation is actively in the
    // Thinking state, before TTS playback begins. The cancelled native turn
    // must not leak a delayed Speaking transition back into the UI.
    await installVoiceStateRecorder(appPage);
    await installTTSPlaybackRecorder(appPage);
    try {
      await appPage.locator('#voice-start-btn').click();
      await expect(appPage.locator('#voice-state-pill')).toHaveText('Listening', {
        timeout: 180_000,
      });
      await expect(appPage.locator('#voice-state-pill')).toHaveText('Thinking', {
        timeout: 8 * 60_000,
      });
      const statesAtStop = await recordedVoiceStates(appPage);
      expect(statesAtStop.at(-1)).toBe('Thinking');
      expect(statesAtStop).not.toContain('Speaking');
      expect(await recordedTTSPlayback(appPage)).toEqual({});
      await appPage.locator('#voice-stop-btn').click();
      await expect(appPage.locator('#voice-state-pill')).toHaveText('Ready', {
        timeout: 8 * 60_000,
      });
      await appPage.waitForTimeout(2_000);
      await expect(appPage.locator('#voice-state-pill')).toHaveText('Ready');
      const statesAfterStop = await recordedVoiceStates(appPage);
      const readyIndex = statesAfterStop.lastIndexOf('Ready');
      expect(readyIndex).toBeGreaterThanOrEqual(0);
      expect(statesAfterStop.slice(readyIndex + 1)).not.toContain('Speaking');
      expect(await recordedTTSPlayback(appPage)).toEqual({});
    } finally {
      await uninstallTTSPlaybackRecorder(appPage);
    }
  });

  test('30 — exercises fake camera and performs deterministic VLM inference', async ({ appPage }) => {
    await navigateTo(appPage, 'vision');
    await ensureModelReady(appPage, '#vision-model-btn', RELEASE_MODELS.vlm, {
      downloadTimeout: 30 * 60_000,
      loadTimeout: 15 * 60_000,
    });

    await appPage.locator('#vision-camera-btn').click();
    await expect(appPage.locator('#vision-status')).toHaveText('Camera ready.', { timeout: 120_000 });
    await appPage.locator('#vision-capture-btn').click();
    await expect(appPage.locator('#vision-frame-meta')).toContainText('Last frame:');
    await expect(appPage.locator('#vision-preview video')).toBeVisible();
    await appPage.locator('#vision-prompt').fill(
      'Describe the most important object visible in this captured camera frame.',
    );
    await appPage.locator('#vision-analyze-btn').click();
    const cameraAnswer = await expectSubstantiveText(appPage.locator('#vision-output'), {
      minLength: 16,
      timeout: 15 * 60_000,
    });
    expect(cameraAnswer).not.toMatch(/empty response|vlm inference failed/i);
    await expect(appPage.locator('#vision-status')).toContainText('Done', {
      timeout: 15 * 60_000,
    });
    await appPage.locator('#vision-camera-btn').click();

    await chooseFileVia(
      appPage,
      () => appPage.locator('#vision-load-image-btn').click(),
      IMAGE_FIXTURE,
    );
    await expect(appPage.locator('#vision-status')).toContainText('Loaded', { timeout: 120_000 });
    await expect(appPage.locator('#vision-preview img')).toBeVisible();
    await appPage.locator('#vision-prompt').fill(
      'Describe the most important visible objects and colors in this image.',
    );
    await appPage.locator('#vision-analyze-btn').click();
    const visionAnswer = await expectSubstantiveText(appPage.locator('#vision-output'), {
      minLength: 24,
      timeout: 15 * 60_000,
    });
    expect(visionAnswer).not.toMatch(/empty response|vlm inference failed/i);
    expect(visionAnswer).toMatch(/cat/i);
    expect(visionAnswer).toMatch(/pink|sofa|remote/i);
    await expect(appPage.locator('#vision-status')).toContainText('Done', {
      timeout: 15 * 60_000,
    });

    await appPage.locator('#vision-prompt').fill(
      'Produce an exhaustive two-hundred-token inventory of every visible detail, ' +
      'its location, color, texture, possible purpose, and relationship to every other object.',
    );
    const cancellationProbe = await appPage.evaluate(() => (
      new Promise<{
        streamedText: string;
        cancelDisabled: boolean | null;
        loadImageDisabled: boolean | null;
      }>((resolve, reject) => {
        const visionTab = document.querySelector<HTMLElement>('#tab-vision');
        const analyzeButton = document.querySelector<HTMLButtonElement>('#vision-analyze-btn');
        if (!visionTab || !analyzeButton || analyzeButton.disabled) {
          reject(new Error('Vision cancellation probe could not start inference.'));
          return;
        }

        const observer = new MutationObserver(() => {
          const output = document.querySelector<HTMLElement>('#vision-output');
          const cancelButton = document.querySelector<HTMLButtonElement>('#vision-cancel-btn');
          const streamedText = output?.innerText.trim() ?? '';
          if (streamedText.length < 4 || !cancelButton || cancelButton.disabled) return;

          observer.disconnect();
          window.clearTimeout(timeout);
          cancelButton.click();
          window.dispatchEvent(new CustomEvent('runanywhere:navigate', {
            detail: { tab: 'chat' },
          }));
          window.dispatchEvent(new CustomEvent('runanywhere:navigate', {
            detail: { tab: 'vision' },
          }));
          resolve({
            streamedText,
            cancelDisabled:
              document.querySelector<HTMLButtonElement>('#vision-cancel-btn')?.disabled ?? null,
            loadImageDisabled:
              document.querySelector<HTMLButtonElement>('#vision-load-image-btn')?.disabled ?? null,
          });
        });
        const timeout = window.setTimeout(() => {
          observer.disconnect();
          reject(new Error('Vision inference did not stream before the cancellation timeout.'));
        }, 8 * 60_000);
        observer.observe(visionTab, { childList: true, subtree: true, characterData: true });
        analyzeButton.click();
      })
    ));
    expect(cancellationProbe.streamedText.length).toBeGreaterThanOrEqual(4);
    expect(cancellationProbe.streamedText).not.toMatch(/\b(?:failed|error|unavailable)\b/i);
    expect(cancellationProbe).toMatchObject({
      cancelDisabled: false,
      loadImageDisabled: true,
    });
    await expect(appPage.locator('#vision-status')).toHaveText('Cancelled.', {
      timeout: 120_000,
    });
    await expect(appPage.locator('#vision-cancel-btn')).toBeDisabled();
    await expect(appPage.locator('#vision-load-image-btn')).toBeEnabled();
    await expect(appPage.locator('#vision-analyze-btn')).toBeDisabled();
    const cancelledVisionText = await appPage.locator('#vision-output').innerText();
    await appPage.waitForTimeout(2_000);
    await expect(appPage.locator('#vision-output')).toHaveText(cancelledVisionText);

    // The consumer composer has a second, production-facing image path.
    await navigateTo(appPage, 'chat');
    await startFreshChat(appPage);
    await chooseChatAttachmentViaMenu(appPage, 'image', IMAGE_FIXTURE);
    await expect(appPage.locator('#chat-attachment-pill')).toContainText('test.jpg');
    await appPage.locator('#chat-input').fill(
      'Identify the main animal and the pink furniture or nearby objects in this image.',
    );
    await appPage.locator('#chat-send-btn').click();
    const chatImageAnswer = await expectSubstantiveText(
      appPage.locator('.chat-message--assistant .chat-bubble').last(), {
      minLength: 20,
      timeout: 15 * 60_000,
    });
    expect(chatImageAnswer).toMatch(/cat/i);
    expect(chatImageAnswer).toMatch(/pink|sofa|remote/i);
    await expect(appPage.locator('#chat-send-btn')).toHaveAttribute('aria-label', 'Send message', {
      timeout: 15 * 60_000,
    });
  });

  test('40 — indexes a real document and returns a grounded RAG answer', async ({ appPage }) => {
    // Reinstantiate the llama.cpp artifact after ONNX registration. This is a
    // production path (explicit acceleration changes and Qwen VLM fallback)
    // and previously let llama.cpp steal the embedding capability despite
    // having no embedding vtable. RAG below proves ONNX lifecycle state and
    // routing survive last-writer registration order.
    const accelerationSwitch = await switchToOppositeAcceleration(appPage);
    expect(accelerationSwitch.active).toBe(accelerationSwitch.requested);
    expect(accelerationSwitch.active).not.toBe(accelerationSwitch.previous);
    expect(accelerationSwitch.badge).toBe(
      accelerationSwitch.requested === 'webgpu' ? 'WebGPU' : 'CPU',
    );

    await navigateTo(appPage, 'documents');
    await appPage.locator('#docs-embedding-model').selectOption(RELEASE_MODELS.embedding.id);
    await appPage.locator('#docs-llm-model').selectOption(RELEASE_MODELS.llm.id);

    if (!(await isModelDownloaded(appPage, RELEASE_MODELS.embedding.id))) {
      await appPage.locator('#docs-embedding-download-btn').click();
      await expect.poll(() => isModelDownloaded(appPage, RELEASE_MODELS.embedding.id), {
        message: 'embedding model must be downloaded for the RAG release gate',
        timeout: 15 * 60_000,
      }).toBe(true);
    }
    if (!(await isModelDownloaded(appPage, RELEASE_MODELS.llm.id))) {
      await appPage.locator('#docs-llm-download-btn').click();
      await expect.poll(() => isModelDownloaded(appPage, RELEASE_MODELS.llm.id), {
        message: 'LLM model must be downloaded for the RAG release gate',
        timeout: 15 * 60_000,
      }).toBe(true);
    }
    await expect(appPage.locator('#docs-embedding-download-btn')).toHaveText('Downloaded');
    await expect(appPage.locator('#docs-llm-download-btn')).toHaveText('Downloaded');

    await chooseFileVia(
      appPage,
      () => appPage.locator('#docs-upload-btn').click(),
      RAG_FIXTURE,
    );
    await expect(appPage.locator('#docs-status')).toContainText('Indexed release-rag.txt', {
      timeout: 10 * 60_000,
    });
    await expect(appPage.locator('#docs-list')).toContainText('release-rag.txt');
    await appPage.locator('#docs-query').fill(
      'What are the deterministic project codename and verified launch color?',
    );
    await appPage.locator('#docs-ask-btn').click();
    const ragAnswer = await expectSubstantiveText(appPage.locator('#docs-answer .docs-answer-text'), {
      minLength: 20,
      timeout: 12 * 60_000,
    });
    expect(ragAnswer).not.toMatch(/no relevant chunks|failed/i);
    await expect(appPage.locator('#docs-answer .docs-sources')).toContainText('MERIDIAN-742');
    await expect(appPage.locator('#docs-answer .docs-sources')).toContainText('cobalt blue');

    // Replace llama.cpp again after the pipeline owns a real vector index.
    // The next query must self-heal the configured LLM without clearing the
    // indexed document from the TypeScript cross-WASM provider.
    const postIndexSwitch = await switchToOppositeAcceleration(appPage);
    expect(postIndexSwitch.active).toBe(postIndexSwitch.requested);
    expect(postIndexSwitch.badge).toBe(
      postIndexSwitch.requested === 'webgpu' ? 'WebGPU' : 'CPU',
    );
    await appPage.locator('#docs-query').fill(
      'Return one exact fact from the document: either the project codename or the launch color.',
    );
    await appPage.locator('#docs-ask-btn').click();
    const postSwitchAnswer = await expectSubstantiveText(
      appPage.locator('#docs-answer .docs-answer-text'),
      { minLength: 8, timeout: 12 * 60_000 },
    );
    expect(postSwitchAnswer).not.toMatch(/no relevant chunks|failed/i);
    expect(postSwitchAnswer).toMatch(/meridian[-\s]?742|cobalt blue/i);
    await expect(appPage.locator('#docs-answer .docs-sources')).toContainText('MERIDIAN-742');
    await expect(appPage.locator('#docs-answer .docs-sources')).toContainText('cobalt blue');

    // The CrossWasm provider exposes the full document lifecycle. Prove that
    // listing is not a synthetic count-only fallback, then remove, re-index,
    // and clear the corpus through the same public facade.
    const indexedDocument = appPage.locator('#docs-list .docs-item', {
      hasText: 'release-rag.txt',
    });
    await expect(indexedDocument).toBeVisible();
    await indexedDocument.locator('.docs-item-delete').click();
    await expect(appPage.locator('#docs-status')).toHaveText('Document removed.');
    await expect(appPage.locator('#docs-list')).toContainText('No documents indexed yet');

    await chooseFileVia(
      appPage,
      () => appPage.locator('#docs-upload-btn').click(),
      RAG_FIXTURE,
    );
    await expect(appPage.locator('#docs-status')).toContainText('Indexed release-rag.txt', {
      timeout: 10 * 60_000,
    });
    await expect(appPage.locator('#docs-list .docs-item')).toHaveCount(1);
    await appPage.locator('#docs-clear-btn').click();
    await expect(appPage.locator('#docs-status')).toHaveText('All documents cleared.');
    await expect(appPage.locator('#docs-list')).toContainText('No documents indexed yet');

    // Runtime teardown destroys the provider but leaves the mounted Documents
    // view's selected model ids intact. Re-entering the tab must invalidate
    // its cached pipeline key and recreate a live provider on the next upload.
    const destroyedAvailability = await appPage.evaluate(async () => {
      const sdk = (window as Window & {
        __RUNANYWHERE_SDK__?: {
          ragDestroyPipeline?: () => Promise<void>;
          rag?: { availability?: () => { available: boolean } };
        };
      }).__RUNANYWHERE_SDK__;
      if (!sdk?.ragDestroyPipeline || !sdk.rag?.availability) {
        throw new Error('Release RAG teardown probe is unavailable.');
      }
      await sdk.ragDestroyPipeline();
      return sdk.rag.availability().available;
    });
    expect(destroyedAvailability).toBe(false);
    await navigateTo(appPage, 'chat');
    await navigateTo(appPage, 'documents');
    await chooseFileVia(
      appPage,
      () => appPage.locator('#docs-upload-btn').click(),
      RAG_FIXTURE,
    );
    await expect(appPage.locator('#docs-status')).toContainText('Indexed release-rag.txt', {
      timeout: 10 * 60_000,
    });

    // A different app surface can replace the global provider even with the
    // same model ids. Generation identity—not availability or ids alone—must
    // make Documents reclaim its own pipeline on the next visible action.
    const replacementGeneration = await appPage.evaluate(async ({ embeddingId, llmId }) => {
      interface PipelineState {
        generation: number;
      }
      const sdk = (window as Window & {
        __RUNANYWHERE_SDK__?: {
          ragCreatePipeline?: (embedding: string, llm: string) => Promise<void>;
          rag?: { pipelineState?: () => PipelineState };
        };
      }).__RUNANYWHERE_SDK__;
      if (!sdk?.ragCreatePipeline || !sdk.rag?.pipelineState) {
        throw new Error('Release RAG pipeline identity probe is unavailable.');
      }
      await sdk.ragCreatePipeline(embeddingId, llmId);
      return sdk.rag.pipelineState().generation;
    }, {
      embeddingId: RELEASE_MODELS.embedding.id,
      llmId: RELEASE_MODELS.llm.id,
    });
    await navigateTo(appPage, 'chat');
    await navigateTo(appPage, 'documents');
    await chooseFileVia(
      appPage,
      () => appPage.locator('#docs-upload-btn').click(),
      RAG_FIXTURE,
    );
    await expect(appPage.locator('#docs-status')).toContainText('Indexed release-rag.txt', {
      timeout: 10 * 60_000,
    });
    const reclaimedGeneration = await appPage.evaluate(() => {
      const sdk = (window as Window & {
        __RUNANYWHERE_SDK__?: { rag?: { pipelineState?: () => { generation: number } } };
      }).__RUNANYWHERE_SDK__;
      if (!sdk?.rag?.pipelineState) {
        throw new Error('Release RAG pipeline identity probe is unavailable.');
      }
      return sdk.rag.pipelineState().generation;
    });
    expect(reclaimedGeneration).toBeGreaterThan(replacementGeneration);
    await appPage.locator('#docs-clear-btn').click();
    await expect(appPage.locator('#docs-status')).toHaveText('All documents cleared.');

    // Also prove the document attachment path in the main assistant composer.
    await navigateTo(appPage, 'chat');
    await startFreshChat(appPage);
    await chooseChatAttachmentViaMenu(appPage, 'document', RAG_FIXTURE);
    await expect(appPage.locator('#chat-attachment-pill')).toContainText('release-rag.txt');
    await appPage.locator('#chat-input').fill(
      'Write a very long, two-hundred-section report grounded in this document. ' +
      'Repeat and analyze every project detail at length.',
    );
    const send = appPage.locator('#chat-send-btn');
    await send.click();
    await expect(send).toHaveAttribute('aria-label', 'Stop generation', { timeout: 120_000 });
    const cancellingReply = appPage.locator('.chat-message--assistant .chat-bubble').last();
    await expect(cancellingReply.locator('.chat-cursor')).toBeVisible({ timeout: 8 * 60_000 });
    await send.click();
    await expect(send).toHaveAttribute('aria-label', 'Send message', { timeout: 120_000 });
    await expect(cancellingReply).toHaveText('Cancelled.');
    const cancelledText = await cancellingReply.innerText();
    await appPage.waitForTimeout(2_000);
    await expect(cancellingReply).toHaveText(cancelledText);

    await startFreshChat(appPage);
    await chooseChatAttachmentViaMenu(appPage, 'document', RAG_FIXTURE);
    await expect(appPage.locator('#chat-attachment-pill')).toContainText('release-rag.txt');
    await appPage.locator('#chat-input').fill(
      'Return one exact fact from this document: either the project codename or launch color.',
    );
    await appPage.locator('#chat-send-btn').click();
    const attachmentReply = appPage.locator('.chat-message--assistant .chat-bubble').last();
    await expect.poll(async () => {
      const text = (await attachmentReply.textContent() ?? '').trim();
      if (/\b(?:failed|error|unavailable)\b/i.test(text)) {
        throw new Error(`Terminal document attachment output: ${text}`);
      }
      return /MERIDIAN-742|cobalt blue/i.test(text);
    }, {
      message: 'document attachment must return a grounded fact after indexing',
      timeout: 12 * 60_000,
      intervals: [500, 1_000, 2_000, 5_000],
    }).toBe(true);
    const sourceStrip = appPage.locator('.chat-message--assistant .chat-source-strip').last();
    await expect(sourceStrip).toContainText('Sources');
    await expect(sourceStrip).toContainText(/release-rag\.txt/i);
    await expect(sourceStrip).toContainText('MERIDIAN-742');
    await expect(sourceStrip).toContainText('cobalt blue');
    await expect(appPage.locator('#chat-send-btn')).toHaveAttribute('aria-label', 'Send message', {
      timeout: 12 * 60_000,
    });
  });

  test('50 — executes Solutions and the complete browser/local-folder storage lifecycle', async ({ appPage }) => {
    await navigateTo(appPage, 'solutions');
    await appPage.locator('#solutions-run-voice').click();
    await expect(appPage.locator('#solutions-log')).toContainText('OK Voice Agent: destroyed.', {
      timeout: 180_000,
    });
    await appPage.locator('#solutions-run-rag').click();
    await expect(appPage.locator('#solutions-log')).toContainText('OK RAG: destroyed.', {
      timeout: 180_000,
    });
    const solutionLog = await appPage.locator('#solutions-log').innerText();
    expect(solutionLog).not.toMatch(/(?:ERR|N\/A) (?:Voice Agent|RAG):/i);

    await navigateTo(appPage, 'storage');
    const vadDelete = appPage.locator(
      `.storage-delete-btn[data-model-id="${RELEASE_MODELS.vad.id}"]`,
    );
    await expect(vadDelete).toBeVisible();
    await vadDelete.click();
    await expect(appPage.locator('.toast')).toContainText(`Deleted ${RELEASE_MODELS.vad.id}`);
    await expect.poll(() => isModelDownloaded(appPage, RELEASE_MODELS.vad.id), {
      timeout: 120_000,
    }).toBe(false);
    await expect(appPage.locator('#storage-info-header')).not.toContainText('unavailable');

    // Playwright cannot operate Chrome's native macOS directory dialog. Use a
    // real, structured-cloneable FileSystemDirectoryHandle from an isolated
    // subdirectory as the picker result. This still exercises the production
    // click handler, IndexedDB handle persistence, selected-root routing, real
    // file writes, reload restore, permission re-authorization, model load,
    // and recursive delete without replacing any SDK method.
    await appPage.evaluate(async (directoryName) => {
      const originRoot = await navigator.storage.getDirectory();
      const selected = await originRoot.getDirectoryHandle(directoryName, { create: true });
      const target = window as Window & {
        showDirectoryPicker?: (options?: { mode?: 'read' | 'readwrite' }) =>
          Promise<FileSystemDirectoryHandle>;
      };
      Object.defineProperty(target, 'showDirectoryPicker', {
        configurable: true,
        value: async (options?: { mode?: 'read' | 'readwrite' }) => {
          if (options?.mode !== 'readwrite') {
            throw new Error('Release picker must request read/write access.');
          }
          return selected;
        },
      });
    }, RELEASE_LOCAL_DIRECTORY);

    await appPage.locator('#storage-choose-dir-btn').click();
    await expect(appPage.locator('.toast')).toContainText(
      `Using folder: ${RELEASE_LOCAL_DIRECTORY}`,
    );
    await expect(appPage.locator('#storage-location-label')).toContainText('Local Folder:');
    await expect(appPage.locator('#storage-location-label')).toContainText(RELEASE_LOCAL_DIRECTORY);
    const selectedState = await readBrowserStorageState(appPage);
    expect(selectedState).toEqual({
      backend: 'fsAccess',
      directoryName: RELEASE_LOCAL_DIRECTORY,
      hasHandle: true,
      ready: true,
      supported: true,
    });

    // Download a fresh real artifact after switching roots, load it, and prove
    // the selected directory—not the default OPFS root—owns the model bytes.
    await navigateTo(appPage, 'vad');
    await ensureModelReady(appPage, '#vad-model-btn', RELEASE_MODELS.vad);
    await expect.poll(
      () => originDirectoryFileSize(
        appPage,
        RELEASE_LOCAL_DIRECTORY,
        'silero_vad.onnx',
      ),
      {
        message: 'the selected persistent directory must contain the VAD model bytes',
        timeout: 180_000,
      },
    ).toBeGreaterThan(2_000_000);

    // Force the restored handle through Chrome's prompt state on reload, then
    // grant it through the visible Re-authorize control. The handle remains a
    // genuine IndexedDB-persisted FileSystemDirectoryHandle throughout.
    await appPage.evaluate((permissionKey) => {
      localStorage.setItem(permissionKey, 'prompt');
    }, RELEASE_LOCAL_PERMISSION_KEY);
    await appPage.context().addInitScript(({ permissionKey }) => {
      interface PermissionCapableDirectoryPrototype {
        queryPermission?: (descriptor?: unknown) => Promise<PermissionState>;
        requestPermission?: (descriptor?: unknown) => Promise<PermissionState>;
      }
      const target = globalThis as typeof globalThis & {
        FileSystemDirectoryHandle?: { prototype: PermissionCapableDirectoryPrototype };
      };
      const prototype = target.FileSystemDirectoryHandle?.prototype;
      if (!prototype) return;
      Object.defineProperties(prototype, {
        queryPermission: {
          configurable: true,
          value: async (): Promise<PermissionState> => (
            localStorage.getItem(permissionKey) === 'granted' ? 'granted' : 'prompt'
          ),
        },
        requestPermission: {
          configurable: true,
          value: async (): Promise<PermissionState> => {
            localStorage.setItem(permissionKey, 'granted');
            return 'granted';
          },
        },
      });
    }, { permissionKey: RELEASE_LOCAL_PERMISSION_KEY });

    await appPage.reload({ waitUntil: 'domcontentloaded' });
    await waitForInteractive(appPage);
    await navigateTo(appPage, 'storage');
    await expect(appPage.locator('#storage-location-label')).toContainText(
      'needs re-authorization',
    );
    await expect(appPage.locator('#storage-reauth-btn')).toBeVisible();
    expect(await readBrowserStorageState(appPage)).toEqual({
      backend: 'opfs',
      directoryName: RELEASE_LOCAL_DIRECTORY,
      hasHandle: true,
      ready: false,
      supported: true,
    });

    await appPage.locator('#storage-reauth-btn').click();
    await expect(appPage.locator('.toast')).toContainText('Access re-authorized');
    await expect(appPage.locator('#storage-location-label')).toContainText('Local Folder:');
    expect(await readBrowserStorageState(appPage)).toEqual({
      backend: 'fsAccess',
      directoryName: RELEASE_LOCAL_DIRECTORY,
      hasHandle: true,
      ready: true,
      supported: true,
    });
    await expect.poll(() => isModelDownloaded(appPage, RELEASE_MODELS.vad.id), {
      message: 'the re-authorized folder must hydrate its downloaded model',
      timeout: 180_000,
    }).toBe(true);

    await navigateTo(appPage, 'vad');
    await ensureModelReady(appPage, '#vad-model-btn', RELEASE_MODELS.vad);
    await navigateTo(appPage, 'storage');
    const externalVadDelete = appPage.locator(
      `.storage-delete-btn[data-model-id="${RELEASE_MODELS.vad.id}"]`,
    );
    await externalVadDelete.click();
    await expect(appPage.locator('.toast')).toContainText(`Deleted ${RELEASE_MODELS.vad.id}`);
    await expect.poll(() => isModelDownloaded(appPage, RELEASE_MODELS.vad.id), {
      timeout: 120_000,
    }).toBe(false);
    await expect.poll(
      () => originDirectoryFileSize(
        appPage,
        RELEASE_LOCAL_DIRECTORY,
        'silero_vad.onnx',
      ),
      {
        message: 'deleting the model must remove it from the selected directory',
        timeout: 120_000,
      },
    ).toBe(0);
  });
});

interface BrowserStorageState {
  backend: 'fsAccess' | 'opfs' | 'memory' | undefined;
  directoryName: string | null | undefined;
  hasHandle: boolean;
  ready: boolean;
  supported: boolean;
}

async function readBrowserStorageState(page: Page): Promise<BrowserStorageState> {
  return page.evaluate(() => {
    const sdk = (window as Window & {
      __RUNANYWHERE_SDK__?: {
        storage?: {
          backend?: 'fsAccess' | 'opfs' | 'memory';
          hasLocalStorageHandle?: boolean;
          isLocalStorageReady?: boolean;
          isLocalStorageSupported?: boolean;
          localStorageDirectoryName?: string | null;
        };
      };
    }).__RUNANYWHERE_SDK__;
    return {
      backend: sdk?.storage?.backend,
      directoryName: sdk?.storage?.localStorageDirectoryName,
      hasHandle: sdk?.storage?.hasLocalStorageHandle === true,
      ready: sdk?.storage?.isLocalStorageReady === true,
      supported: sdk?.storage?.isLocalStorageSupported === true,
    };
  });
}

async function originDirectoryFileSize(
  page: Page,
  directoryName: string,
  expectedFilename: string,
): Promise<number> {
  return page.evaluate(async ({ directoryName: name, expectedFilename: filename }) => {
    const visit = async (directory: FileSystemDirectoryHandle): Promise<number> => {
      for await (const [entryName, handle] of directory.entries()) {
        if (handle.kind === 'file' && entryName === filename) {
          return (await (handle as FileSystemFileHandle).getFile()).size;
        }
        if (handle.kind === 'directory') {
          const nestedSize = await visit(handle as FileSystemDirectoryHandle);
          if (nestedSize > 0) return nestedSize;
        }
      }
      return 0;
    };

    try {
      const originRoot = await navigator.storage.getDirectory();
      const selected = await originRoot.getDirectoryHandle(name);
      return await visit(selected);
    } catch (error) {
      if (error instanceof DOMException && error.name === 'NotFoundError') return 0;
      throw error;
    }
  }, { directoryName, expectedFilename });
}

interface RuntimeLifecycleProbe {
  initialized: boolean;
  servicesReady: boolean;
  shellState: string | undefined;
  backend: string | undefined;
  modelUI: string | undefined;
  accelerationBadgeCount: number;
}

async function readRuntimeLifecycle(page: Page): Promise<RuntimeLifecycleProbe> {
  return page.evaluate(() => {
    const target = window as Window & {
      __RUNANYWHERE_AI_READY__?: { state?: string };
      __RUNANYWHERE_SDK__?: {
        isInitialized?: boolean;
        areServicesReady?: boolean;
      };
    };
    return {
      initialized: target.__RUNANYWHERE_SDK__?.isInitialized === true,
      servicesReady: target.__RUNANYWHERE_SDK__?.areServicesReady === true,
      shellState: target.__RUNANYWHERE_AI_READY__?.state,
      backend: document.documentElement.dataset.runanywhereAiBackend,
      modelUI: document.documentElement.dataset.runanywhereAiModelUiReady,
      accelerationBadgeCount: document.querySelectorAll('#accel-badge').length,
    };
  });
}

async function chooseFileVia(
  page: Page,
  openChooser: () => Promise<unknown>,
  filePath: string,
): Promise<void> {
  const [chooser] = await Promise.all([
    page.waitForEvent('filechooser', { timeout: 120_000 }),
    openChooser(),
  ]);
  await chooser.setFiles(filePath);
}

async function chooseChatAttachmentViaMenu(
  page: Page,
  kind: 'document' | 'image',
  filePath: string,
): Promise<void> {
  const input = page.locator(kind === 'document' ? '#chat-document-input' : '#chat-image-input');
  await input.evaluate((element) => {
    element.dataset.releasePickerActivated = 'false';
    element.addEventListener('click', () => {
      element.dataset.releasePickerActivated = 'true';
    }, { once: true });
  });
  await page.locator('#chat-attach-btn').click();
  const action = page.locator(`#chat-attach-menu [data-action="${kind}"]`);
  await expect(action).toBeVisible();
  await action.click();
  await expect(input).toHaveAttribute('data-release-picker-activated', 'true');
  await input.setInputFiles(filePath);
  await input.evaluate((element) => {
    delete element.dataset.releasePickerActivated;
  });
}

async function switchToOppositeAcceleration(page: Page): Promise<{
  previous: 'cpu' | 'webgpu';
  requested: 'cpu' | 'webgpu';
  active: string | null | undefined;
  badge: string | undefined;
}> {
  return page.evaluate(async () => {
    interface ReleaseRuntime {
      active?: string | null;
      setAcceleration?: (mode: 'cpu' | 'webgpu') => Promise<void>;
    }
    const runtime = (window as Window & {
      __RUNANYWHERE_SDK__?: { runtime?: ReleaseRuntime };
    }).__RUNANYWHERE_SDK__?.runtime;
    if (!runtime?.setAcceleration || (runtime.active !== 'cpu' && runtime.active !== 'webgpu')) {
      throw new Error('Release RAG gate requires an active acceleration switcher.');
    }
    const previous = runtime.active;
    const requested = previous === 'webgpu' ? 'cpu' : 'webgpu';
    let timeoutId = 0;
    try {
      await Promise.race([
        runtime.setAcceleration(requested),
        new Promise<never>((_resolve, reject) => {
          timeoutId = window.setTimeout(() => {
            reject(new Error(`Acceleration switch to ${requested} timed out.`));
          }, 5 * 60_000);
        }),
      ]);
    } finally {
      window.clearTimeout(timeoutId);
    }
    return {
      previous,
      requested,
      active: runtime.active,
      badge: document.querySelector('#accel-badge')?.textContent?.trim(),
    };
  });
}

async function chooseVoiceSlot(
  page: Page,
  slot: 'stt' | 'llm' | 'tts' | 'vad',
  model: { id: string; query: string },
): Promise<void> {
  const trigger = page.locator(`[data-slot="${slot}"] [data-change="${slot}"]`);
  await ensureModelReady(page, trigger, model);
  await expect(page.locator(`[data-slot="${slot}"]`)).toContainText('Ready');
}

async function unloadModelThroughPicker(
  page: Page,
  trigger: string,
  model: { id: string; query: string },
): Promise<void> {
  const sheet = page.locator('.modal-sheet');
  await page.locator(trigger).click();
  await expect(sheet).toBeVisible();
  await page.locator('#model-sheet-search').fill(model.query);
  const row = page.locator(
    `#model-sheet-list [data-model-id="${model.id}"]`,
  ).first();
  await expect(row).toBeVisible();
  const unload = row.locator(
    `[data-action="unload"][data-model-id="${model.id}"]`,
  );
  await expect(unload, `${model.id} must be active before setup verification`).toBeVisible();
  await unload.click();
  await expect(
    row.locator(`[data-action="load"][data-model-id="${model.id}"]`),
    `${model.id} unload must finish before the picker closes`,
  ).toBeVisible({ timeout: 120_000 });
  await expect.poll(() => isModelLoaded(page, model.id), {
    message: `${model.id} must be unloaded through its visible picker`,
    timeout: 120_000,
    intervals: [500, 1_000, 2_000],
  }).toBe(false);
  await page.locator('#model-sheet-close').click();
  await expect(sheet).toBeHidden();
  expect(await isModelDownloaded(page, model.id)).toBe(true);
}

async function setThinkingMode(page: Page, enabled: boolean): Promise<void> {
  await navigateTo(page, 'settings');
  const toggle = page.locator('#settings-thinking-toggle');
  const current = await toggle.evaluate((node) => node.classList.contains('on'));
  if (current !== enabled) await toggle.click();
  if (enabled) {
    await expect(toggle).toHaveClass(/\bon\b/);
  } else {
    await expect(toggle).toHaveClass(/^(?!.*\bon\b)/);
  }
}

async function startFreshChat(page: Page): Promise<void> {
  const messages = page.locator('.chat-message--user, .chat-message--assistant');
  const input = page.locator('#chat-input');
  if (await messages.count() === 0 && await input.inputValue() === '') return;
  await page.locator('#consumer-new-chat-btn').click();
  await expect(messages).toHaveCount(0);
  await expect(input).toHaveValue('');
}

async function setGenerationTokenBudget(page: Page, target: number): Promise<void> {
  if (!Number.isInteger(target) || target < 500 || target > 20_000 || target % 500 !== 0) {
    throw new Error(`Invalid generation token budget: ${target}`);
  }

  await navigateTo(page, 'settings');
  const value = page.locator('#settings-tokens-val');
  for (let attempt = 0; attempt < 40; attempt += 1) {
    const current = Number(await value.textContent());
    if (current === target) break;
    await page.locator(
      current < target ? '#settings-tokens-plus' : '#settings-tokens-minus',
    ).click();
  }
  await expect(value).toHaveText(String(target));
}

async function runThinkingEnabledTurn(
  page: Page,
  prompt: string,
): Promise<string> {
  const send = page.locator('#chat-send-btn');
  const maxAttempts = 3;
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    await startFreshChat(page);
    await page.locator('#chat-input').fill(prompt);
    await send.click();
    await expect(send).toHaveAttribute('aria-label', 'Stop generation', { timeout: 120_000 });
    const liveReply = page.locator('.chat-message--assistant').last();
    await expect(liveReply.locator('.chat-thinking')).toHaveAttribute('open', '', {
      timeout: 30_000,
    });
    await expect(send).toHaveAttribute('aria-label', 'Send message', {
      timeout: 12 * 60_000,
    });

    const reply = page.locator('.chat-message--assistant').last();
    await expect(reply).toBeVisible();
    const completedThinking = reply.locator('.chat-thinking');
    await expect(completedThinking).not.toHaveAttribute('open', '');
    await expect(reply.locator('.chat-bubble')).toBeVisible();
    expect(await reply.evaluate((message) => {
      const thinking = message.querySelector('.chat-thinking');
      const answer = message.querySelector('.chat-bubble');
      return Boolean(
        thinking
        && answer
        && (thinking.compareDocumentPosition(answer) & Node.DOCUMENT_POSITION_FOLLOWING),
      );
    }), 'the final answer must render below the collapsed reasoning trace').toBe(true);
    await expect(reply.locator('.chat-bubble')).not.toContainText(/<\/?(?:think|thinking)>/i);
    await expectSubstantiveText(reply.locator('.chat-thinking-content'), {
      minLength: 12,
      timeout: 30_000,
      forbidden: /\b(?:failed|error|unavailable)\b/i,
    });
    try {
      await expectSubstantiveText(reply.locator('.chat-bubble'), {
        minLength: 8,
        timeout: 30_000,
        forbidden: /response limit|without producing a final answer|no final answer|cancelled/i,
      });
      await completedThinking.locator('summary').click();
      await expect(completedThinking).toHaveAttribute('open', '');
      await completedThinking.locator('summary').click();
      await expect(completedThinking).not.toHaveAttribute('open', '');
      return (await reply.locator('.chat-bubble').textContent() ?? '').trim();
    } catch (error) {
      const retryable = /response limit|without producing a final answer|no final answer|cancelled/i.test(
        error instanceof Error ? error.message : String(error),
      );
      if (!retryable || attempt === maxAttempts) throw error;
    }
  }
  throw new Error('Thinking-enabled generation exhausted its retry budget.');
}

async function runToolTurn(
  page: Page,
  prompt: string,
  expectedTool: 'calculate' | 'get_current_time' | 'get_weather',
  expectedResult: RegExp,
  options: {
    maxAttempts?: number;
    executionCount?: () => number;
  } = {},
): Promise<void> {
  const maxAttempts = Math.max(1, options.maxAttempts ?? 2);
  const send = page.locator('#chat-send-btn');
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    await page.locator('#chat-input').fill(prompt);
    await send.click();
    await expect(send).toHaveAttribute('aria-label', 'Stop generation', { timeout: 120_000 });
    await expect(send).toHaveAttribute('aria-label', 'Send message', {
      timeout: 15 * 60_000,
    });
    const reply = page.locator('.chat-message--assistant').last();
    const toolCall = reply.locator('.chat-tool-call').filter({ hasText: expectedTool }).first();
    if (await toolCall.count() > 0) {
      await expect(toolCall, `${expectedTool} must be rendered in the assistant trace`).toBeVisible();
      await expect(toolCall.locator('summary')).toContainText('completed');
      const trace = await toolCall.locator('pre').textContent();
      expect(trace ?? '').toMatch(expectedResult);
      expect(trace ?? '').not.toMatch(/\bError:/i);
      await expectSubstantiveText(reply.locator('.chat-bubble'), {
        minLength: 8,
        timeout: 15 * 60_000,
        forbidden: /\b(?:failed|error|unavailable)\b|did not (?:produce|provide)/i,
      });
      return;
    }

    const executionCount = options.executionCount?.() ?? 0;
    const terminalText = (await reply.innerText()).replace(/\s+/g, ' ').trim();
    if (executionCount > 0) {
      throw new Error(
        `${expectedTool} executed ${executionCount} request(s) but its trace was not rendered: ${terminalText}`,
      );
    }
    if (attempt === maxAttempts) {
      throw new Error(
        `${expectedTool} produced no tool call after ${maxAttempts} attempt(s): ${terminalText}`,
      );
    }
    await startFreshChat(page);
    await expect(page.locator('#chat-tools-btn')).toHaveClass(/\bactive\b/);
  }
}

interface STTStreamRecord {
  text: string;
  isFinal: boolean;
  renderedText?: string;
}

async function installSTTStreamRecorder(page: Page): Promise<void> {
  await page.evaluate(() => {
    interface STTStreamResult {
      text: string;
      isFinal: boolean;
    }
    type STTStream = (...args: unknown[]) => AsyncIterable<STTStreamResult>;
    const target = window as Window & {
      __RUNANYWHERE_SDK__?: { transcribeStream?: STTStream };
      __RA_RELEASE_STT_STREAM__?: STTStreamRecord[];
      __RA_RELEASE_STT_ORIGINAL__?: STTStream;
    };
    const sdk = target.__RUNANYWHERE_SDK__;
    if (!sdk?.transcribeStream) {
      throw new Error('RunAnywhere.transcribeStream is unavailable');
    }
    if (!target.__RA_RELEASE_STT_ORIGINAL__) {
      target.__RA_RELEASE_STT_ORIGINAL__ = sdk.transcribeStream;
    }
    const original = target.__RA_RELEASE_STT_ORIGINAL__;
    target.__RA_RELEASE_STT_STREAM__ = [];
    sdk.transcribeStream = (...args: unknown[]): AsyncIterable<STTStreamResult> => {
      const source = original.apply(sdk, args);
      return {
        async *[Symbol.asyncIterator](): AsyncGenerator<STTStreamResult> {
          for await (const partial of source) {
            const record: STTStreamRecord = {
              text: partial.text.trim(),
              isFinal: partial.isFinal === true,
            };
            target.__RA_RELEASE_STT_STREAM__?.push(record);
            yield partial;
            // `for await` resumes this wrapper only after the consumer has
            // rendered the yielded partial and requested the next item.
            record.renderedText = document
              .querySelector('#transcribe-output')
              ?.textContent
              ?.trim();
          }
        },
      };
    };
  });
}

async function resetSTTStreamRecorder(page: Page): Promise<void> {
  await page.evaluate(() => {
    const target = window as Window & { __RA_RELEASE_STT_STREAM__?: STTStreamRecord[] };
    target.__RA_RELEASE_STT_STREAM__ = [];
  });
}

async function recordedSTTStream(page: Page): Promise<STTStreamRecord[]> {
  return page.evaluate(() => (
    (window as Window & { __RA_RELEASE_STT_STREAM__?: STTStreamRecord[] })
      .__RA_RELEASE_STT_STREAM__ ?? []
  ));
}

async function expectRenderedSTTPartial(page: Page, expectedFinal: RegExp): Promise<void> {
  await expect.poll(async () => {
    const records = await recordedSTTStream(page);
    return records.some((record) => (
      !record.isFinal
      && record.text.length > 0
      && record.renderedText === record.text
    ));
  }, {
    message: 'live STT must emit and visibly render a non-final partial',
    timeout: 120_000,
    intervals: [100, 250, 500],
  }).toBe(true);
  await expectFinalSTTStream(page, expectedFinal);

  const records = await recordedSTTStream(page);
  const finalIndex = records.findIndex((record) => record.isFinal);
  const partialIndex = records.findIndex((record) => !record.isFinal && record.text.length > 0);
  expect(partialIndex).toBeGreaterThanOrEqual(0);
  expect(finalIndex).toBeGreaterThan(partialIndex);
}

async function expectFinalSTTStream(page: Page, expectedFinal: RegExp): Promise<void> {
  await expect.poll(async () => {
    const records = await recordedSTTStream(page);
    return records.some((record) => record.isFinal && expectedFinal.test(record.text));
  }, {
    message: 'live STT must terminate with the expected final transcript',
    timeout: 120_000,
    intervals: [100, 250, 500],
  }).toBe(true);
}

async function uninstallSTTStreamRecorder(page: Page): Promise<void> {
  await page.evaluate(() => {
    interface STTStreamResult {
      text: string;
      isFinal: boolean;
    }
    type STTStream = (...args: unknown[]) => AsyncIterable<STTStreamResult>;
    const target = window as Window & {
      __RUNANYWHERE_SDK__?: { transcribeStream?: STTStream };
      __RA_RELEASE_STT_STREAM__?: STTStreamRecord[];
      __RA_RELEASE_STT_ORIGINAL__?: STTStream;
    };
    if (target.__RUNANYWHERE_SDK__ && target.__RA_RELEASE_STT_ORIGINAL__) {
      target.__RUNANYWHERE_SDK__.transcribeStream = target.__RA_RELEASE_STT_ORIGINAL__;
    }
    delete target.__RA_RELEASE_STT_ORIGINAL__;
    delete target.__RA_RELEASE_STT_STREAM__;
  });
}

async function installVoiceStateRecorder(page: Page): Promise<void> {
  await page.evaluate(() => {
    const target = window as Window & {
      __RA_RELEASE_VOICE_STATES__?: string[];
      __RA_RELEASE_VOICE_OBSERVER__?: MutationObserver;
    };
    target.__RA_RELEASE_VOICE_OBSERVER__?.disconnect();
    target.__RA_RELEASE_VOICE_STATES__ = [];
    const host = document.querySelector('#tab-voice');
    const record = () => {
      const state = document.querySelector('#voice-state-pill')?.textContent?.trim();
      if (state && target.__RA_RELEASE_VOICE_STATES__?.at(-1) !== state) {
        target.__RA_RELEASE_VOICE_STATES__?.push(state);
      }
    };
    record();
    if (host) {
      target.__RA_RELEASE_VOICE_OBSERVER__ = new MutationObserver(record);
      target.__RA_RELEASE_VOICE_OBSERVER__.observe(host, {
        childList: true,
        subtree: true,
        characterData: true,
      });
    }
  });
}

async function recordedVoiceStates(page: Page): Promise<string[]> {
  return page.evaluate(() => (
    (window as Window & { __RA_RELEASE_VOICE_STATES__?: string[] })
      .__RA_RELEASE_VOICE_STATES__ ?? []
  ));
}

interface TTSPlaybackRecord {
  startedAt?: number;
  completedAt?: number;
  stopRequestedAt?: number;
  durationMs?: number;
}

async function expectNaturalPlaybackCompleted(
  page: Page,
  options: { minDurationMs: number },
): Promise<TTSPlaybackRecord> {
  await expect.poll(() => recordedTTSPlayback(page), {
    message: 'playback must emit started and completed lifecycle events',
    timeout: 8 * 60_000,
    intervals: [100, 250, 500, 1_000],
  }).toMatchObject({
    startedAt: expect.any(Number),
    completedAt: expect.any(Number),
    durationMs: expect.any(Number),
  });
  const playback = await recordedTTSPlayback(page);
  const durationMs = playback.durationMs ?? 0;
  const elapsedMs = (playback.completedAt ?? 0) - (playback.startedAt ?? 0);
  expect(durationMs).toBeGreaterThan(options.minDurationMs);
  expect(elapsedMs, 'playback must not complete substantially faster than natural audio time')
    .toBeGreaterThanOrEqual(durationMs * 0.8);
  expect(elapsedMs, 'playback must complete without a prolonged audio stall')
    .toBeLessThanOrEqual((durationMs * 1.5) + 2_000);
  return playback;
}

async function installTTSPlaybackRecorder(page: Page): Promise<void> {
  await page.evaluate(() => {
    interface PlaybackEvents {
      on: (
        name: 'playback.started' | 'playback.completed',
        listener: (event: { durationMs: number }) => void,
      ) => () => void;
    }
    const target = window as Window & {
      __RUNANYWHERE_SDK__?: { events?: PlaybackEvents };
      __RA_RELEASE_TTS_PLAYBACK__?: TTSPlaybackRecord;
      __RA_RELEASE_TTS_UNSUBS__?: Array<() => void>;
    };
    target.__RA_RELEASE_TTS_UNSUBS__?.forEach((unsubscribe) => unsubscribe());
    target.__RA_RELEASE_TTS_PLAYBACK__ = {};
    const events = target.__RUNANYWHERE_SDK__?.events;
    if (!events) throw new Error('RunAnywhere.events is unavailable');
    target.__RA_RELEASE_TTS_UNSUBS__ = [
      events.on('playback.started', (event) => {
        target.__RA_RELEASE_TTS_PLAYBACK__ = {
          ...target.__RA_RELEASE_TTS_PLAYBACK__,
          startedAt: Date.now(),
          durationMs: event.durationMs,
        };
      }),
      events.on('playback.completed', (event) => {
        target.__RA_RELEASE_TTS_PLAYBACK__ = {
          ...target.__RA_RELEASE_TTS_PLAYBACK__,
          completedAt: Date.now(),
          durationMs: event.durationMs,
        };
      }),
    ];
  });
}

async function recordedTTSPlayback(page: Page): Promise<TTSPlaybackRecord> {
  return page.evaluate(() => (
    (window as Window & { __RA_RELEASE_TTS_PLAYBACK__?: TTSPlaybackRecord })
      .__RA_RELEASE_TTS_PLAYBACK__ ?? {}
  ));
}

async function uninstallTTSPlaybackRecorder(page: Page): Promise<void> {
  await page.evaluate(() => {
    const target = window as Window & {
      __RA_RELEASE_TTS_UNSUBS__?: Array<() => void>;
      __RA_RELEASE_TTS_PLAYBACK__?: TTSPlaybackRecord;
    };
    target.__RA_RELEASE_TTS_UNSUBS__?.forEach((unsubscribe) => unsubscribe());
    delete target.__RA_RELEASE_TTS_UNSUBS__;
    delete target.__RA_RELEASE_TTS_PLAYBACK__;
  });
}
