// model-abi.ts — typed access to the commons model lifecycle and registry.
//
// Mirrors Swift's `CppBridge.ModelLifecycle` + `CppBridge.ModelRegistry`: every
// call is a generated request message in, a generated result message out. This
// file is the only place that knows the addon's model entry points exist, and it
// is also where the public `ModelCategory` / `InferenceFramework` names are
// translated to and from their proto ordinals.

import { SDKException } from '../errors';
import {
  CurrentModelRequest,
  CurrentModelResult,
  InferenceFramework as ProtoFramework,
  ModelCategory as ProtoCategory,
  ModelCompatibilityRequest,
  ModelCompatibilityResult,
  ModelDeleteResult,
  ModelDiscoveryRequest,
  ModelDiscoveryResult,
  ModelGetRequest,
  ModelGetResult,
  ModelImportRequest,
  ModelImportResult,
  ModelInfo as ProtoModelInfo,
  ModelListRequest,
  ModelListResult,
  ModelLoadRequest,
  ModelLoadResult,
  ModelQuery,
  ModelRegistryRefreshRequest,
  ModelRegistryRefreshResult,
  ModelRegistryStatus,
  ModelUnloadRequest,
  ModelUnloadResult,
  RegisterModelFromUrlRequest,
  RegisterMultiFileModelRequest,
} from '@runanywhere/proto-ts/model_types';
import { ComponentLifecycleSnapshot, SDKComponent } from '@runanywhere/proto-ts/sdk_events';
import type { SDKError } from '@runanywhere/proto-ts/errors';
import type { RaBackend } from './backend';
import { invokeProto } from './proto-abi';
import { InferenceFramework, ModelCategory } from './types';
import type { ModelInfo } from './types';

const CATEGORY_TO_PROTO: Record<ModelCategory, ProtoCategory> = {
  [ModelCategory.LANGUAGE]: ProtoCategory.MODEL_CATEGORY_LANGUAGE,
  [ModelCategory.VISION]: ProtoCategory.MODEL_CATEGORY_VISION,
  [ModelCategory.EMBEDDING]: ProtoCategory.MODEL_CATEGORY_EMBEDDING,
  [ModelCategory.SPEECH_TO_TEXT]: ProtoCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
  [ModelCategory.TEXT_TO_SPEECH]: ProtoCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
  [ModelCategory.VOICE_ACTIVITY]: ProtoCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
  [ModelCategory.RERANK]: ProtoCategory.MODEL_CATEGORY_RERANK,
  [ModelCategory.DIARIZATION]: ProtoCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION,
  [ModelCategory.SEGMENTATION]: ProtoCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION,
  [ModelCategory.IMAGE]: ProtoCategory.MODEL_CATEGORY_IMAGE_GENERATION,
  // LoRA adapters are catalogued by the LoRA registry, not this one; there is no
  // ModelCategory for them, so they list as unspecified rather than as some
  // unrelated modality.
  [ModelCategory.LORA]: ProtoCategory.MODEL_CATEGORY_UNSPECIFIED,
};

const CATEGORY_FROM_PROTO = new Map<ProtoCategory, ModelCategory>(
  (Object.entries(CATEGORY_TO_PROTO) as Array<[ModelCategory, ProtoCategory]>)
    .filter(([, proto]) => proto !== ProtoCategory.MODEL_CATEGORY_UNSPECIFIED)
    .map(([name, proto]) => [proto, name])
);

const FRAMEWORK_TO_PROTO: Record<InferenceFramework, ProtoFramework> = {
  [InferenceFramework.LLAMA_CPP]: ProtoFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
  [InferenceFramework.ONNX]: ProtoFramework.INFERENCE_FRAMEWORK_ONNX,
  [InferenceFramework.SHERPA]: ProtoFramework.INFERENCE_FRAMEWORK_SHERPA,
  [InferenceFramework.QHEXRT]: ProtoFramework.INFERENCE_FRAMEWORK_QHEXRT,
  [InferenceFramework.COREML]: ProtoFramework.INFERENCE_FRAMEWORK_COREML,
};

