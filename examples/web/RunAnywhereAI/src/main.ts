/**
 * RunAnywhere AI - Web Demo Application
 *
 * Full-featured demo matching the iOS example app.
 * Twelve-panel navigation: Chat, Advanced, Storage, Settings, Voice, Vision,
 * Documents, Transcribe, Speak, VAD, Solutions, and Benchmarks.
 */

import './styles/design-system.css';
import './styles/commons.css';
import './styles/components.css';
import { buildAppShell, getActiveTabId, isChatRouteActive } from './app';
import { RunAnywhere, type Environment } from '@runanywhere/web';
import { registerAll as registerModelCatalogAll } from './services/model-catalog';
import {
  notifyCatalogRegistered,
  resetCatalogRegistrationState,
} from './components/model-selection';
import {
  getHostedAPIConfiguration,
  setAPIConfigurationApplyHandler,
  type APIConfiguration,
  type APIConfigurationApplyResult,
} from './views/settings';
import { formatError } from './services/format-error';
import { appLogger } from './services/app-logger';
import {
  engineFailures,
  failureDiagnostics,
  reportEngineRegistration,
  resetEngineAvailability,
  setEngineRetryHandler,
} from './services/engine-availability';
import { escapeHtml } from './services/escape-html';
import { icon, type IconName } from './components/icons';

type AppReadinessState = 'booting' | 'initializing-sdk' | 'building-shell' | 'interactive' | 'error';
type SDKReadinessState = 'initializing' | 'ready' | 'unavailable';
type BackendReadinessState = 'pending' | 'registered' | 'unavailable';
type IdentityReadinessState = 'not-required' | 'pending' | 'ready' | 'unavailable';
type AppReadinessStep =
  | 'booting'
  | 'initializing-sdk'
  | 'registering-llamacpp'
  | 'registering-onnx'
  | 'catalog'
  | 'building-shell'
  | 'interactive'
  | 'error';

interface AppShellProbe {
  shellReady: boolean;
  modelUiReady: boolean;
  modelUiTarget: 'get-started' | 'toolbar' | null;
  activeTab: string | null;
  reason: string;
}

interface AppReadinessSnapshot extends AppShellProbe {
  ready: boolean;
  state: AppReadinessState;
  sdk: SDKReadinessState;
  backend: BackendReadinessState;
  identity: IdentityReadinessState;
  identityError?: string;
  step: AppReadinessStep;
  backendError?: string;
  updatedAt: number;
  error?: string;
}

declare global {
  interface Window {
    __RUNANYWHERE_AI_READY__?: AppReadinessSnapshot;
    // Exposed for browser-harness tests (Playwright E2E). Safe to probe
    // from outside the example because it only exposes the singleton
    // public API surface — not any internal state. Not used by the app.
    __RUNANYWHERE_SDK__?: typeof RunAnywhere;
  }
}

// Expose the SDK singleton for E2E tests. This is a reference to the
// already-imported module; no additional code is pulled in.
window.__RUNANYWHERE_SDK__ = RunAnywhere;

let sdkReadinessState: SDKReadinessState = 'initializing';
let sdkInitializationError: string | undefined;
let backendReadinessState: BackendReadinessState = 'pending';
let backendRegistrationError: string | undefined;
let identityReadinessState: IdentityReadinessState = 'not-required';
let identityInitializationError: string | undefined;
let appReadinessState: AppReadinessState = 'booting';
let readinessStep: AppReadinessStep = 'booting';

interface RuntimeConfiguration {
  environment: Environment;
  apiKey?: string;
  /** Spelled to match `SDKInitOptions.baseURL`; this object is passed to `initialize()` as-is. */
  baseURL?: string;
}

let activeRuntimeConfiguration: RuntimeConfiguration | null = null;
let runtimeReconfigurationPromise: Promise<APIConfigurationApplyResult> | null = null;

setAPIConfigurationApplyHandler(applyAPIConfiguration);
setEngineRetryHandler(retryEngineRegistration);

