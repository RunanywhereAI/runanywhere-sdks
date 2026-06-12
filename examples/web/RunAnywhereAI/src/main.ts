/**
 * RunAnywhere AI - Web Demo Application
 *
 * Full-featured demo matching the iOS example app.
 * 11-tab navigation: Chat, Vision, Voice, Transcribe, Speak, VAD, Docs,
 * Storage, Solutions, Bench, Settings (see `TABS` in app.ts).
 */

import './styles/design-system.css';
import './styles/commons.css';
import './styles/components.css';
import { buildAppShell } from './app';
import {
  RunAnywhere,
  modelInfoIsAvailableForUse,
  modelInfoIsDownloadedOnDisk,
} from '@runanywhere/web';
import { SDKEnvironment } from '@runanywhere/proto-ts/model_types';
import { registerAll as registerModelCatalogAll } from './services/model-catalog';
import { notifyCatalogRegistered } from './components/model-selection';
import { getStoredApiKey, getStoredBaseURL } from './views/settings';
import { formatError } from './services/format-error';

type AppReadinessState = 'booting' | 'initializing-sdk' | 'building-shell' | 'interactive' | 'error';
type SDKReadinessState = 'initializing' | 'ready' | 'unavailable';
type BackendReadinessState = 'pending' | 'registered' | 'unavailable';

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

function publishReadiness(state: AppReadinessState, error?: string): AppReadinessSnapshot {
  const probe = probeAppShell();
  // Inference readiness is independent of app-shell readiness: when the
  // backend WASM is missing or fails to register, the model selector is
  // intentionally disabled (catalogRegistered=false), but the rest of the
  // demo (Voice/Documents/Settings tabs, feature-unavailable placeholders)
  // is still navigable. Treating that as "not interactive" would convert
  // the documented degraded mode into a fatal initialization error view.
  const backendDegraded = backendReadinessState === 'unavailable';
  const ready = state === 'interactive'
    && probe.shellReady
    && (probe.modelUiReady || backendDegraded);
  const snapshot: AppReadinessSnapshot = {
    ...probe,
    ready,
    state,
    sdk: sdkReadinessState,
    backend: backendReadinessState,
    backendError: backendRegistrationError,
    updatedAt: Date.now(),
    error: error ?? sdkInitializationError,
  };

  window.__RUNANYWHERE_AI_READY__ = snapshot;

  const root = document.documentElement;
  root.dataset.runanywhereAiReady = ready ? 'true' : 'false';
  root.dataset.runanywhereAiState = state;
  root.dataset.runanywhereAiSdk = sdkReadinessState;
  root.dataset.runanywhereAiBackend = backendReadinessState;
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

  const app = document.getElementById('app');
  if (app) {
    app.dataset.runanywhereAiReady = ready ? 'true' : 'false';
    app.dataset.runanywhereAiState = state;
  }

  window.dispatchEvent(new CustomEvent('runanywhere-ai-readinesschange', { detail: snapshot }));
  return snapshot;
}

function probeAppShell(): AppShellProbe {
  const app = document.getElementById('app');
  const tabContent = app?.querySelector('.tab-content') ?? null;
  const tabBar = app?.querySelector('.tab-bar') ?? null;
  const activePanel = app?.querySelector<HTMLElement>('.tab-panel.active') ?? null;
  const chatPanel = document.getElementById('tab-chat');
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
      && activePanel === chatPanel
      && loadingHidden,
  );
  const modelUiReady = Boolean(
    shellReady
      && modelUiTarget,
  );

  if (!app) return { shellReady, modelUiReady, modelUiTarget, activeTab: null, reason: 'missing-app-root' };
  if (!tabContent || !tabBar) return { shellReady, modelUiReady, modelUiTarget, activeTab: null, reason: 'missing-tab-shell' };
  if (!activePanel) return { shellReady, modelUiReady, modelUiTarget, activeTab: null, reason: 'missing-active-tab' };
  if (activePanel !== chatPanel) {
    return {
      shellReady,
      modelUiReady,
      modelUiTarget,
      activeTab: (activePanel.dataset.tab ?? activePanel.id) || null,
      reason: 'chat-tab-not-active',
    };
  }
  if (!loadingHidden) return { shellReady, modelUiReady, modelUiTarget, activeTab: 'chat', reason: 'loading-screen-visible' };
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
 * - On Chrome/Firefox: `crossOriginIsolated` is already true via server
 *   headers, so this is a no-op (SW registers silently for future use).
 * - On Safari/iOS: `crossOriginIsolated` is false, so the SW installs
 *   and the page reloads once to activate it.
 */
