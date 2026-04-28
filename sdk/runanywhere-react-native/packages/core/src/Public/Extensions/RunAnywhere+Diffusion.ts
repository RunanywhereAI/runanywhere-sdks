/**
 * RunAnywhere+Diffusion.ts
 *
 * Public API for diffusion (image generation) operations on the RN SDK.
 * Wave 2: aligned to proto-canonical Diffusion shapes
 * (`@runanywhere/proto-ts/diffusion_options`).
 *
 * Matches Swift: `Public/Extensions/Diffusion/RunAnywhere+Diffusion.swift`.
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import {
  type DiffusionConfiguration,
  type DiffusionGenerationOptions,
  type DiffusionProgress,
  type DiffusionResult,
  type DiffusionCapabilities,
  DiffusionMode,
  DiffusionScheduler,
  DiffusionModelVariant,
} from '@runanywhere/proto-ts/diffusion_options';

const logger = new SDKLogger('RunAnywhere.Diffusion');

/**
 * RN-local streaming wrapper. Mirrors the LLM/VLM streaming primitive
 * shape with `progress` (events) + `result` (final) + `cancel`.
 */
export interface DiffusionStreamingResult {
  progress: AsyncIterable<DiffusionProgress>;
  result: Promise<DiffusionResult>;
  cancel: () => void;
}

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

