/**
 * RunAnywhere+ModelRegistry.ts
 *
 * Canonical model registration / discovery / download surface,
 * matching the Swift SDK.
 *
 * Wraps the proto-byte ABI on the core Nitro HybridObject:
 *   - registerModelProto              - register / registerMultiFile
 *   - getAvailableModelsProto         - listModels
 *   - getDownloadedModelsProto        - downloadedModels
 *   - downloadPlanProto               - downloadModel (plan)
 *   - downloadStartProto              - downloadModel (start)
 *   - setDownloadProgressCallbackProto - downloadModel (stream)
 *
 * Hermes constraint: download streaming returns an `AsyncIterable<DownloadProgress>`
 * that callers MUST drive with manual `iterator.next()` loops (see CLAUDE.md).
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import { ensureServicesReady } from '../../../Foundation/Initialization/ServicesReadyGuard';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import {
  ModelArtifactType,
  ModelCategory,
  ModelFileRole,
  ModelFormat,
  type ModelInfo,
  ModelInfo as ModelInfoCodec,
  ModelInfoList,
  ModelGetRequest,
  ModelGetResult,
  ModelImportRequest,
  ModelImportResult,
  ModelListRequest,
  ModelListResult,
  ModelQuery,
  ModelSource,
  InferenceFramework,
} from '@runanywhere/proto-ts/model_types';
import { ThinkingTagPattern } from '@runanywhere/proto-ts/thinking_tag_pattern';
import {
  DownloadCancelRequest,
  DownloadPlanRequest,
  DownloadFailureReason,
  DownloadPlanResult,
  DownloadStage,
  DownloadState,
  type DownloadProgress,
  DownloadProgress as DownloadProgressCodec,
  DownloadStartRequest,
  DownloadStartResult,
} from '@runanywhere/proto-ts/download_service';
import {
  ErrorCategory,
  ErrorCode,
} from '@runanywhere/proto-ts/errors';
import { arrayBufferToBytes } from '../../../services/ProtoBytes';
import { encodeProtoMessage } from '../../../services/ProtoWire';

// ---------------------------------------------------------------------------
// Public types — match the Swift signatures.
// ---------------------------------------------------------------------------

/**
 * Single-file registration shorthand. Mirrors Swift's
 * `RunAnywhere.registerModel(id:name:url:framework:...)` — keep the optional
 * fields in lock-step with `RunAnywhere+Storage.swift:19-72`.
 */
