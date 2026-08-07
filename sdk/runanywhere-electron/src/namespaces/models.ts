// The models namespace, mirroring Swift `RunAnywhere.models`. Registration,
// download (single-file, multi-file, and archive), load/unload, and the registry
// reads all map onto commons ops; commons owns resolution, the download plan,
// extraction, and the loaded-model state. Generation verbs auto-load through
// `ensureLoaded`, so an app registers its catalog once and then names a model.

import {
  ArchiveType,
  ArchiveStructure,
  CurrentModelRequest,
  CurrentModelResult,
  InferenceFramework,
  ModelCategory,
  ModelFileRole,
  ModelFormat,
  ModelGetRequest,
  ModelGetResult,
  ModelInfo as ProtoModelInfo,
  ModelListRequest,
  ModelListResult,
  ModelLoadRequest,
  ModelLoadResult,
  ModelSource,
  ModelUnloadRequest,
  RegisterModelFromUrlRequest,
  RegisterMultiFileModelRequest,
} from '@runanywhere/proto-ts/model_types';
import {
  DownloadPlanRequest,
  DownloadPlanResult,
  DownloadProgress as ProtoDownloadProgress,
  DownloadStage,
  DownloadStartRequest,
  DownloadStartResult,
  DownloadSubscribeRequest,
} from '@runanywhere/proto-ts/download_service';

import type { RaBackend } from '../backend.js';
import { SDKException } from '../errors.js';
import { bridgeStream } from '../stream.js';
import type { DownloadEvent, ModelFilter, ModelInfo, ModelsState } from '../types.js';

const sleep = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

/** Backend a model runs on. Friendly names mapped to the proto enum. */
export type ModelFramework = 'llamaCpp' | 'onnx' | 'sherpa' | 'qhexrt' | 'coreml' | 'mlx';

/** What a model does. Friendly names mapped to `ModelCategory`. */
export type ModelModality =
  | 'language'
  | 'vision'
  | 'multimodal'
  | 'speechRecognition'
  | 'speechSynthesis'
  | 'embedding'
  | 'voiceActivityDetection'
  | 'speakerDiarization'
  | 'semanticSegmentation'
  | 'imageGeneration';

const FRAMEWORK: Record<ModelFramework, InferenceFramework> = {
  llamaCpp: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
  onnx: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
  sherpa: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
  qhexrt: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
  coreml: InferenceFramework.INFERENCE_FRAMEWORK_COREML,
  mlx: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
};

const CATEGORY: Record<ModelModality, ModelCategory> = {
  language: ModelCategory.MODEL_CATEGORY_LANGUAGE,
  vision: ModelCategory.MODEL_CATEGORY_VISION,
  multimodal: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
  speechRecognition: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
  speechSynthesis: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
  embedding: ModelCategory.MODEL_CATEGORY_EMBEDDING,
  voiceActivityDetection: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
  speakerDiarization: ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION,
  semanticSegmentation: ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION,
  imageGeneration: ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION,
};

const ARCHIVE_TYPE: Record<string, ArchiveType> = {
  zip: ArchiveType.ARCHIVE_TYPE_ZIP,
  'tar.bz2': ArchiveType.ARCHIVE_TYPE_TAR_BZ2,
  'tar.gz': ArchiveType.ARCHIVE_TYPE_TAR_GZ,
  'tar.xz': ArchiveType.ARCHIVE_TYPE_TAR_XZ,
};

const ARCHIVE_STRUCTURE: Record<string, ArchiveStructure> = {
  singleFileNested: ArchiveStructure.ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED,
  directoryBased: ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED,
  nestedDirectory: ArchiveStructure.ARCHIVE_STRUCTURE_NESTED_DIRECTORY,
};

const FILE_ROLE: Record<string, ModelFileRole> = {
  primary: ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL,
  companion: ModelFileRole.MODEL_FILE_ROLE_COMPANION,
  visionProjector: ModelFileRole.MODEL_FILE_ROLE_VISION_PROJECTOR,
  tokenizer: ModelFileRole.MODEL_FILE_ROLE_TOKENIZER,
  config: ModelFileRole.MODEL_FILE_ROLE_CONFIG,
  vocabulary: ModelFileRole.MODEL_FILE_ROLE_VOCABULARY,
};

/** One file of a multi-file model. Mirrors Swift `RAModelFileDescriptor`. */
export interface ModelFileSpec {
  url: string;
  filename: string;
  role?: keyof typeof FILE_ROLE;
  isRequired?: boolean;
  sizeBytes?: number;
}

interface RegisterCommon {
  id?: string;
  name?: string;
  framework?: ModelFramework;
  modality?: ModelModality;
  memoryRequiredBytes?: number;
  downloadSizeBytes?: number;
  contextLength?: number;
  supportsThinking?: boolean;
}

