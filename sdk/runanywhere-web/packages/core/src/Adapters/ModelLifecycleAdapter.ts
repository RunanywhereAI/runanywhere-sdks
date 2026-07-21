import {
  CurrentModelRequest,
  CurrentModelResult,
  ModelLoadRequest,
  ModelLoadResult,
  ModelUnloadRequest,
  ModelUnloadResult,
  type CurrentModelRequest as ProtoCurrentModelRequest,
  type CurrentModelResult as ProtoCurrentModelResult,
  type ModelLoadRequest as ProtoModelLoadRequest,
  type ModelLoadResult as ProtoModelLoadResult,
  type ModelUnloadRequest as ProtoModelUnloadRequest,
  type ModelUnloadResult as ProtoModelUnloadResult,
} from '@runanywhere/proto-ts/model_types';
import {
  ComponentLifecycleSnapshot,
  type ComponentLifecycleSnapshot as ProtoComponentLifecycleSnapshot,
  type SDKComponent as ProtoSDKComponent,
} from '@runanywhere/proto-ts/sdk_events';
import { SDKLogger } from '../Foundation/SDKLogger.js';
import { ProtoWasmBridge, type ProtoWasmModule } from '../runtime/ProtoWasm.js';
import { getModuleForFramework } from '../runtime/EmscriptenModule.js';
import { InferenceFramework } from '@runanywhere/proto-ts/model_types';

function frameworkToBridgeName(framework: InferenceFramework | string): string | null {
  if (typeof framework === 'string') return framework.toLowerCase() || null;
  switch (framework) {
    case InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP: return 'llamacpp';
    case InferenceFramework.INFERENCE_FRAMEWORK_ONNX: return 'onnx';
    case InferenceFramework.INFERENCE_FRAMEWORK_SHERPA: return 'sherpa';
    case InferenceFramework.INFERENCE_FRAMEWORK_PIPER_TTS: return 'sherpa';
    default: return null;
  }
}

function lookupFrameworkModule(framework: InferenceFramework | string): ModelLifecycleModule | null {
  const name = frameworkToBridgeName(framework);
  if (!name) return null;
  const mod = getModuleForFramework(name);
  return mod ? (mod as unknown as ModelLifecycleModule) : null;
}

const logger = new SDKLogger('ModelLifecycleAdapter');

type DefaultModuleListener = (adapter: ModelLifecycleAdapter) => void;

export interface ModelLifecycleModule extends ProtoWasmModule {
  _rac_get_model_registry?(): number;
  _rac_model_lifecycle_load_proto?(
    registryHandle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number | Promise<number>;
  _rac_model_lifecycle_unload_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number | Promise<number>;
  _rac_model_lifecycle_current_model_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_component_lifecycle_snapshot_proto?(
    component: number,
    outSnapshot: number,
  ): number;
  _rac_model_lifecycle_reset?(): void;
}

let defaultModule: ModelLifecycleModule | null = null;
const defaultModuleListeners: DefaultModuleListener[] = [];

/**
 * JSPI does not permit arbitrary synchronous re-entry into a WebAssembly
 * instance while one of its promising exports is suspended/unwinding. Model
 * loads and unloads use `ccall(..., { async: true })`; a concurrent
 * `currentModel()`/snapshot probe against that same module can otherwise
 * strand the JSPI promise after native model creation has already succeeded.
 */
const asyncMutationsByModule = new WeakMap<ModelLifecycleModule, number>();

function beginAsyncMutation(module: ModelLifecycleModule): void {
  asyncMutationsByModule.set(module, (asyncMutationsByModule.get(module) ?? 0) + 1);
}

function endAsyncMutation(module: ModelLifecycleModule): void {
  const remaining = (asyncMutationsByModule.get(module) ?? 1) - 1;
  if (remaining > 0) asyncMutationsByModule.set(module, remaining);
  else asyncMutationsByModule.delete(module);
}

function hasAsyncMutation(module: ModelLifecycleModule): boolean {
  return (asyncMutationsByModule.get(module) ?? 0) > 0;
}

function requireSynchronousResult(
  result: number | Promise<number>,
  operation: string,
): number {
  if (result instanceof Promise) {
    throw new Error(`${operation} is asynchronous for this WASM module; use the async lifecycle API`);
  }
  return Number(result);
}

export class ModelLifecycleAdapter {
  static setDefaultModule(module: ModelLifecycleModule): void {
    defaultModule = module;
    const adapter = new ModelLifecycleAdapter(module);
    for (const listener of defaultModuleListeners) {
      try {
        listener(adapter);
      } catch (error) {
        logger.warning(
          `default module listener failed: ${
            error instanceof Error ? error.message : String(error)
          }`,
        );
      }
    }
  }