export interface RegisterModelInput {
  /**
   * Optional stable id. When omitted, commons' canonical
   * `rac_register_model_from_url_proto` derives it from the URL; the local
   * fallback (only hit when the native ABI is unavailable) uses the
   * Kotlin-parity URL-tail derivation.
   */
  id?: string;
  name: string;
  url: string;
  framework: InferenceFramework;
  /** Estimated runtime RAM, used for compatibility checks. */
  memoryRequirement?: number;
  /** Optional model category (Swift shorthand defaults to LANGUAGE). */
  modality?: ModelCategory;
  /** Optional artifact archive type hint. */
  artifactType?: ModelArtifactType;
  /** Optional thinking-tag support flag. */
  supportsThinking?: boolean;
  /** Optional LoRA adapter compatibility flag (Swift parity). */
  supportsLora?: boolean;
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
 *
 * Builds a complete `ModelInfo` from the caller's input — including every
 * capability field (id, framework, category, memory/download sizing, thinking
 * and LoRA flags, artifact type) — and persists it through the registry's
 * proto save path (`rac_model_registry_register_proto`) in a single call. That
 * plain register path already persists every capability field, so the prior
 * from-url-then-patch-then-resave dance is unnecessary.
 *
 * Returns the resolved `ModelInfo` proto so callers can pipe it straight into
 * `downloadModel(...)`.
 */
export async function registerModel(
  input: RegisterModelInput,
): Promise<ModelInfo> {
  if (!isNativeModuleAvailable()) throw SDKException.nativeModuleUnavailable();
  const native = requireNativeModule();
  const modality = input.modality ?? ModelCategory.MODEL_CATEGORY_LANGUAGE;
  const memoryHint =
    input.memoryRequirement !== undefined && input.memoryRequirement > 0
      ? input.memoryRequirement
      : undefined;
  const supportsThinking = input.supportsThinking ?? false;
  const supportsLora = input.supportsLora ?? false;

  const model = ModelInfoCodec.fromPartial({
    id: input.id ?? deriveModelIdFromUrl(input.url, input.name),
    name: input.name,
    category: modality,
    framework: input.framework,
    preferredFramework: input.framework,
    format: ModelFormat.MODEL_FORMAT_UNSPECIFIED,
    downloadUrl: input.url,
    source: ModelSource.MODEL_SOURCE_REMOTE,
    supportsThinking,
    supportsLora,
    ...(memoryHint !== undefined
      ? { downloadSizeBytes: memoryHint, memoryRequiredBytes: memoryHint }
      : {}),
    ...(supportsThinking ? { thinkingPattern: ThinkingTagPattern.fromPartial({}) } : {}),
    ...(input.artifactType !== undefined ? { artifactType: input.artifactType } : {}),
  });

  const accepted = await native.registerModelProto(
    encodeProtoMessage(model, ModelInfoCodec),
  );
  if (!accepted) {
    throw SDKException.of(
      ErrorCode.ERROR_CODE_INVALID_STATE,
      `Model registry rejected '${model.id}'. Ensure the SDK is initialized before calling registerModel().`,
      { category: ErrorCategory.ERROR_CATEGORY_INTERNAL },
    );
  }

  return model;
}

/**
 * Kotlin-parity URL → id fallback. Mirrors `deriveModelIdFromUrl` in
 * `RunAnywhereStorage.kt:337-344` so an RN caller that omits `id` ends up
 * with the same id Kotlin's local fallback produces.
 */
function deriveModelIdFromUrl(url: string, name: string): string {
  const tail = url.split('/').pop()?.split('?')[0]?.trim() ?? '';
  if (tail.length > 0) {
    const withoutExtension = tail.split('.')[0];
    if (withoutExtension && withoutExtension.length > 0) {
      return withoutExtension;
    }
  }
  const normalized = name.replace(/\s+/g, '-').toLowerCase();
  return normalized.length > 0 ? normalized : `model-${Date.now()}`;
}

/**
 * Register a single-file remote model by URL. Canonical entry point that
 * mirrors Swift's `RunAnywhere.registerModel(id:name:url:framework:...)`,
 * Kotlin's `RunAnywhere.registerModel(...)`, Flutter's
 * `RunAnywhere.registerModel(...)`, and Web's `registerModelFromUrl(...)`.
 *
 * Delegates to `registerModel`, which builds a complete `ModelInfo` from the
 * caller's input and persists it through the registry's proto save path in a
 * single call.
 */
export async function registerModelFromUrl(
  url: string,
  name: string,
  framework: InferenceFramework,
  options: Omit<RegisterModelInput, 'url' | 'name' | 'framework'> = {},
): Promise<ModelInfo> {
  return registerModel({ url, name, framework, ...options });
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
    ...(input.memoryRequirement !== undefined && input.memoryRequirement > 0
      ? { memoryRequiredBytes: input.memoryRequirement }
      : {}),
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
  const bytes = encodeProtoMessage(message, ModelInfoCodec);
  return native.registerModelProto(bytes);
}

// ---------------------------------------------------------------------------
// Listing
// ---------------------------------------------------------------------------

/**
 * Get all registered models. Mirrors Swift's `RunAnywhere.listModels(_:)`.
 */
export async function listModels(
  _request: ModelListRequest = ModelListRequest.fromPartial({
    includeCounts: true,
  })
): Promise<ModelListResult> {
  if (!isNativeModuleAvailable()) {
    return ModelListResult.fromPartial({
      success: false,
      errorMessage: 'Native module not available',
    });
  }
  const native = requireNativeModule();
  const buffer = await native.getAvailableModelsProto();
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) {
    return ModelListResult.fromPartial({
      success: false,
      errorMessage: 'getAvailableModelsProto returned an empty result',
    });
  }
  return modelListResult(ModelInfoList.decode(bytes));
}