/** A model to make loadable by id, mirroring the Swift `ModelRegistration` factories. */
export type ModelRegistrationSpec =
  | ({ kind: 'local'; path: string } & RegisterCommon)
  | ({ kind: 'url'; url: string } & RegisterCommon)
  | ({ kind: 'archive'; url: string; structure: keyof typeof ARCHIVE_STRUCTURE; archiveType?: keyof typeof ARCHIVE_TYPE } & RegisterCommon)
  | ({ kind: 'multiFile'; files: ModelFileSpec[] } & RegisterCommon);

/** The registration builders (mirrors Swift `ModelRegistration.url/.archive/.multiFile`, plus a local path). */
export const ModelRegistration = {
  local(path: string, opts: RegisterCommon = {}): ModelRegistrationSpec {
    return { kind: 'local', path, ...opts };
  },
  url(url: string, opts: RegisterCommon = {}): ModelRegistrationSpec {
    return { kind: 'url', url, ...opts };
  },
  archive(
    url: string,
    structure: keyof typeof ARCHIVE_STRUCTURE,
    opts: RegisterCommon & { archiveType?: keyof typeof ARCHIVE_TYPE } = {}
  ): ModelRegistrationSpec {
    return { kind: 'archive', url, structure, ...opts };
  },
  multiFile(files: ModelFileSpec[], opts: RegisterCommon = {}): ModelRegistrationSpec {
    return { kind: 'multiFile', files, ...opts };
  },
};

/** Per-load overrides. */
export interface LoadOptions {
  contextLength?: number;
  threads?: number;
  forceReload?: boolean;
  /** Pin the engine explicitly (overrides the registry). Needed when a local
   * rescan can't infer it — e.g. a bare model.onnx that would otherwise route to
   * the highest-priority engine (llama.cpp) instead of onnx. */
  framework?: ModelFramework;
  /** Pin the component category explicitly (overrides the registry). */
  category?: ModelModality;
}

export interface ModelsNamespace {
  /** Make a model loadable by id (single-file url, archive, or multi-file). */
  register(spec: ModelRegistrationSpec): Promise<ModelInfo>;
  /** All registered models, optionally filtered. */
  list(filter?: ModelFilter): Promise<ModelInfo[]>;
  /** A single registered model, or null. */
  get(id: string): Promise<ModelInfo | null>;
  /** Download a registered model, streaming progress until it completes. */
  download(id: string): AsyncIterableIterator<DownloadEvent>;
  /** Delete a model's files and reset its registry path. */
  delete(id: string): Promise<void>;
  /** Load a registered (and downloaded) model into its component. */
  load(id: string, options?: LoadOptions): Promise<ModelInfo>;
  /** Unload the model in a component (defaults to whatever is loaded). */
  unload(id?: string): Promise<void>;
  /** Loaded models and storage snapshot. */
  state(): Promise<ModelsState>;
}

function toModelInfo(m: ProtoModelInfo): ModelInfo {
  return {
    id: m.id,
    name: m.name || m.id,
    localPath: m.localPath ?? '',
    downloaded: m.isDownloaded === true,
  };
}

function frameworkOf(spec: RegisterCommon): InferenceFramework {
  return spec.framework
    ? FRAMEWORK[spec.framework]
    : InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED;
}

function categoryOf(spec: RegisterCommon): ModelCategory {
  return spec.modality ? CATEGORY[spec.modality] : ModelCategory.MODEL_CATEGORY_LANGUAGE;
}

/** Resolve `modelId` into its component: resident, else download-if-needed, then load. */
export async function ensureLoaded(
  backend: RaBackend,
  models: ModelsNamespace,
  modelId: string,
  category: ModelCategory
): Promise<void> {
  const current = CurrentModelResult.decode(
    await backend.currentModel(
      CurrentModelRequest.encode(CurrentModelRequest.fromPartial({ category })).finish()
    )
  );
  if (current.model?.id === modelId) return;
  const info = await models.get(modelId);
  if (info && !info.downloaded) {
    for await (const ev of models.download(modelId)) {
      if (ev.type === 'failed') throw SDKException.modelLoadFailed(modelId, new Error(ev.message));
    }
  }
  await models.load(modelId);
}

