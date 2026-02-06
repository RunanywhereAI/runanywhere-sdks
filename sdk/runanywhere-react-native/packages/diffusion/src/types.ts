/**
 * Diffusion Types for React Native SDK
 *
 * Matches Swift DiffusionTypes.swift and Kotlin DiffusionTypes.kt
 */

// ============================================================================
// Tokenizer Source
// ============================================================================

export type DiffusionTokenizerSource =
  | { type: 'sd15' }
  | { type: 'sd2' }
  | { type: 'sdxl' }
  | { type: 'custom'; baseURL: string };

export const DiffusionTokenizerSources = {
  SD15: { type: 'sd15' } as const,
  SD2: { type: 'sd2' } as const,
  SDXL: { type: 'sdxl' } as const,
  Custom: (baseURL: string): DiffusionTokenizerSource => ({
    type: 'custom',
    baseURL,
  }),
};

export function getTokenizerBaseURL(source: DiffusionTokenizerSource): string {
  switch (source.type) {
    case 'sd15':
      return 'https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/tokenizer';
    case 'sd2':
      return 'https://huggingface.co/stabilityai/stable-diffusion-2-1/resolve/main/tokenizer';
    case 'sdxl':
      return 'https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/tokenizer';
    case 'custom':
      return source.baseURL;
  }
}

// ============================================================================
// Model Variant
// ============================================================================

export type DiffusionModelVariant =
  | 'sd15'
  | 'sd21'
  | 'sdxl'
  | 'sdxl_turbo'
  | 'sdxs'
  | 'lcm';

export const DiffusionModelVariants = {
  SD15: 'sd15' as const,
  SD21: 'sd21' as const,
  SDXL: 'sdxl' as const,
  SDXL_TURBO: 'sdxl_turbo' as const,
  SDXS: 'sdxs' as const,
  LCM: 'lcm' as const,
};

export function getDefaultResolution(variant: DiffusionModelVariant): {
  width: number;
  height: number;
} {
  switch (variant) {
    case 'sd15':
      return { width: 512, height: 512 };
    case 'sd21':
      return { width: 768, height: 768 };
    case 'sdxl':
    case 'sdxl_turbo':
      return { width: 1024, height: 1024 };
    case 'sdxs':
    case 'lcm':
      return { width: 512, height: 512 };
  }
}

export function getDefaultSteps(variant: DiffusionModelVariant): number {
  switch (variant) {
    case 'sd15':
    case 'sd21':
    case 'sdxl':
      return 28;
    case 'sdxl_turbo':
      return 4;
    case 'sdxs':
      return 1;
    case 'lcm':
      return 4;
  }
}

// ============================================================================
// Scheduler
// ============================================================================

export type DiffusionScheduler =
  | 'dpm++_2m_karras'
  | 'dpm++_2m'
  | 'dpm++_2m_sde'
  | 'ddim'
  | 'euler'
  | 'euler_a'
  | 'pndm'
  | 'lms';

export const DiffusionSchedulers = {
  DPM_PP_2M_KARRAS: 'dpm++_2m_karras' as const,
  DPM_PP_2M: 'dpm++_2m' as const,
  DPM_PP_2M_SDE: 'dpm++_2m_sde' as const,
  DDIM: 'ddim' as const,
  EULER: 'euler' as const,
  EULER_ANCESTRAL: 'euler_a' as const,
  PNDM: 'pndm' as const,
  LMS: 'lms' as const,
};

// ============================================================================
// Generation Mode
// ============================================================================

export type DiffusionMode = 'txt2img' | 'img2img' | 'inpainting';

export const DiffusionModes = {
  TEXT_TO_IMAGE: 'txt2img' as const,
  IMAGE_TO_IMAGE: 'img2img' as const,
  INPAINTING: 'inpainting' as const,
};

// ============================================================================
// Configuration
// ============================================================================

export interface DiffusionConfiguration {
  modelId?: string;
  preferredFramework?: string;
  modelVariant?: DiffusionModelVariant;
  enableSafetyChecker?: boolean;
  reduceMemory?: boolean;
  tokenizerSource?: DiffusionTokenizerSource;
}

// ============================================================================
// Generation Options
// ============================================================================

export interface DiffusionGenerationOptions {
  prompt: string;
  negativePrompt?: string;
  width?: number;
  height?: number;
  steps?: number;
  guidanceScale?: number;
  seed?: number;
  scheduler?: DiffusionScheduler;
  mode?: DiffusionMode;
  denoiseStrength?: number;
  reportIntermediateImages?: boolean;
  progressStride?: number;
}

export function createTextToImageOptions(
  prompt: string,
  options?: Partial<Omit<DiffusionGenerationOptions, 'prompt' | 'mode'>>
): DiffusionGenerationOptions {
  return {
    prompt,
    mode: 'txt2img',
    negativePrompt: options?.negativePrompt ?? '',
    width: options?.width ?? 512,
    height: options?.height ?? 512,
    steps: options?.steps ?? 28,
    guidanceScale: options?.guidanceScale ?? 7.5,
    seed: options?.seed ?? -1,
    scheduler: options?.scheduler ?? 'dpm++_2m_karras',
    ...options,
  };
}

// ============================================================================
// Progress
// ============================================================================

export interface DiffusionProgress {
  progress: number;
  currentStep: number;
  totalSteps: number;
  stage: string;
  intermediateImageBase64?: string;
}

// ============================================================================
// Result
// ============================================================================

export interface DiffusionResult {
  imageBase64: string;
  width: number;
  height: number;
  seedUsed: number;
  generationTimeMs: number;
  safetyFlagged: boolean;
}

// ============================================================================
// Model Info
// ============================================================================

export interface DiffusionModelInfo {
  supportsTextToImage: boolean;
  supportsImageToImage: boolean;
  supportsInpainting: boolean;
  maxWidth: number;
  maxHeight: number;
  modelVariant: DiffusionModelVariant;
}
