/**
 * RunAnywhere+Models.ts
 *
 * Model registry and download extension for RunAnywhere SDK.
 * Matches iOS: RunAnywhere+ModelManagement.swift and RunAnywhere+ModelAssignments.swift
 */

import { DownloadProgress } from '@runanywhere/proto-ts/download_service';
import {
  requireNativeModule,
  isNativeModuleAvailable,
} from '../../native';
import { ModelRegistry } from '../../services/ModelRegistry';
import { FileSystem, MultiFileModelCache } from '../../services/FileSystem';
import type { ModelFileDescriptor } from '../../services/FileSystem';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import type { ModelInfo, LLMFramework, ModelCompatibilityResult } from '../../types';
import { ModelCategory, ModelArtifactType, ModelFormat, ConfigurationSource } from '../../types';

const logger = new SDKLogger('RunAnywhere.Models');

// Track active downloads so cancelDownload() can reach into native.
const activeDownloads = new Set<string>();

// ============================================================================
// Model Registry Extension
// ============================================================================

/**
 * Get available models from the catalog
 */
export async function getAvailableModels(): Promise<ModelInfo[]> {
  return ModelRegistry.getAvailableModels();
}

/**
 * Get available frameworks
 */
export function getAvailableFrameworks(): LLMFramework[] {
  const {
    ServiceRegistry,
  } = require('../../Foundation/DependencyInjection/ServiceRegistry');

  const llmProviders = ServiceRegistry.shared.allLLMProviders();
  const frameworksSet = new Set<LLMFramework>();

  for (const provider of llmProviders) {
    if (provider.getProvidedModels) {
      const models = provider.getProvidedModels();
      for (const model of models) {
        for (const framework of model.compatibleFrameworks) {
          frameworksSet.add(framework);
        }
        if (model.preferredFramework) {
          frameworksSet.add(model.preferredFramework);
        }
      }
    }
  }

  return Array.from(frameworksSet);
}

/**
 * Get models for a specific framework
 */
export async function getModelsForFramework(
  framework: LLMFramework
): Promise<ModelInfo[]> {
  const allModels = await ModelRegistry.getAvailableModels();
  return allModels.filter(
    (model) =>
      model.compatibleFrameworks.includes(framework) ||
      model.preferredFramework === framework
  );
}

/**
 * Get info for a specific model
 */
export async function getModelInfo(modelId: string): Promise<ModelInfo | null> {
  return ModelRegistry.getModel(modelId);
}

/**
 * Check if a model is downloaded
 */
export async function isModelDownloaded(modelId: string): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }
  const native = requireNativeModule();
  return native.isModelDownloaded(modelId);
}

/**
 * Get local path for a downloaded model
 */
export async function getModelPath(modelId: string): Promise<string | null> {
  if (!isNativeModuleAvailable()) {
    return null;
  }
  const native = requireNativeModule();
  return native.getModelPath(modelId);
}

/**
 * Get mmproj path for a VLM model
 * Searches for mmproj file in the same directory as the main model
 * Returns undefined if not found (backend will auto-detect)
 */
export async function getMmprojPath(modelId: string): Promise<string | undefined> {
  const modelPath = await getModelPath(modelId);
  if (!modelPath) {
    return undefined;
  }
  return FileSystem.findMmprojForModel(modelPath);
}

/**
 * Get list of downloaded models
 */
export async function getDownloadedModels(): Promise<ModelInfo[]> {
  return ModelRegistry.getDownloadedModels();
}

// ============================================================================
// Model Assignments Extension
// ============================================================================

/**
 * Refresh the model registry — T4.9 unified cross-SDK surface.
 *
 * Routes to the native `refreshModelRegistry(include, rescan, prune)` Nitro
 * method, which delegates to the commons C ABI `rac_model_registry_refresh`.
 */