async function ensureCrossOriginIsolation(): Promise<void> {
  if (crossOriginIsolated) {
    console.log('[COI] Already cross-origin isolated');
    return;
  }

  if (!('serviceWorker' in navigator)) {
    console.warn('[COI] Service workers not supported — SharedArrayBuffer may be unavailable');
    return;
  }

  const registration = await navigator.serviceWorker.register('/coi-serviceworker.js');

  // If the SW is already active and controlling this page, COI should be
  // enabled. If we're still not isolated, something else is wrong.
  if (navigator.serviceWorker.controller) {
    console.warn('[COI] Service worker active but page is not cross-origin isolated');
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
    console.log('[COI] Service worker activated — reloading for cross-origin isolation');
    window.location.reload();
    // Halt execution — the reload will re-enter main()
    await new Promise(() => {});
  }
}

// ---------------------------------------------------------------------------
// Initialization Flow (matches iOS RunAnywhereAIApp.swift)
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  publishReadiness('booting');

  // Step 0: Ensure cross-origin isolation for SharedArrayBuffer (Safari/iOS)
  await ensureCrossOriginIsolation();

  // Show loading screen while SDK initializes
  showLoadingScreen();
  publishReadiness('initializing-sdk');

  try {
    // Step 1: Initialize the SDK (load WASM, register backends)
    await initializeSDK();

    // Step 2: Hide loading screen and show the app
    hideLoadingScreen();
    publishReadiness('building-shell');
    buildAppShell();
    await waitForInteractiveShell();
  } catch (error) {
    // Show error view with retry
    const message = formatError(error);
    showErrorView(message);
    publishReadiness('error', message);
  }
}

// ---------------------------------------------------------------------------
// SDK Initialization
// ---------------------------------------------------------------------------

