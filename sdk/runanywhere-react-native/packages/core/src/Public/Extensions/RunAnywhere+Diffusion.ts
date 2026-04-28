/**
 * RunAnywhere+Diffusion.ts
 *
 * Public API for diffusion (image generation) operations on the RN SDK.
 * Routes through the C++ component layer for architectural consistency with
 * LLM/STT/TTS. Mirrors the Swift surface so callers writing against either
 * SDK have a 1:1 method set.
 *
 * Matches iOS: RunAnywhere+Diffusion.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import type {
  DiffusionConfiguration,
  DiffusionGenerationOptions,
  DiffusionProgress,
  DiffusionResult,
  DiffusionCapabilities,
  DiffusionStreamingResult,
} from '../../types/DiffusionTypes';
import { DiffusionMode, DiffusionScheduler } from '../../types/DiffusionTypes';

const logger = new SDKLogger('RunAnywhere.Diffusion');

/**
 * Diffusion native dispatch surface. All methods are optional so the bridge
 * layer can ship without diffusion support on platforms where it is not yet
 * implemented (e.g. Android prior to NNAPI image-gen support).
 */
interface DiffusionNativeModule {
  diffusionLoadModel?: (
    modelPath: string,
    modelId: string,
    modelName: string,
    configJson: string | undefined
  ) => Promise<boolean>;
  diffusionUnloadModel?: () => Promise<boolean>;
  diffusionIsModelLoaded?: () => Promise<boolean>;
  diffusionCurrentModelId?: () => Promise<string>;
  diffusionGenerate?: (optionsJson: string) => Promise<string>;
  diffusionGenerateStream?: (
    optionsJson: string,
    onProgress: (progressJson: string) => void
  ) => Promise<string>;
  diffusionCancel?: () => Promise<boolean>;
  diffusionGetCapabilities?: () => Promise<string>;
  diffusionCurrentFramework?: () => Promise<string>;
}

function getNative(): DiffusionNativeModule {
  return requireNativeModule() as unknown as DiffusionNativeModule;
}

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    const byte = bytes[i];
    if (byte !== undefined) binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function normaliseImage(value: string | ArrayBuffer | undefined): string | null {
  if (!value) return null;
  if (typeof value === 'string') return value;
  return arrayBufferToBase64(value);
}

function serialiseOptions(opts: DiffusionGenerationOptions): string {
  return JSON.stringify({
    prompt: opts.prompt,
    negative_prompt: opts.negativePrompt ?? '',
    width: opts.width ?? 512,
    height: opts.height ?? 512,
    steps: opts.steps ?? 28,
    guidance_scale: opts.guidanceScale ?? 7.5,
    seed: opts.seed ?? -1,
    scheduler: opts.scheduler ?? DiffusionScheduler.DPMPP2MKarras,
    mode: opts.mode ?? DiffusionMode.TextToImage,
    input_image: normaliseImage(opts.inputImage),
    mask_image: normaliseImage(opts.maskImage),
    denoise_strength: opts.denoiseStrength ?? 0.75,
    report_intermediate_images: opts.reportIntermediateImages ?? false,
    progress_stride: opts.progressStride ?? 1,
  });
}

function parseResult(json: string): DiffusionResult {
  const parsed = JSON.parse(json) as {
    image_data?: string;
    imageData?: string;
    width?: number;
    height?: number;
    seed_used?: number;
    seedUsed?: number;
    generation_time_ms?: number;
    generationTimeMs?: number;
    safety_flagged?: boolean;
    safetyFlagged?: boolean;
  };
  return {
    imageData: parsed.image_data ?? parsed.imageData ?? '',
    width: parsed.width ?? 0,
    height: parsed.height ?? 0,
    seedUsed: parsed.seed_used ?? parsed.seedUsed ?? 0,
    generationTimeMs: parsed.generation_time_ms ?? parsed.generationTimeMs ?? 0,
    safetyFlagged: parsed.safety_flagged ?? parsed.safetyFlagged ?? false,
  };
}

function parseProgress(json: string): DiffusionProgress {
  const parsed = JSON.parse(json) as {
    progress?: number;
    current_step?: number;
    currentStep?: number;
    total_steps?: number;
    totalSteps?: number;
    stage?: string;
    intermediate_image?: string;
    intermediateImage?: string;
  };
  return {
    progress: parsed.progress ?? 0,
    currentStep: parsed.current_step ?? parsed.currentStep ?? 0,
    totalSteps: parsed.total_steps ?? parsed.totalSteps ?? 0,
    stage: parsed.stage ?? 'Processing',
    intermediateImage: parsed.intermediate_image ?? parsed.intermediateImage,
  };
}

