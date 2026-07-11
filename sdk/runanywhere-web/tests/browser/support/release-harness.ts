import {
  expect,
  test as base,
  type BrowserContext,
  type Locator,
  type Page,
  type TestInfo,
} from '@playwright/test';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';

export const RELEASE_E2E_ENABLED = process.env.RA_RUN_FULL_E2E === '1';
const HAS_RUNTIME_CREDENTIALS = Boolean(
  process.env.RUNANYWHERE_API_KEY?.trim(),
);
const CONFIGURED_BASE_URL = process.env.RA_E2E_BASE_URL;
const TARGETS_REMOTE_ORIGIN = Boolean(
  CONFIGURED_BASE_URL
  && !/^https?:\/\/(?:localhost|127\.0\.0\.1|\[::1\])(?::|\/|$)/i.test(CONFIGURED_BASE_URL),
);
const RELEASE_TRACE_ENABLED = process.env.RA_E2E_TRACE === '1'
  && !HAS_RUNTIME_CREDENTIALS
  && !TARGETS_REMOTE_ORIGIN;

const REPO_ROOT = resolve(__dirname, '../../../../..');
export const AUDIO_FIXTURE = resolve(
  REPO_ROOT,
  'Playground/openclaw-hybrid-assistant/tests/audio/hey-jarvis-real.wav',
);
export const IMAGE_FIXTURE = resolve(
  REPO_ROOT,
  'examples/android/RunAnywhereAI/app/src/androidTest/assets/test.jpg',
);
export const RAG_FIXTURE = resolve(__dirname, '../fixtures/release-rag.txt');

export const RELEASE_MODELS = {
  llm: {
    id: 'smollm2-360m-q8_0',
    query: 'SmolLM2 360M',
  },
  thinkingLlm: {
    id: 'qwen3-0.6b-q4_k_m',
    query: 'Qwen3 0.6B',
  },
  stt: {
    id: 'sherpa-onnx-whisper-tiny.en',
    query: 'Whisper Tiny',
  },
  tts: {
    id: 'vits-piper-en_US-lessac-medium',
    query: 'Piper TTS',
  },
  alternateTts: {
    id: 'vits-piper-en_GB-alba-medium',
    query: 'British English',
  },
  vad: {
    id: 'silero-vad',
    query: 'Silero VAD',
  },
  vlm: {
    id: 'smolvlm2-256m-video-instruct-q8_0',
    query: 'SmolVLM2 256M',
  },
  embedding: {
    id: 'all-minilm-l6-v2',
    query: 'MiniLM L6',
  },
} as const;

type DiagnosticKind =
  | `console.${string}`
  | 'pageerror'
  | 'requestfailed'
  | 'http'
  | 'pagecrash';

export interface BrowserDiagnostic {
  at: string;
  kind: DiagnosticKind;
  message: string;
  method?: string;
  resourceType?: string;
  status?: number;
  url?: string;
  expected?: boolean;
}

interface ExpectedFailureScope {
  pattern: RegExp;
  matches: number;
}

const expectedFailureScopes = new WeakMap<Page, ExpectedFailureScope[]>();

interface BrowserSDKProbe {
  isInitialized?: boolean;
  getModel?: (modelId: string) => {
    category?: unknown;
    isDownloaded?: boolean;
    localPath?: string;
  } | null;
  downloadedModels?: () => {
    models?: Array<{ id?: string; category?: unknown; localPath?: string }>;
  } | null;
  listModels?: () => {
    models?: Array<{ id?: string; category?: unknown }>;
  } | null;
  currentModel?: (options: {
    category: unknown;
    includeModelMetadata: boolean;
  }) => { modelId?: string } | null;
}

interface ReleaseSession {
  context: BrowserContext;
  page: Page;
  events: BrowserDiagnostic[];
}

interface ReleaseTestFixtures {
  releaseArtifacts: void;
}

interface ReleaseWorkerFixtures {
  releaseSession: ReleaseSession;
  appPage: Page;
}