export async function refreshModelRegistry(
  options: {
    includeRemoteCatalog?: boolean;
    rescanLocal?: boolean;
    pruneOrphans?: boolean;
  } = {}
): Promise<boolean> {
  const includeRemoteCatalog = options.includeRemoteCatalog ?? true;
  const rescanLocal = options.rescanLocal ?? false;
  const pruneOrphans = options.pruneOrphans ?? false;

  let nativeSucceeded = !includeRemoteCatalog;
  if (includeRemoteCatalog) {
    if (!isNativeModuleAvailable()) {
      logger.warning('refreshModelRegistry: native module unavailable for remote catalog refresh');
    } else {
      const native = requireNativeModule();
      try {
        nativeSucceeded = await native.refreshModelRegistry(
          includeRemoteCatalog,
          rescanLocal,
          pruneOrphans
        );
      } catch (error) {
        logger.warning('refreshModelRegistry remote step failed:', { error });
      }
    }
  }

  let localSucceeded = !(rescanLocal || pruneOrphans);
  if (rescanLocal || pruneOrphans) {
    localSucceeded = await reconcileLocalRegistryModels({
      rescanLocal,
      pruneOrphans,
    });
  }

  return nativeSucceeded && localSucceeded;
}

/**
 * Fetch model assignments for the current device from the backend.
 *
 * Updated for T4.9: when `forceRefresh` is true, routes through the unified
 * `refreshModelRegistry` native surface to trigger a remote catalog fetch,
 * then returns the freshly-populated registry contents.
 */
export async function fetchModelAssignments(
  forceRefresh = false,
  initState: { isCoreInitialized: boolean },
  ensureServicesReady: () => Promise<void>
): Promise<ModelInfo[]> {
  if (!initState.isCoreInitialized) {
    throw new Error('SDK not initialized. Call initialize() first.');
  }

  await ensureServicesReady();

  if (forceRefresh) {
    logger.info('Fetching model assignments (forceRefresh)...');
    await refreshModelRegistry({ includeRemoteCatalog: true });
  } else {
    logger.info('Fetching model assignments from cache...');
  }

  try {
    const models = await ModelRegistry.getAllModels();
    logger.info(`Successfully fetched ${models.length} model assignments`);
    return models;
  } catch (error) {
    logger.warning('Failed to fetch model assignments:', { error });
    return [];
  }
}

/**
 * Get available models for a specific category
 */
export async function getModelsForCategory(
  category: ModelCategory,
  initState: { isCoreInitialized: boolean },
  ensureServicesReady: () => Promise<void>
): Promise<ModelInfo[]> {
  if (!initState.isCoreInitialized) {
    throw new Error('SDK not initialized. Call initialize() first.');
  }

  await ensureServicesReady();

  // Get models by category via ModelRegistry (delegates to native)
  const allModels = await ModelRegistry.getModelsByCategory(category);
  return allModels;
}

/**
 * Clear cached model assignments.
 * Resets local state; next fetch will get fresh data from the registry.
 */
export async function clearModelAssignmentsCache(
  initState: { isCoreInitialized: boolean }
): Promise<void> {
  if (!initState.isCoreInitialized) {
    return;
  }

  ModelRegistry.reset();
}

/**
 * Register a model from a download URL.
 *
 * Matches iOS: RunAnywhere.registerModel(id:name:url:framework:modality:artifactType:memoryRequirement:supportsThinking:)
 */
export async function registerModel(options: {
  id?: string;
  name: string;
  url: string;
  framework: LLMFramework;
  modality?: ModelCategory;
  artifactType?: ModelArtifactType;
  memoryRequirement?: number;
  supportsThinking?: boolean;
}): Promise<ModelInfo> {
  const now = new Date().toISOString();
  const modelId = options.id ?? generateModelId(options.url);

  let isDownloaded = false;
  let localPath: string | undefined;

  if (FileSystem.isAvailable()) {
    try {
      const frameworkDir = inferFrameworkDir(options.framework);
      const exists = await FileSystem.modelExists(modelId, frameworkDir);
      if (exists) {
        localPath = await FileSystem.getModelPath(modelId, frameworkDir);
        isDownloaded = true;
        logger.info(`Model ${modelId} found on disk: ${localPath}`);
      }
    } catch (error) {
      logger.debug(`Could not check for existing model ${modelId}: ${error}`);
    }
  }

  const modelInfo: ModelInfo = {
    id: modelId,
    name: options.name,
    category: options.modality ?? ModelCategory.MODEL_CATEGORY_LANGUAGE,
    format: inferFormat(options.url, options.framework),
    downloadURL: options.url,
    localPath,
    downloadSize: undefined,
    memoryRequired: options.memoryRequirement,
    compatibleFrameworks: [options.framework],
    preferredFramework: options.framework,
    supportsThinking: options.supportsThinking ?? false,
    metadata: { tags: [] },
    source: ConfigurationSource.Local,
    createdAt: now,
    updatedAt: now,
    syncPending: false,
    usageCount: 0,
    isDownloaded,
    isAvailable: true,
  };

  await ModelRegistry.registerModel(modelInfo);

  logger.info(`Registered model: ${modelId} (${options.name})${isDownloaded ? ' [already downloaded]' : ''}`);

  return modelInfo;
}