function publishReadiness(state: AppReadinessState, error?: string): AppReadinessSnapshot {
  appReadinessState = state;
  const probe = probeAppShell();
  // Inference readiness is independent of app-shell readiness: when the
  // backend WASM is missing or fails to register, the model selector is
  // intentionally disabled (catalogRegistered=false), but the rest of the
  // demo (Voice/Documents/Settings tabs plus explicit unavailable states)
  // is still navigable. Treating that as "not interactive" would convert
  // the documented degraded mode into a fatal initialization error view.
  //
  // A surface other than the assistant is the third case: the model selector is
  // not part of that screen at all, so its absence there says nothing about
  // readiness. `probeAppShell` already reports `interactive` for those routes.
  const backendDegraded = backendReadinessState === 'unavailable';
  const ready = state === 'interactive'
    && probe.shellReady
    && (probe.modelUiReady || backendDegraded || probe.reason === 'interactive');
  const snapshot: AppReadinessSnapshot = {
    ...probe,
    ready,
    state,
    sdk: sdkReadinessState,
    backend: backendReadinessState,
    backendError: backendRegistrationError,
    identity: identityReadinessState,
    identityError: identityInitializationError,
    step: readinessStep,
    updatedAt: Date.now(),
    error: error ?? sdkInitializationError,
  };

  window.__RUNANYWHERE_AI_READY__ = snapshot;

  const root = document.documentElement;
  root.dataset.runanywhereAiReady = ready ? 'true' : 'false';
  root.dataset.runanywhereAiState = state;
  root.dataset.runanywhereAiSdk = sdkReadinessState;
  root.dataset.runanywhereAiBackend = backendReadinessState;
  root.dataset.runanywhereAiIdentity = identityReadinessState;
  root.dataset.runanywhereAiStep = readinessStep;
  root.dataset.runanywhereAiShellReady = probe.shellReady ? 'true' : 'false';
  root.dataset.runanywhereAiModelUiReady = probe.modelUiReady ? 'true' : 'false';
  root.dataset.runanywhereAiModelUiTarget = probe.modelUiTarget ?? '';
  root.dataset.runanywhereAiActiveTab = probe.activeTab ?? '';
  root.dataset.runanywhereAiReason = probe.reason;
  if (snapshot.error) {
    root.dataset.runanywhereAiError = snapshot.error;
  } else {
    delete root.dataset.runanywhereAiError;
  }
  if (backendRegistrationError) {
    root.dataset.runanywhereAiBackendError = backendRegistrationError;
  } else {
    delete root.dataset.runanywhereAiBackendError;
  }
  if (identityInitializationError) {
    root.dataset.runanywhereAiIdentityError = identityInitializationError;
  } else {
    delete root.dataset.runanywhereAiIdentityError;
  }

  const app = document.getElementById('app');
  if (app) {
    app.dataset.runanywhereAiReady = ready ? 'true' : 'false';
    app.dataset.runanywhereAiState = state;
  }

  window.dispatchEvent(new CustomEvent('runanywhere-ai-readinesschange', { detail: snapshot }));
  return snapshot;
}

function publishReadinessStep(step: AppReadinessStep): void {
  readinessStep = step;
  updateLoadingStatus(step);
  publishReadiness(appReadinessState);
}

/**
 * Consumer-facing wording for each boot step.
 *
 * The status line used to print the internal slug — "Step: registering
 * llamacpp..." — which is the engine package's name, not language a user of a
 * consumer app has any way to interpret. The step values themselves stay
 * internal identifiers; this is the one place they become English.
 */
const LOADING_STATUS_TEXT: Record<AppReadinessStep, string> = {
  booting: 'Loading the SDK…',
  'initializing-sdk': 'Starting the on-device runtime…',
  'registering-llamacpp': 'Preparing text generation…',
  'registering-onnx': 'Preparing speech…',
  catalog: 'Checking available models…',
  'building-shell': 'Almost ready…',
  interactive: 'Ready.',
  error: 'Something went wrong.',
};

function updateLoadingStatus(step: AppReadinessStep): void {
  const status = document.getElementById('loading-status');
  if (status) status.textContent = LOADING_STATUS_TEXT[step];
}

async function withTimeout<T>(step: string, timeoutMs: number, operation: Promise<T>): Promise<T> {
  let timeoutId: number | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timeoutId = window.setTimeout(() => {
      reject(new Error(`Timed out after ${Math.round(timeoutMs / 1000)}s while ${step}. Check network, WASM assets, and browser diagnostics.`));
    }, timeoutMs);
  });
  try {
    return await Promise.race([operation, timeout]);
  } finally {
    if (timeoutId !== undefined) window.clearTimeout(timeoutId);
  }
}