// ============================================================================
// Model Lifecycle
// ============================================================================

/**
 * Load a diffusion model.
 *
 * Expects a CoreML model directory containing .mlmodelc files
 * (Unet.mlmodelc, TextEncoder.mlmodelc, etc.).
 *
 * Matches Swift: `RunAnywhere.loadDiffusionModel(modelPath:modelId:modelName:configuration:)`
 */
export async function loadDiffusionModel(
  modelPath: string,
  modelId: string,
  modelName: string,
  configuration?: DiffusionConfiguration
): Promise<void> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = getNative();
  if (!native.diffusionLoadModel) {
    throw new Error('Diffusion is not supported on this platform yet');
  }
  const configJson = configuration
    ? JSON.stringify({
        model_id: configuration.modelId,
        model_variant: configuration.modelVariant,
        enable_safety_checker: configuration.enableSafetyChecker ?? true,
        reduce_memory: configuration.reduceMemory ?? false,
        preferred_framework: configuration.preferredFramework,
        tokenizer_source: configuration.tokenizerSource,
      })
    : undefined;
  const ok = await native.diffusionLoadModel(
    modelPath,
    modelId,
    modelName,
    configJson
  );
  if (!ok) {
    throw new Error(`Failed to load diffusion model: ${modelId}`);
  }
  logger.info(`Diffusion model loaded: ${modelId}`);
}

/**
 * Unload the current diffusion model.
 *
 * Matches Swift: `RunAnywhere.unloadDiffusionModel()`
 */
export async function unloadDiffusionModel(): Promise<void> {
  if (!isNativeModuleAvailable()) return;
  const native = getNative();
  if (!native.diffusionUnloadModel) return;
  await native.diffusionUnloadModel();
  logger.info('Diffusion model unloaded');
}

/**
 * Check if a diffusion model is loaded.
 *
 * Matches Swift: `RunAnywhere.isDiffusionModelLoaded`
 */
export async function isDiffusionModelLoaded(): Promise<boolean> {
  if (!isNativeModuleAvailable()) return false;
  const native = getNative();
  if (!native.diffusionIsModelLoaded) return false;
  return native.diffusionIsModelLoaded();
}

/**
 * Get the currently loaded diffusion model ID.
 *
 * Matches Swift: `RunAnywhere.currentDiffusionModelId`
 */
export async function currentDiffusionModelId(): Promise<string | null> {
  if (!isNativeModuleAvailable()) return null;
  const native = getNative();
  if (!native.diffusionCurrentModelId) return null;
  const id = await native.diffusionCurrentModelId();
  return id && id.length > 0 ? id : null;
}

/**
 * Get the currently loaded inference framework name (e.g. "coreml").
 *
 * Matches Swift: `RunAnywhere.currentDiffusionFramework`
 */
export async function currentDiffusionFramework(): Promise<string | null> {
  if (!isNativeModuleAvailable()) return null;
  const native = getNative();
  if (!native.diffusionCurrentFramework) return null;
  const framework = await native.diffusionCurrentFramework();
  return framework && framework.length > 0 ? framework : null;
}

// ============================================================================
// Generation
// ============================================================================

/**
 * Generate an image from a text prompt.
 *
 * Matches Swift: `RunAnywhere.generateImage(prompt:options:)`
 */
export async function generateImage(
  prompt: string,
  options?: DiffusionGenerationOptions
): Promise<DiffusionResult> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = getNative();
  if (!native.diffusionGenerate) {
    throw new Error('Diffusion is not supported on this platform yet');
  }
  const opts: DiffusionGenerationOptions = {
    prompt,
    ...(options ?? {}),
  };
  const optionsJson = serialiseOptions(opts);
  const json = await native.diffusionGenerate(optionsJson);
  return parseResult(json);
}

/**
 * Generate an image with progress streaming.
 *
 * Returns an AsyncIterable of progress events plus a Promise for the final
 * result. Pattern mirrors `generateStream` for LLMs and `processImageStream`
 * for VLMs.
 *
 * Matches Swift: `RunAnywhere.generateImageStream(prompt:options:)`
 */