export function createModelsNamespace(backend: RaBackend): ModelsNamespace {
  async function findById(id: string): Promise<ProtoModelInfo | null> {
    const res = ModelGetResult.decode(
      await backend.modelGet(ModelGetRequest.encode(ModelGetRequest.fromPartial({ modelId: id })).finish())
    );
    return res.model ?? null;
  }

  const ns: ModelsNamespace = {
    async register(spec) {
      // The Electron SDK requires an explicit id (the catalog always has one).
      // Commons id-derivation for bare HF refs is not relied on here, so a
      // registered model is always addressable by the id the caller chose.
      if (!spec.id) throw SDKException.invalidInput('models.register requires an id');
      const id = spec.id;
      if (spec.kind === 'local') {
        // Infer the on-disk format from the framework: ONNX models are .onnx,
        // sherpa models are extracted folders, everything else is a GGUF file.
        const format =
          spec.framework === 'onnx'
            ? ModelFormat.MODEL_FORMAT_ONNX
            : spec.framework === 'sherpa'
              ? ModelFormat.MODEL_FORMAT_FOLDER
              : ModelFormat.MODEL_FORMAT_GGUF;
        const info = ProtoModelInfo.fromPartial({
          id,
          name: spec.name ?? id,
          category: categoryOf(spec),
          framework: spec.framework ? FRAMEWORK[spec.framework] : InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
          format,
          localPath: spec.path,
          source: ModelSource.MODEL_SOURCE_LOCAL,
          isDownloaded: true,
          supportsThinking: spec.supportsThinking ?? false,
        });
        await backend.registerModel(ProtoModelInfo.encode(info).finish());
        return { id, name: spec.name ?? id, localPath: spec.path, downloaded: true };
      }
      if (spec.kind === 'url') {
        await backend.registerModelFromUrl(
          RegisterModelFromUrlRequest.encode(
            RegisterModelFromUrlRequest.fromPartial({
              id,
              url: spec.url,
              ...(spec.name ? { name: spec.name } : {}),
              framework: frameworkOf(spec),
              category: categoryOf(spec),
              ...(spec.memoryRequiredBytes ? { memoryRequiredBytes: spec.memoryRequiredBytes } : {}),
              ...(spec.downloadSizeBytes ? { downloadSizeBytes: spec.downloadSizeBytes } : {}),
              ...(spec.contextLength ? { contextLength: spec.contextLength } : {}),
              supportsThinking: spec.supportsThinking ?? false,
            })
          ).finish()
        );
      } else if (spec.kind === 'multiFile') {
        await backend.registerMultiFile(
          RegisterMultiFileModelRequest.encode(
            RegisterMultiFileModelRequest.fromPartial({
              id,
              ...(spec.name ? { name: spec.name } : {}),
              framework: frameworkOf(spec),
              category: categoryOf(spec),
              files: spec.files.map((f) => ({
                url: f.url,
                filename: f.filename,
                isRequired: f.isRequired ?? true,
                role: f.role ? FILE_ROLE[f.role] : ModelFileRole.MODEL_FILE_ROLE_UNSPECIFIED,
                ...(f.sizeBytes ? { sizeBytes: f.sizeBytes } : {}),
              })),
              ...(spec.downloadSizeBytes ? { downloadSizeBytes: spec.downloadSizeBytes } : {}),
              ...(spec.contextLength ? { contextLength: spec.contextLength } : {}),
              supportsThinking: spec.supportsThinking ?? false,
            })
          ).finish()
        );
      } else {
        // archive: register a ModelInfo carrying an archive artifact.
        const info = ProtoModelInfo.fromPartial({
          id,
          name: spec.name ?? id,
          category: categoryOf(spec),
          framework: frameworkOf(spec),
          format: ModelFormat.MODEL_FORMAT_UNSPECIFIED,
          downloadUrl: spec.url,
          source: ModelSource.MODEL_SOURCE_REMOTE,
          supportsThinking: spec.supportsThinking ?? false,
          archive: {
            type: spec.archiveType ? ARCHIVE_TYPE[spec.archiveType] : archiveTypeFromUrl(spec.url),
            structure: ARCHIVE_STRUCTURE[spec.structure],
          },
        });
        await backend.registerModel(ProtoModelInfo.encode(info).finish());
      }
      return { id, name: spec.name ?? id, localPath: '', downloaded: false };
    },

    async list(filter) {
      const req = ModelListRequest.fromPartial({
        query: {
          ...(filter?.category ? { category: CATEGORY[filter.category as ModelModality] } : {}),
          ...(filter?.downloadedOnly ? { downloadedOnly: true } : {}),
        },
      });
      const res = ModelListResult.decode(await backend.modelList(ModelListRequest.encode(req).finish()));
      let out = (res.models?.models ?? []).map(toModelInfo);
      if (filter?.search) {
        const q = filter.search.toLowerCase();
        out = out.filter((m) => m.id.toLowerCase().includes(q) || m.name.toLowerCase().includes(q));
      }
      return out;
    },

    async get(id) {
      const m = await findById(id);
      return m ? toModelInfo(m) : null;
    },

    download(id) {
      return bridgeStream<DownloadEvent>(async (sink) => {
        sink.push({ type: 'started', modelId: id });
        // Plan first (commons needs the model metadata to build the file plan),
        // then start with that plan, then poll — same order as Swift.
        const info = await findById(id);
        if (!info) {
          sink.push({ type: 'failed', message: `model not registered: ${id}` });
          sink.end();
          return;
        }
        const plan = DownloadPlanResult.decode(
          await backend.downloadPlan(
            DownloadPlanRequest.encode(DownloadPlanRequest.fromPartial({ modelId: id, model: info })).finish()
          )
        );
        if (!plan.canStart) {
          sink.push({ type: 'failed', message: plan.error?.message || 'download cannot start' });
          sink.end();
          return;
        }
        const start = DownloadStartResult.decode(
          await backend.downloadStart(
            DownloadStartRequest.encode(
              DownloadStartRequest.fromPartial({ modelId: id, plan, updateRegistryOnCompletion: true })
            ).finish()
          )
        );
        if (!start.accepted) {
          sink.push({ type: 'failed', message: start.error?.message || 'download not accepted' });
          sink.end();
          return;
        }
        const subscribe = DownloadSubscribeRequest.encode(
          DownloadSubscribeRequest.fromPartial({ modelId: id, taskId: start.taskId })
        ).finish();
        for (;;) {
          const p = ProtoDownloadProgress.decode(await backend.downloadProgressPoll(subscribe));
          if (p.error?.message) {
            sink.push({ type: 'failed', message: p.error.message });
            break;
          }
          if (p.stage === DownloadStage.DOWNLOAD_STAGE_EXTRACTING) {
            sink.push({ type: 'extracting', percent: p.overallProgress * 100 });
          } else if (p.stage === DownloadStage.DOWNLOAD_STAGE_COMPLETED) {
            const m = await findById(id);
            sink.push({
              type: 'completed',
              model: m ? toModelInfo(m) : { id, name: id, localPath: p.localPath, downloaded: true },
            });
            break;
          } else {
            sink.push({
              type: 'progress',
              modelId: id,
              receivedBytes: p.bytesDownloaded,
              totalBytes: p.totalBytes,
              percent: p.overallProgress * 100,
            });
          }
          await sleep(250);
        }
        sink.end();
      });
    },

    async delete(id) {
      await backend.deleteModel(id);
    },

    async load(id, options) {
      const info = await findById(id);
      // Caller-pinned framework/category win over the registry (a local rescan can
      // mis-route a bare .onnx to llama.cpp); else use the registry; else default.
      const framework = options?.framework
        ? FRAMEWORK[options.framework]
        : info?.framework || InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED;
      const category = options?.category
        ? CATEGORY[options.category]
        : info?.category || ModelCategory.MODEL_CATEGORY_LANGUAGE;
      const req = ModelLoadRequest.fromPartial({
        modelId: id,
        framework,
        category,
        validateAvailability: false,
        ...(options?.contextLength ? { contextLength: options.contextLength } : {}),
        ...(options?.forceReload ? { forceReload: true } : {}),
      });
      const res = ModelLoadResult.decode(await backend.loadModel(ModelLoadRequest.encode(req).finish()));
      if (res.error?.message) throw SDKException.modelLoadFailed(id, new Error(res.error.message));
      return { id, name: info?.name || id, localPath: res.resolvedPath ?? '', downloaded: true };
    },

    async unload(id) {
      await backend.unloadModel(
        ModelUnloadRequest.encode(ModelUnloadRequest.fromPartial(id ? { modelId: id } : {})).finish()
      );
    },

    async state() {
      const res = ModelListResult.decode(
        await backend.modelList(
          ModelListRequest.encode(ModelListRequest.fromPartial({ query: { downloadedOnly: true } })).finish()
        )
      );
      return {
        loaded: [],
        storageUsedBytes: (res.models?.models ?? []).reduce((n, m) => n + (m.downloadSizeBytes || 0), 0),
        storageFreeBytes: 0,
      };
    },
  };
  return ns;
}

function archiveTypeFromUrl(url: string): ArchiveType {
  const lower = url.toLowerCase();
  if (lower.endsWith('.tar.bz2')) return ArchiveType.ARCHIVE_TYPE_TAR_BZ2;
  if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) return ArchiveType.ARCHIVE_TYPE_TAR_GZ;
  if (lower.endsWith('.tar.xz')) return ArchiveType.ARCHIVE_TYPE_TAR_XZ;
  if (lower.endsWith('.zip')) return ArchiveType.ARCHIVE_TYPE_ZIP;
  return ArchiveType.ARCHIVE_TYPE_UNSPECIFIED;
}