function probeAppShell(): AppShellProbe {
  const app = document.getElementById('app');
  const tabContent = app?.querySelector('.tab-content') ?? null;
  const tabBar = app?.querySelector('.tab-bar') ?? null;
  const activePanel = app?.querySelector<HTMLElement>('.tab-panel.active') ?? null;
  const chatPanel = document.getElementById('tab-chat');
  // The shell now restores the tab named by the URL, so the assistant is the
  // panel that *should* be showing only when the URL says so. Deep-linking to
  // `#/benchmarks` must not read as "the chat tab failed to activate" and tip
  // `waitForInteractiveShell` into the fatal initialization error view. Loading
  // the app with no fragment still routes to chat, so the default path — and
  // every probe the browser suite makes — is unchanged.
  const onChatRoute = app !== null && isChatRouteActive();
  const modelTrigger = document.getElementById('chat-toolbar-model') as HTMLElement | null;
  const modelTriggerText = document.getElementById('chat-toolbar-model-text')?.textContent?.trim() ?? '';
  const modelOverlay = document.getElementById('chat-model-overlay') as HTMLElement | null;
  const getStartedTrigger = document.getElementById('chat-get-started-btn') as HTMLButtonElement | null;
  const loadingScreen = document.getElementById('loading-screen');
  const loadingHidden = !loadingScreen || loadingScreen.classList.contains('hidden');
  const modelOverlayVisible = Boolean(modelOverlay && isElementActionable(modelOverlay));
  const getStartedReady = Boolean(
    modelOverlayVisible
      && getStartedTrigger
      && isElementActionable(getStartedTrigger)
      && !getStartedTrigger.disabled
      && getStartedTrigger.textContent?.trim(),
  );
  const toolbarReady = Boolean(
    !modelOverlayVisible
      && modelTrigger
      && isElementActionable(modelTrigger)
      && modelTriggerText.length > 0,
  );
  const modelUiTarget = getStartedReady ? 'get-started' : toolbarReady ? 'toolbar' : null;

  const shellReady = Boolean(
    app
      && tabContent
      && tabBar
      && activePanel
      && chatPanel
      // On the chat route the active panel has to *be* the chat panel; on any
      // other route it has to be the panel that route names, which is exactly
      // what `.tab-panel.active` already is.
      && (!onChatRoute || activePanel === chatPanel)
      && loadingHidden,
  );
  const modelUiReady = Boolean(
    shellReady
      && modelUiTarget,
  );
  const routedTab = getActiveTabId();

  if (!app) return { shellReady, modelUiReady, modelUiTarget, activeTab: null, reason: 'missing-app-root' };
  if (!tabContent || !tabBar) return { shellReady, modelUiReady, modelUiTarget, activeTab: null, reason: 'missing-tab-shell' };
  if (!activePanel) return { shellReady, modelUiReady, modelUiTarget, activeTab: null, reason: 'missing-active-tab' };
  if (onChatRoute && activePanel !== chatPanel) {
    return {
      shellReady,
      modelUiReady,
      modelUiTarget,
      activeTab: (activePanel.dataset.tab ?? activePanel.id) || null,
      reason: 'chat-tab-not-active',
    };
  }
  if (!loadingHidden) return { shellReady, modelUiReady, modelUiTarget, activeTab: routedTab, reason: 'loading-screen-visible' };
  // The model selector lives on the assistant. A deep link to another surface is
  // interactive without it, and claiming otherwise would be the probe lying.
  if (!onChatRoute) {
    return { shellReady, modelUiReady, modelUiTarget, activeTab: routedTab, reason: 'interactive' };
  }
  if (!modelTrigger && !getStartedTrigger) {
    return { shellReady, modelUiReady, modelUiTarget, activeTab: 'chat', reason: 'missing-model-selector' };
  }
  if (!modelUiTarget) {
    return { shellReady, modelUiReady, modelUiTarget, activeTab: 'chat', reason: 'model-selector-not-actionable' };
  }

  return { shellReady, modelUiReady, modelUiTarget, activeTab: 'chat', reason: 'interactive' };
}

function isElementActionable(element: HTMLElement): boolean {
  if (!element.isConnected) return false;

  const rect = element.getBoundingClientRect();
  const style = window.getComputedStyle(element);
  return rect.width > 0
    && rect.height > 0
    && style.display !== 'none'
    && style.visibility !== 'hidden'
    && style.pointerEvents !== 'none';
}

async function waitForInteractiveShell(): Promise<AppReadinessSnapshot> {
  await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
  readinessStep = 'interactive';
  const snapshot = publishReadiness('interactive');
  if (!snapshot.ready) {
    // The shell never reached interactive readiness AND the backend isn't
    // explicitly degraded — that's a real failure, not a missing-WASM
    // fallback path. Still report which probe field tripped so the error
    // view tells the user what to look at.
    throw new Error(`App shell did not reach interactive readiness: ${snapshot.reason}`);
  }
  return snapshot;
}

// ---------------------------------------------------------------------------
// Cross-Origin Isolation (enables SharedArrayBuffer on Safari/iOS)
// ---------------------------------------------------------------------------

/**
 * Registers a service worker that injects COOP/COEP headers for browsers
 * that don't support `credentialless` COEP (Safari/WebKit).
 *
 * - On Chrome/Firefox: `crossOriginIsolated` is already true via Vite or the
 *   static host's response headers, so this is a no-op.
 * - On Safari/iOS: `crossOriginIsolated` is false, so the SW installs
 *   and the page reloads once to activate it.
 */
