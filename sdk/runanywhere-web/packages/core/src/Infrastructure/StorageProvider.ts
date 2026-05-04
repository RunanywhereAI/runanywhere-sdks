/**
 * StorageProvider.ts
 *
 * Uniform interface for persistent model storage backends.
 * On the Web platform we ship three concrete providers:
 *   - `fsAccess`   — File System Access API (user picked a directory)
 *   - `opfs`       — Origin Private File System (default persistent fallback)
 *   - `memory`     — Volatile MEMFS (no persistence)
 *
 * Mirrors the storage-backend contract so that other platforms (Swift / Kotlin /
 * Flutter / RN) can implement their analogue under a shared API name. Today
 * the Web SDK already stores via OPFSStorage / LocalFileStorage internally — this
 * interface exposes a stable way for application code (and other platforms) to
 * reason about which backend is active without leaking implementation details.
 *
 * This file intentionally has no runtime dependencies on the Emscripten module
 * or `OPFSStorage` — it is a shape definition only. Concrete providers attach
 * via `RunAnywhere.storage.setProvider(...)`.
 */

/** Stable identifier for a storage backend. */
export type StorageProviderId = 'fsAccess' | 'opfs' | 'memory' | (string & { _custom?: never });

/** Capabilities a provider may advertise. */
export interface StorageProviderCapabilities {
  /** Whether files survive a page reload. */
  persistent: boolean;
  /** Whether files persist across browser-storage clearing (i.e. real disk). */
  durable: boolean;
  /** Whether the user explicitly chose this directory. */
  userChosen: boolean;
  /** Approximate quota in bytes if known (null = unknown / unbounded). */
  quotaBytes?: number | null;
  /** Approximate usage in bytes if known. */
  usageBytes?: number | null;
}

/**
 * Generic storage provider interface.
 * Concrete implementations live elsewhere — this is the contract the rest of
 * the SDK uses (parallel to `DownloadProvider` etc.).
 */
export interface StorageProvider {
  /** Stable identifier used by `RunAnywhere.storageBackend`. */
  readonly id: StorageProviderId;
  /** Human-readable name (e.g. directory name for `fsAccess`). */
  readonly displayName: string;
  /** Whether the provider is ready to read/write. */
  readonly isReady: boolean;
  /** Capability bits. */
  readonly capabilities: StorageProviderCapabilities;
}
