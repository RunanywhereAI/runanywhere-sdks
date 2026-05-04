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
import { SDKLogger } from '../Foundation/SDKLogger';
import { ProtoWasmBridge, type ProtoWasmModule } from '../runtime/ProtoWasm';

const logger = new SDKLogger('ModelLifecycleAdapter');

type DefaultModuleListener = (adapter: ModelLifecycleAdapter) => void;

export interface ModelLifecycleModule extends ProtoWasmModule {
  _rac_get_model_registry?(): number;
  _rac_model_lifecycle_load_proto?(
    registryHandle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_model_lifecycle_unload_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
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
      (requestPtr, requestSize, outResult) => (
        this.module._rac_model_lifecycle_load_proto!(
          registryHandle,
          requestPtr,
          requestSize,
          outResult,
        )
      ),
      'rac_model_lifecycle_load_proto',
    );
  }

  unload(request: ProtoModelUnloadRequest): ProtoModelUnloadResult | null {
    if (!this.ensureExports('unload', ['_rac_model_lifecycle_unload_proto'])) {
      return null;
    }

    return this.bridge().withEncodedRequest(
      request,
      ModelUnloadRequest,
      ModelUnloadResult,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_model_lifecycle_unload_proto!(
          requestPtr,
          requestSize,
          outResult,
        )
      ),
      'rac_model_lifecycle_unload_proto',
    );
  }

  currentModel(
    request: ProtoCurrentModelRequest = {},
  ): ProtoCurrentModelResult | null {
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
