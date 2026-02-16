/** RunAnywhere Web SDK - Diffusion Types */

export enum DiffusionScheduler {
  DPM_PP_2M_Karras = 0,
  DPM_PP_2M = 1,
  DPM_PP_2M_SDE = 2,
  DDIM = 3,
  Euler = 4,
  EulerAncestral = 5,
  PNDM = 6,
  LMS = 7,
}

export enum DiffusionModelVariant {
  SD_1_5 = 0,
  SD_2_1 = 1,
  SDXL = 2,
  SDXL_Turbo = 3,
  SDXS = 4,
  LCM = 5,
}

export enum DiffusionMode {
  TextToImage = 0,
  ImageToImage = 1,
  Inpainting = 2,
}

export interface DiffusionGenerationOptions {
  /** Text prompt */
  prompt: string;
  /** Negative prompt (optional) */
  negativePrompt?: string;
  /** Image width (default: 512) */
  width?: number;
  /** Image height (default: 512) */
  height?: number;
  /** Number of denoising steps (default: 28) */
  steps?: number;
  /** Guidance scale (default: 7.5) */
  guidanceScale?: number;
  /** Seed (-1 for random) */
  seed?: number;
  /** Scheduler (default: DPM++ 2M Karras) */
  scheduler?: DiffusionScheduler;
  /** Generation mode (default: TextToImage) */
  mode?: DiffusionMode;
  /** Denoising strength for img2img (0-1, default: 0.75) */
  denoiseStrength?: number;
  /** Report intermediate images (default: false) */
  reportIntermediateImages?: boolean;
}

export interface DiffusionGenerationResult {
  /** RGBA image data */
  imageData: Uint8ClampedArray;
  /** Image width */
  width: number;
  /** Image height */
  height: number;
  /** Seed used for generation */
  seedUsed: number;
  /** Generation time in milliseconds */
  generationTimeMs: number;
  /** Whether safety checker flagged the image */
  safetyFlagged: boolean;
}

export type DiffusionProgressCallback = (step: number, totalSteps: number, progress: number) => void;