/**
 * Register a multi-file model (e.g., ONNX embedding model with vocab.txt, or VLM with mmproj).
 * All files are downloaded into the same directory so companion files are co-located.
 *
 * Matches iOS: RunAnywhere.registerMultiFileModel(id:name:files:framework:modality:memoryRequirement:)
 */
export async function registerMultiFileModel(options: {
  id: string;
  name: string;
  files: ModelFileDescriptor[];
  framework: LLMFramework;
  modality?: ModelCategory;
  memoryRequirement?: number;
}): Promise<ModelInfo> {
  const now = new Date().toISOString();

  MultiFileModelCache.set(options.id, options.files);

  let isDownloaded = false;
  let localPath: string | undefined;

  if (FileSystem.isAvailable()) {
    try {
      const frameworkDir = inferFrameworkDir(options.framework);
      const exists = await FileSystem.modelExists(options.id, frameworkDir);
      if (exists) {
        localPath = FileSystem.getModelFolder(options.id, frameworkDir);
        isDownloaded = true;
        logger.info(`Multi-file model ${options.id} found on disk: ${localPath}`);
      }
    } catch (error) {
      logger.debug(`Could not check for existing model ${options.id}: ${error}`);
    }
  }

  const modelInfo: ModelInfo = {
    id: options.id,
    name: options.name,
    category: options.modality ?? ModelCategory.MODEL_CATEGORY_LANGUAGE,
    format: ModelFormat.MODEL_FORMAT_ONNX,
    downloadURL: options.files[0]?.url,
    localPath,
    downloadSize: undefined,
    memoryRequired: options.memoryRequirement,
    compatibleFrameworks: [options.framework],
    preferredFramework: options.framework,
    supportsThinking: false,
    metadata: {
      tags: [],
      description: `Multi-file model (${options.files.length} files)`,
    },
    source: ConfigurationSource.Local,
    createdAt: now,
    updatedAt: now,
    syncPending: false,
    usageCount: 0,
    isDownloaded,
    isAvailable: true,
  };

  await ModelRegistry.registerModel(modelInfo);

  logger.info(
    `Registered multi-file model: ${options.id} (${options.name}, ${options.files.length} files)` +
    `${isDownloaded ? ' [already downloaded]' : ''}`
  );

  return modelInfo;
}

function inferFrameworkDir(framework: LLMFramework): string {
  switch (framework) {
    case 'ONNX': return 'ONNX';
    case 'LlamaCpp': return 'LlamaCpp';
    default: return framework;
  }
}

function getPreferredFramework(model: ModelInfo): LLMFramework | null {
  return model.preferredFramework ?? model.compatibleFrameworks[0] ?? null;
}

async function localPathExists(path: string): Promise<boolean> {
  try {
    if (await FileSystem.fileExists(path)) {
      return true;
    }
    return await FileSystem.directoryExists(path);
  } catch {
    return false;
  }
}

async function resolveDownloadedLocalPath(model: ModelInfo): Promise<string | undefined> {
  if (!FileSystem.isAvailable()) {
    return undefined;
  }

  if (model.localPath && await localPathExists(model.localPath)) {
    return model.localPath;
  }

  const framework = getPreferredFramework(model);
  if (!framework) {
    return undefined;
  }

  const frameworkDir = inferFrameworkDir(framework);
  const exists = await FileSystem.modelExists(model.id, frameworkDir);
  if (!exists) {
    return undefined;
  }

  if (frameworkDir === 'ONNX') {
    return FileSystem.getModelFolder(model.id, frameworkDir);
  }

  return FileSystem.getModelPath(model.id, frameworkDir);
}

