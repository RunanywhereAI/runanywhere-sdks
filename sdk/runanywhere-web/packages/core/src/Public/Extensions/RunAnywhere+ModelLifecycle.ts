import type {
  CurrentModelRequest,
  CurrentModelResult,
  ModelCategory,
  ModelInfo,
  ModelLoadRequest,
  ModelLoadResult,
  ModelUnloadRequest,
  ModelUnloadResult,
} from '@runanywhere/proto-ts/model_types';
import {
  InferenceFramework,
  ModelCategory as ModelCategoryEnum,
  ModelInfo as ModelInfoCodec,
  ModelLoadRequest as ModelLoadRequestCodec,
  ModelLoadResult as ModelLoadResultCodec,
  ModelUnloadRequest as ModelUnloadRequestCodec,
} from '@runanywhere/proto-ts/model_types';
import type {
  ComponentLifecycleSnapshot,
  SDKComponent,
} from '@runanywhere/proto-ts/sdk_events';
import { ComponentLifecycleState } from '@runanywhere/proto-ts/component_types';
import { ModelLifecycleAdapter } from '../../Adapters/ModelLifecycleAdapter.js';
import { prepareModelLoad, recoverModelLoadFailure } from '../../Foundation/RuntimeConfig.js';
import { ProtoErrorCode, SDKException } from '../../Foundation/SDKException.js';
import { ModelRegistry } from './RunAnywhere+ModelRegistry.js';
import { OPFSBridge } from '../../Infrastructure/OPFSBridge.js';
import {
  frameworkOPFSDir,
  isExtractedDirectoryArtifact,
  primaryFilenameFromModel,
} from '../../Infrastructure/FrameworkOPFSPaths.js';
import {
  getAllRegisteredModules,
  getModuleForModel,
  recordModelLifecycle,
} from '../../runtime/EmscriptenModule.js';
import type { EmscriptenRunanywhereModule } from '../../runtime/EmscriptenModule.js';
import { getActiveBackendWorkerHost } from '../../runtime/BackendWorkerHost.js';
import {
  clearModelOwnedByBackendWorker,
  isModelOwnedByBackendWorker,
  listBackendWorkerOwnedModels,
  markModelOwnedByBackendWorker,
} from '../../runtime/BackendWorkerModelOwnership.js';

export type {
  CurrentModelRequest,
  CurrentModelResult,
  ModelLoadRequest,
  ModelLoadResult,
  ModelUnloadRequest,
  ModelUnloadResult,
} from '@runanywhere/proto-ts/model_types';
export type {
  ComponentLifecycleEvent,
  ComponentLifecycleSnapshot,
  SDKComponent,
} from '@runanywhere/proto-ts/sdk_events';
export { ComponentLifecycleState } from '@runanywhere/proto-ts/component_types';

function requireAdapter(
  framework?: InferenceFramework | null,
): ModelLifecycleAdapter {
  const adapter = (framework !== undefined && framework !== null)
    ? ModelLifecycleAdapter.tryDefaultForFramework(framework)
    : ModelLifecycleAdapter.tryDefault();
  if (!adapter) {
    throw SDKException.backendNotAvailable(
      'ModelLifecycle',
      'RunAnywhere model lifecycle proto adapter is not installed. Register a backend WASM module (e.g. LlamaCPP.register()) during app init.',
    );
  }
  return adapter;
}

function lifecycleModuleAsEmscripten(
  adapter: ModelLifecycleAdapter,
): EmscriptenRunanywhereModule {
  return adapter.boundModule as unknown as EmscriptenRunanywhereModule;
}

function isBackendWorkerEligibleLLM(
  model: ModelInfo | null,
  request: ModelLoadRequest,
): boolean {
  const framework = model?.framework ?? request.framework;
  if (
    framework !== undefined
    && framework !== null
    && framework !== InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN
    && framework !== InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP
  ) {
    return false;
  }
  const category = model?.category ?? request.category;
  return (
    category === ModelCategoryEnum.MODEL_CATEGORY_LANGUAGE
    || category === ModelCategoryEnum.MODEL_CATEGORY_VISION
    || category === ModelCategoryEnum.MODEL_CATEGORY_MULTIMODAL
    || category === undefined
  );
}

