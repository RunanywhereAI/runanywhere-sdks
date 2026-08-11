/**
 * StreamWorkerFactoryRegistry.ts
 *
 * T6.1 — Worker-path orchestrator support.
 *
 * @internal @experimental
 *
 * INTERNAL/EXPERIMENTAL — paired with `OffscreenRuntimeBridge.ts`. No
 * production backend currently calls `setStreamWorkerFactory(...)`. See
 * the removal contract on `OffscreenRuntimeBridge.ts` for disposition.
 *
 * Singleton registry that lets a backend package (`@runanywhere/web-llamacpp`,
 * `@runanywhere/web-onnx`) install the function that constructs the streaming
 * Web Worker. Core's worker orchestration stays bundler-neutral (no
 * backend-specific `new Worker(new URL(...))` is baked in); the factory
 * contains the bundler binding.
 *
 * If no factory is registered when `OffscreenRuntimeBridge.tryGet()` is called,
 * the bridge falls back to `null` and adapters transparently use the existing
 * main-thread `streamCallback` (queueMicrotask) path.
 *
 * Lifecycle:
 *   - Backend calls `setStreamWorkerFactory(fn)` once during its `register()`.
 *   - Backend may call `setStreamWorkerFactory(null)` during teardown to
 *     release the singleton.
 */

import { SDKLogger } from '../Foundation/SDKLogger.js';

const logger = new SDKLogger('StreamWorkerFactory');

/**
 * Factory function returning a fresh `Worker` instance. Implementations
 * typically look like:
 *
 *     setStreamWorkerFactory(() => new Worker(
 *       new URL('./streamWorker.bundle.js', import.meta.url),
 *       { type: 'module' },
 *     ));
 *
 * The factory is invoked at most once per `OffscreenRuntimeBridge`
 * lifetime — the bridge caches the spawned Worker.
 */
export type StreamWorkerFactory = () => Worker;

let _factory: StreamWorkerFactory | null = null;

/**
 * Install (or clear) the Worker factory. Passing `null` releases the
 * factory; the next bridge access will return `null` and adapters fall
 * back to the main-thread streaming path.
 */
export function setStreamWorkerFactory(factory: StreamWorkerFactory | null): void {
  const wasInstalled = _factory != null;
  _factory = factory;
  if (factory != null && !wasInstalled) {
    logger.debug('stream worker factory installed');
  } else if (factory == null && wasInstalled) {
    logger.debug('stream worker factory cleared');
  }
}

/**
 * Return the currently-registered Worker factory, or `null` if none.
 */
export function getStreamWorkerFactory(): StreamWorkerFactory | null {
  return _factory;
}

/**
 * Convenience predicate — true iff a factory is currently registered.
 */
export function hasStreamWorkerFactory(): boolean {
  return _factory != null;
}