async function reconcileLocalRegistryModels(options: {
  rescanLocal: boolean;
  pruneOrphans: boolean;
}): Promise<boolean> {
  if (!FileSystem.isAvailable()) {
    logger.warning('refreshModelRegistry: react-native-fs unavailable for local reconciliation');
    return false;
  }

  try {
    const models = await ModelRegistry.getAllModels();
    const now = new Date().toISOString();

    for (const model of models) {
      const discoveredPath =
        options.rescanLocal || model.localPath
          ? await resolveDownloadedLocalPath(model)
          : undefined;

      if (discoveredPath) {
        if (!model.isDownloaded || model.localPath !== discoveredPath) {
          await ModelRegistry.updateModel({
            ...model,
            localPath: discoveredPath,
            isDownloaded: true,
            isAvailable: true,
            updatedAt: now,
          });
        }
        continue;
      }

      if (options.pruneOrphans && (model.isDownloaded || model.localPath)) {
        await ModelRegistry.updateModel({
          ...model,
          localPath: undefined,
          isDownloaded: false,
          updatedAt: now,
        });
      }
    }

    return true;
  } catch (error) {
    logger.warning('refreshModelRegistry local reconciliation failed:', { error });
    return false;
  }
}

function inferFormat(url: string, framework?: LLMFramework): ModelFormat {
  const lower = url.toLowerCase();
  if (lower.includes('.gguf')) return ModelFormat.MODEL_FORMAT_GGUF;
  if (lower.includes('.onnx')) return ModelFormat.MODEL_FORMAT_ONNX;
  if (lower.includes('.zip')) return ModelFormat.MODEL_FORMAT_ZIP;
  // Archives (.tar.gz, .tar.bz2) are packaging, not format.
  // Derive format from framework: ONNX archives contain ONNX models.
  if (lower.includes('.tar.gz') || lower.includes('.tar.bz2')) {
    if (framework === 'ONNX') return ModelFormat.MODEL_FORMAT_ONNX;
    return ModelFormat.MODEL_FORMAT_GGUF;
  }
  if (framework === 'ONNX') return ModelFormat.MODEL_FORMAT_ONNX;
  return ModelFormat.MODEL_FORMAT_GGUF;
}

function generateModelId(url: string): string {
  const urlObj = new URL(url);
  const pathname = urlObj.pathname;
  const filename = pathname.split('/').pop() ?? 'model';
  return filename.replace(/\.(gguf|bin|safetensors|tar\.gz|zip)$/i, '');
}

// ============================================================================
// Model Download Extension
// ============================================================================

/**
 * Re-export the canonical proto `DownloadProgress` shape so existing
 * consumers of this module keep a single import surface. The shape is the
 * full 10-field `runanywhere.v1.DownloadProgress` message from
 * `@runanywhere/proto-ts/download_service`.
 */
export { DownloadProgress } from '@runanywhere/proto-ts/download_service';

function urlExtension(url: string): string {
  const lower = url.toLowerCase();
  if (lower.includes('.gguf')) return '.gguf';
  if (lower.includes('.onnx')) return '.onnx';
  if (lower.includes('.tar.bz2')) return '.tar.bz2';
  if (lower.includes('.tar.gz')) return '.tar.gz';
  if (lower.includes('.zip')) return '.zip';
  return '';
}

function isArchiveUrl(url: string): boolean {
  const lower = url.toLowerCase();
  return (
    lower.includes('.tar.bz2') ||
    lower.includes('.tar.gz') ||
    lower.includes('.zip')
  );
}

function buildCancelToken(modelId: string, suffix?: string): string {
  return suffix ? `${modelId}::${suffix}` : modelId;
}

/**
 * Download a model.
 *
 * Transport is owned by native C++ (`rac_http_download_execute`, which
 * routes through the registered platform HTTP transport — OkHttp on Android,
 * URLSession on iOS). `react-native-fs` is only used for filesystem path
 * resolution and existence checks. Cancellation is routed through the
 * native cancel-token registry.
 *
 * Per-tick progress is delivered as a JSON-encoded
 * `runanywhere.v1.DownloadProgress` from the native side; we decode it with
 * `DownloadProgress.fromJSON` from `@runanywhere/proto-ts`.
 */