/**
 * Query registered models. Mirrors Swift's `RunAnywhere.queryModels(_:)`.
 */
export async function queryModels(query: ModelQuery): Promise<ModelListResult> {
  if (!isNativeModuleAvailable()) {
    return ModelListResult.fromPartial({
      success: false,
      errorMessage: 'Native module not available',
    });
  }
  const native = requireNativeModule();
  const buffer = await native.queryModelsProto(
    encodeProtoMessage(query, ModelQuery)
  );
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) {
    return ModelListResult.fromPartial({
      success: false,
      errorMessage: 'queryModelsProto returned an empty result',
    });
  }
  return modelListResult(ModelInfoList.decode(bytes));
}

/**
 * Get one registered model. Mirrors Swift's `RunAnywhere.getModel(_:)`.
 */
export async function getModel(request: ModelGetRequest): Promise<ModelGetResult> {
  if (!isNativeModuleAvailable()) {
    return ModelGetResult.fromPartial({
      found: false,
      errorMessage: 'Native module not available',
    });
  }
  const native = requireNativeModule();
  const buffer = await native.getModelInfoProto(request.modelId);
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) {
    return ModelGetResult.fromPartial({
      found: false,
      errorMessage: `Model not found: ${request.modelId}`,
    });
  }
  return ModelGetResult.fromPartial({
    found: true,
    model: ModelInfoCodec.decode(bytes),
  });
}

/**
 * Get downloaded models. Mirrors Swift's `RunAnywhere.downloadedModels()`.
 */
export async function downloadedModels(): Promise<ModelListResult> {
  if (!isNativeModuleAvailable()) {
    return ModelListResult.fromPartial({
      success: false,
      errorMessage: 'Native module not available',
    });
  }
  const native = requireNativeModule();
  const buffer = await native.getDownloadedModelsProto();
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) {
    return ModelListResult.fromPartial({
      success: false,
      errorMessage: 'getDownloadedModelsProto returned an empty result',
    });
  }
  return modelListResult(ModelInfoList.decode(bytes));
}

/**
 * Import a stable, platform-normalized local model path into the native
 * registry. Mirrors Swift's `RunAnywhere.importModel(_:)`.
 */
export async function importModel(
  request: ModelImportRequest
): Promise<ModelImportResult> {
  if (!isNativeModuleAvailable()) {
    return ModelImportResult.fromPartial({
      success: false,
      errorMessage: 'Native module not available',
    });
  }

  const native = requireNativeModule();
  const buffer = await native.importModelProto(
    encodeProtoMessage(request, ModelImportRequest)
  );
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) {
    return ModelImportResult.fromPartial({
      success: false,
      errorMessage: 'importModelProto returned an empty result',
    });
  }
  return ModelImportResult.decode(bytes);
}

function modelListResult(models: ModelInfoList): ModelListResult {
  return ModelListResult.fromPartial({
    success: true,
    models,
    totalCount: models.models.length,
    downloadedCount: models.models.filter((model) => model.isDownloaded).length,
    availableCount: models.models.filter((model) => model.isAvailable).length,
    filteredCount: models.models.length,
  });
}

// ---------------------------------------------------------------------------
// Download progress multiplexer (HOTSPOT-RN-CORE-003)
// ---------------------------------------------------------------------------
//
// The native side exposes a single process-wide
// `setDownloadProgressCallbackProto` slot. Concurrent `downloadModel(id)`
// iterators must share that slot, otherwise the most recent caller would
// overwrite the previous iterator's callback and strand its progress events.
//
// This multiplexer registers the native callback exactly once, fan-outs each
// inbound `DownloadProgress` to every subscriber whose `modelId` filter
// matches, and only clears the native slot when the last subscriber leaves.
// Subscribers are responsible for their own filtering/queueing semantics.
type DownloadProgressSubscriber = (progress: DownloadProgress) => void;

interface DownloadProgressEntry {
  modelId: string;
  callback: DownloadProgressSubscriber;
}

