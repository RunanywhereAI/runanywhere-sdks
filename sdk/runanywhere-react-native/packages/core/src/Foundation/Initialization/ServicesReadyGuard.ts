/**
 * ServicesReadyGuard
 *
 * Lazily-injected Phase-2 readiness gate used by every public inference
 * extension (LLM, STT, TTS, VAD, loadModel, downloadModel).
 *
 * Mirrors Swift's `RunAnywhere.ensureServicesReady()` internal static guard
 * (`RunAnywhere.swift:336-352`). Swift can call the static directly because all
 * extensions live in the same module. TypeScript modules are independent files,
 * so the guard is registered once by `RunAnywhere.ts` at construction time and
 * invoked by the extension files through this indirection — avoiding a circular
 * import between extensions → RunAnywhere → extensions.
 */

type ServicesReadyFn = () => Promise<void>;

let _ensureServicesReady: ServicesReadyFn | null = null;

/**
 * Called once by `RunAnywhere.ts` to register the Phase-2 guard.
 * Idempotent — re-registering with the same function is a no-op.
 */
export function registerServicesReadyGuard(fn: ServicesReadyFn): void {
  _ensureServicesReady = fn;
}

/**
 * Await Phase-2 (services) initialization before proceeding.
 *
 * O(1) after first successful Phase-2 completion (
 * `completeServicesInitialization` short-circuits on the cached
 * `hasCompletedServicesInit` flag). Errors PROPAGATE — matching Swift's
 * `try await ensureServicesReady()` used by generate / transcribe /
 * synthesize / RAG / voice-agent and the other throwing entry points.
 *
 * Result-returning, non-throwing call sites (listModels / getModel /
 * refreshModelRegistry / loadModel) should use
 * `ensureServicesReadyOrIgnore()` instead — Swift's `try?` sites.
 */
export async function ensureServicesReady(): Promise<void> {
  if (_ensureServicesReady) {
    await _ensureServicesReady();
  }
}

/**
 * `try?` variant of [ensureServicesReady]: swallow Phase-2 failures so a
 * transient services-init error does not block local-only operation. Mirrors
 * Swift's `try? await ensureServicesReady()` in `listModels`, `getModel`,
 * `refreshModelRegistry`, and `loadModel`.
 */
export async function ensureServicesReadyOrIgnore(): Promise<void> {
  try {
    await ensureServicesReady();
  } catch {
    // Non-fatal: mirrors Swift `try? await ensureServicesReady()`.
  }
}
