// Deterministic teardown for objects that own a native handle (a loaded model
// slot, a RAG session, a voice session). The explicit dispose()/close() call is
// the contract; `using` is sugar over it. A FinalizationRegistry frees a handle
// a caller forgot to release, but only as a backstop — GC timing is not
// guaranteed, so nothing correctness-critical may depend on it.

/** Releases the underlying native handle. Called at most once per resource. */
export type FreeFn = () => void;

interface LeakInfo {
  release: FreeFn;
  label: string;
  warn: (message: string) => void;
}

// The backstop action when a resource is collected without being disposed.
// Exported so the warn-then-free-once behavior is unit-testable without driving
// the garbage collector.
export function releaseLeaked(info: LeakInfo): void {
  info.warn(
    `RunAnywhere: ${info.label} was garbage-collected before dispose() — releasing its ` +
      'native handle as a backstop. Dispose it explicitly or use `using` for deterministic cleanup.'
  );
  try {
    info.release();
  } catch {
    // A finalizer runs during GC; it must never throw.
  }
}

const registry = new FinalizationRegistry<LeakInfo>(releaseLeaked);

/**
 * Registers `owner` for backstop cleanup and runs `release` exactly once, on the
 * first `free()` (or, failing that, when `owner` is collected).
 *
 * `release` MUST capture only the handle and the backend, never `owner`. A
 * closure that captures the owning object keeps it reachable forever, so the
 * registry would never fire and the backstop would be dead. The correct shape,
 * built entirely from constructor parameters rather than `this`:
 *
 *   class RagSession extends NativeResource {
 *     constructor(backend: RaBackend, readonly id: string) {
 *       super(`RAG session ${id}`, () => backend.ragClose(id));
 *     }
 *   }
 */
export class ResourceGuard {
  #released = false;
  readonly #token = {};

  constructor(owner: object, private readonly release: FreeFn, label: string) {
    registry.register(owner, { release, label, warn: (m) => console.warn(m) }, this.#token);
  }

  free(): void {
    if (this.#released) return;
    this.#released = true;
    registry.unregister(this.#token);
    this.release();
  }

  get released(): boolean {
    return this.#released;
  }
}

/**
 * Base for a handle-owning object. Subclasses pass a `release` closure over the
 * handle (see ResourceGuard's contract about not capturing `this`). `dispose()`,
 * `close()`, and `Symbol.dispose` are the same idempotent release.
 */
export abstract class NativeResource {
  readonly #guard: ResourceGuard;

  protected constructor(label: string, release: FreeFn) {
    this.#guard = new ResourceGuard(this, release, label);
  }

  dispose(): void {
    this.#guard.free();
  }

  close(): void {
    this.#guard.free();
  }

  [Symbol.dispose](): void {
    this.#guard.free();
  }

  protected get disposed(): boolean {
    return this.#guard.released;
  }
}