async function initializeSDK(): Promise<void> {
  // V2 Architecture: core (`@runanywhere/web`) is pure TypeScript with no WASM.
  // Backend packages register independently — `@runanywhere/web-llamacpp`
  // loads `racommons-llamacpp.wasm` and installs the module on every core
  // proto-byte adapter via `setRunanywhereModule`. Until a backend has
  // registered, inference verbs throw "backend not available".
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
    // Credentials from Settings — iOS parity: runSDKInitialize()
    // (RunAnywhereAIApp.swift:113-138). When a usable apiKey + baseURL pair
    // is stored, initialize against production; otherwise development.
    // Logging boots from the environment automatically inside initialize().
    const apiKey = getStoredApiKey();
    const baseURL = getStoredBaseURL();
    if (
      apiKey !== null
      && baseURL !== null
      && !looksLikePlaceholder(apiKey)
      && isUsableHTTPURL(baseURL)
    ) {
      await RunAnywhere.initialize({
        apiKey,
        baseURL,
        environment: SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
      });
    } else {
      await RunAnywhere.initialize({
        environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
      });
    }

    // Attempt to restore previously chosen local storage directory
    // (web-only: File System Access API persistence).
    const localRestored = await RunAnywhere.storage.restoreLocalStorage();
    if (localRestored) {
      console.log('[RunAnywhere] Local storage restored:', RunAnywhere.storage.localStorageDirectoryName);
    }

    // Register the llamacpp WASM backend. This is best-effort: if the
    // WASM file is missing (e.g. a fresh dev cold-start before the build
    // ran), the rest of the app shell continues to load and views show
    // their `feature-unavailable` placeholder. Backend status is recorded
    // on the readiness snapshot so the interactive probe can treat the
    // disabled model picker as a degraded-but-interactive state instead
    // of a fatal initialization failure.
    let activeAcceleration: 'cpu' | 'webgpu' = 'cpu';
    try {
      const { LlamaCPP } = await import('@runanywhere/web-llamacpp');
      await LlamaCPP.register({ acceleration: 'auto' });
      activeAcceleration = LlamaCPP.accelerationMode;
      backendReadinessState = 'registered';
      backendRegistrationError = undefined;
      console.log('[RunAnywhere] llamacpp backend registered:', activeAcceleration);
    } catch (err) {
      backendReadinessState = 'unavailable';
      backendRegistrationError = formatError(err);
      console.warn(
        '[RunAnywhere] llamacpp backend failed to register; chat will show feature-unavailable:',
        backendRegistrationError,
      );
    }

    // Register the ONNX/Sherpa WASM backend (STT/TTS/VAD/Embeddings) at init
    // alongside llamacpp — iOS parity: RunAnywhereAIApp.swift:89-90
    // (`LlamaCPP.register` + `ONNX.register`). Same degraded, non-fatal
    // behavior as llamacpp on failure.
    try {
      const { ONNX } = await import('@runanywhere/web-onnx');
      await ONNX.register();
      console.log('[RunAnywhere] onnx/sherpa backend registered');
    } catch (err) {
      console.warn(
        '[RunAnywhere] onnx backend failed to register; STT/TTS/VAD will show feature-unavailable:',
        formatError(err),
      );
    }

    // Register the example model catalog ONCE — iOS parity:
    // RunAnywhereAIApp.swift:98 (`ModelCatalogBootstrap.registerAll()`).
    const registeredCount = await registerModelCatalogAll();
    notifyCatalogRegistered(registeredCount);

    // iOS parity: RunAnywhereAIApp.swift:99 (`refreshSDKCatalogs()`).
    await refreshSDKCatalogs();

    console.log(
      '[RunAnywhere] SDK initialized, version:', RunAnywhere.version,
      '| storage backend:', RunAnywhere.storage.backend,
    );

    showAccelerationBadge(activeAcceleration);
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
 * Post-init registry refresh + logging — iOS parity: `refreshSDKCatalogs()`
 * (RunAnywhereAIApp.swift:168-193).
 */
async function refreshSDKCatalogs(): Promise<void> {
  console.log('[RunAnywhere] Refreshing SDK model registry...');

  RunAnywhere.refreshModelRegistry();

  const list = RunAnywhere.listModels();
  if (list) {
    const models = list.models;
    const downloaded = models.filter((m) => modelInfoIsDownloadedOnDisk(m)).length;
    const available = models.filter((m) => modelInfoIsAvailableForUse(m)).length;
    console.log(
      `[RunAnywhere] Model registry: registered=${models.length}, downloaded=${downloaded}, available=${available}`,
    );
  } else {
    console.warn('[RunAnywhere] Model registry refresh incomplete: list unavailable');
  }

  try {
    const adapters = await RunAnywhere.lora.allRegistered();
    console.log(`[RunAnywhere] LoRA registry: ${adapters.length} entries`);
  } catch (err) {
    console.warn('[RunAnywhere] LoRA catalog unavailable:', formatError(err));
  }
}

/**
 * iOS parity: `looksLikePlaceholder(_:)` (RunAnywhereAIApp.swift:140-145).
 */
function looksLikePlaceholder(value: string): boolean {
  return /YOUR_|<your|REPLACE_ME|PLACEHOLDER/i.test(value);
}

/**
 * iOS parity: `isUsableHTTPURL(_:)` (RunAnywhereAIApp.swift:147-161).
 */
function isUsableHTTPURL(value: string): boolean {
  const trimmed = value.trim();
  if (looksLikePlaceholder(trimmed)) return false;
  let url: URL;
  try {
    url = new URL(trimmed);
  } catch {
    return false;
  }
  const scheme = url.protocol.replace(':', '').toLowerCase();
  if (scheme !== 'http' && scheme !== 'https') return false;
  const host = url.hostname;
  if (!host || /\s/.test(host) || host.includes('<') || host.includes('>')) return false;
  return true;
}

/**
 * Display a small floating badge indicating the active hardware acceleration.
 */
function showAccelerationBadge(mode: string): void {
  const badge = document.createElement('div');
  badge.id = 'accel-badge';
  const isGPU = mode === 'webgpu';
  badge.textContent = isGPU ? 'WebGPU' : 'CPU';
  badge.className = `accel-badge ${isGPU ? 'accel-badge--gpu' : 'accel-badge--cpu'}`;
  document.body.appendChild(badge);
}

// ---------------------------------------------------------------------------
// Loading Screen
// ---------------------------------------------------------------------------

function showLoadingScreen(): void {
  document.getElementById('loading-screen')?.remove();

  const screen = document.createElement('div');
  screen.className = 'loading-screen';
  screen.id = 'loading-screen';
  screen.innerHTML = `
    <div class="loading-logo">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100">
        <defs>
          <linearGradient id="logo-grad" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" style="stop-color:#FF5500"/>
            <stop offset="100%" style="stop-color:#E64500"/>
          </linearGradient>
        </defs>
        <circle cx="50" cy="50" r="45" fill="url(#logo-grad)" opacity="0.15"/>
        <circle cx="50" cy="50" r="30" fill="url(#logo-grad)" opacity="0.3"/>
        <text x="50" y="58" text-anchor="middle" fill="url(#logo-grad)" font-size="28" font-weight="bold" font-family="-apple-system, system-ui, sans-serif">RA</text>
      </svg>
    </div>
    <div class="loading-text">
      <h2>Setting Up Your AI</h2>
      <p>Preparing your private AI assistant...</p>
    </div>
    <div class="loading-bar">
      <div class="loading-bar-fill"></div>
    </div>
    <p class="text-sm text-tertiary">Initializing SDK...</p>
  `;
  document.body.appendChild(screen);
}

function hideLoadingScreen(): void {
  const screen = document.getElementById('loading-screen');
  if (screen) {
    screen.classList.add('hidden');
    setTimeout(() => screen.remove(), 500);
  }
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
      <p class="text-secondary max-w-md">${message}</p>
      <button class="btn btn-primary btn-lg" id="retry-btn">Retry</button>
    </div>
  `;

  document.getElementById('retry-btn')!.addEventListener('click', () => {
    app.innerHTML = '';
    main();
  });
}

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

main();