function onnxWorkerModality(
  model: ModelInfo | null,
  request: ModelLoadRequest,
): 'stt' | 'tts' | 'vad' | 'embeddings' | null {
  const category = model?.category ?? request.category;
  switch (category) {
    case ModelCategoryEnum.MODEL_CATEGORY_SPEECH_RECOGNITION:
      return 'stt';
    case ModelCategoryEnum.MODEL_CATEGORY_SPEECH_SYNTHESIS:
      return 'tts';
    case ModelCategoryEnum.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
      return 'vad';
    case ModelCategoryEnum.MODEL_CATEGORY_EMBEDDING:
      return 'embeddings';
    default:
      return null;
  }
}

function hydratePathsForModel(model: ModelInfo | null): string[] {
  if (!model?.localPath) return [];
  const files = model.multiFile?.files ?? [];
  if (files.length > 1) {
    return files
      .map((file) => (file.filename ? `${model.localPath}/${file.filename}` : ''))
      .filter(Boolean);
  }
  return [model.localPath];
}

function currentModelFromBackendWorker(
  request: CurrentModelRequest,
): CurrentModelResult | null {
  const owned = listBackendWorkerOwnedModels();
  if (owned.length === 0) return null;

  for (const entry of owned) {
    const model = safeGetModelSnapshot(entry.modelId);
    if (!model) continue;
    if (
      request.category !== undefined
      && request.category !== null
      && model.category !== undefined
      && model.category !== request.category
    ) {
      continue;
    }
    if (
      request.framework !== undefined
      && request.framework !== null
      && request.framework !== InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN
      && model.framework !== undefined
      && model.framework !== request.framework
    ) {
      continue;
    }
    return {
      modelId: entry.modelId,
      model: request.includeModelMetadata ? model : undefined,
      loadedAtUnixMs: entry.loadedAtUnixMs,
      found: true,
      errorMessage: '',
      category: model.category ?? ModelCategoryEnum.MODEL_CATEGORY_UNSPECIFIED,
      framework: model.framework ?? InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN,
      resolvedPath: model.localPath ?? '',
      resolvedArtifacts: model.multiFile?.files ?? [],
    };
  }
  return null;
}

async function loadModelViaBackendWorker(
  request: ModelLoadRequest,
  model: ModelInfo | null,
  adapter: ModelLifecycleAdapter,
): Promise<ModelLoadResult | null> {
  // Prefer an explicit snapshot, else the live registry entry. Derive backend
  // from the resolved model so a null snapshot cannot force ONNX STT onto the
  // llamacpp worker.
  const resolved = model ?? (
    request.modelId ? ModelRegistry.getModel(request.modelId) : null
  );
  const modality = onnxWorkerModality(resolved, request);
  const backendId = modality ? 'onnx' : 'llamacpp';
  const host = getActiveBackendWorkerHost(backendId);
  if (!host || (!modality && !isBackendWorkerEligibleLLM(resolved, request))) return null;
  if (!resolved) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_MODEL_NOT_FOUND,
      `model not found in registry: ${request.modelId}`,
      'loadModel',
    );
  }

  const requestBytes = ModelLoadRequestCodec.encode(request).finish();
  const modelInfoBytes = ModelInfoCodec.encode(resolved).finish();
  const response = await host.loadModel(
    modality ?? 'llm',
    {
      requestBytes,
      modelInfoBytes,
      hydratePaths: hydratePathsForModel(resolved),
    },
  ) as { resultBytes?: Uint8Array };
  if (!response?.resultBytes) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_MODEL_LOAD_FAILED,
      'BackendWorker model load returned no result bytes',
      'loadModel',
    );
  }
  const result = ModelLoadResultCodec.decode(response.resultBytes);
  if (result.success) {
    markModelOwnedByBackendWorker(request.modelId, backendId);
    recordModelLifecycle(request.modelId, lifecycleModuleAsEmscripten(adapter), true);
  }
  return result;
}

function registeredLifecycleAdapters(): ModelLifecycleAdapter[] {
  return getAllRegisteredModules().map((module) => (
    ModelLifecycleAdapter.fromModule(module)
  ));
}

/**
 * Resolve a model-specific unload to the WASM that owns its framework.
 *
 * Every backend has a private `g_loaded` map. The model registry is mirrored
 * across modules, so its framework is the durable ownership signal even after
 * another backend becomes the legacy default. Requests without an owner
 * signal (category-only, unknown model, or unscoped unload-all) must fan out.
 */