async function ensureCrossOriginIsolation(): Promise<void> {
  if (crossOriginIsolated) {
    appLogger.info('[COI] Already cross-origin isolated');
    return;
  }

  if (!('serviceWorker' in navigator)) {
    appLogger.warning('[COI] Service workers not supported — SharedArrayBuffer may be unavailable');
    return;
  }

  const registration = await navigator.serviceWorker.register('/coi-serviceworker.js');

  // If the SW is already active and controlling this page, COI should be
  // enabled. If we're still not isolated, something else is wrong.
  if (navigator.serviceWorker.controller) {
    appLogger.warning('[COI] Service worker active but page is not cross-origin isolated');
    return;
  }

  // Wait for the newly installed SW to activate, then reload so its
  // fetch handler can inject the required headers.
  const sw = registration.installing || registration.waiting;
  if (sw) {
    await new Promise<void>((resolve) => {
      sw.addEventListener('statechange', () => {
        if (sw.state === 'activated') resolve();
      });
      // If it's already activated by the time we check
      if (sw.state === 'activated') resolve();
    });
    appLogger.info('[COI] Service worker activated — reloading for cross-origin isolation');
    window.location.reload();
    // Halt execution — the reload will re-enter main()
    await new Promise(() => {});
  }
}

// ---------------------------------------------------------------------------
// Initialization Flow (matches iOS RunAnywhereAIApp.swift)
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  readinessStep = 'booting';
  publishReadiness('booting');

  // The boot screen is already on screen — index.html ships it as static markup
  // so it paints with the document. This only matters on the retry path, where
  // the previous attempt removed it. It must come *before* the awaited step
  // below, or a retry shows a blank page for the duration of that step.
  showLoadingScreen();

  // Step 0: Ensure cross-origin isolation for SharedArrayBuffer (Safari/iOS)
  await withTimeout('setting up cross-origin isolation', 60_000, ensureCrossOriginIsolation());

  publishReadinessStep('initializing-sdk');
  publishReadiness('initializing-sdk');

  try {
    // Step 1: Initialize the SDK (load WASM, register backends)
    await initializeSDK();

    // Step 2: Hide loading screen and show the app
    hideLoadingScreen();
    publishReadinessStep('building-shell');
    publishReadiness('building-shell');
    buildAppShell();
    await waitForInteractiveShell();
  } catch (error) {
    // Show error view with retry
    const message = formatError(error);
    readinessStep = 'error';
    showErrorView(message);
    publishReadiness('error', message);
  }
}

// ---------------------------------------------------------------------------
// SDK Initialization
// ---------------------------------------------------------------------------

async function initializeSDK(): Promise<void> {
  // V2 Architecture: core (`@runanywhere/web`) owns the backend-neutral
  // TypeScript facade plus the commons-only `racommons.wasm`. Backend packages
  // register independently and load their own self-contained inference WASM;
  // until one registers a capability, that inference verb reports unavailable.
  //
  // Mirrors iOS `initializeSDK()` (RunAnywhereAIApp.swift:84-109):
  // initialize → register backends → ModelCatalogBootstrap.registerAll() →
  // refreshSDKCatalogs(). `RunAnywhere.initialize()` is fail-closed — a core
  // WASM load failure throws and `main()` shows the error view with retry
  // (iOS parity: RunAnywhereAIApp.swift:105-108 InitializationErrorView).
  // Note: iOS registers backends BEFORE initialize() to dodge a Swift
  // concurrency suspension race; on Web the backend packages install onto
  // core adapters, so the SDK-documented order is initialize() first.
  try {
    const hostedConfiguration = getHostedAPIConfiguration();
    const configuration: RuntimeConfiguration = hostedConfiguration
      ? {
          apiKey: hostedConfiguration.apiKey,
          // Mapped field-by-field rather than spread, because the spread's
          // excess properties are invisible to the type checker: the name has
          // to match `SDKInitOptions.baseURL` exactly or the URL is dropped at
          // runtime while both sides still compile, and production init fails
          // with "URL required".
          baseURL: hostedConfiguration.baseURL,
          environment: 'production',
        }
      : { environment: 'development' };
    await startRuntime(configuration, hostedConfiguration !== null);
    activeRuntimeConfiguration = configuration;
    sdkReadinessState = 'ready';
    sdkInitializationError = undefined;
  } catch (err) {
    // Fail closed — iOS parity: RunAnywhereAIApp.swift:105-108. main()'s
    // catch shows the error view with a Retry button.
    sdkReadinessState = 'unavailable';
    sdkInitializationError = formatError(err);
    throw err;
  }
}

/**
 * Initialize core, register both independent WASM backends, then seed and
 * hydrate the model catalog. Settings reuses this exact boot path so applying
 * credentials cannot leave a partially configured runtime hidden behind a
 * success message.
 */
