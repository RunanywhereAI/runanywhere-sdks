/**
 * ModelRegistryAdapter.ts — T4.9 Web binding for
 * `rac_model_registry_refresh`.
 *
 * The Web SDK's `ModelRegistry` (pure-TS) still owns the JS-side catalog
 * (UI state, listeners), but this adapter exposes the unified C-ABI refresh
 * so the browser surface is symmetric with Swift / Kotlin / RN / Flutter.
 * The remote-catalog step flows through whatever transport the caller
 * configured on the native side (typically a fetch-backed assignment
 * callback installed at SDK init); `rescan_local` and `prune_orphans` are
 * no-ops in the browser today because there is no persistent filesystem
 * for discovery.
 */

import { SDKLogger } from '../Foundation/SDKLogger';

const logger = new SDKLogger('ModelRegistryAdapter');

export interface ModelRegistryModule {
  _rac_get_model_registry?(): number;
  /**
   * Emscripten ABI lowering of
   * `rac_result_t rac_model_registry_refresh(handle, opts_by_value)`.
   *
   * Clang with the WASM ABI splits `rac_model_registry_refresh_opts_t`
   * (three `rac_bool_t` int32s + one pointer) into the individual scalar
   * arguments shown below. If the ABI version of clang ever changes to
   * pass the struct through a hidden sret pointer, this binding will need
   * to allocate and pass a pointer instead.
   */
  _rac_model_registry_refresh?(
    handle: number,
    includeRemoteCatalog: number,
    rescanLocal: number,
    pruneOrphans: number,
    discoveryCallbacks: number,
  ): number;
}

let defaultModule: ModelRegistryModule | null = null;

export interface RefreshOptions {
  includeRemoteCatalog?: boolean;
  rescanLocal?: boolean;
  pruneOrphans?: boolean;
}

export class ModelRegistryAdapter {
  /**
   * Install the default Emscripten module (called by backend packages on
   * load). Mirrors the pattern used by `HTTPAdapter.setDefaultModule`.
   */
  static setDefaultModule(module: ModelRegistryModule): void {
    defaultModule = module;
  }

  static clearDefaultModule(): void {
    defaultModule = null;
  }

  /** Returns the installed module, or `null` if no backend has loaded yet. */
  static tryDefault(): ModelRegistryAdapter | null {
    if (!defaultModule) return null;
    return new ModelRegistryAdapter(defaultModule);
  }

  private constructor(private readonly module: ModelRegistryModule) {}

  /** Refresh the registry via `rac_model_registry_refresh`. */
  refresh(options: RefreshOptions = {}): boolean {
    const mod = this.module;
    if (!mod._rac_get_model_registry || !mod._rac_model_registry_refresh) {
      logger.warning(
        'refresh: module missing rac_get_model_registry / rac_model_registry_refresh exports',
      );
      return false;
    }

    const handle = mod._rac_get_model_registry();
    if (!handle) {
      logger.warning('refresh: global registry handle is null');
      return false;
    }

    try {
      const rc = mod._rac_model_registry_refresh(
        handle,
        options.includeRemoteCatalog ? 1 : 0,
        options.rescanLocal ? 1 : 0,
        options.pruneOrphans ? 1 : 0,
        0, // discovery_callbacks = nullptr
      );
      if (rc !== 0) {
        logger.warning(`rac_model_registry_refresh returned rc=${rc}`);
        return false;
      }
      return true;
    } catch (error) {
      logger.warning(
        `rac_model_registry_refresh threw: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
      return false;
    }
  }
}