export async function downloadModel(
  modelId: string,
  onProgress?: (progress: DownloadProgress) => void
): Promise<string> {
  const modelInfo = await ModelRegistry.getModel(modelId);
  if (!modelInfo) {
    throw new Error(`Model not found: ${modelId}`);
  }

  if (!modelInfo.downloadURL) {
    throw new Error(`Model has no download URL: ${modelId}`);
  }

  if (!FileSystem.isAvailable()) {
    throw new Error('react-native-fs not installed - cannot resolve model paths');
  }

  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available - cannot download models');
  }

  const native = requireNativeModule();
  const framework = modelInfo.preferredFramework;

  activeDownloads.add(modelId);
  let lastLoggedProgress = -1;

  /**
   * Decode the native progress JSON and forward a well-formed
   * `DownloadProgress` to the caller. `scaleOffset`/`scale` collapse
   * per-file progress into the [0,1] range spanning the full multi-file
   * download.
   */
  const emit = (progressJson: string, scaleOffset = 0, scale = 1) => {
    let raw: DownloadProgress;
    try {
      raw = DownloadProgress.fromJSON(JSON.parse(progressJson));
    } catch (err) {
      logger.warning(`Failed to decode DownloadProgress JSON: ${err}`);
      return;
    }

    const bytesDownloaded = raw.bytesDownloaded ?? 0;
    const totalBytes = raw.totalBytes || modelInfo.downloadSize || 0;
    const stageProgress = totalBytes > 0 ? bytesDownloaded / totalBytes : raw.stageProgress ?? 0;
    const overallProgress = scaleOffset + stageProgress * scale;

    const pct = Math.round(overallProgress * 100);
    if (pct - lastLoggedProgress >= 10) {
      logger.debug(`Download progress: ${pct}%`);
      lastLoggedProgress = pct;
    }

    if (onProgress) {
      // Forward the full 10-field shape, overriding the fields we can
      // derive on the JS side (modelId is authoritative here; stageProgress
      // is rescaled for multi-file downloads).
      onProgress(
        DownloadProgress.fromPartial({
          ...raw,
          modelId,
          bytesDownloaded,
          totalBytes,
          stageProgress: overallProgress,
        })
      );
    }
  };

  try {
    const multiFileDescriptors = MultiFileModelCache.get(modelId);
    if (multiFileDescriptors && multiFileDescriptors.length > 0) {
      logger.info('Starting multi-file download (native):', {
        modelId,
        fileCount: multiFileDescriptors.length,
      });

      const frameworkDir = framework || 'ONNX';
      const destFolder = FileSystem.getModelFolder(modelId, frameworkDir);

      await FileSystem.ensureDirectory(FileSystem.getRunAnywhereDirectory());
      await FileSystem.ensureDirectory(FileSystem.getModelsDirectory());
      await FileSystem.ensureDirectory(FileSystem.getFrameworkDirectory(frameworkDir));
      await FileSystem.ensureDirectory(destFolder);

      const fileCount = multiFileDescriptors.length;

      for (let index = 0; index < fileCount; index++) {
        const fileDescriptor = multiFileDescriptors[index];
        const fileDestination = `${destFolder}/${fileDescriptor.filename}`;

        if (await FileSystem.fileExists(fileDestination)) {
          logger.info(`File already exists, skipping: ${fileDescriptor.filename}`);
          continue;
        }

        logger.info(`Downloading file ${index + 1}/${fileCount}: ${fileDescriptor.filename}`);

        const offset = index / fileCount;
        const scale = 1.0 / fileCount;
        const token = buildCancelToken(modelId, `${index}`);

        await native.downloadModel(
          fileDescriptor.url,
          fileDestination,
          token,
          (progressJson: string) => emit(progressJson, offset, scale),
          fileDescriptor.checksumSha256,
        );

        logger.info(`Completed file ${index + 1}/${fileCount}: ${fileDescriptor.filename}`);
      }

      logger.info('Multi-file download completed:', { modelId, destFolder });

      const updatedModel: ModelInfo = {
        ...modelInfo,
        localPath: destFolder,
        isDownloaded: true,
      };
      await ModelRegistry.updateModel(updatedModel);

      return destFolder;
    }

    // Single-file model — decide destination (archive vs direct model file).
    const frameworkDir = framework || 'LlamaCpp';
    const folder = FileSystem.getModelFolder(modelId, frameworkDir);
    await FileSystem.ensureDirectory(FileSystem.getRunAnywhereDirectory());
    await FileSystem.ensureDirectory(FileSystem.getModelsDirectory());
    await FileSystem.ensureDirectory(FileSystem.getFrameworkDirectory(frameworkDir));
    await FileSystem.ensureDirectory(folder);

    const needsExtraction = isArchiveUrl(modelInfo.downloadURL);
    const extension = urlExtension(modelInfo.downloadURL);
    const fileName = needsExtraction
      ? `${modelId}_${Date.now()}.tmp`
      : `${modelId}${extension}`;
    const destPath = needsExtraction
      ? `${FileSystem.getCacheDirectory()}/${fileName}`
      : `${folder}/${fileName}`;

    if (!needsExtraction && (await FileSystem.fileExists(destPath))) {
      logger.info(`Model already exists on disk: ${destPath}`);
      const updatedModel: ModelInfo = {
        ...modelInfo,
        localPath: destPath,
        isDownloaded: true,
      };
      await ModelRegistry.updateModel(updatedModel);
      return destPath;
    }

    logger.info('Starting download (native):', {
      modelId,
      url: modelInfo.downloadURL,
      destPath,
    });

    await native.downloadModel(
      modelInfo.downloadURL,
      destPath,
      buildCancelToken(modelId),
      (progressJson: string) => emit(progressJson),
      modelInfo.checksumSha256,
    );

    let finalPath = destPath;
    if (needsExtraction) {
      logger.info(`Extracting archive for ${frameworkDir}...`);
      try {
        finalPath = await FileSystem.extractArchive(destPath, folder);
        await FileSystem.deleteFile(destPath);
      } catch (extractError) {
        await FileSystem.deleteFile(destPath).catch(() => undefined);
        throw new Error(`Archive extraction failed: ${extractError}`);
      }
    }

    logger.info('Download completed:', { modelId, destPath: finalPath });

    const updatedModel: ModelInfo = {
      ...modelInfo,
      localPath: finalPath,
      isDownloaded: true,
    };
    await ModelRegistry.updateModel(updatedModel);

    return finalPath;
  } finally {
    activeDownloads.delete(modelId);
  }
}