const FRAMEWORK_FROM_PROTO = new Map<ProtoFramework, InferenceFramework>(
  (Object.entries(FRAMEWORK_TO_PROTO) as Array<[InferenceFramework, ProtoFramework]>).map(
    ([name, proto]) => [proto, name]
  )
);

/** The proto ordinal for a public category name. */
export function categoryToProto(category: ModelCategory): ProtoCategory {
  return CATEGORY_TO_PROTO[category] ?? ProtoCategory.MODEL_CATEGORY_UNSPECIFIED;
}

/** The public category name for a proto ordinal, or undefined when unmapped. */
export function categoryFromProto(category: ProtoCategory): ModelCategory | undefined {
  return CATEGORY_FROM_PROTO.get(category);
}

/** The proto ordinal for a public framework name. */
export function frameworkToProto(framework: InferenceFramework): ProtoFramework {
  return FRAMEWORK_TO_PROTO[framework] ?? ProtoFramework.INFERENCE_FRAMEWORK_UNSPECIFIED;
}

/** The public framework name for a proto ordinal, or undefined when unmapped. */
export function frameworkFromProto(framework: ProtoFramework): InferenceFramework | undefined {
  return FRAMEWORK_FROM_PROTO.get(framework);
}

/**
 * A registry row as the public surface sees it. `downloaded` reads
 * `registry_status`, which the proto comment names as the only durable
 * downloaded-ness signal — a non-empty `local_path` survives file deletion.
 */
export function toPublicModelInfo(model: ProtoModelInfo): ModelInfo {
  return {
    id: model.id,
    name: model.name || model.id,
    category: categoryFromProto(model.category) ?? ModelCategory.LANGUAGE,
    framework: frameworkFromProto(model.framework),
    localPath: model.localPath || undefined,
    downloaded: model.registryStatus === ModelRegistryStatus.MODEL_REGISTRY_STATUS_DOWNLOADED,
    sizeBytes: model.downloadSizeBytes ?? 0,
  };
}

/** Raise a commons-authored error, or return the result when there is none. */
function orThrow<T extends { error?: SDKError | undefined }>(result: T): T {
  if (result.error) throw SDKException.fromProto(result.error);
  return result;
}

/** The commons model layer, bound to one backend. */
export class ModelAbi {
  constructor(private readonly backend: RaBackend) {}

  load(request: ModelLoadRequest): Promise<ModelLoadResult> {
    return invokeProto(
      (bytes) => this.backend.modelLoad(bytes),
      ModelLoadRequest,
      request,
      ModelLoadResult
    );
  }

  resolvePaths(request: ModelLoadRequest): Promise<ModelLoadResult> {
    return invokeProto(
      (bytes) => this.backend.modelResolvePaths(bytes),
      ModelLoadRequest,
      request,
      ModelLoadResult
    );
  }

  unload(request: ModelUnloadRequest): Promise<ModelUnloadResult> {
    return invokeProto(
      (bytes) => this.backend.modelUnload(bytes),
      ModelUnloadRequest,
      request,
      ModelUnloadResult
    );
  }

  current(request: CurrentModelRequest): Promise<CurrentModelResult> {
    return invokeProto(
      (bytes) => this.backend.modelCurrent(bytes),
      CurrentModelRequest,
      request,
      CurrentModelResult
    );
  }

  async register(model: ProtoModelInfo): Promise<ProtoModelInfo> {
    return invokeProto(
      (bytes) => this.backend.modelRegistryRegister(bytes),
      ProtoModelInfo,
      model,
      ProtoModelInfo
    );
  }

  async update(model: ProtoModelInfo): Promise<ProtoModelInfo> {
    return invokeProto(
      (bytes) => this.backend.modelRegistryUpdate(bytes),
      ProtoModelInfo,
      model,
      ProtoModelInfo
    );
  }