/**
 * The release suite deliberately shares this worker-scoped page/context.
 * Playwright's normal `page` fixture creates a new context for every test,
 * which would discard OPFS and force every modality to redownload its model.
 */
export const test = base.extend<ReleaseTestFixtures, ReleaseWorkerFixtures>({
  releaseSession: [async ({ browser }, use, workerInfo) => {
    const configuredBaseURL = workerInfo.project.use.baseURL;
    const baseURL = typeof configuredBaseURL === 'string'
      ? configuredBaseURL
      : 'http://localhost:5173';
    const context = await browser.newContext({
      baseURL,
      ignoreHTTPSErrors: /^https:\/\/localtest\.me(?::|\/|$)/i.test(baseURL),
      viewport: { width: 1440, height: 1000 },
      permissions: ['microphone', 'camera', 'clipboard-read', 'clipboard-write'],
      acceptDownloads: true,
      serviceWorkers: 'allow',
    });
    const page = await context.newPage();
    const events = observeBrowserDiagnostics(page);

    // The default Playwright trace option only instruments its built-in page
    // fixture. This context is custom, so trace it explicitly and create one
    // chunk per named release test in the automatic fixture below.
    if (RELEASE_TRACE_ENABLED) {
      await context.tracing.start({ screenshots: true, snapshots: true, sources: true });
    }
    try {
      await use({ context, page, events });
    } finally {
      if (RELEASE_TRACE_ENABLED) {
        await context.tracing.stop().catch(() => undefined);
      }
      let closeTimeout: ReturnType<typeof setTimeout> | undefined;
      try {
        await Promise.race([
          context.close().catch(() => undefined),
          new Promise<void>((resolveClose) => {
            closeTimeout = setTimeout(resolveClose, 30_000);
          }),
        ]);
      } finally {
        if (closeTimeout !== undefined) clearTimeout(closeTimeout);
      }
    }
  }, { scope: 'worker' }],

  appPage: [async ({ releaseSession }, use) => {
    await use(releaseSession.page);
  }, { scope: 'worker' }],

  releaseArtifacts: [async ({ releaseSession }, use, testInfo) => {
    const { context, page, events } = releaseSession;
    const eventOffset = events.length;
    let traceChunkStarted = false;

    if (RELEASE_TRACE_ENABLED) {
      try {
        await context.tracing.startChunk({ title: testInfo.titlePath.join(' > ') });
        traceChunkStarted = true;
      } catch {
        // A page crash still needs the diagnostics/screenshot attempt below.
      }
    }

    try {
      await use();
    } finally {
      // A credentialed Settings test clears its field in its own `finally`,
      // and this defense-in-depth scrub runs before any automatic screenshot.
      // Dispatch `change` so the app's session-only settings object is also
      // cleared; no password value is ever included in an artifact.
      await scrubPasswordInputs(page);
      const diagnostics = events.slice(eventOffset);
      const snapshot = await collectRuntimeSnapshot(page);
      await attachJSON(testInfo, 'browser-diagnostics', { diagnostics, snapshot });

      if (!page.isClosed()) {
        const screenshotPath = testInfo.outputPath('checkpoint.png');
        const captured = await page.screenshot({
          path: screenshotPath,
          fullPage: true,
          animations: 'disabled',
          caret: 'hide',
          timeout: 30_000,
        }).then(() => true).catch(() => false);
        if (captured) {
          await testInfo.attach('checkpoint', {
            path: screenshotPath,
            contentType: 'image/png',
          });
        }
      }

      if (traceChunkStarted) {
        const tracePath = testInfo.outputPath('trace.zip');
        const traced = await context.tracing.stopChunk({ path: tracePath })
          .then(() => true)
          .catch(() => false);
        if (traced) {
          await testInfo.attach('trace', {
            path: tracePath,
            contentType: 'application/zip',
          });
        }
      }

      const unexpected = diagnostics.filter(isUnexpectedFailure);
      expect.soft(
        unexpected,
        `Unexpected browser failures:\n${unexpected.map(formatDiagnostic).join('\n')}`,
      ).toEqual([]);
    }
  }, { auto: true }],
});