const downloadProgressSubscribers = new Set<DownloadProgressEntry>();
let downloadProgressCallbackInstalled: Promise<void> | null = null;

function dispatchDownloadProgress(progressBytes: ArrayBuffer): void {
  const progress = DownloadProgressCodec.decode(arrayBufferToBytes(progressBytes));
  // Snapshot the subscriber set before dispatch — handlers may unsubscribe
  // synchronously on their terminal event, mutating the live set.
  const snapshot = Array.from(downloadProgressSubscribers);
  for (const entry of snapshot) {
    if (progress.modelId && entry.modelId !== progress.modelId) continue;
    try {
      entry.callback(progress);
    } catch {
      // A misbehaving subscriber must not break the fan-out.
    }
  }
}

async function ensureNativeDownloadCallback(): Promise<void> {
  if (downloadProgressCallbackInstalled) {
    await downloadProgressCallbackInstalled;
    return;
  }
  const native = requireNativeModule();
  const pending = native
    .setDownloadProgressCallbackProto(dispatchDownloadProgress)
    .then(() => undefined)
    .catch((err: unknown) => {
      downloadProgressCallbackInstalled = null;
      throw err;
    });
  downloadProgressCallbackInstalled = pending;
  await pending;
}

async function clearNativeDownloadCallbackIfIdle(): Promise<void> {
  if (downloadProgressSubscribers.size > 0) return;
  if (!downloadProgressCallbackInstalled) return;
  downloadProgressCallbackInstalled = null;
  const native = requireNativeModule();
  await native.clearDownloadProgressCallbackProto().catch(() => {});
}

async function subscribeToDownloadProgress(
  entry: DownloadProgressEntry,
): Promise<void> {
  downloadProgressSubscribers.add(entry);
  try {
    await ensureNativeDownloadCallback();
  } catch (err) {
    downloadProgressSubscribers.delete(entry);
    await clearNativeDownloadCallbackIfIdle();
    throw err;
  }
}

async function unsubscribeFromDownloadProgress(
  entry: DownloadProgressEntry,
): Promise<void> {
  downloadProgressSubscribers.delete(entry);
  await clearNativeDownloadCallbackIfIdle();
}

// ---------------------------------------------------------------------------
// Download (canonical async iterable)
// ---------------------------------------------------------------------------

function isTerminalProgress(progress: DownloadProgress): boolean {
  return (
    progress.state === DownloadState.DOWNLOAD_STATE_COMPLETED ||
    progress.state === DownloadState.DOWNLOAD_STATE_FAILED ||
    progress.state === DownloadState.DOWNLOAD_STATE_CANCELLED ||
    progress.stage === DownloadStage.DOWNLOAD_STAGE_COMPLETED
  );
}

function isCompletedProgress(progress: DownloadProgress): boolean {
  if (progress.state === DownloadState.DOWNLOAD_STATE_FAILED) {
    throw SDKException.of(
      ErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
      progress.errorMessage || 'Download failed',
      { category: ErrorCategory.ERROR_CATEGORY_NETWORK }
    );
  }
  if (progress.state === DownloadState.DOWNLOAD_STATE_CANCELLED) {
    throw SDKException.of(
      ErrorCode.ERROR_CODE_CANCELLED,
      'Download cancelled',
      { category: ErrorCategory.ERROR_CATEGORY_NETWORK }
    );
  }
  return (
    progress.state === DownloadState.DOWNLOAD_STATE_COMPLETED ||
    progress.stage === DownloadStage.DOWNLOAD_STAGE_COMPLETED
  );
}

/**
 * Plan a download and retry once after clearing oversize partial bytes.
 *
 * Mirrors Swift's `RunAnywhere+Storage.swift` `planDownload(...)` self-heal:
 * when a previous interrupted download left more bytes on disk than the new
 * plan expects (e.g. a CDN swap shrank Content-Length), commons rejects with
 * "existing partial bytes exceed". Instead of surfacing that as a permanent
 * stuck state, delete the oversize partials and re-plan once. `react-native-fs`
 * is an optional dependency; if it is unavailable we fall back to the original
 * rejection so callers still see a deterministic error.
 */