  static clearDefaultModule(): void {
    defaultModule = null;
  }

  static onDefaultModuleReady(listener: DefaultModuleListener): () => void {
    defaultModuleListeners.push(listener);
    if (defaultModule) {
      try {
        listener(new ModelLifecycleAdapter(defaultModule));
      } catch (error) {
        logger.warning(
          `default module listener failed: ${
            error instanceof Error ? error.message : String(error)
          }`,
        );
      }
    }
    return () => {
      const index = defaultModuleListeners.indexOf(listener);
      if (index >= 0) defaultModuleListeners.splice(index, 1);
    };
  }

  static tryDefault(): ModelLifecycleAdapter | null {
    return defaultModule ? new ModelLifecycleAdapter(defaultModule) : null;
  }

  /**
   * Wrap a specific module in an adapter. Web-multi-WASM only: each WASM
   * artifact (commons, llamacpp, onnx-sherpa) owns its own static lifecycle
   * map (`g_loaded`), so cross-module aggregation (e.g. "is the LLM
   * component ready in any backend?") must walk every module individually.
   */
  static fromModule(module: ModelLifecycleModule): ModelLifecycleAdapter {
    return new ModelLifecycleAdapter(module);
  }

  /**
   * Return an adapter bound to the WASM that owns the framework's plugin
   * registry, falling back to the default. Web-multi-WASM only: native SDKs
   * share one process-wide plugin registry and don't need this dispatch.
   */
  static tryDefaultForFramework(
    framework: InferenceFramework | string | undefined | null,
  ): ModelLifecycleAdapter | null {
    if (framework !== undefined && framework !== null && framework !== '') {
      const mod = lookupFrameworkModule(framework as InferenceFramework | string);
      if (mod) return new ModelLifecycleAdapter(mod);
    }
    return ModelLifecycleAdapter.tryDefault();
  }

  /** The backend module selected for a framework, without default fallback. */
  static moduleForFramework(
    framework: InferenceFramework | string | undefined | null,
  ): ModelLifecycleModule | null {
    if (framework === undefined || framework === null || framework === '') return null;
    return lookupFrameworkModule(framework as InferenceFramework | string);
  }

  /** Module this adapter dispatches lifecycle calls to. */
  get boundModule(): ModelLifecycleModule {
    return this.module;
  }

  private constructor(private readonly module: ModelLifecycleModule) {}

  supportsProtoLifecycle(): boolean {
    return this.missingExports([
      '_rac_get_model_registry',
      '_rac_model_lifecycle_load_proto',
      '_rac_model_lifecycle_unload_proto',
      '_rac_model_lifecycle_current_model_proto',
      '_rac_component_lifecycle_snapshot_proto',
      '_rac_model_lifecycle_reset',
    ]).length === 0;
  }

  load(request: ProtoModelLoadRequest): ProtoModelLoadResult | null {
    if (!this.ensureExports('load', [
      '_rac_get_model_registry',
      '_rac_model_lifecycle_load_proto',
    ])) {
      return null;
    }

    const registryHandle = this.module._rac_get_model_registry!();
    if (!registryHandle) {
      logger.warning('load: global registry handle is null');
      return null;
    }

    return this.bridge().withEncodedRequest(
      request,
      ModelLoadRequest,
      ModelLoadResult,
      (requestPtr, requestSize, outResult) => requireSynchronousResult(
        this.module._rac_model_lifecycle_load_proto!(
          registryHandle,
          requestPtr,
          requestSize,
          outResult,
        ),
        'rac_model_lifecycle_load_proto',
      ),
      'rac_model_lifecycle_load_proto',
    );
  }

  async loadAsync(request: ProtoModelLoadRequest): Promise<ProtoModelLoadResult | null> {
    if (!this.ensureExports('load', [
      '_rac_get_model_registry',
      '_rac_model_lifecycle_load_proto',
    ])) {
      return null;
    }

    const registryHandle = this.module._rac_get_model_registry!();
    if (!registryHandle) {
      logger.warning('load: global registry handle is null');
      return null;
    }

    beginAsyncMutation(this.module);
    try {
      return await this.bridge().withEncodedRequestAsync(
        request,
        ModelLoadRequest,
        ModelLoadResult,
        (requestPtr, requestSize, outResult) => this.callLoad(
          registryHandle,
          requestPtr,
          requestSize,
          outResult,
        ),
        'rac_model_lifecycle_load_proto',
      );
    } finally {
      endAsyncMutation(this.module);
    }
  }