export { expect };

export function assertFixtureFiles(): void {
  for (const fixture of [AUDIO_FIXTURE, IMAGE_FIXTURE, RAG_FIXTURE]) {
    expect(existsSync(fixture), `release fixture must exist: ${fixture}`).toBe(true);
  }
}

export async function waitForInteractive(page: Page): Promise<void> {
  await page.waitForFunction(() => {
    const probe = (window as Window & {
      __RUNANYWHERE_AI_READY__?: { ready?: boolean; state?: string; backend?: string };
    }).__RUNANYWHERE_AI_READY__;
    return probe?.ready === true && probe.state === 'interactive';
  }, undefined, { timeout: 180_000 });

  const snapshot = await page.evaluate(() => {
    const target = window as Window & {
      __RUNANYWHERE_AI_READY__?: { ready?: boolean; state?: string; backend?: string; error?: string };
      __RUNANYWHERE_SDK__?: { isInitialized?: boolean };
    };
    return {
      readiness: target.__RUNANYWHERE_AI_READY__,
      sdkInitialized: target.__RUNANYWHERE_SDK__?.isInitialized === true,
      crossOriginIsolated: window.crossOriginIsolated,
    };
  });

  expect(snapshot.readiness?.state).toBe('interactive');
  expect(snapshot.readiness?.backend, snapshot.readiness?.error).toBe('registered');
  expect(snapshot.sdkInitialized).toBe(true);
  expect(snapshot.crossOriginIsolated).toBe(true);
  await expect(page.locator('html')).toHaveAttribute('data-runanywhere-ai-backend', 'registered');
}

export async function navigateTo(page: Page, tab: string): Promise<void> {
  await page.evaluate((target) => {
    window.dispatchEvent(new CustomEvent('runanywhere:navigate', {
      detail: { tab: target },
    }));
  }, tab);
  await expect(page.locator(`#tab-${tab}`)).toHaveClass(/\bactive\b/);
  await expect(page.locator(`#tab-${tab}`)).toBeVisible();
}

