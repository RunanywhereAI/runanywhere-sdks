/**
 * ServicesReadyGuard
 *
 * Lazily-injected Phase-2 readiness gate used by every public inference
 * extension (LLM, STT, TTS, VAD, loadModel, downloadModel).
 *
 * Mirrors Swift's `RunAnywhere.ensureServicesReady()` internal static guard
 * (`RunAnywhere.swift:321-330`). Swift can call the static directly because all
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
 * `hasCompletedServicesInit` flag). Errors are swallowed with `try?` semantics
 * — matching Swift's `try? await ensureServicesReady()` in `loadModel` /
 * `downloadModel` — so a transient Phase-2 failure does not block inference.
 */
export async function ensureServicesReady(): Promise<void> {
  if (_ensureServicesReady) {
    try {
      await _ensureServicesReady();
    } catch {
      // Non-fatal: mirrors Swift `try? await ensureServicesReady()`.
    }
  }
}
