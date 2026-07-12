/**
 * SolutionAdapter.ts (Web / WASM)
 *
 * v3 / T4.7+T4.8 — proto-byte / YAML driven L5 solution runtime. Wraps
 * the `_rac_solution_*` Emscripten exports declared in
 * `EmscriptenModule.ts` (and wired in `sdk/runanywhere-web/wasm/
 * CMakeLists.txt`).
 *
 * Capability shape mirrors the other 4 SDKs — callers reach the API
 * through `RunAnywhere.solutions.run({ config | configBytes | yaml })`
 * and receive a [SolutionHandle] whose verbs map 1:1 to the C ABI.
 *
 * The adapter is stateless. Each `run(...)` call allocates a fresh
 * `rac_solution_handle_t` and returns a [SolutionHandle] that owns it.
 * Callers MUST invoke `handle.destroy()` (or `handle.close()`) when
 * finished — there is no JS finalizer that releases native memory.
 */

import { SolutionConfig } from '@runanywhere/proto-ts/solutions';
import { SDKException } from '../Foundation/SDKException.js';
import { RAC_OK, RAC_ERROR_FEATURE_NOT_AVAILABLE } from '../Foundation/RACErrors.js';
import {
  getModuleForCapability,
  tryRunanywhereModule,
  type EmscriptenRunanywhereModule,
} from '../runtime/EmscriptenModule.js';

function assertOk(op: string, rc: number): void {
  if (rc === RAC_ERROR_FEATURE_NOT_AVAILABLE) {
    throw SDKException.backendNotAvailable(
      `Solution.${op}`,
      `Native solution runtime returned RAC_ERROR_FEATURE_NOT_AVAILABLE (rc=${rc}). ` +
      'This Web WASM build does not include the requested solution capability.',
    );
  }

  if (rc !== RAC_OK) {
    throw new Error(`rac_solution_${op} failed (rc=${rc})`);
  }
}

function isRagSolutionYaml(yaml: string): boolean {
  return /^\s*rag\s*:/m.test(yaml);
}

function moduleSupportsRAG(module: EmscriptenRunanywhereModule): boolean {
  try {
    return (
      typeof module._rac_rag_session_create_proto === 'function' &&
      typeof module._rac_rag_query_proto === 'function'
    );
  } catch {
    return false;
  }
}

/**
 * Lifecycle handle for a created (not started) solution. Forwards
 * each verb to the underlying C ABI. Always invoke [destroy] (or
 * [close]) — there is no JS finalizer.
 */
export class SolutionHandle {
  private handle: number | null;
  private readonly module: EmscriptenRunanywhereModule;

  /** @internal — constructed by [SolutionAdapter.run]. */
  constructor(handle: number, module: EmscriptenRunanywhereModule) {
    if (!handle) {
      throw new Error('Cannot wrap a null rac_solution_handle_t');
    }
    this.handle = handle;
    this.module = module;
  }

  /** True until [destroy] (or [close]) clears the underlying handle. */
  get isAlive(): boolean {
    return this.handle !== null && this.handle !== 0;
  }

  /** Start the underlying scheduler (non-blocking). */
  start(): void {
    assertOk('start', this.module._rac_solution_start(this.requireHandle()));
  }

  /** Request a graceful shutdown (non-blocking). */
  stop(): void {
    assertOk('stop', this.module._rac_solution_stop(this.requireHandle()));
  }

  /** Force-cancel the graph; returns once workers observe cancellation. */
  cancel(): void {
    assertOk('cancel', this.module._rac_solution_cancel(this.requireHandle()));
  }

  /** Feed one UTF-8 item into the root input edge. */
  feed(item: string): void {
    const m = this.module;
    const handle = this.requireHandle();
    const itemLen = m.lengthBytesUTF8(item) + 1;
    const itemPtr = m._malloc(itemLen);
    try {
      m.stringToUTF8(item, itemPtr, itemLen);
      assertOk('feed', m._rac_solution_feed(handle, itemPtr));
    } finally {
      m._free(itemPtr);
    }
  }

