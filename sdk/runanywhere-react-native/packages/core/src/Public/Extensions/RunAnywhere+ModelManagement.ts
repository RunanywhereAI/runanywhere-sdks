/**
 * RunAnywhere+ModelManagement.ts
 *
 * Canonical model registration / discovery / download / delete / load surface,
 * matching the Swift / Kotlin / Flutter / Web SDKs.
 *
 * Wraps the proto-byte ABI on the core Nitro HybridObject:
 *   - registerModelProto              - register / registerMultiFile
 *   - getAvailableModelsProto         - getAvailableModels
 *   - getDownloadedModelsProto        - getDownloadedModels
 *   - downloadPlanProto               - downloadModel (plan)
 *   - downloadStartProto              - downloadModel (start)
 *   - setDownloadProgressCallbackProto - downloadModel (stream)
 *   - downloadCancelProto             - cancelDownload
 *   - storageDeleteProto              - deleteModel
 *   - modelLifecycleUnloadProto       - deleteModel (release handles first)
 *   - modelLifecycleLoadProto         - loadModel (sugar overload)
 *
 * Hermes constraint: download streaming returns an `AsyncIterable<DownloadProgress>`
 * that callers MUST drive with manual `iterator.next()` loops (see CLAUDE.md).
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import { SDKException } from '../../Foundation/ErrorTypes/SDKException';
import {
  ModelArtifactType,
  ModelCategory,
  ModelDeleteRequest,
  ModelDeleteResult,
  ModelFileRole,
  ModelFormat,
  type ModelInfo,
  ModelInfo as ModelInfoCodec,
  ModelInfoList,
  ModelLoadRequest,
  ModelLoadResult,
  type InferenceFramework,
} from '@runanywhere/proto-ts/model_types';
import {
  DownloadCancelRequest,
  DownloadCancelResult,
  DownloadPlanRequest,
  DownloadPlanResult,
  type DownloadProgress,
  DownloadProgress as DownloadProgressCodec,
  DownloadStartRequest,
  DownloadStartResult,
} from '@runanywhere/proto-ts/download_service';
import { arrayBufferToBytes, bytesToArrayBuffer } from '../../services/ProtoBytes';

// ---------------------------------------------------------------------------
// Public types — match the Swift / Kotlin signatures.
// ---------------------------------------------------------------------------

/**
 * Single-file registration shorthand. Mirrors Swift's
 * `RunAnywhere.registerModel(id:name:url:framework:...)`.
 */
export interface RegisterModelInput {
  id: string;
  name: string;
  url: string;
  framework: InferenceFramework;
  /** Estimated runtime RAM, used for compatibility checks. */
  memoryRequirement?: number;
  /** Optional model category (defaults to LANGUAGE for back-compat). */
  modality?: ModelCategory;
  /** Optional artifact archive type hint. */
  artifactType?: ModelArtifactType;
  /** Optional thinking-tag support flag. */
  supportsThinking?: boolean;
}

/**
 * Multi-file registration shorthand. Mirrors Swift's
 * `RunAnywhere.registerMultiFileModel(id:name:files:framework:...)`.
 */
export interface RegisterMultiFileModelInput {
  id: string;
  name: string;
  files: Array<{ url: string; filename: string; isRequired: boolean }>;
  framework: InferenceFramework;
  modality?: ModelCategory;
  memoryRequirement?: number;
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

/**
 * Register a model in the native registry from a single download URL.
 */
export async function registerModel(input: RegisterModelInput): Promise<boolean> {
  if (!isNativeModuleAvailable()) return false;
  const native = requireNativeModule();
  const message = ModelInfoCodec.fromPartial({
    id: input.id,
    name: input.name,
    category: input.modality ?? ModelCategory.MODEL_CATEGORY_LANGUAGE,
    framework: input.framework,
    preferredFramework: input.framework,
    format: ModelFormat.MODEL_FORMAT_GGUF,
    downloadUrl: input.url,
    memoryRequiredBytes: input.memoryRequirement ?? 0,
    supportsThinking: input.supportsThinking ?? false,
    artifactType: input.artifactType,
  });
  const bytes = bytesToArrayBuffer(ModelInfoCodec.encode(message).finish());
  return native.registerModelProto(bytes);
}

/**
 * Register a multi-file model where the runtime needs more than one
 * artifact (e.g. VLM main + projector, embedding model + vocab).
 */
export async function registerMultiFileModel(
  input: RegisterMultiFileModelInput
): Promise<boolean> {
  if (!isNativeModuleAvailable()) return false;
  const native = requireNativeModule();
  const message = ModelInfoCodec.fromPartial({
    id: input.id,
    name: input.name,
    category: input.modality ?? ModelCategory.MODEL_CATEGORY_LANGUAGE,
    framework: input.framework,
    preferredFramework: input.framework,
    format: ModelFormat.MODEL_FORMAT_GGUF,
    memoryRequiredBytes: input.memoryRequirement ?? 0,
    multiFile: {
      files: input.files.map((file, idx) => ({
        role:
          idx === 0
            ? ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL
            : ModelFileRole.MODEL_FILE_ROLE_VISION_PROJECTOR,
        url: file.url,
        filename: file.filename,
        relativePath: file.filename,
        isRequired: file.isRequired,
      })),
    },
  });
  const bytes = bytesToArrayBuffer(ModelInfoCodec.encode(message).finish());
  return native.registerModelProto(bytes);
}

// ---------------------------------------------------------------------------
// Listing
// ---------------------------------------------------------------------------

/**
 * Get all registered models. Mirrors Swift's `RunAnywhere.getAvailableModels()`.
 */
export async function getAvailableModels(): Promise<ModelInfo[]> {
  if (!isNativeModuleAvailable()) return [];
  const native = requireNativeModule();
  const buffer = await native.getAvailableModelsProto();
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) return [];
  return ModelInfoList.decode(bytes).models;
}