/**
 * Cancel an ongoing download via the native cancel-token registry.
 * All cancel tokens emitted for this modelId (base + per-file for multi-file
 * downloads) are signalled so the in-flight request aborts.
 */
export async function cancelDownload(modelId: string): Promise<boolean> {
  if (!activeDownloads.has(modelId)) return false;
  if (!isNativeModuleAvailable()) return false;

  const native = requireNativeModule();
  const baseToken = buildCancelToken(modelId);
  let cancelled = await native.cancelDownload(baseToken);
  // Best-effort cancel for per-file tokens (multi-file downloads). We probe
  // a bounded range because the file count is not retained here.
  for (let i = 0; i < 64; i++) {
    const token = buildCancelToken(modelId, `${i}`);
    const ok = await native.cancelDownload(token);
    cancelled = cancelled || ok;
    if (!ok) break;
  }
  activeDownloads.delete(modelId);
  if (cancelled) logger.info(`Cancelled download: ${modelId}`);
  return cancelled;
}

/**
 * Delete a downloaded model
 */
export async function deleteModel(modelId: string): Promise<boolean> {
  try {
    const modelInfo = await ModelRegistry.getModel(modelId);
    const url = modelInfo?.downloadURL ?? '';
    let extension = '';
    if (url.includes('.gguf')) {
      extension = '.gguf';
    } else if (url.includes('.onnx')) {
      extension = '.onnx';
    } else if (url.includes('.tar.bz2')) {
      extension = '.tar.bz2';
    } else if (url.includes('.tar.gz')) {
      extension = '.tar.gz';
    } else if (url.includes('.zip')) {
      extension = '.zip';
    }
    const fileName = `${modelId}${extension}`;

    // Delete using FileSystem service
    const deleted = await FileSystem.deleteModel(fileName);
    if (deleted) {
      logger.info(`Deleted model: ${modelId}`);
    }

    // Also try plain model ID in case of different naming
    await FileSystem.deleteModel(modelId);

    // Update model in registry
    if (modelInfo) {
      const updatedModel: ModelInfo = {
        ...modelInfo,
        localPath: undefined,
        isDownloaded: false,
      };
      await ModelRegistry.updateModel(updatedModel);
    }

    return true;
  } catch (error) {
    logger.error('Delete model error:', { error });
    return false;
  }
}

/**
 * Delete all downloaded models while keeping catalog entries registered.
 */
export async function deleteAllModels(): Promise<boolean> {
  const downloaded = await getDownloadedModels();
  let ok = true;
  for (const model of downloaded) {
    ok = (await deleteModel(model.id)) && ok;
  }
  return ok;
}

/**
 * Check if a model is compatible with the current device
 * Returns RAM and storage compatibility info
 */
export async function checkCompatibility(modelId: string): Promise<ModelCompatibilityResult> {
  return ModelRegistry.checkCompatibility(modelId);
}