export async function ensureModelReady(
  page: Page,
  trigger: string | Locator,
  model: { id: string; query: string },
  options: { downloadTimeout?: number; loadTimeout?: number } = {},
): Promise<void> {
  const downloadTimeout = options.downloadTimeout ?? 30 * 60_000;
  const loadTimeout = options.loadTimeout ?? 12 * 60_000;
  const sheet = page.locator('.modal-sheet');

  if (await sheet.isVisible().catch(() => false)) {
    await page.locator('#model-sheet-close').click();
    await expect(sheet).toBeHidden();
  }

  const target = typeof trigger === 'string' ? page.locator(trigger) : trigger;
  await expect(target).toBeVisible();
  await target.click();
  await expect(sheet).toBeVisible();

  const search = page.locator('#model-sheet-search');
  await expect(search).toBeVisible();
  await search.fill(model.query);
  const row = page.locator(`#model-sheet-list [data-model-id="${model.id}"]`).first();
  await expect(row, `model picker row for ${model.id}`).toBeVisible();

  if (await isModelLoaded(page, model.id)) {
    const select = row.locator(`[data-action="select"][data-model-id="${model.id}"]`);
    if (await select.isVisible().catch(() => false)) {
      await select.click();
    } else {
      await page.locator('#model-sheet-close').click();
    }
    await expect(sheet).toBeHidden();
    return;
  }

  if (!(await isModelDownloaded(page, model.id))) {
    const download = row.locator(`[data-action="download"][data-model-id="${model.id}"]`);
    await expect(download, `download action for ${model.id}`).toBeVisible();
    await download.click();
    console.info(`[release-e2e] ${model.id}: download requested`);
    await waitForModelDownload(page, row, model.id, downloadTimeout);
  }

  if (!(await isModelLoaded(page, model.id))) {
    const load = row.locator(`[data-action="load"][data-model-id="${model.id}"]`);
    await expect(load, `load action for ${model.id}`).toBeVisible({ timeout: 60_000 });
    console.info(`[release-e2e] ${model.id}: load requested`);
    await load.click();
    const loadDeadline = Date.now() + loadTimeout;
    while (true) {
      // Read the picker atomically in-page. A successful load either renders
      // a loaded action or immediately selects the model and removes the
      // sheet; retaining a Locator rooted at the replaced row can otherwise
      // wait on a detached element for the full test timeout.
      const loadState = await page.evaluate((id) => {
        const picker = document.querySelector<HTMLElement>('.modal-sheet');
        if (!picker) return { completed: true, errorText: '' };
        const actions = Array.from(
          picker.querySelectorAll<HTMLElement>('[data-model-id][data-action]'),
        );
        const loaded = actions.some((action) => (
          action.dataset.modelId === id
          && (action.dataset.action === 'select' || action.dataset.action === 'unload')
        ));
        const modelRow = Array.from(
          picker.querySelectorAll<HTMLElement>('[data-model-id]'),
        ).find((candidate) => candidate.dataset.modelId === id);
        const errorText = modelRow?.querySelector<HTMLElement>('.model-row-error')
          ?.textContent?.trim() ?? '';
        return { completed: loaded, errorText };
      }, model.id);
      if (loadState.completed) break;
      if (loadState.errorText) {
        throw new Error(`${model.id} load failed in the model picker: ${loadState.errorText}`);
      }
      if (Date.now() >= loadDeadline) {
        throw new Error(`${model.id} did not reach the visible loaded state before timeout`);
      }
      await page.waitForTimeout(1_000);
    }
    const retainedByNative = await isModelLoaded(page, model.id);
    if (!retainedByNative) {
      throw new Error(
        `${model.id} reached the visible loaded state but native lifecycle did not retain it`,
      );
    }
    console.info(`[release-e2e] ${model.id}: loaded`);
  }

  if (await sheet.isVisible().catch(() => false)) {
    const select = row.locator(`[data-action="select"][data-model-id="${model.id}"]`);
    if (await select.isVisible().catch(() => false)) {
      await select.click();
    } else {
      await page.locator('#model-sheet-close').click();
    }
  }
  await expect(sheet).toBeHidden();
  expect(await isModelDownloaded(page, model.id)).toBe(true);
  expect(await isModelLoaded(page, model.id)).toBe(true);
}

async function waitForModelDownload(
  page: Page,
  row: Locator,
  modelId: string,
  timeout: number,
): Promise<void> {
  const deadline = Date.now() + timeout;
  const retryAction = row.locator(`[data-action="download"][data-model-id="${modelId}"]`);
  let retries = 0;
  let lastProgressBucket = -1;
  let lastStatus = 'download starting';

  while (Date.now() < deadline) {
    if (await isModelDownloaded(page, modelId)) {
      console.info(`[release-e2e] ${modelId}: download persisted to OPFS`);
      return;
    }

    const snapshot = await row.evaluate((element) => {
      const progress = element.querySelector<HTMLElement>('.progress-fill')?.style.width ?? '';
      return {
        progress,
        text: (element.textContent ?? '').replace(/\s+/g, ' ').trim(),
      };
    }).catch(() => ({ progress: '', text: 'model row unavailable' }));
    lastStatus = snapshot.text;
    const progress = Number.parseFloat(snapshot.progress);
    if (Number.isFinite(progress)) {
      const bucket = Math.floor(progress / 10) * 10;
      if (bucket > lastProgressBucket) {
        lastProgressBucket = bucket;
        console.info(`[release-e2e] ${modelId}: download ${bucket}%`);
      }
    }

    const retryVisible = await retryAction.isVisible().catch(() => false);
    const retryLabel = retryVisible ? (await retryAction.textContent() ?? '').trim() : '';
    if (/^retry$/i.test(retryLabel)) {
      retries += 1;
      if (retries > 3) {
        throw new Error(`${modelId} download failed after 3 visible Retry attempts: ${lastStatus}`);
      }
      console.info(`[release-e2e] ${modelId}: activating visible Retry (${retries}/3)`);
      await retryAction.click();
    }

    await page.waitForTimeout(1_000);
  }

  throw new Error(`${modelId} did not persist to OPFS before timeout: ${lastStatus}`);
}

