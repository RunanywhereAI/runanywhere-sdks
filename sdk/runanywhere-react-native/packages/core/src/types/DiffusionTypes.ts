/**
 * DiffusionTypes.ts
 *
 * Type definitions for diffusion (image generation) functionality.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Diffusion/DiffusionTypes.swift
 */

/**
 * Tokenizer source for Stable Diffusion models.
 * Apple's compiled CoreML models don't include tokenizer files, so they must
 * be downloaded separately. This specifies which HuggingFace repository to
 * download them from.
 *
 * Matches Swift: `DiffusionTokenizerSource`
 */
export type DiffusionTokenizerSource =
  | { kind: 'sd15' }
  | { kind: 'sd2' }
  | { kind: 'sdxl' }
  | { kind: 'custom'; baseURL: string };

/**
 * Stable Diffusion model variants.
 *
 * Matches Swift: `DiffusionModelVariant`
 */
export enum DiffusionModelVariant {
  /** Stable Diffusion 1.5 (512x512 default) */
  SD15 = 'sd15',
  /** Stable Diffusion 2.1 (768x768 default) */
  SD21 = 'sd21',
  /** SDXL (1024x1024 default, requires 8GB+ RAM) */
  SDXL = 'sdxl',
  /** SDXL Turbo - Fast 4-step, no CFG needed */
  SDXLTurbo = 'sdxl_turbo',
  /** SDXS - Ultra-fast 1-step, no CFG needed */
  SDXS = 'sdxs',
  /** LCM (Latent Consistency Model) - Fast 4-step with low CFG */
  LCM = 'lcm',
}

/**
 * Diffusion scheduler/sampler types for the denoising process.
 *
 * Matches Swift: `DiffusionScheduler`
 */
export enum DiffusionScheduler {
  /** DPM++ 2M Karras - Recommended for best quality/speed tradeoff */
  DPMPP2MKarras = 'dpm++_2m_karras',
  /** DPM++ 2M */
  DPMPP2M = 'dpm++_2m',
  /** DPM++ 2M SDE */
  DPMPP2MSDE = 'dpm++_2m_sde',
  /** DDIM */
  DDIM = 'ddim',
  /** Euler */
  Euler = 'euler',
  /** Euler Ancestral */
  EulerAncestral = 'euler_a',
  /** PNDM */
  PNDM = 'pndm',
  /** LMS */
  LMS = 'lms',
}

/**
 * Generation mode for diffusion.
 *
 * Matches Swift: `DiffusionMode`
 */
export enum DiffusionMode {
  /** Generate image from text prompt */
  TextToImage = 'txt2img',
  /** Transform input image with prompt */
  ImageToImage = 'img2img',
  /** Edit specific regions with mask */
  Inpainting = 'inpainting',
}

/**
 * Configuration for the diffusion component.
 *
 * Matches Swift: `DiffusionConfiguration`
 */
export interface DiffusionConfiguration {
  /** Model ID (optional - uses default if not specified) */
  modelId?: string;

  /** Model variant (SD 1.5, SD 2.1, SDXL, etc.) */
  modelVariant?: DiffusionModelVariant;

  /** Enable safety checker for NSFW content filtering */
  enableSafetyChecker?: boolean;

  /** Reduce memory footprint (may reduce quality) */
  reduceMemory?: boolean;

  /** Preferred framework for generation */
  preferredFramework?: string;

  /**
   * Tokenizer source for downloading missing tokenizer files.
   * If undefined, defaults to the tokenizer matching the model variant.
   */
  tokenizerSource?: DiffusionTokenizerSource;
}

/**
 * Options for image generation.
 *
 * Matches Swift: `DiffusionGenerationOptions`
 */
export interface DiffusionGenerationOptions {
  /** Text prompt describing the desired image */
  prompt: string;

  /** Negative prompt - things to avoid in the image */
  negativePrompt?: string;

  /** Output image width in pixels */
  width?: number;

  /** Output image height in pixels */
  height?: number;

  /** Number of denoising steps (10-50, default: 28) */
  steps?: number;

  /** Classifier-free guidance scale (1.0-20.0, default: 7.5) */
  guidanceScale?: number;

  /** Random seed for reproducibility (-1 for random) */
  seed?: number;

  /** Scheduler/sampler algorithm */
  scheduler?: DiffusionScheduler;

  /** Generation mode */
  mode?: DiffusionMode;

  /** Input image data for img2img/inpainting (base64 or ArrayBuffer of PNG/JPEG) */
  inputImage?: string | ArrayBuffer;

  /** Mask image data for inpainting (base64 or ArrayBuffer of grayscale PNG) */
  maskImage?: string | ArrayBuffer;

  /** Denoising strength for img2img (0.0-1.0) */
  denoiseStrength?: number;

  /** Report intermediate images during generation */
  reportIntermediateImages?: boolean;

  /** Report progress every N steps */
  progressStride?: number;
}

/**
 * Progress update during image generation.
 *
 * Matches Swift: `DiffusionProgress`
 */
export interface DiffusionProgress {
  /** Progress percentage (0.0 - 1.0) */
  progress: number;

  /** Current step number (1-based) */
  currentStep: number;

  /** Total number of steps */
  totalSteps: number;

  /** Current stage description */
  stage: string;

  /** Intermediate image data (base64 PNG, available if requested) */
  intermediateImage?: string;
}

/**
 * Result of image generation.
 *
 * Matches Swift: `DiffusionResult`
 */
export interface DiffusionResult {
  /** Generated image data (base64 PNG) */
  imageData: string;

  /** Image width in pixels */
  width: number;

  /** Image height in pixels */
  height: number;

  /** Seed used for generation (for reproducibility) */
  seedUsed: number;

  /** Total generation time in milliseconds */
  generationTimeMs: number;

  /** Whether the image was flagged by safety checker */
  safetyFlagged?: boolean;
}

/**
 * Diffusion service capabilities.
 *
 * Matches Swift: `DiffusionCapabilities`
 */
export interface DiffusionCapabilities {
  /** Supported model variants */
  supportedVariants: DiffusionModelVariant[];

  /** Supported schedulers */
  supportedSchedulers: DiffusionScheduler[];

  /** Supported modes */
  supportedModes: DiffusionMode[];

  /** Maximum supported width */
  maxWidth: number;

  /** Maximum supported height */
  maxHeight: number;

  /** Whether intermediate images are supported */
  supportsIntermediateImages: boolean;
}

/**
 * Streaming result for diffusion image generation.
 *
 * Mirrors the LLM/VLM streaming pattern: AsyncIterable for progress events
 * plus a Promise for the final DiffusionResult.
 */
export interface DiffusionStreamingResult {
  /** Async iterator for progress events */
  progress: AsyncIterable<DiffusionProgress>;

  /** Promise that resolves to the final image result */
  result: Promise<DiffusionResult>;

  /** Cancel the generation */
  cancel: () => void;
}