async function startRuntime(
  configuration: RuntimeConfiguration,
  requireAllBackends: boolean,
): Promise<void> {
  publishReadinessStep('initializing-sdk');
  await withTimeout('initializing the SDK', 60_000, RunAnywhere.initialize(configuration));

  const localRestored = await withTimeout(
    'restoring local storage',
    60_000,
    RunAnywhere.storage.restore(),
  );
  if (localRestored) {
    appLogger.info('[RunAnywhere] Local storage restored:', RunAnywhere.storage.directoryName);
  }

  let activeAcceleration: 'cpu' | 'webgpu' = 'cpu';
  const backendErrors: string[] = [];

  try {
    publishReadinessStep('registering-llamacpp');
    const { LlamaCPP } = await import('@runanywhere/web-llamacpp');
    await withTimeout(
      'registering the llama.cpp backend',
      120_000,
      LlamaCPP.register({
        acceleration: 'auto',
        requireBackendWorker: true,
        preferBackendWorker: true,
      }),
    );
    // Prefer SDK runtime.active (worker WebGPU when available) over the
    // main-thread bridge mode, which may stay on CPU while the worker owns GPU.
    activeAcceleration =
      RunAnywhere.runtime.active === 'webgpu' || RunAnywhere.runtime.active === 'cpu'
        ? RunAnywhere.runtime.active
        : LlamaCPP.accelerationMode;
    appLogger.info('[RunAnywhere] llamacpp backend registered:', activeAcceleration);
    reportEngineRegistration('llamacpp', { ok: true });
  } catch (err) {
    const message = formatError(err);
    backendErrors.push(`llamacpp: ${message}`);
    // Pass the formatted string, not the Error: `appLogger` deliberately
    // reduces an Error to `{ errorType }` so a message carrying a signed URL
    // can never reach the console. A string routes through
    // `sanitizeDiagnosticText` instead, which redacts credentials and keeps the
    // actionable part ("which artifact failed to load").
    appLogger.warning(
      '[RunAnywhere] llamacpp backend failed to register; chat will show feature-unavailable:',
      message,
    );
    // Tell the UI which engine died, so the picker can disable exactly the rows
    // that need it instead of offering downloads that cannot load.
    reportEngineRegistration('llamacpp', { ok: false, error: message });
  }

  try {
    publishReadinessStep('registering-onnx');
    const { ONNX } = await import('@runanywhere/web-onnx');
    await withTimeout(
      'registering the ONNX/Sherpa backend',
      120_000,
      // WebGPU-first for speech when browser + ORT EP probe succeed; else CPU.
      ONNX.register({
        acceleration: 'auto',
        threads: 2,
        requireBackendWorker: true,
        preferBackendWorker: true,
      }),
    );
    const speech = RunAnywhere.runtime.speech;
    appLogger.info(
      '[RunAnywhere] onnx/sherpa backend registered:',
      `accel=${ONNX.accelerationMode}`,
      `threads=${ONNX.threads}`,
      `speechContext=${speech.executionContext}`,
      ONNX.accelerationMode === 'webgpu'
        ? '(ORT WebGPU EP active)'
        : `(CPU — ${ONNX.lastFallbackReason ?? 'WebGPU unavailable or ORT EP probe failed'}; embeddings share this path)`,
    );
    // Expose for browser diagnostics (accel badge / CDP).
    (globalThis as { __RUNANYWHERE_ONNX_DIAG__?: unknown }).__RUNANYWHERE_ONNX_DIAG__ = {
      accelerationMode: ONNX.accelerationMode,
      threads: ONNX.threads,
      lastFallbackReason: ONNX.lastFallbackReason,
      diagnostics: ONNX.lastWorkerDiagnostics,
      speech,
    };
    reportEngineRegistration('onnx', { ok: true });
  } catch (err) {
    const message = formatError(err);
    backendErrors.push(`onnx/sherpa: ${message}`);
    // Formatted string, not the Error — see the llamacpp branch above.
    appLogger.warning(
      '[RunAnywhere] onnx backend failed to register; STT/TTS/VAD will show feature-unavailable:',
      message,
    );
    reportEngineRegistration('onnx', { ok: false, error: message });
  }

  backendReadinessState = backendErrors.length === 0 ? 'registered' : 'unavailable';
  backendRegistrationError = backendErrors.length > 0 ? backendErrors.join('; ') : undefined;
  if (requireAllBackends && backendErrors.length > 0) {
    throw new Error(`Backend registration failed (${backendErrors.join('; ')})`);
  }

  publishReadinessStep('catalog');
  const registeredCount = await withTimeout(
    'registering the model catalog',
    60_000,
    registerModelCatalogAll(),
  );
  if (requireAllBackends && registeredCount === 0) {
    throw new Error('Model catalog registration failed: no models were registered.');
  }

  // Hydrate OPFS → registry *before* notifying the picker. Otherwise the UI
  // seeds every row as "Download" and can miss the later models.hydrated
  // refresh (collapsed families / sheet opened from stale rowStates).
  await withTimeout('hydrating the model registry', 60_000, RunAnywhere.storage.refresh());
  await withTimeout('refreshing SDK catalogs', 60_000, refreshSDKCatalogs());
  notifyCatalogRegistered(registeredCount);

  // Identity is cloud-dependent and the SDK completes it in the background
  // after initialize() returns, so the shell never waits on it.
  identityReadinessState = 'not-required';
  identityInitializationError = undefined;

  appLogger.info(
    '[RunAnywhere] SDK initialized, version:', RunAnywhere.version,
    '| storage backend:', RunAnywhere.storage.backend,
  );

  showAccelerationBadge(activeAcceleration);
}