  unload(request: ProtoModelUnloadRequest): ProtoModelUnloadResult | null {
    if (!this.ensureExports('unload', ['_rac_model_lifecycle_unload_proto'])) {
      return null;
    }

    return this.bridge().withEncodedRequest(
      request,
      ModelUnloadRequest,
      ModelUnloadResult,
      (requestPtr, requestSize, outResult) => requireSynchronousResult(
        this.module._rac_model_lifecycle_unload_proto!(
          requestPtr,
          requestSize,
          outResult,
        ),
        'rac_model_lifecycle_unload_proto',
      ),
      'rac_model_lifecycle_unload_proto',
    );
  }

  async unloadAsync(request: ProtoModelUnloadRequest): Promise<ProtoModelUnloadResult | null> {
    if (!this.ensureExports('unload', ['_rac_model_lifecycle_unload_proto'])) {
      return null;
    }

    beginAsyncMutation(this.module);
    try {
      return await this.bridge().withEncodedRequestAsync(
        request,
        ModelUnloadRequest,
        ModelUnloadResult,
        (requestPtr, requestSize, outResult) => this.callUnload(
          requestPtr,
          requestSize,
          outResult,
        ),
        'rac_model_lifecycle_unload_proto',
      );
    } finally {
      endAsyncMutation(this.module);
    }
  }

  currentModel(
    request: ProtoCurrentModelRequest = { includeModelMetadata: false },
  ): ProtoCurrentModelResult | null {
    if (hasAsyncMutation(this.module)) return null;
    if (!this.ensureExports('currentModel', [
      '_rac_model_lifecycle_current_model_proto',
    ])) {
      return null;
    }

    return this.bridge().withEncodedRequest(
      request,
      CurrentModelRequest,
      CurrentModelResult,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_model_lifecycle_current_model_proto!(
          requestPtr,
          requestSize,
          outResult,
        )
      ),
      'rac_model_lifecycle_current_model_proto',
    );
  }

  componentSnapshot(
    component: ProtoSDKComponent,
  ): ProtoComponentLifecycleSnapshot | null {
    if (hasAsyncMutation(this.module)) return null;
    if (!this.ensureExports('componentSnapshot', [
      '_rac_component_lifecycle_snapshot_proto',
    ])) {
      return null;
    }

    return this.bridge().callResultProto(
      ComponentLifecycleSnapshot,
      (outSnapshot) => (
        this.module._rac_component_lifecycle_snapshot_proto!(component, outSnapshot)
      ),
      'rac_component_lifecycle_snapshot_proto',
    );
  }

  reset(): boolean {
    if (!this.ensureExports('reset', ['_rac_model_lifecycle_reset'])) return false;
    this.module._rac_model_lifecycle_reset!();
    return true;
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }

  private callLoad(
    registryHandle: number,
    requestPtr: number,
    requestSize: number,
    outResult: number,
  ): number | Promise<number> {
    if (typeof this.module.ccall === 'function') {
      const result = this.module.ccall(
        'rac_model_lifecycle_load_proto',
        'number',
        ['number', 'number', 'number', 'number'],
        [registryHandle, requestPtr, requestSize, outResult],
        { async: true },
      );
      return result instanceof Promise
        ? result.then((value) => Number(value))
        : Number(result);
    }
    const result = this.module._rac_model_lifecycle_load_proto!(
      registryHandle,
      requestPtr,
      requestSize,
      outResult,
    );
    return result instanceof Promise
      ? result.then((value) => Number(value))
      : Number(result);
  }

  private callUnload(
    requestPtr: number,
    requestSize: number,
    outResult: number,
  ): number | Promise<number> {
    if (typeof this.module.ccall === 'function') {
      const result = this.module.ccall(
        'rac_model_lifecycle_unload_proto',
        'number',
        ['number', 'number', 'number'],
        [requestPtr, requestSize, outResult],
        { async: true },
      );
      return result instanceof Promise
        ? result.then((value) => Number(value))
        : Number(result);
    }
    const result = this.module._rac_model_lifecycle_unload_proto!(
      requestPtr,
      requestSize,
      outResult,
    );
    return result instanceof Promise
      ? result.then((value) => Number(value))
      : Number(result);
  }

  private ensureExports(
    operation: string,
    required: Array<keyof ModelLifecycleModule>,
  ): boolean {
    const missing = this.missingExports(required);
    if (missing.length > 0) {
      logger.warning(`${operation}: module missing lifecycle proto exports: ${missing.join(', ')}`);
      return false;
    }
    return true;
  }

  private missingExports(required: Array<keyof ModelLifecycleModule>): string[] {
    return [
      ...this.bridge().missingProtoBufferExports(),
      ...required.filter((key) => !this.module[key]).map(String),
    ];
  }
}