export async function generateImageStream(
  prompt: string,
  options?: DiffusionGenerationOptions
): Promise<DiffusionStreamingResult> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = getNative();
  if (!native.diffusionGenerateStream) {
    throw new Error('Diffusion streaming is not supported on this platform yet');
  }

  // Force-enable intermediate image reporting for streaming consumers.
  const opts: DiffusionGenerationOptions = {
    prompt,
    ...(options ?? {}),
    reportIntermediateImages: options?.reportIntermediateImages ?? true,
    progressStride: options?.progressStride ?? 1,
  };
  const optionsJson = serialiseOptions(opts);

  const queue: DiffusionProgress[] = [];
  let resolver: ((value: IteratorResult<DiffusionProgress>) => void) | null =
    null;
  let done = false;
  let streamError: Error | null = null;
  let cancelled = false;

  let resolveResult!: (value: DiffusionResult) => void;
  let rejectResult!: (error: Error) => void;
  const resultPromise = new Promise<DiffusionResult>((resolve, reject) => {
    resolveResult = resolve;
    rejectResult = reject;
  });

  native
    .diffusionGenerateStream(optionsJson, (progressJson: string) => {
      if (cancelled) return;
      try {
        const progress = parseProgress(progressJson);
        if (resolver) {
          resolver({ value: progress, done: false });
          resolver = null;
        } else {
          queue.push(progress);
        }
      } catch (err) {
        logger.warning(`Failed to parse diffusion progress: ${String(err)}`);
      }
    })
    .then((resultJson: string) => {
      const result = parseResult(resultJson);
      done = true;
      resolveResult(result);
      if (resolver) {
        resolver({ value: undefined as unknown as DiffusionProgress, done: true });
        resolver = null;
      }
    })
    .catch((err: Error) => {
      streamError = err;
      done = true;
      rejectResult(err);
      if (resolver) {
        resolver({ value: undefined as unknown as DiffusionProgress, done: true });
        resolver = null;
      }
    });

  async function* progressGenerator(): AsyncGenerator<DiffusionProgress> {
    while (!done || queue.length > 0) {
      if (queue.length > 0) {
        yield queue.shift()!;
      } else if (!done) {
        const next = await new Promise<IteratorResult<DiffusionProgress>>(
          (resolve) => {
            resolver = resolve;
          }
        );
        if (next.done) break;
        yield next.value;
      }
    }
    if (streamError) throw streamError;
  }

  const cancel = (): void => {
    cancelled = true;
    void cancelImageGeneration();
    if (resolver) {
      done = true;
      resolver({ value: undefined as unknown as DiffusionProgress, done: true });
      resolver = null;
    }
  };

  return {
    progress: progressGenerator(),
    result: resultPromise,
    cancel,
  };
}

/**
 * Cancel ongoing image generation.
 *
 * Matches Swift: `RunAnywhere.cancelImageGeneration()`
 */
export async function cancelImageGeneration(): Promise<void> {
  if (!isNativeModuleAvailable()) return;
  const native = getNative();
  if (!native.diffusionCancel) return;
  await native.diffusionCancel();
}

/**
 * Get diffusion service capabilities.
 *
 * Matches Swift: `RunAnywhere.getDiffusionCapabilities()`
 */
export async function getDiffusionCapabilities(): Promise<DiffusionCapabilities> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = getNative();
  if (!native.diffusionGetCapabilities) {
    return {
      supportedVariants: [],
      supportedSchedulers: [],
      supportedModes: [],
      maxWidth: 0,
      maxHeight: 0,
      supportsIntermediateImages: false,
    };
  }
  const json = await native.diffusionGetCapabilities();
  try {
    const parsed = JSON.parse(json);
    return {
      supportedVariants: parsed.supported_variants ?? parsed.supportedVariants ?? [],
      supportedSchedulers:
        parsed.supported_schedulers ?? parsed.supportedSchedulers ?? [],
      supportedModes: parsed.supported_modes ?? parsed.supportedModes ?? [],
      maxWidth: parsed.max_width ?? parsed.maxWidth ?? 0,
      maxHeight: parsed.max_height ?? parsed.maxHeight ?? 0,
      supportsIntermediateImages:
        parsed.supports_intermediate_images ??
        parsed.supportsIntermediateImages ??
        false,
    };
  } catch {
    return {
      supportedVariants: [],
      supportedSchedulers: [],
      supportedModes: [],
      maxWidth: 0,
      maxHeight: 0,
      supportsIntermediateImages: false,
    };
  }
}