export async function isModelDownloaded(page: Page, modelId: string): Promise<boolean> {
  return page.evaluate((id) => {
    const sdk = (window as Window & { __RUNANYWHERE_SDK__?: BrowserSDKProbe })
      .__RUNANYWHERE_SDK__;
    if (!sdk) return false;
    try {
      const model = sdk.getModel?.(id);
      if (model?.isDownloaded && model?.localPath) return true;
      const downloaded = sdk.downloadedModels?.();
      return Boolean(downloaded?.models?.some((entry: { id?: string; localPath?: string }) => (
        entry.id === id && Boolean(entry.localPath)
      )));
    } catch {
      return false;
    }
  }, modelId);
}

export async function isModelLoaded(page: Page, modelId: string): Promise<boolean> {
  return page.evaluate((id) => {
    const sdk = (window as Window & { __RUNANYWHERE_SDK__?: BrowserSDKProbe })
      .__RUNANYWHERE_SDK__;
    if (!sdk) return false;
    try {
      const model = sdk.getModel?.(id);
      if (model?.category == null) return false;
      const current = sdk.currentModel?.({
        category: model.category,
        includeModelMetadata: false,
      });
      return current?.modelId === id;
    } catch {
      return false;
    }
  }, modelId);
}

export async function expectSubstantiveText(
  locator: Locator,
  options: { minLength?: number; timeout?: number; forbidden?: RegExp } = {},
): Promise<string> {
  const minLength = options.minLength ?? 12;
  const timeout = options.timeout ?? 10 * 60_000;
  const forbidden = options.forbidden
    ?? /\((?:no response|no transcript|waiting for speech)[^)]*\)|\b(?:failed|error|unavailable)\b/i;
  const pending = /\((?:no response|no transcript|waiting for speech)[^)]*\)|^\s*(?:Thinking)?(?:…|\.\.\.)\s*$/i;
  let substantiveText = '';

  await expect.poll(async () => {
    const text = (await locator.textContent() ?? '').trim();
    pending.lastIndex = 0;
    if (pending.test(text)) return false;
    forbidden.lastIndex = 0;
    if (forbidden.test(text)) {
      throw new Error(`Terminal output from ${locator}: ${text}`);
    }
    if (text.length < minLength) return false;
    substantiveText = text;
    return true;
  }, {
    message: `expected substantive output from ${locator}`,
    timeout,
    intervals: [500, 1_000, 2_000, 5_000],
  }).toBe(true);

  return substantiveText;
}

/**
 * Capture a deliberately induced request failure without weakening the
 * release gate for that URL afterward. The failure still appears in the JSON
 * diagnostics with `expected: true`, and the callback must make a substantive
 * UI assertion (for example, the model row changing to Retry).
 */
export async function withExpectedNetworkFailure<T>(
  page: Page,
  pattern: RegExp,
  action: () => Promise<T>,
): Promise<T> {
  const scope: ExpectedFailureScope = { pattern, matches: 0 };
  const scopes = expectedFailureScopes.get(page) ?? [];
  scopes.push(scope);
  expectedFailureScopes.set(page, scopes);
  try {
    const result = await action();
    expect(scope.matches, `expected an induced network failure matching ${pattern}`).toBeGreaterThan(0);
    return result;
  } finally {
    const active = expectedFailureScopes.get(page) ?? [];
    const index = active.indexOf(scope);
    if (index >= 0) active.splice(index, 1);
  }
}