/** Decode a base64 string to a `Uint8Array`. */
function base64ToBytes(b64: string): Uint8Array {
  if (!b64) return new Uint8Array(0);
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function serialiseOptions(opts: DiffusionGenerationOptions): string {
  return JSON.stringify({
    prompt: opts.prompt,
    negative_prompt: opts.negativePrompt ?? '',
    width: opts.width ?? 0,
    height: opts.height ?? 0,
    num_inference_steps: opts.numInferenceSteps ?? 0,
    guidance_scale: opts.guidanceScale ?? 7.5,
    seed: opts.seed ?? -1,
    scheduler:
      opts.scheduler ?? DiffusionScheduler.DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS,
    mode: opts.mode ?? DiffusionMode.DIFFUSION_MODE_TEXT_TO_IMAGE,
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
    total_time_ms?: number;
    totalTimeMs?: number;
    generation_time_ms?: number;
    generationTimeMs?: number;
    safety_flag?: boolean;
    safetyFlag?: boolean;
    safety_flagged?: boolean;
    safetyFlagged?: boolean;
    used_scheduler?: number;
    usedScheduler?: number;
  };
  const totalTimeMs =
    parsed.total_time_ms ??
    parsed.totalTimeMs ??
    parsed.generation_time_ms ??
    parsed.generationTimeMs ??
    0;
  const safetyFlag =
    parsed.safety_flag ??
    parsed.safetyFlag ??
    parsed.safety_flagged ??
    parsed.safetyFlagged ??
    false;
  return {
    imageData: base64ToBytes(parsed.image_data ?? parsed.imageData ?? ''),
    width: parsed.width ?? 0,
    height: parsed.height ?? 0,
    seedUsed: parsed.seed_used ?? parsed.seedUsed ?? 0,
    totalTimeMs,
    safetyFlag,
    usedScheduler:
      parsed.used_scheduler ??
      parsed.usedScheduler ??
      DiffusionScheduler.DIFFUSION_SCHEDULER_UNSPECIFIED,
  };
}

function parseProgress(json: string): DiffusionProgress {
  const parsed = JSON.parse(json) as {
    progress?: number;
    progress_percent?: number;
    progressPercent?: number;
    current_step?: number;
    currentStep?: number;
    total_steps?: number;
    totalSteps?: number;
    stage?: string;
    intermediate_image?: string;
    intermediateImage?: string;
    intermediate_image_data?: string;
    intermediateImageData?: string;
  };
  const intermediateBase64 =
    parsed.intermediate_image_data ??
    parsed.intermediateImageData ??
    parsed.intermediate_image ??
    parsed.intermediateImage;
  return {
    progressPercent:
      parsed.progress_percent ?? parsed.progressPercent ?? parsed.progress ?? 0,
    currentStep: parsed.current_step ?? parsed.currentStep ?? 0,
    totalSteps: parsed.total_steps ?? parsed.totalSteps ?? 0,
    stage: parsed.stage ?? 'Processing',
    intermediateImageData: intermediateBase64
      ? base64ToBytes(intermediateBase64)
      : undefined,
  };
}

// ============================================================================
// Model Lifecycle
// ============================================================================

/**
 * Load a diffusion model.
 *
 * Matches Swift: `RunAnywhere.loadDiffusionModel(modelPath:modelId:modelName:configuration:)`.
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
        model_variant: configuration.modelVariant,
        enable_safety_checker: configuration.enableSafetyChecker ?? true,
        max_memory_mb: configuration.maxMemoryMb ?? 0,
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

/** Unload the current diffusion model. */
export async function unloadDiffusionModel(): Promise<void> {
  if (!isNativeModuleAvailable()) return;
  const native = getNative();
  if (!native.diffusionUnloadModel) return;
  await native.diffusionUnloadModel();
  logger.info('Diffusion model unloaded');
}

/** Whether a diffusion model is loaded. */
export async function isDiffusionModelLoaded(): Promise<boolean> {
  if (!isNativeModuleAvailable()) return false;
  const native = getNative();
  if (!native.diffusionIsModelLoaded) return false;
  return native.diffusionIsModelLoaded();
}

/** Get the currently loaded diffusion model ID. */
export async function currentDiffusionModelId(): Promise<string | null> {
  if (!isNativeModuleAvailable()) return null;
  const native = getNative();
  if (!native.diffusionCurrentModelId) return null;
  const id = await native.diffusionCurrentModelId();
  return id && id.length > 0 ? id : null;
}

/** Get the currently loaded inference framework name (e.g. "coreml"). */
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
 * Matches Swift: `RunAnywhere.generateImage(prompt:options:)`.
 */
export async function generateImage(
  prompt: string,
  options?: Partial<DiffusionGenerationOptions>
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
    negativePrompt: options?.negativePrompt ?? '',
    width: options?.width ?? 0,
    height: options?.height ?? 0,
    numInferenceSteps: options?.numInferenceSteps ?? 0,
    guidanceScale: options?.guidanceScale ?? 7.5,
    seed: options?.seed ?? -1,
    scheduler:
      options?.scheduler ?? DiffusionScheduler.DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS,
    mode: options?.mode ?? DiffusionMode.DIFFUSION_MODE_TEXT_TO_IMAGE,
  };
  const optionsJson = serialiseOptions(opts);
  const json = await native.diffusionGenerate(optionsJson);
  return parseResult(json);
}

/**
 * Generate an image with progress streaming.
 *
 * Matches Swift: `RunAnywhere.generateImageStream(prompt:options:)`.
 */
export async function generateImageStream(
  prompt: string,
  options?: Partial<DiffusionGenerationOptions>
): Promise<DiffusionStreamingResult> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = getNative();
  if (!native.diffusionGenerateStream) {
    throw new Error('Diffusion streaming is not supported on this platform yet');
  }

  const opts: DiffusionGenerationOptions = {
    prompt,
    negativePrompt: options?.negativePrompt ?? '',
    width: options?.width ?? 0,
    height: options?.height ?? 0,
    numInferenceSteps: options?.numInferenceSteps ?? 0,
    guidanceScale: options?.guidanceScale ?? 7.5,
    seed: options?.seed ?? -1,
    scheduler:
      options?.scheduler ?? DiffusionScheduler.DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS,
    mode: options?.mode ?? DiffusionMode.DIFFUSION_MODE_TEXT_TO_IMAGE,
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

/** Cancel ongoing image generation. */
export async function cancelImageGeneration(): Promise<void> {
  if (!isNativeModuleAvailable()) return;
  const native = getNative();
  if (!native.diffusionCancel) return;
  await native.diffusionCancel();
}

/**
 * Get diffusion service capabilities.
 *
 * Matches Swift: `RunAnywhere.getDiffusionCapabilities()`.
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
      maxResolutionPx: 0,
    };
  }
  const json = await native.diffusionGetCapabilities();
  try {
    const parsed = JSON.parse(json) as {
      supported_variants?: DiffusionModelVariant[];
      supportedVariants?: DiffusionModelVariant[];
      supported_schedulers?: DiffusionScheduler[];
      supportedSchedulers?: DiffusionScheduler[];
      max_width?: number;
      maxWidth?: number;
      max_height?: number;
      maxHeight?: number;
      max_resolution_px?: number;
      maxResolutionPx?: number;
    };
    const maxResolutionPx =
      parsed.max_resolution_px ??
      parsed.maxResolutionPx ??
      Math.max(
        parsed.max_width ?? parsed.maxWidth ?? 0,
        parsed.max_height ?? parsed.maxHeight ?? 0
      );
    return {
      supportedVariants:
        parsed.supported_variants ?? parsed.supportedVariants ?? [],
      supportedSchedulers:
        parsed.supported_schedulers ?? parsed.supportedSchedulers ?? [],
      maxResolutionPx,
    };
  } catch {
    return {
      supportedVariants: [],
      supportedSchedulers: [],
      maxResolutionPx: 0,
    };
  }
}