/**
 * Get only the models the registry believes have been successfully downloaded.
 * Mirrors Swift's `RunAnywhere.getDownloadedModels()`.
 */
export async function getDownloadedModels(): Promise<ModelInfo[]> {
  if (!isNativeModuleAvailable()) return [];
  const native = requireNativeModule();
  const buffer = await native.getDownloadedModelsProto();
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) return [];
  return ModelInfoList.decode(bytes).models;
}

// ---------------------------------------------------------------------------
// Download (canonical async iterable)
// ---------------------------------------------------------------------------

function isTerminalProgress(progress: DownloadProgress): boolean {
  return (
    progress.state === 5 || // DOWNLOAD_STATE_COMPLETED
    progress.state === 6 || // DOWNLOAD_STATE_FAILED
    progress.state === 7 // DOWNLOAD_STATE_CANCELLED
  );
}

/**
 * Streaming download of a registered model identifier. Yields proto-canonical
 * `DownloadProgress` events from the native download service.
 *
 * Hermes-safe: callers MUST iterate via `iterator.next()` (see CLAUDE.md).
 */
export function downloadModel(modelId: string): AsyncIterable<DownloadProgress> {
  if (!isNativeModuleAvailable()) {
    return {
      [Symbol.asyncIterator](): AsyncIterator<DownloadProgress> {
        return {
          async next(): Promise<IteratorResult<DownloadProgress>> {
            throw SDKException.nativeModuleUnavailable();
          },
        };
      },
    };
  }

  const native = requireNativeModule();

  return {
    [Symbol.asyncIterator](): AsyncIterator<DownloadProgress> {
      let started = false;
      let completed = false;
      let activeTaskId: string | undefined;
      const queue: DownloadProgress[] = [];
      let resolver:
        | ((value: IteratorResult<DownloadProgress>) => void)
        | null = null;
      let streamError: Error | null = null;

      const finish = () => {
        completed = true;
        if (resolver) {
          resolver({
            value: undefined as unknown as DownloadProgress,
            done: true,
          });
          resolver = null;
        }
      };

      const onBytes = (progressBytes: ArrayBuffer): void => {
        try {
          const progress = DownloadProgressCodec.decode(
            arrayBufferToBytes(progressBytes)
          );
          if (progress.modelId && progress.modelId !== modelId) return;
          if (resolver) {
            resolver({ value: progress, done: false });
            resolver = null;
          } else {
            queue.push(progress);
          }
        } catch (err) {
          streamError = err instanceof Error ? err : new Error(String(err));
          finish();
        }
      };

      const start = async (): Promise<void> => {
        if (started) return;
        started = true;
        try {
          await native.setDownloadProgressCallbackProto(onBytes);
          const modelBuffer = await native.getModelInfoProto(modelId);
          const modelBytes = arrayBufferToBytes(modelBuffer);
          if (modelBytes.byteLength === 0) {
            streamError = new Error(`model ${modelId} is not registered`);
            await native.clearDownloadProgressCallbackProto().catch(() => {});
            finish();
            return;
          }
          const model = ModelInfoCodec.decode(modelBytes);
          const planRequest = DownloadPlanRequest.fromPartial({
            modelId,
            model,
          });
          const planBytes = await native.downloadPlanProto(
            bytesToArrayBuffer(DownloadPlanRequest.encode(planRequest).finish())
          );
          const plan = DownloadPlanResult.decode(arrayBufferToBytes(planBytes));
          if (!plan.canStart) {
            streamError = new Error(
              plan.errorMessage || `download plan rejected for ${modelId}`
            );
            await native.clearDownloadProgressCallbackProto().catch(() => {});
            finish();
            return;
          }
          const startRequest = DownloadStartRequest.fromPartial({
            modelId,
            plan,
            updateRegistryOnCompletion: true,
          });
          const startBytes = await native.downloadStartProto(
            bytesToArrayBuffer(
              DownloadStartRequest.encode(startRequest).finish()
            )
          );
          const startResult = DownloadStartResult.decode(
            arrayBufferToBytes(startBytes)
          );
          if (!startResult.accepted) {
            streamError = new Error(
              startResult.errorMessage || `download not accepted for ${modelId}`
            );
            await native.clearDownloadProgressCallbackProto().catch(() => {});
            finish();
            return;
          }
          activeTaskId = startResult.taskId;
        } catch (err) {
          streamError = err instanceof Error ? err : new Error(String(err));
          await native.clearDownloadProgressCallbackProto().catch(() => {});
          finish();
        }
      };

      return {
        async next(): Promise<IteratorResult<DownloadProgress>> {
          if (!started) await start();
          if (queue.length > 0) {
            const value = queue.shift()!;
            if (isTerminalProgress(value)) {
              finish();
              await native.clearDownloadProgressCallbackProto().catch(() => {});
            }
            return { value, done: false };
          }
          if (streamError) throw streamError;
          if (completed) {
            return {
              value: undefined as unknown as DownloadProgress,
              done: true,
            };
          }
          return new Promise<IteratorResult<DownloadProgress>>((resolve) => {
            resolver = resolve;
          }).then(async (result) => {
            if (streamError) throw streamError;
            if (!result.done && isTerminalProgress(result.value)) {
              finish();
              await native.clearDownloadProgressCallbackProto().catch(() => {});
            }
            return result;
          });
        },
        async return(): Promise<IteratorResult<DownloadProgress>> {
          if (activeTaskId) {
            const cancelRequest = DownloadCancelRequest.fromPartial({
              taskId: activeTaskId,
              modelId,
              deletePartialBytes: false,
            });
            try {
              await native.downloadCancelProto(
                bytesToArrayBuffer(
                  DownloadCancelRequest.encode(cancelRequest).finish()
                )
              );
            } catch {
              /* noop */
            }
          }
          await native.clearDownloadProgressCallbackProto().catch(() => {});
          finish();
          return {
            value: undefined as unknown as DownloadProgress,
            done: true,
          };
        },
      };
    },
  };
}