function attachFailureListeners(page: Page, events: BrowserDiagnostic[]): void {
  page.on('console', (message) => {
    const location = message.location();
    const event: BrowserDiagnostic = {
      at: new Date().toISOString(),
      kind: `console.${message.type()}`,
      message: redact(message.text()),
      ...(location.url ? { url: safeURL(location.url) } : {}),
    };
    markExpectedFailure(page, event);
    events.push(event);
    if (process.env.RA_E2E_BROWSER_LOGS === '1') {
      console.info(`[browser:${message.type()}] ${event.message}`);
    }
  });
  page.on('pageerror', (error) => {
    events.push({
      at: new Date().toISOString(),
      kind: 'pageerror',
      message: redact(error.stack || error.message),
    });
  });
  page.on('requestfailed', (request) => {
    const event: BrowserDiagnostic = {
      at: new Date().toISOString(),
      kind: 'requestfailed',
      message: redact(request.failure()?.errorText || 'request failed'),
      method: request.method(),
      resourceType: request.resourceType(),
      url: safeURL(request.url()),
    };
    markExpectedFailure(page, event);
    events.push(event);
  });
  page.on('response', (response) => {
    if (response.status() < 400) return;
    const request = response.request();
    const event: BrowserDiagnostic = {
      at: new Date().toISOString(),
      kind: 'http',
      message: `${response.status()} ${response.statusText()}`.trim(),
      method: request.method(),
      resourceType: request.resourceType(),
      status: response.status(),
      url: safeURL(response.url()),
    };
    markExpectedFailure(page, event);
    events.push(event);
  });
  page.on('crash', () => {
    events.push({
      at: new Date().toISOString(),
      kind: 'pagecrash',
      message: 'Chromium page crashed',
    });
  });
}

async function collectRuntimeSnapshot(page: Page): Promise<Record<string, unknown>> {
  if (page.isClosed()) return { pageClosed: true };
  return page.evaluate(() => {
    const target = window as Window & {
      __RUNANYWHERE_AI_READY__?: unknown;
      __RUNANYWHERE_SDK__?: BrowserSDKProbe;
    };
    const sdk = target.__RUNANYWHERE_SDK__;
    let downloadedModels: Array<{ id?: string; localPath?: string }> = [];
    let currentModels: Array<{ category: unknown; modelId?: string }> = [];
    try {
      downloadedModels = (sdk?.downloadedModels?.()?.models ?? []).map(
        (model: { id?: string; localPath?: string }) => ({
          id: model.id,
          localPath: model.localPath,
        }),
      );
    } catch {
      // Keep the evidence snapshot available even if the registry probe fails.
    }
    try {
      const categories = new Set(
        (sdk?.listModels?.()?.models ?? [])
          .map((model) => model.category)
          .filter((category) => category != null),
      );
      currentModels = Array.from(categories).map((category) => ({
        category,
        modelId: sdk?.currentModel?.({
          category,
          includeModelMetadata: false,
        })?.modelId,
      })).filter((model) => Boolean(model.modelId));
    } catch {
      // Component snapshots are supporting evidence, not a reason to hide the
      // primary diagnostics when one category probe is unavailable.
    }
    return {
      url: window.location.href.split('?')[0],
      readiness: target.__RUNANYWHERE_AI_READY__,
      sdkInitialized: sdk?.isInitialized === true,
      crossOriginIsolated: window.crossOriginIsolated,
      activePanel: document.querySelector('.tab-panel.active')?.id ?? null,
      theme: document.documentElement.dataset.theme ?? null,
      localStorageKeys: Object.keys(localStorage),
      downloadedModels,
      currentModels,
    };
  }).catch((error) => ({ snapshotError: redact(String(error)) }));
}