  async get(modelId: string): Promise<ProtoModelInfo | null> {
    const result = await invokeProto(
      (bytes) => this.backend.modelRegistryGet(bytes),
      ModelGetRequest,
      { modelId },
      ModelGetResult
    );
    // An unknown id is `found: false` carrying a MODEL_NOT_FOUND envelope, which
    // is an answer rather than a failure — anything that actually went wrong
    // arrives as a rejected promise from the addon's proto-buffer status.
    if (!result.found) return null;
    return orThrow(result).model ?? null;
  }

  async list(query?: ModelQuery): Promise<ProtoModelInfo[]> {
    const result = orThrow(
      await invokeProto(
        (bytes) => this.backend.modelRegistryList(bytes),
        ModelListRequest,
        { query },
        ModelListResult
      )
    );
    return result.models?.models ?? [];
  }

  async remove(modelId: string): Promise<ModelDeleteResult> {
    const reply = await this.backend.modelRegistryRemove(modelId);
    return orThrow(ModelDeleteResult.decode(reply));
  }

  refresh(request: ModelRegistryRefreshRequest): Promise<ModelRegistryRefreshResult> {
    return invokeProto(
      (bytes) => this.backend.modelRegistryRefresh(bytes),
      ModelRegistryRefreshRequest,
      request,
      ModelRegistryRefreshResult
    );
  }

  /**
   * Ask commons whether a model fits this machine. The caller supplies the RAM
   * and disk probes; commons reads the requirement out of the registry row and
   * returns canRun / canFit plus its reasons.
   */
  compatibility(request: ModelCompatibilityRequest): Promise<ModelCompatibilityResult> {
    return invokeProto(
      (bytes) => this.backend.modelCompatibility(bytes),
      ModelCompatibilityRequest,
      request,
      ModelCompatibilityResult
    );
  }

  discover(request: ModelDiscoveryRequest): Promise<ModelDiscoveryResult> {
    return invokeProto(
      (bytes) => this.backend.modelRegistryDiscover(bytes),
      ModelDiscoveryRequest,
      request,
      ModelDiscoveryResult
    );
  }

  /**
   * Adopt a model already on disk. Commons owns what import means — normalize
   * the path, optionally copy it into the managed store, validate the format
   * and expected files, then write the row — which is why this is not
   * `register()` with a path.
   */
  import(request: ModelImportRequest): Promise<ModelImportResult> {
    return invokeProto(
      (bytes) => this.backend.modelRegistryImport(bytes),
      ModelImportRequest,
      request,
      ModelImportResult
    );
  }

  /**
   * What commons' lifecycle store holds for one component. An unloaded
   * component is an answer, not a failure: the snapshot comes back with
   * `COMPONENT_LIFECYCLE_STATE_NOT_LOADED` and no model id.
   */
  async componentSnapshot(component: SDKComponent): Promise<ComponentLifecycleSnapshot> {
    return ComponentLifecycleSnapshot.decode(await this.backend.modelComponentSnapshot(component));
  }

  registerFromUrl(request: RegisterModelFromUrlRequest): Promise<ProtoModelInfo> {
    return invokeProto(
      (bytes) => this.backend.modelRegisterFromUrl(bytes),
      RegisterModelFromUrlRequest,
      request,
      ProtoModelInfo
    );
  }

  registerMultiFile(request: RegisterMultiFileModelRequest): Promise<ProtoModelInfo> {
    return invokeProto(
      (bytes) => this.backend.modelRegisterMultiFile(bytes),
      RegisterMultiFileModelRequest,
      request,
      ProtoModelInfo
    );
  }
}

// `ModelImportRequest` is re-exported as a VALUE, not just a type: `models.import`
// takes the generated message, so a caller needs its `fromPartial` to build one —
// the same reason the storage request messages are values.
export {
  ComponentLifecycleSnapshot,
  ModelImportRequest,
  ModelRegistryStatus,
  SDKComponent,
};
export type { ModelImportResult, ProtoModelInfo };