/**
 * Apply Settings credentials in-place. If the new production runtime fails,
 * restore the previous in-memory configuration so the rest of the app remains
 * usable; neither configuration is written to localStorage.
 */
function applyAPIConfiguration(
  configuration: APIConfiguration,
): Promise<APIConfigurationApplyResult> {
  if (runtimeReconfigurationPromise) return runtimeReconfigurationPromise;

  runtimeReconfigurationPromise = (async () => {
    const next: RuntimeConfiguration = {
      apiKey: configuration.apiKey,
      baseURL: configuration.baseURL,
      environment: 'production',
    };
    const previous = activeRuntimeConfiguration;

    sdkReadinessState = 'initializing';
    backendReadinessState = 'pending';
    backendRegistrationError = undefined;
    resetEngineAvailability();
    identityReadinessState = 'not-required';
    identityInitializationError = undefined;

    try {
      await teardownRuntime();
      await startRuntime(next, true);
      activeRuntimeConfiguration = next;
      sdkReadinessState = 'ready';
      sdkInitializationError = undefined;
      return {
        environment: next.environment,
        telemetryEnabled: next.environment === 'production',
      };
    } catch (err) {
      const applyError = formatError(err);
      let restored = false;
      try {
        await teardownRuntime();
        const fallback: RuntimeConfiguration = previous ?? { environment: 'development' };
        await startRuntime(fallback, false);
        activeRuntimeConfiguration = fallback;
        sdkReadinessState = 'ready';
        sdkInitializationError = undefined;
        restored = true;
      } catch (restoreErr) {
        sdkReadinessState = 'unavailable';
        sdkInitializationError = formatError(restoreErr);
      }

      throw new Error(
        restored
          ? `Could not apply production configuration: ${applyError}. The previous runtime was restored.`
          : `Could not apply production configuration: ${applyError}. Runtime recovery also failed.`,
      );
    }
  })().finally(() => {
    runtimeReconfigurationPromise = null;
  });

  return runtimeReconfigurationPromise;
}

/**
 * Re-run the boot path with the configuration already in effect.
 *
 * A WASM registration failure is often transient — one chunk request failed,
 * the tab was offline, a proxy stalled — and a full page reload throws away
 * conversations, the loaded catalog state, and whatever tab the user was on.
 * This is the same teardown-then-`startRuntime` sequence Settings uses, minus
 * the credential change, so recovery costs a few seconds instead of a reload.
 *
 * `requireAllBackends: false` matches boot: one engine failing must not abort
 * the other's registration or tip the app into the fatal error view.
 * `startRuntime` reports each outcome through `reportEngineRegistration`, so
 * the UI ends up truthful whether this succeeds, partly succeeds, or throws.
 */
async function retryEngineRegistration(): Promise<void> {
  // Serialize against a Settings apply: both drive teardown + startRuntime, and
  // interleaving them would register backends onto a runtime being destroyed.
  if (runtimeReconfigurationPromise) {
    await runtimeReconfigurationPromise.catch(() => undefined);
    return;
  }

  const configuration = activeRuntimeConfiguration ?? { environment: 'development' };
  backendReadinessState = 'pending';
  backendRegistrationError = undefined;
  publishReadiness(appReadinessState);

  runtimeReconfigurationPromise = (async () => {
    await teardownRuntime();
    await startRuntime(configuration, false);
    return {
      environment: configuration.environment,
      telemetryEnabled: configuration.environment === 'production',
    };
  })().finally(() => {
    runtimeReconfigurationPromise = null;
  });

  try {
    await runtimeReconfigurationPromise;
    sdkReadinessState = 'ready';
    sdkInitializationError = undefined;
  } finally {
    // Republish either way: on failure the snapshot must show the engines still
    // unavailable rather than stay stuck on 'pending'.
    publishReadiness(appReadinessState);
  }
}