function adaptersForUnload(request: ModelUnloadRequest): ModelLifecycleAdapter[] {
  const ownedModule = request.modelId ? getModuleForModel(request.modelId) : null;
  if (ownedModule) {
    return [ModelLifecycleAdapter.fromModule(
      ownedModule as unknown as Parameters<typeof ModelLifecycleAdapter.fromModule>[0],
    )];
  }
  const snapshot = request.modelId ? safeGetModelSnapshot(request.modelId) : null;
  const framework = snapshot?.framework ?? request.framework;
  if (
    framework !== undefined
    && framework !== null
    && framework !== InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN
  ) {
    return [requireAdapter(framework)];
  }

  const registered = registeredLifecycleAdapters();
  return registered.length > 0 ? registered : [requireAdapter()];
}

function aggregateUnloadResults(
  results: readonly (ModelUnloadResult | null)[],
): ModelUnloadResult | null {
  const present = results.filter((result): result is ModelUnloadResult => result !== null);
  if (present.length === 0) return null;
  if (present.length === 1) return present[0];

  const success = present.some((result) => result.success);
  const unloadedModelIds = Array.from(new Set(
    present.flatMap((result) => result.unloadedModelIds),
  )).sort((left, right) => left.localeCompare(right));
  const warnings = Array.from(new Set(
    present.flatMap((result) => result.warnings),
  )).sort((left, right) => left.localeCompare(right));
  const errors = Array.from(new Set(
    present.map((result) => result.errorMessage).filter((message) => message.length > 0),
  )).sort((left, right) => left.localeCompare(right));

  return {
    success,
    unloadedModelIds,
    errorMessage: success ? '' : errors.join('; '),
    unloadedAtUnixMs: Math.max(...present.map((result) => result.unloadedAtUnixMs)),
    warnings,
  };
}

function unloadAcrossAdapters(request: ModelUnloadRequest): ModelUnloadResult | null {
  const results: Array<ModelUnloadResult | null> = [];
  let firstError: unknown;
  for (const adapter of adaptersForUnload(request)) {
    try {
      const result = adapter.unload(request);
      results.push(result);
      if (result?.success) {
        for (const modelId of result.unloadedModelIds) {
          recordModelLifecycle(modelId, lifecycleModuleAsEmscripten(adapter), false);
        }
      }
    } catch (error) {
      firstError ??= error;
    }
  }
  if (firstError !== undefined) throw firstError;
  return aggregateUnloadResults(results);
}

async function unloadAcrossAdaptersAsync(
  request: ModelUnloadRequest,
): Promise<ModelUnloadResult | null> {
  const results: Array<ModelUnloadResult | null> = [];
  let firstError: unknown;
  // Keep cleanup sequential: each Emscripten module owns independent native
  // state, and deterministic teardown is more important than parallelism here.
  for (const adapter of adaptersForUnload(request)) {
    try {
      const result = await adapter.unloadAsync(request);
      results.push(result);
      if (result?.success) {
        for (const modelId of result.unloadedModelIds) {
          recordModelLifecycle(modelId, lifecycleModuleAsEmscripten(adapter), false);
        }
      }
    } catch (error) {
      firstError ??= error;
    }
  }
  if (firstError !== undefined) throw firstError;
  return aggregateUnloadResults(results);
}

/**
 * Fan a category-only unload out to worker-resident models.
 *
 * A category-only async request (no `modelId`, `unloadAll:false`) never
 * satisfies the modelId/unloadAll worker-dispatch guard in `unloadModelAsync`,
 * so a model of that category living in a BackendWorker (e.g. ONNX embeddings
 * in the onnx worker) would stay loaded while the main-thread adapters report
 * success. Dispatch the same category request to every active worker that owns
 * a model of the requested category, then drop those ownership records.
 */
async function unloadCategoryAcrossWorkers(request: ModelUnloadRequest): Promise<void> {
  if (request.modelId || request.unloadAll) return;
  const { category } = request;
  if (category === undefined || category === ModelCategoryEnum.MODEL_CATEGORY_UNSPECIFIED) return;

  const idsByBackend = new Map<'llamacpp' | 'onnx', string[]>();
  for (const owned of listBackendWorkerOwnedModels()) {
    if (safeGetModelSnapshot(owned.modelId)?.category !== category) continue;
    const ids = idsByBackend.get(owned.backendId) ?? [];
    ids.push(owned.modelId);
    idsByBackend.set(owned.backendId, ids);
  }
  if (idsByBackend.size === 0) return;

  const requestBytes = ModelUnloadRequestCodec.encode(request).finish();
  for (const [backendId, modelIds] of idsByBackend) {
    const host = getActiveBackendWorkerHost(backendId);
    if (!host) continue;
    await host.unloadModel(backendId === 'onnx' ? 'stt' : 'llm', { requestBytes });
    for (const modelId of modelIds) clearModelOwnedByBackendWorker(modelId, backendId);
  }
}