  /** Signal end-of-stream on the root input edge. */
  closeInput(): void {
    assertOk(
      'close_input',
      this.module._rac_solution_close_input(this.requireHandle()),
    );
  }

  /** Cancel, join, and release native resources. Idempotent. */
  destroy(): void {
    if (this.handle === null || this.handle === 0) return;
    const handle = this.handle;
    this.handle = null;
    this.module._rac_solution_destroy(handle);
  }

  /** Alias for [destroy] — gives the API a more conventional close-shape. */
  close(): void {
    this.destroy();
  }

  private requireHandle(): number {
    if (this.handle === null || this.handle === 0) {
      throw new Error('SolutionHandle has already been destroyed');
    }
    return this.handle;
  }
}

/** Argument shape for [SolutionAdapter.run]. Exactly one form may be set. */
export type SolutionRunInput =
  | { config: SolutionConfig; configBytes?: never; yaml?: never }
  | { config?: never; configBytes: Uint8Array; yaml?: never }
  | { config?: never; configBytes?: never; yaml: string };

/**
 * Stateless adapter that materialises a [SolutionHandle] from either
 * a typed `SolutionConfig` proto, raw proto bytes, or a YAML document.
 *
 * Usage:
 *
 *     import { SolutionAdapter } from '@runanywhere/web';
 *     const handle = SolutionAdapter.run({
 *       config: SolutionConfig.create({ voiceAgent: { ... } }),
 *     });
 *     handle.start();
 *     try {
 *       handle.feed('hello');
 *     } finally {
 *       handle.destroy();
 *     }
 */
export const SolutionAdapter = {
  /**
   * Construct and return a (created, not started) solution. Exactly
   * one of the three input forms must be supplied.
   *
   * @param input    Typed proto, raw proto bytes, or YAML document.
   * @param module   Optional Emscripten module override — backend
   *                 packages with their own WASM module pass it here.
   *                 Otherwise the capability registry selects and pins a
   *                 concrete module for the handle's complete lifetime.
   */
  run(
    input: SolutionRunInput,
    module?: EmscriptenRunanywhereModule,
  ): SolutionHandle {
    if (typeof input !== 'object' || input === null) {
      throw new Error(
        'SolutionAdapter.run expects an object — { config } | { configBytes } | { yaml }',
      );
    }

    const { yaml, configBytes, config } = input as {
      yaml?: string;
      configBytes?: Uint8Array;
      config?: SolutionConfig;
    };

    if (yaml !== undefined) {
      const isRag = isRagSolutionYaml(yaml);
      const selectedModule = module
        ?? (isRag ? getModuleForCapability('rag') : null)
        ?? tryRunanywhereModule();
      return createFromYaml(
        yaml,
        requireSolutionModule(selectedModule, isRag ? 'RAG solution YAML' : 'Solutions'),
      );
    }

    let bytes: Uint8Array;
    let isRag = false;
    if (configBytes !== undefined) {
      bytes = configBytes;
      try {
        isRag = SolutionConfig.decode(bytes).rag !== undefined;
      } catch {
        // Preserve native decode/error semantics for malformed raw bytes.
      }
    } else if (config !== undefined) {
      bytes = SolutionConfig.encode(config).finish();
      isRag = config.rag !== undefined;
    } else {
      throw new Error(
        'SolutionAdapter.run requires exactly one of config / configBytes / yaml',
      );
    }

    if (bytes.length === 0) {
      throw new Error(
        'Solution config bytes are empty — refusing to call rac_solution_create_from_proto',
      );
    }

    const selectedModule = module
      ?? (isRag ? getModuleForCapability('rag') : null)
      ?? tryRunanywhereModule();
    return createFromProto(
      bytes,
      requireSolutionModule(selectedModule, isRag ? 'RAG solution config' : 'Solutions'),
      isRag,
    );
  },
};