/** Backends own native registrations, so release them before core shutdown. */
async function teardownRuntime(): Promise<void> {
  resetCatalogRegistrationState();

  try {
    const { ONNX } = await import('@runanywhere/web-onnx');
    ONNX.unregister();
  } catch (err) {
    appLogger.warning('[RunAnywhere] ONNX teardown failed:', err);
  }

  try {
    const { LlamaCPP } = await import('@runanywhere/web-llamacpp');
    LlamaCPP.unregister();
  } catch (err) {
    appLogger.warning('[RunAnywhere] llamacpp teardown failed:', err);
  }

  // `reset()` closes every open session (RAG index, voice pipeline) before it
  // releases the WASM modules, so views never need to unwind them here.
  await RunAnywhere.reset();
}

/**
 * Post-init registry refresh + logging — iOS parity: `refreshSDKCatalogs()`
 * (RunAnywhereAIApp.swift:168-193).
 */
async function refreshSDKCatalogs(): Promise<void> {
  appLogger.info('[RunAnywhere] Refreshing SDK model registry...');
  await RunAnywhere.storage.refresh();

  const catalog = RunAnywhere.models.list();
  const downloaded = RunAnywhere.models.list({ downloadedOnly: true }).length;
  const available = RunAnywhere.models.list({ availableOnly: true }).length;
  appLogger.info(
    `[RunAnywhere] Model registry: registered=${catalog.length}, downloaded=${downloaded}, available=${available}`,
  );

  try {
    const { applied } = await RunAnywhere.lora.list();
    appLogger.info(`[RunAnywhere] LoRA adapters applied: ${applied.length}`);
  } catch (err) {
    // Formatted string so the reason survives the logger's Error redaction.
    appLogger.warning('[RunAnywhere] LoRA state unavailable:', formatError(err));
  }
}

/**
 * The runtime row in the drawer footer: where inference is actually running.
 *
 * WHERE IT LIVES, AND WHY IT MOVED. This was a `position: fixed` block pinned to
 * the bottom-right corner at `z-index: 140`, three lines tall and
 * `pointer-events: none` — so at a 390px viewport it sat *on top of* the chat
 * composer, un-clickable and un-dismissable, over the one control the screen
 * exists for. It now sits in the drawer footer, where it is a labelled fact
 * about the session instead of an overlay on the conversation.
 *
 * WHAT IT SAYS. One consumer sentence ("Runs entirely on this device"), one
 * detail line naming the execution path in words, and one chip carrying the
 * accelerator token. `title` keeps the full per-modality matrix for diagnostics,
 * which is where a build-log-shaped string belongs.
 *
 * `runtime.modalities` reports *where* a modality would execute (worker vs main
 * thread), not *whether* an engine registered — with no engine at all it still
 * answers `status: 'main'`. So the per-engine outcome this app tracked itself is
 * checked first; without it the row would report a running LLM path while the
 * screen behind it says the engine never loaded.
 */
function showAccelerationBadge(llmMode: string): void {
  const slot = document.getElementById('consumer-runtime-slot');
  if (!slot) return;

  const failures = engineFailures();
  if (failures.length > 0) {
    slot.innerHTML = runtimeRowMarkup({
      variant: 'unavailable',
      icon: 'warning',
      headline: 'On-device engine unavailable',
      detail: failures.map((failure) => failure.label).join(' · ') + ' did not load',
      chip: 'None',
      title: failureDiagnostics(failures),
    });
    return;
  }

  const mods = RunAnywhere.runtime.modalities;
  const speech = RunAnywhere.runtime.speech;
  const llmGPU = llmMode === 'webgpu' || mods.llm.acceleration === 'webgpu';
  const speechGPU = speech.acceleration === 'webgpu';
  const accelWord = (accel: string | null | undefined) =>
    (accel === 'webgpu' ? 'WebGPU' : accel === 'cpu' ? 'CPU' : '—');

  // Two paths, named in the words a user would use for them, and only split
  // apart when they actually differ — "Chat and speech on CPU" is the common
  // case and reads as one fact rather than a table with one row per engine.
  const chatWord = accelWord(llmGPU ? 'webgpu' : mods.llm.acceleration ?? 'cpu');
  const speechWord = mods.stt.status === 'unavailable'
    ? null
    : accelWord(speechGPU ? 'webgpu' : speech.acceleration ?? 'cpu');
  const detail = speechWord === null
    ? `Chat on ${chatWord}`
    : chatWord === speechWord
      ? `Chat and speech on ${chatWord}`
      : `Chat on ${chatWord} · speech on ${speechWord}`;

  slot.innerHTML = runtimeRowMarkup({
    variant: llmGPU || speechGPU ? 'gpu' : 'cpu',
    icon: 'lock',
    headline: 'Runs entirely on this device',
    detail,
    chip: llmGPU || speechGPU ? 'WebGPU' : 'CPU',
    title: Object.entries(mods)
      .map(([id, m]) => `${id}=${m.status}/${m.acceleration ?? 'none'}${m.note ? ` (${m.note})` : ''}`)
      .concat(speech.threads > 1 ? [`speech threads=${speech.threads}`] : [])
      .join('\n'),
  });
}