async function attachJSON(testInfo: TestInfo, name: string, value: unknown): Promise<void> {
  await testInfo.attach(name, {
    body: redact(JSON.stringify(value, null, 2)),
    contentType: 'application/json',
  });
}

function isUnexpectedFailure(event: BrowserDiagnostic): boolean {
  if (event.expected) return false;
  if (isAllowlisted(event)) return false;
  const fatalWarning = event.kind === 'console.warning' && (
    /Panel .* on(?:Activate|Deactivate) error/i.test(event.message)
    || /WebGPU .*?(?:failed|retrying|CPU WASM artifact)/i.test(event.message)
    || /(?:audio )?playback failed|voice turn failed|pipeline recommendation failed/i.test(event.message)
    || /backend failed to register|teardown failed/i.test(event.message)
    || /model-ready callback threw|listener threw|capability probe failed/i.test(event.message)
  );
  return fatalWarning
    || event.kind === 'pageerror'
    || event.kind === 'pagecrash'
    || event.kind === 'requestfailed'
    || event.kind === 'http'
    || event.kind === 'console.error';
}

function markExpectedFailure(page: Page, event: BrowserDiagnostic): void {
  const scopes = expectedFailureScopes.get(page) ?? [];
  for (const scope of scopes) {
    scope.pattern.lastIndex = 0;
    const haystack = `${event.url ?? ''}\n${event.message}`;
    const resourceMatches = scope.pattern.test(haystack);
    if (resourceMatches) {
      event.expected = true;
      scope.matches += 1;
      return;
    }
  }
}

/** Attach credential-safe diagnostics to an additional page (for CPU fallback). */
export function observeBrowserDiagnostics(page: Page): BrowserDiagnostic[] {
  const events: BrowserDiagnostic[] = [];
  attachFailureListeners(page, events);
  return events;
}

export function unexpectedBrowserDiagnostics(
  events: readonly BrowserDiagnostic[],
): BrowserDiagnostic[] {
  return events.filter(isUnexpectedFailure);
}

async function scrubPasswordInputs(page: Page): Promise<void> {
  if (page.isClosed()) return;
  await page.locator('input[type="password"]').evaluateAll((inputs) => {
    for (const input of inputs) {
      if (!(input instanceof HTMLInputElement) || input.value.length === 0) continue;
      input.value = '';
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.dispatchEvent(new Event('change', { bubbles: true }));
    }
  }).catch(() => undefined);
}

function isAllowlisted(event: BrowserDiagnostic): boolean {
  if (/\bNO_COLOR\b/i.test(event.message)) return true;
  if (/model assignment base URL is not configured/i.test(event.message)) return true;
  if (
    event.kind === 'http'
    && event.status === 404
    && /\/(?:favicon\.ico|\.well-known\/appspecific\/com\.chrome\.devtools\.json)$/i.test(event.url ?? '')
  ) {
    return true;
  }
  return false;
}

function formatDiagnostic(event: BrowserDiagnostic): string {
  const request = event.method ? ` ${event.method}` : '';
  const target = event.url ? ` ${event.url}` : '';
  return `[${event.kind}]${request}${target}: ${event.message}`;
}

function safeURL(raw: string): string {
  try {
    const url = new URL(raw);
    url.username = '';
    url.password = '';
    url.search = '';
    url.hash = '';
    return url.toString();
  } catch {
    return raw.split(/[?#]/, 1)[0];
  }
}

function redact(value: string): string {
  let redacted = value
    .replace(/\bBearer\s+[^\s"']+/gi, 'Bearer [REDACTED]')
    .replace(/\bsk-[A-Za-z0-9_-]{8,}\b/g, '[REDACTED-KEY]')
    .replace(/((?:api[-_ ]?key|authorization)["']?\s*[:=]\s*["']?)[^\s,"'}]+/gi, '$1[REDACTED]');
  const processKey = process.env.RUNANYWHERE_API_KEY?.trim();
  if (processKey) redacted = redacted.split(processKey).join('[REDACTED-KEY]');
  return redacted;
}