function requireSolutionModule(
  module: EmscriptenRunanywhereModule | null,
  feature: string,
): EmscriptenRunanywhereModule {
  if (module) return module;
  throw SDKException.backendNotAvailable(
    feature,
    'No registered Web WASM module owns the requested solution capability.',
  );
}

/**
 * Return a live Uint32Array view of the module's WASM heap.
 *
 * Emscripten only puts `HEAPU32` on the Module object when it is listed
 * in `-sEXPORTED_RUNTIME_METHODS`. If the backend WASM was compiled
 * without that flag we derive the view from `HEAPU8.buffer` (HEAPU8 is
 * always exported).
 */
function heapU32(m: EmscriptenRunanywhereModule): Uint32Array {
  if (m.HEAPU32) return m.HEAPU32;

  // Fallback: derive from HEAPU8's underlying ArrayBuffer.
  if (m.HEAPU8) return new Uint32Array(m.HEAPU8.buffer);

  throw new Error(
    'RunAnywhere WASM module is missing HEAPU8/HEAPU32. ' +
    'Ensure a backend (e.g. LlamaCPP) has been registered via ' +
    'registerWasmModule() before calling RunAnywhere.solutions.run().',
  );
}

function createFromProto(
  bytes: Uint8Array,
  module: EmscriptenRunanywhereModule,
  isRag = false,
): SolutionHandle {
  const m = module;

  if (isRag && !moduleSupportsRAG(m)) {
    throw SDKException.backendNotAvailable(
      'RAG solution config',
      'RAG solution config is unavailable in this Web WASM build because the native ' +
      'rac_rag_* exports are missing, likely because RAC_BACKEND_RAG=OFF.',
    );
  }

  const bytesPtr = m._malloc(bytes.length);
  // wasm32: pointers are 4 bytes — that's the only emscripten target we ship.
  const outHandlePtr = m._malloc(4);
  try {
    m.HEAPU8.set(bytes, bytesPtr);
    heapU32(m)[outHandlePtr >>> 2] = 0;

    const rc = m._rac_solution_create_from_proto(
      bytesPtr,
      bytes.length,
      outHandlePtr,
    );
    assertOk('create_from_proto', rc);

    const handle = heapU32(m)[outHandlePtr >>> 2];
    if (!handle) {
      throw new Error(
        'rac_solution_create_from_proto returned RAC_SUCCESS with a null handle',
      );
    }
    return new SolutionHandle(handle, m);
  } finally {
    m._free(bytesPtr);
    m._free(outHandlePtr);
  }
}

function createFromYaml(
  yaml: string,
  module: EmscriptenRunanywhereModule,
): SolutionHandle {
  const m = module;

  if (isRagSolutionYaml(yaml) && !moduleSupportsRAG(m)) {
    throw SDKException.backendNotAvailable(
      'RAG solution YAML',
      'RAG solution YAML is unavailable in this Web WASM build because the native ' +
      'rac_rag_* exports are missing, likely because RAC_BACKEND_RAG=OFF.',
    );
  }

  const yamlLen = m.lengthBytesUTF8(yaml) + 1;
  const yamlPtr = m._malloc(yamlLen);
  const outHandlePtr = m._malloc(4);
  try {
    m.stringToUTF8(yaml, yamlPtr, yamlLen);
    heapU32(m)[outHandlePtr >>> 2] = 0;

    const rc = m._rac_solution_create_from_yaml(yamlPtr, outHandlePtr);
    assertOk('create_from_yaml', rc);

    const handle = heapU32(m)[outHandlePtr >>> 2];
    if (!handle) {
      throw new Error(
        'rac_solution_create_from_yaml returned RAC_SUCCESS with a null handle',
      );
    }
    return new SolutionHandle(handle, m);
  } finally {
    m._free(yamlPtr);
    m._free(outHandlePtr);
  }
}