async function resolveLocalPathFromOpfs(model: ModelInfo): Promise<string | null> {
  if (model.localPath) return model.localPath;

  const frameworkDir = frameworkOPFSDir(model.framework as InferenceFramework);
  if (!frameworkDir) return null;

  const modelDir = `/opfs/RunAnywhere/Models/${frameworkDir}/${model.id}`;
  const isMultiFile = (model.multiFile?.files?.length ?? 0) > 1;
  // Whisper/Piper (and other Sherpa archives) land as extracted directories;
  // the .tar.gz primary name from downloadUrl is deleted after unpack.
  if (isExtractedDirectoryArtifact(model) || isMultiFile) {
    const hasDir = await OPFSBridge.directoryHasArtifacts([
      'RunAnywhere',
      'Models',
      frameworkDir,
      model.id,
    ]);
    return hasDir ? modelDir : null;
  }

  const filename = primaryFilenameFromModel(model);
  if (!filename) return null;

  const opfsPath = `${modelDir}/${filename}`;
  if (!(await OPFSBridge.exists(opfsPath))) return null;
  if (!(await isOpfsArtifactComplete(opfsPath, expectedDownloadBytes(model)))) return null;
  return opfsPath;
}

/** Expected on-disk payload size for completeness checks after interrupted downloads. */
function expectedDownloadBytes(model: ModelInfo): number {
  const fromFiles = (model.multiFile?.files ?? []).reduce(
    (total, file) => total + Math.max(0, Number(file.sizeBytes ?? 0)),
    0,
  );
  return Math.max(0, Number(model.downloadSizeBytes ?? 0), fromFiles);
}

/**
 * True when OPFS holds enough of the payload to treat the download as finished.
 * Uses the same 80% threshold as commons `validate_downloaded_sizes` so a
 * mid-refresh partial never masquerades as a ready model.
 */
async function isOpfsArtifactComplete(path: string, expectedBytes: number): Promise<boolean> {
  const size = await OPFSBridge.fileSize(path);
  if (size <= 0) return false;
  if (expectedBytes <= 0) return true;
  return size * 5 >= expectedBytes * 4;
}

function opfsSegmentsFromPath(path: string): string[] | null {
  if (!path.startsWith('/opfs/')) return null;
  const segments = path.slice('/opfs/'.length).split('/').filter(Boolean);
  return segments.length > 0 ? segments : null;
}

async function assertDownloadedArtifactReady(model: ModelInfo): Promise<void> {
  const localPath = model.localPath;
  if (!localPath) return;
  const expected = expectedDownloadBytes(model);
  const files = model.multiFile?.files ?? [];
  if (files.length > 1) {
    for (const file of files) {
      if (!file.filename) continue;
      const filePath = `${localPath}/${file.filename}`;
      const fileExpected = Math.max(0, Number(file.sizeBytes ?? 0));
      if (!(await OPFSBridge.exists(filePath))
        || !(await isOpfsArtifactComplete(filePath, fileExpected))) {
        throw new Error(
          `Model download is incomplete for '${file.filename}'. `
          + 'Tap Retry to finish downloading before using this model.',
        );
      }
    }
    return;
  }

  // Archive-extracted speech models (Whisper/Piper) set localPath to a
  // directory. OPFS fileSize() on a directory is always 0, which previously
  // failed Voice AI setup with "incomplete (0 of ~N bytes)" even after a
  // successful extract.
  const segments = opfsSegmentsFromPath(localPath);
  if (segments && await OPFSBridge.isOPFSDirectory(segments)) {
    if (!(await OPFSBridge.directoryHasArtifacts(segments))) {
      throw new Error(
        `Model download is incomplete (extracted folder is empty). `
        + 'Tap Retry to finish downloading before using this model.',
      );
    }
    return;
  }

  if (!(await OPFSBridge.exists(localPath))
    || !(await isOpfsArtifactComplete(localPath, expected))) {
    const actual = await OPFSBridge.fileSize(localPath);
    throw new Error(
      `Model download is incomplete`
      + (expected > 0 ? ` (${actual} of ~${expected} bytes)` : '')
      + '. Tap Retry to finish downloading before using this model.',
    );
  }
}

