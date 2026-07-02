import {
  CurrentModelRequest,
  CurrentModelResult,
  InferenceFramework,
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
import { clientFor, type Capability } from '../runtime/HostRegistry';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

function frameworkCapability(framework: InferenceFramework | string): Capability | null {
  if (typeof framework === 'string') {
    const name = framework.toLowerCase();
    if (name === 'llamacpp' || name === 'onnx' || name === 'sherpa') return name;
    return null;
  }
  switch (framework) {
    case InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP: return 'llamacpp';
    case InferenceFramework.INFERENCE_FRAMEWORK_ONNX: return 'onnx';
    case InferenceFramework.INFERENCE_FRAMEWORK_SHERPA: return 'sherpa';
    case InferenceFramework.INFERENCE_FRAMEWORK_PIPER_TTS: return 'sherpa';
    default: return null;
  }
}

export class ModelLifecycleAdapter {
  static tryDefault(): ModelLifecycleAdapter | null {
    const client = clientFor('commons');
    return client ? new ModelLifecycleAdapter(client) : null;
  }

  static tryDefaultForFramework(
    framework: InferenceFramework | string | undefined | null,
  ): ModelLifecycleAdapter | null {
    if (framework !== undefined && framework !== null && framework !== '') {
      const cap = frameworkCapability(framework);
      const client = cap ? clientFor(cap) : null;
      if (client) return new ModelLifecycleAdapter(client);
    }
    return ModelLifecycleAdapter.tryDefault();
  }

  private constructor(private readonly client: WorkerProtoClient) {}

  async load(request: ProtoModelLoadRequest): Promise<ProtoModelLoadResult | null> {
    const registryHandle = await this.client.callRc('rac_get_model_registry', []);
    if (!registryHandle) return null;
    const bytes = ModelLoadRequest.encode(request).finish();
    return this.client.callProto(
      'rac_model_lifecycle_load_proto',
      [Arg.num(registryHandle), Arg.bytes(bytes), Arg.outProto()],
      ModelLoadResult,
    );
  }

  unload(request: ProtoModelUnloadRequest): Promise<ProtoModelUnloadResult | null> {
    const bytes = ModelUnloadRequest.encode(request).finish();
    return this.client.callProto(
      'rac_model_lifecycle_unload_proto',
      [Arg.bytes(bytes), Arg.outProto()],
      ModelUnloadResult,
    );
  }

  currentModel(
    request: ProtoCurrentModelRequest = { includeModelMetadata: false },
  ): Promise<ProtoCurrentModelResult | null> {
    const bytes = CurrentModelRequest.encode(request).finish();
    return this.client.callProto(
      'rac_model_lifecycle_current_model_proto',
      [Arg.bytes(bytes), Arg.outProto()],
      CurrentModelResult,
    );
  }

  componentSnapshot(component: ProtoSDKComponent): Promise<ProtoComponentLifecycleSnapshot | null> {
    return this.client.callProto(
      'rac_component_lifecycle_snapshot_proto',
      [Arg.num(component), Arg.outProto()],
      ComponentLifecycleSnapshot,
    );
  }

  async reset(): Promise<void> {
    await this.client.callRc('rac_model_lifecycle_reset', []);
  }
}
