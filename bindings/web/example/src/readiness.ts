/**
 * Readiness contract published for the SDK's own browser gates.
 *
 * `bindings/web/tests/browser/*` drives whatever app `RA_E2E_APP_DIR`
 * points at (this harness by default) and probes two globals rather than a
 * DOM layout, so the gates stay valid across app rewrites:
 *
 *   `window.__RUNANYWHERE_AI_READY__` — boot progress and its terminal state.
 *   `window.__RUNANYWHERE_SDK__`      — the imported SDK singleton, so the
 *                                       harness can inspect the public surface
 *                                       without re-bundling it through Vite.
 *
 * The root element also mirrors the backend state as
 * `data-runanywhere-ai-backend`, which Playwright can await without polling
 * script state.
 */

export type ReadinessState = 'booting' | 'initializing-sdk' | 'interactive' | 'error';
export type BackendState = 'pending' | 'registered' | 'unavailable';
export type ReadinessStep =
  | 'booting'
  | 'initializing-sdk'
  | 'registering-llamacpp'
  | 'registering-catalog'
  | 'interactive'
  | 'error';

export interface ReadinessSnapshot {
  /** True once the app can accept a prompt. */
  ready: boolean;
  state: ReadinessState;
  backend: BackendState;
  step: ReadinessStep;
  /** True once the (single-screen) shell is usable — the smoke gate reads it. */
  shellReady: boolean;
  /** Human-readable explanation of the current state. */
  reason: string;
  error?: string;
}

declare global {
  interface Window {
    __RUNANYWHERE_AI_READY__?: ReadinessSnapshot;
    __RUNANYWHERE_SDK__?: unknown;
  }
}

const snapshot: ReadinessSnapshot = {
  ready: false,
  state: 'booting',
  backend: 'pending',
  step: 'booting',
  shellReady: false,
  reason: 'App script evaluated; SDK boot not started.',
};

window.__RUNANYWHERE_AI_READY__ = snapshot;

/** Merge a boot-progress update into the published snapshot. */
export function publishReadiness(patch: Partial<ReadinessSnapshot>): void {
  Object.assign(snapshot, patch);
  window.__RUNANYWHERE_AI_READY__ = snapshot;
  document.documentElement.dataset.runanywhereAiBackend = snapshot.backend;
}

/** Expose the imported SDK singleton to the browser harness. */
export function publishSDK(sdk: unknown): void {
  window.__RUNANYWHERE_SDK__ = sdk;
}