async function planDownload(
  native: ReturnType<typeof requireNativeModule>,
  request: DownloadPlanRequest
): Promise<DownloadPlanResult> {
  const planBytes = await native.downloadPlanProto(
    encodeProtoMessage(request, DownloadPlanRequest)
  );
  const plan = DownloadPlanResult.decode(arrayBufferToBytes(planBytes));
  if (
    plan.canStart ||
    plan.failureReason !== DownloadFailureReason.DOWNLOAD_FAILURE_REASON_OVERSIZE_PARTIAL_BYTES
  ) {
    return plan;
  }

  // react-native-fs is an optional peer dependency and the require() below is
  // guarded. Type it with a minimal local interface (only the members used) so
  // the SDK source type-checks even when the module's declarations are not
  // resolvable from the consumer's resolution context (e.g. an app that maps
  // the SDK to source rather than its built types).
  let RNFS: {
    exists(path: string): Promise<boolean>;
    unlink(path: string): Promise<void>;
  };
  try {
    RNFS = require('react-native-fs');
  } catch {
    return plan;
  }

  for (const file of plan.files) {
    if (!file.destinationPath) continue;
    if (await RNFS.exists(file.destinationPath)) {
      await RNFS.unlink(file.destinationPath).catch(() => {});
    }
  }

  const retryBytes = await native.downloadPlanProto(
    encodeProtoMessage(request, DownloadPlanRequest)
  );
  return DownloadPlanResult.decode(arrayBufferToBytes(retryBytes));
}