function isIncompleteDownloadError(err: unknown): boolean {
  const message = err instanceof Error ? err.message : String(err);
  return /incomplete|interrupted|not found in browser storage|is empty in browser storage/i.test(
    message,
  );
}

// Web-internal lifecycle namespace. The cross-SDK canonical contract lives on
// `RunAnywhere.{loadModel,unloadModel,currentModel,componentLifecycleSnapshot}`
// (top-level, mirroring Swift's source-of-truth surface). The extras exposed
// below — `supportsNativeLifecycle`, `loadModelAsync`, `unloadModelAsync`,
// `unloadAllModels`, `isLoaded`, `isComponentReady`, `reset` — are Web-only
// helpers required by the OPFS/MEMFS async hydration model and the
// multi-WASM module fan-out (LlamaCPP + ONNX private heaps). They are NOT
// part of the portable cross-SDK surface; iOS/Android/Flutter/RN do not
// expose them. Keep them internal to the Web package so app authors who
// follow Swift as the reference do not accidentally bind to them.
export const WebModelLifecycle = {
  supportsNativeLifecycle(): boolean {
    return ModelLifecycleAdapter.tryDefault()?.supportsProtoLifecycle() ?? false;
  },

  loadModel(request: ModelLoadRequest): ModelLoadResult | null {
    const snapshot = request.modelId ? safeGetModelSnapshot(request.modelId) : null;
    const adapter = requireAdapter(snapshot?.framework);
    const result = adapter.load(request);
    if (result?.success) recordModelLifecycle(request.modelId, lifecycleModuleAsEmscripten(adapter), true);
    return result;
  },

  async loadModelAsync(request: ModelLoadRequest): Promise<ModelLoadResult | null> {
    let modelSnapshot = request.modelId ? safeGetModelSnapshot(request.modelId) : null;
    if (modelSnapshot && !modelSnapshot.localPath) {
      const resolvedPath = await resolveLocalPathFromOpfs(modelSnapshot);
      if (resolvedPath) {
        modelSnapshot = { ...modelSnapshot, localPath: resolvedPath, isDownloaded: true };
        ModelRegistry.registerModel(modelSnapshot);
      }
    }
    await prepareModelLoad({ request, model: modelSnapshot });
    if (modelSnapshot) {
      ModelRegistry.registerModel(modelSnapshot);
    }

    // OPFS persistence: model files were persisted to OPFS
    // after download (see RunAnywhere.downloadModel). On a fresh tab the
    // Emscripten MEMFS is empty, so the C++ engine loader's `fopen` /
    // `mmap` against the canonical /opfs/... path would fail. Restore
    // the bytes from OPFS into MEMFS before invoking the backend loader.
    //
    // Multi-WASM caveat: each Emscripten WASM artifact (commons, llamacpp,
    // onnx-sherpa) has its OWN private MEMFS. The C++ engine `fopen`
    // executes inside whichever backend WASM owns the plugin route — NOT
    // necessarily commons. Hydrate ONLY that load-target module: copying a
    // 2.5 GB GGUF into commons + llamacpp + onnx at once OOMs the tab and
    // surfaces as "missing from 3 MEMFS module(s) after OPFS restore".
    //
    // When the BackendWorker owns LLM load/inference, skip main-thread
    // hydration so we do not keep a second copy of the GGUF in UI-thread
    // MEMFS. The worker hydrates its own MEMFS during loadModel RPC.
    const adapter = requireAdapter(modelSnapshot?.framework);
    const workerEligible = Boolean(
      (onnxWorkerModality(modelSnapshot, request)
        ? getActiveBackendWorkerHost('onnx')
        : getActiveBackendWorkerHost('llamacpp'))
      && (onnxWorkerModality(modelSnapshot, request) || isBackendWorkerEligibleLLM(modelSnapshot, request)),
    );
    if (modelSnapshot?.localPath && !workerEligible) {
      const loadModule = lifecycleModuleAsEmscripten(adapter);
      const modules = [loadModule];
      try {
        await assertDownloadedArtifactReady(modelSnapshot);
        // Multi-file models (VLM = primary GGUF + mmproj sidecar,
        // embeddings = model.onnx + vocab.txt) store every file inside the
        // model folder; `localPath` is the folder. OPFS `getFileHandle` on
        // a directory throws DOMException, so restoring the path as a
        // single file silently produces zero bytes — the C++ engine then
        // fails with "No such file or directory" (e.g. SmolVLM2 load).
        // Iterate each file under the folder and restore individually.
        const files = modelSnapshot.multiFile?.files ?? [];
        if (files.length > 1) {
          for (const file of files) {
            if (!file.filename) continue;
            const filePath = `${modelSnapshot.localPath}/${file.filename}`;
            await OPFSBridge.ensureModelPathReadyForLoad(modules, filePath);
          }
        } else {
          await OPFSBridge.ensureModelPathReadyForLoad(modules, modelSnapshot.localPath);
        }
      } catch (err) {
        // Incomplete OPFS after a mid-download refresh: clear the registry
        // flag so the UI swaps "Use" back to "Retry".
        if (modelSnapshot.id && isIncompleteDownloadError(err)) {
          try {
            ModelRegistry.updateDownloadStatus(modelSnapshot.id, null);
          } catch { /* ignore */ }
        }
        throw SDKException.fromCode(
          -ProtoErrorCode.ERROR_CODE_MODEL_LOAD_FAILED,
          err instanceof Error ? err.message : String(err),
          'loadModel',
        );
      }
    } else if (modelSnapshot?.localPath && workerEligible) {
      try {
        await assertDownloadedArtifactReady(modelSnapshot);
      } catch (err) {
        if (modelSnapshot.id && isIncompleteDownloadError(err)) {
          try {
            ModelRegistry.updateDownloadStatus(modelSnapshot.id, null);
          } catch { /* ignore */ }
        }
        throw SDKException.fromCode(
          -ProtoErrorCode.ERROR_CODE_MODEL_LOAD_FAILED,
          err instanceof Error ? err.message : String(err),
          'loadModel',
        );
      }
    }

    try {
      const workerResult = await loadModelViaBackendWorker(request, modelSnapshot, adapter);
      if (workerResult) return workerResult;

      const result = await adapter.loadAsync(request);
      if (result?.success) {
        clearModelOwnedByBackendWorker(request.modelId);
        recordModelLifecycle(request.modelId, lifecycleModuleAsEmscripten(adapter), true);
      }
      return result;
    } catch (error) {
      const recovered = await recoverModelLoadFailure({
        request,
        model: modelSnapshot,
        error,
      });
      if (!recovered) throw error;
      if (modelSnapshot) {
        ModelRegistry.registerModel(modelSnapshot);
      }
      const retryAdapter = requireAdapter(modelSnapshot?.framework);
      const workerResult = await loadModelViaBackendWorker(request, modelSnapshot, retryAdapter);
      if (workerResult) return workerResult;
      const result = await retryAdapter.loadAsync(request);
      if (result?.success) {
        clearModelOwnedByBackendWorker(request.modelId);
        recordModelLifecycle(request.modelId, lifecycleModuleAsEmscripten(retryAdapter), true);
      }
      return result;
    }
  },

  unloadModel(request: ModelUnloadRequest): ModelUnloadResult | null {
    if (request.modelId && isModelOwnedByBackendWorker(request.modelId, 'llamacpp')) {
      clearModelOwnedByBackendWorker(request.modelId, 'llamacpp');
    } else if (request.modelId && isModelOwnedByBackendWorker(request.modelId, 'onnx')) {
      clearModelOwnedByBackendWorker(request.modelId, 'onnx');
    } else if (request.unloadAll) {
      clearModelOwnedByBackendWorker();
      clearModelOwnedByBackendWorker(undefined, 'onnx');
    }
    return unloadAcrossAdapters(request);
  },

  async unloadModelAsync(request: ModelUnloadRequest): Promise<ModelUnloadResult | null> {
    const backendId = request.modelId && isModelOwnedByBackendWorker(request.modelId, 'onnx')
      ? 'onnx'
      : 'llamacpp';
    const host = getActiveBackendWorkerHost(backendId);
    if (
      host
      && (
        (request.modelId && isModelOwnedByBackendWorker(request.modelId, backendId))
        || request.unloadAll
      )
    ) {
      const requestBytes = ModelUnloadRequestCodec.encode(request).finish();
      await host.unloadModel(backendId === 'onnx' ? 'stt' : 'llm', { requestBytes });
      if (request.unloadAll) {
        clearModelOwnedByBackendWorker(undefined, backendId);
      } else {
        clearModelOwnedByBackendWorker(request.modelId, backendId);
      }
    } else {
      // Category-only async unloads (no modelId, unloadAll:false) skip the
      // guard above, so a worker-resident model of that category (e.g. ONNX
      // embeddings) would stay loaded while main-thread adapters report
      // success. Fan the category request out to the owning workers too.
      await unloadCategoryAcrossWorkers(request);
    }
    return unloadAcrossAdaptersAsync(request);
  },

  unloadAllModels(): ModelUnloadResult | null {
    return unloadAcrossAdapters({ modelId: '', unloadAll: true });
  },

  currentModel(
    request: CurrentModelRequest = { includeModelMetadata: false },
  ): CurrentModelResult | null {
    // Models loaded in the BackendWorker are invisible to main-thread
    // g_loaded maps — surface JS ownership first so Use/chat UI stays honest.
    const workerOwned = currentModelFromBackendWorker(request);
    if (workerOwned) return workerOwned;

    if (
      request.framework !== undefined
      && request.framework !== InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN
    ) {
      return requireAdapter(request.framework).currentModel(request);
    }
    // Aggregate across all registered WASM modules: LlamaCPP holds LLM/VLM
    // state in its g_loaded map; ONNX holds STT/TTS/VAD/Embedding state in
    // its own map. The default adapter only sees one — return the first
    // module that reports a non-empty current model.
    const modules = getAllRegisteredModules();
    if (modules.length === 0) return requireAdapter().currentModel(request);
    let fallback: CurrentModelResult | null = null;
    for (const mod of modules) {
      const result = ModelLifecycleAdapter.fromModule(
        mod as unknown as Parameters<typeof ModelLifecycleAdapter.fromModule>[0],
      ).currentModel(request);
      if (result?.modelId) return result;
      if (!fallback && result) fallback = result;
    }
    return fallback ?? requireAdapter().currentModel(request);
  },

  isLoaded(request: CurrentModelRequest = { includeModelMetadata: false }): boolean {
    const current = WebModelLifecycle.currentModel(request);
    return Boolean(current?.modelId);
  },

  // Canonical cross-SDK helper (mirrors Swift `modelInfoForCategory`):
  // returns the full `ModelInfo` for the model currently loaded under
  // `category`, or null when nothing is loaded. Forces
  // `includeModelMetadata=true` so callers get the populated proto rather
  // than reconstructing a stand-in.
  modelInfoForCategory(category: ModelCategory): ModelInfo | null {
    const result = WebModelLifecycle.currentModel({ category, includeModelMetadata: true });
    if (!result?.found) return null;
    return result.model ?? null;
  },

  componentLifecycleSnapshot(component: SDKComponent): ComponentLifecycleSnapshot | null {
    // Each WASM module has its own static `g_loaded` map — a model loaded
    // against the LlamaCPP WASM is invisible to ONNX's snapshot and vice
    // versa. Walk every registered module and prefer any READY result over
    // NOT_LOADED so the Voice tab can correctly see LLM (loaded in
    // LlamaCPP) + STT/TTS (loaded in ONNX) simultaneously.
    const modules = getAllRegisteredModules();
    if (modules.length === 0) return requireAdapter().componentSnapshot(component);
    let best: ComponentLifecycleSnapshot | null = null;
    for (const mod of modules) {
      const snap = ModelLifecycleAdapter.fromModule(
        mod as unknown as Parameters<typeof ModelLifecycleAdapter.fromModule>[0],
      ).componentSnapshot(component);
      if (!snap) continue;
      if (snap.state === ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY) return snap;
      if (!best) best = snap;
    }
    return best;
  },

  isComponentReady(component: SDKComponent): boolean {
    return WebModelLifecycle.componentLifecycleSnapshot(component)?.state ===
      ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY;
  },

  reset(): boolean {
    const registered = registeredLifecycleAdapters();
    const adapters = registered.length > 0 ? registered : [requireAdapter()];
    // Catch per module and do not use Array.every directly: either could
    // short-circuit and leave a later backend's private lifecycle map uncleared.
    const results = adapters.map((adapter) => {
      try {
        return adapter.reset();
      } catch {
        return false;
      }
    });
    return results.every((result) => result);
  },
};

function safeGetModelSnapshot(modelId: string): ModelInfo | null {
  try {
    return ModelRegistry.getModel(modelId);
  } catch {
    return null;
  }
}