interface RuntimeRow {
  variant: 'gpu' | 'cpu' | 'unavailable';
  icon: IconName;
  headline: string;
  detail: string;
  /**
   * A single token, never a sentence. The chip is the one glanceable part of the
   * row, and it is also what the release browser suite reads out of
   * `#accel-badge` — so it stays one word per state.
   */
  chip: string;
  title: string;
}

function runtimeRowMarkup(row: RuntimeRow): string {
  return `
    <div class="consumer-runtime consumer-runtime--${row.variant}" title="${escapeHtml(row.title)}">
      <span class="consumer-runtime__icon">${icon(row.icon, { size: 16 })}</span>
      <span class="consumer-runtime__text">
        <span class="consumer-runtime__headline">${escapeHtml(row.headline)}</span>
        <span class="consumer-runtime__detail">${escapeHtml(row.detail)}</span>
      </span>
      <span id="accel-badge" class="accel-badge accel-badge--${row.variant}">${escapeHtml(row.chip)}</span>
    </div>
  `;
}

// ---------------------------------------------------------------------------
// Loading Screen
// ---------------------------------------------------------------------------

/**
 * Make the boot screen visible.
 *
 * The markup lives in index.html so it paints with the document rather than
 * after the module graph runs — see the comment there. This must therefore never
 * build or replace it: re-creating the node would throw away an already-painted
 * screen and flash. It only un-hides, which matters on the retry path, where
 * hideLoadingScreen() has already run and removed the element.
 */
function showLoadingScreen(): void {
  // Cancel a pending teardown before adopting the node it is about to delete.
  // hideLoadingScreen() removes the element 500ms after fading it out, so a
  // Retry click inside that window would un-hide the screen and then have it
  // yanked out from under the boot it just started — leaving the user on a blank
  // page with no sign that anything is happening.
  if (loadingScreenRemovalTimer !== null) {
    clearTimeout(loadingScreenRemovalTimer);
    loadingScreenRemovalTimer = null;
  }

  const existing = document.getElementById('loading-screen');
  if (existing) {
    existing.classList.remove('hidden');
    return;
  }

  // Retry after a failed boot: the original was removed, so rebuild the same
  // structure index.html ships.
  const screen = document.createElement('div');
  screen.className = 'loading-screen';
  screen.id = 'loading-screen';
  screen.innerHTML = `
    <div class="loading-logo">
      <img src="/runanywhere-logo.svg" alt="" width="100" height="100" />
    </div>
    <div class="loading-text">
      <h2>Starting RunAnywhere</h2>
      <p>Getting your on-device AI ready&hellip;</p>
    </div>
    <div class="loading-bar">
      <div class="loading-bar-fill"></div>
    </div>
    <p class="text-sm text-tertiary" id="loading-status">Loading the SDK&hellip;</p>
  `;
  document.body.appendChild(screen);
}

/** Pending removal timer, so showLoadingScreen() can cancel a fade in flight. */
let loadingScreenRemovalTimer: number | null = null;

function hideLoadingScreen(): void {
  const screen = document.getElementById('loading-screen');
  if (!screen) return;

  screen.classList.add('hidden');
  if (loadingScreenRemovalTimer !== null) clearTimeout(loadingScreenRemovalTimer);
  loadingScreenRemovalTimer = window.setTimeout(() => {
    loadingScreenRemovalTimer = null;
    screen.remove();
  }, 500);
}

// ---------------------------------------------------------------------------
// Error View
// ---------------------------------------------------------------------------

function showErrorView(message: string): void {
  hideLoadingScreen();

  const app = document.getElementById('app')!;
  app.innerHTML = `
    <div class="error-view">
      <div class="error-icon">&#9888;&#65039;</div>
      <h2>Initialization Failed</h2>
      <p class="text-secondary max-w-md" id="initialization-error-message"></p>
      <button class="btn btn-primary btn-lg" id="retry-btn">Retry</button>
    </div>
  `;

  // Initialization errors can contain remote/WASM-provided text. Render the
  // diagnostic as text so a failed upstream cannot inject markup into the app.
  const messageElement = document.getElementById('initialization-error-message');
  if (messageElement) messageElement.textContent = message;

  document.getElementById('retry-btn')!.addEventListener('click', () => {
    app.innerHTML = '';
    void main();
  });
}

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

void main();
