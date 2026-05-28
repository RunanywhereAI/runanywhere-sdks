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
import type { InferenceFramework } from '@runanywhere/proto-ts/model_types';
import type {
  ComponentLifecycleSnapshot,
  SDKComponent,
} from '@runanywhere/proto-ts/sdk_events';
import { ComponentLifecycleState } from '@runanywhere/proto-ts/component_types';
import { ModelLifecycleAdapter } from '../../Adapters/ModelLifecycleAdapter';
import { prepareModelLoad, recoverModelLoadFailure } from '../../Foundation/RuntimeConfig';
import { SDKErrorCode, SDKException } from '../../Foundation/SDKException';
import { ModelRegistry } from './RunAnywhere+ModelRegistry';
import { OPFSBridge } from '../../Infrastructure/OPFSBridge';
import {
  frameworkOPFSDir,
  primaryFilenameFromModel,
} from '../../Infrastructure/FrameworkOPFSPaths';
import { getAllRegisteredModules } from '../../runtime/EmscriptenModule';

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

function requireAdapter(framework?: unknown): ModelLifecycleAdapter {
  const adapter = (framework !== undefined && framework !== null)
    ? ModelLifecycleAdapter.tryDefaultForFramework(framework as never)
    : ModelLifecycleAdapter.tryDefault();
  if (!adapter) {
    throw SDKException.backendNotAvailable(
      'ModelLifecycle',
      'RunAnywhere model lifecycle proto adapter is not installed. Register a backend WASM module (e.g. LlamaCPP.register()) during app init.',
    );
  }
  return adapter;
}

async function resolveLocalPathFromOpfs(model: ModelInfo): Promise<string | null> {
  if (model.localPath) return model.localPath;

  const frameworkDir = frameworkOPFSDir(model.framework as InferenceFramework);
  if (!frameworkDir) return null;

  const filename = primaryFilenameFromModel(model);
  if (!filename) return null;

  const opfsPath = `/opfs/RunAnywhere/Models/${frameworkDir}/${model.id}/${filename}`;
  if (!(await OPFSBridge.exists(opfsPath))) return null;

  const isMultiFile = (model.multiFile?.files?.length ?? 0) > 1;
  return isMultiFile
    ? `/opfs/RunAnywhere/Models/${frameworkDir}/${model.id}`
    : opfsPath;
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
    return requireAdapter(snapshot?.framework).load(request);
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

    // BUG-WEB-002 / OPFS persistence: model files were persisted to OPFS
    // after download (see RunAnywhere.downloadModel). On a fresh tab the
    // Emscripten MEMFS is empty, so the C++ engine loader's `fopen` /
    // `mmap` against the canonical /opfs/... path would fail. Restore
    // the bytes from OPFS into MEMFS before invoking the backend loader.
    //
    // Multi-WASM caveat: each Emscripten WASM artifact (commons, llamacpp,
    // onnx-sherpa) has its OWN private MEMFS. The C++ engine `fopen`
    // executes inside whichever backend WASM owns the plugin route — NOT
    // necessarily commons. Restoring into commons alone leaves the
    // backend's `fopen` returning ENOENT (see post-OPFS E2E report, Bug A:
    // "gguf_init_from_file ... No such file or directory"). Fan the
    // restore out to every registered backend module so the file is
    // reachable from whichever vtable claims the load. This is unique to
    // Web/Emscripten — iOS/Android/Flutter/RN share one libc filesystem
    // and have no equivalent isolation.
    if (modelSnapshot?.localPath) {
      const modules = getAllRegisteredModules();
      if (modules.length > 0) {
        try {
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
          throw SDKException.fromCode(
            SDKErrorCode.ModelLoadFailed,
            err instanceof Error ? err.message : String(err),
            'loadModel',
          );
        }
      }
    }

    try {
      return await requireAdapter(modelSnapshot?.framework).loadAsync(request);
    } catch (error) {
      const recovered = await recoverModelLoadFailure({ request, error });
      if (!recovered) throw error;
      if (modelSnapshot) {
        ModelRegistry.registerModel(modelSnapshot);
      }
      return requireAdapter(modelSnapshot?.framework).loadAsync(request);
    }
  },

  unloadModel(request: ModelUnloadRequest): ModelUnloadResult | null {
    return requireAdapter().unload(request);
  },

  unloadModelAsync(request: ModelUnloadRequest): Promise<ModelUnloadResult | null> {
    return requireAdapter().unloadAsync(request);
  },

  unloadAllModels(): ModelUnloadResult | null {
    return requireAdapter().unload({ modelId: '', unloadAll: true });
  },

  currentModel(
    request: CurrentModelRequest = { includeModelMetadata: false },
  ): CurrentModelResult | null {
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
    return requireAdapter().reset();
  },
};

function safeGetModelSnapshot(modelId: string) {
  try {
    return ModelRegistry.getModel(modelId);
  } catch {
    return null;
  }
}