async function persistDownloadCompletion(
  model: ModelInfo,
  progress: DownloadProgress
): Promise<void> {
  const localPath = progress.localPath || model.localPath;
  if (!localPath) {
    throw SDKException.of(
      ErrorCode.ERROR_CODE_INVALID_STATE,
      'Download completed without a local_path; cannot import completion into the model registry',
      { category: ErrorCategory.ERROR_CATEGORY_NETWORK }
    );
  }

  const importedModel = ModelInfoCodec.fromPartial({
    ...model,
    localPath,
    isDownloaded: true,
    isAvailable: true,
    updatedAtUnixMs: Date.now(),
  });
  const result = await importModel(
    ModelImportRequest.fromPartial({
      model: importedModel,
      sourcePath: localPath,
      overwriteExisting: true,
      copyIntoManagedStorage: false,
      validateBeforeRegister: false,
      files: importedModel.multiFile?.files ?? [],
    })
  );

  if (!result.success) {
    throw SDKException.of(
      ErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
      result.errorMessage || 'Downloaded model could not be imported into the registry',
      { category: ErrorCategory.ERROR_CATEGORY_NETWORK }
    );
  }
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
      let subscribed = false;
      let activeTaskId: string | undefined;
      let modelForImport: ModelInfo | undefined;
      let completionImported = false;
      const queue: DownloadProgress[] = [];
      let resolver:
        | ((value: IteratorResult<DownloadProgress>) => void)
        | null = null;
      let streamError: Error | null = null;

      const onProgress: DownloadProgressSubscriber = (progress) => {
        try {
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

      const subscriberEntry: DownloadProgressEntry = {
        modelId,
        callback: onProgress,
      };

      const teardownSubscription = async (): Promise<void> => {
        if (!subscribed) return;
        subscribed = false;
        await unsubscribeFromDownloadProgress(subscriberEntry);
      };

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

      const start = async (): Promise<void> => {
        if (started) return;
        started = true;
        try {
          await ensureServicesReady();
          await subscribeToDownloadProgress(subscriberEntry);
          subscribed = true;
          const modelBuffer = await native.getModelInfoProto(modelId);
          const modelBytes = arrayBufferToBytes(modelBuffer);
          if (modelBytes.byteLength === 0) {
            streamError = new Error(`model ${modelId} is not registered`);
            await teardownSubscription();
            finish();
            return;
          }
          const model = ModelInfoCodec.decode(modelBytes);
          modelForImport = model;
          const planRequest = DownloadPlanRequest.fromPartial({
            modelId,
            model,
          });
          const plan = await planDownload(native, planRequest);
          if (!plan.canStart) {
            streamError = new Error(
              plan.errorMessage || `download plan rejected for ${modelId}`
            );
            await teardownSubscription();
            finish();
            return;
          }
          const startRequest = DownloadStartRequest.fromPartial({
            modelId,
            plan,
            updateRegistryOnCompletion: false,
          });
          const startBytes = await native.downloadStartProto(
            encodeProtoMessage(startRequest, DownloadStartRequest)
          );
          const startResult = DownloadStartResult.decode(
            arrayBufferToBytes(startBytes)
          );
          if (!startResult.accepted) {
            streamError = new Error(
              startResult.errorMessage || `download not accepted for ${modelId}`
            );
            await teardownSubscription();
            finish();
            return;
          }
          activeTaskId = startResult.taskId;
          if (startResult.initialProgress) {
            queue.push(startResult.initialProgress);
          }
        } catch (err) {
          streamError = err instanceof Error ? err : new Error(String(err));
          await teardownSubscription();
          finish();
        }
      };

      const handleProgress = async (
        progress: DownloadProgress
      ): Promise<void> => {
        if (!isCompletedProgress(progress) || completionImported) return;
        if (!modelForImport) {
          throw SDKException.modelNotFound(modelId);
        }
        await persistDownloadCompletion(modelForImport, progress);
        completionImported = true;
      };

      return {
        async next(): Promise<IteratorResult<DownloadProgress>> {
          if (!started) await start();
          if (queue.length > 0) {
            const value = queue.shift()!;
            if (isTerminalProgress(value)) {
              await handleProgress(value);
              finish();
              await teardownSubscription();
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
              await handleProgress(result.value);
              finish();
              await teardownSubscription();
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
                encodeProtoMessage(cancelRequest, DownloadCancelRequest)
              );
            } catch {
              /* noop */
            }
          }
          await teardownSubscription();
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

/**
 * Flat alias for `downloadModel` that matches Swift's canonical shape:
 * `RunAnywhere.downloadModel(_ model, onProgress:) async throws -> DownloadProgress`.
 *
 * Drives the underlying `AsyncIterable<DownloadProgress>` internally and calls
 * `onProgress` for each event, returning the final terminal `DownloadProgress`
 * on success or throwing on failure/cancellation — mirroring
 * `RunAnywhere+Storage.swift:177-263`.
 *
 * Callers that prefer the streaming iterable can still use `downloadModel(id)`
 * directly; both shapes are supported.
 */
export async function downloadModelWithProgress(
  model: ModelInfo,
  onProgress?: (progress: DownloadProgress) => void,
): Promise<DownloadProgress> {
  const iterable = downloadModel(model.id);
  const iterator = iterable[Symbol.asyncIterator]();
  let last: DownloadProgress | undefined;
  while (true) {
    const result = await iterator.next();
    if (result.done) break;
    const progress = result.value;
    onProgress?.(progress);
    last = progress;
    if (isTerminalProgress(progress)) break;
  }
  if (!last) {
    throw SDKException.of(
      ErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
      'Download completed without any progress event',
      { category: ErrorCategory.ERROR_CATEGORY_NETWORK },
    );
  }
  return last;
}

/**
 * Framework the SDK falls back to when a category has no explicit model
 * framework resolved (e.g. a pending UI selection that has not yet matched a
 * catalogued model). Mirrors commons' `rac_model_category_default_framework`
 * and Swift's `RAModelCategory.defaultFramework`.
 */
export function getDefaultFramework(
  category: ModelCategory
): InferenceFramework {
  switch (category) {
    case ModelCategory.MODEL_CATEGORY_LANGUAGE:
    case ModelCategory.MODEL_CATEGORY_MULTIMODAL:
      return InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP;
    case ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION:
    case ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:
    case ModelCategory.MODEL_CATEGORY_EMBEDDING:
    case ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
      return InferenceFramework.INFERENCE_FRAMEWORK_ONNX;
    default:
      return InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN;
  }
}