/** Cancel an in-flight download by model id. */
export async function cancelDownload(modelId: string): Promise<boolean> {
  if (!isNativeModuleAvailable()) return false;
  const native = requireNativeModule();
  const request = DownloadCancelRequest.fromPartial({
    taskId: '',
    modelId,
    deletePartialBytes: false,
  });
  const buffer = await native.downloadCancelProto(
    bytesToArrayBuffer(DownloadCancelRequest.encode(request).finish())
  );
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) return false;
  const result = DownloadCancelResult.decode(bytes);
  return result.success;
}

// ---------------------------------------------------------------------------
// Deletion
// ---------------------------------------------------------------------------

/**
 * Delete a downloaded model's files. Releases any in-flight handles first
 * via `modelLifecycleUnloadProto` then removes the artifact bytes via
 * `storageDeleteProto`. Registry entry is retained so the model can be
 * re-downloaded.
 */
export async function deleteModel(modelId: string): Promise<boolean> {
  if (!isNativeModuleAvailable()) return false;
  const native = requireNativeModule();
  // Release any in-flight handles first.
  await native
    .modelLifecycleUnloadProto(
      bytesToArrayBuffer(
        ModelLoadRequest.encode(
          ModelLoadRequest.fromPartial({
            modelId,
            forceReload: false,
            validateAvailability: false,
          })
        ).finish()
      )
    )
    .catch(() => new ArrayBuffer(0));

  const request = ModelDeleteRequest.fromPartial({
    modelId,
    deleteFiles: true,
    unregister: false,
    unloadIfLoaded: true,
  });
  const buffer = await native
    .storageDeleteProto(
      bytesToArrayBuffer(ModelDeleteRequest.encode(request).finish())
    )
    .catch(() => new ArrayBuffer(0));
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) return false;
  const result = ModelDeleteResult.decode(bytes);
  return result.success;
}

// ---------------------------------------------------------------------------
// Sugar overload for model loading by id (mirrors Swift `RunAnywhere.loadModel`).
// ---------------------------------------------------------------------------

/**
 * Load a model by its registered id. Sugar overload over
 * `loadModelLifecycle(request)` — mirrors Swift's `RunAnywhere.loadModel(_:)`.
 *
 * @param modelId  registered model identifier
 * @param category optional category hint forwarded to the lifecycle request
 * @returns true if the model loaded successfully
 */
export async function loadModel(
  modelId: string,
  category?: ModelCategory
): Promise<boolean> {
  if (!isNativeModuleAvailable()) return false;
  const native = requireNativeModule();
  const request = ModelLoadRequest.fromPartial({
    modelId,
    category,
    forceReload: false,
    validateAvailability: true,
  });
  const buffer = await native.modelLifecycleLoadProto(
    bytesToArrayBuffer(ModelLoadRequest.encode(request).finish())
  );
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) return false;
  const result = ModelLoadResult.decode(bytes);
  return result.success;
}
