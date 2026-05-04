/**
 * RunAnywhere Web SDK - Diffusion Extension
 *
 * Adds image generation capabilities using diffusion models.
 * Uses the RACommons rac_diffusion_component_* C API (same as iOS/Android).
 *
 * Mirrors: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Diffusion/
 *
 * Usage:
 *   import { Diffusion, DiffusionScheduler, DiffusionMode } from '@runanywhere/web';
 *
 *   await Diffusion.loadModel('/models/sd-v1-5', 'sd-1.5');
 *   const result = await Diffusion.generate({
 *     prompt: 'A sunset over mountains',
 *     width: 512, height: 512, steps: 28,
 *   });
 *   // result.imageData is Uint8ClampedArray RGBA
 */

import { RunAnywhere, SDKException, SDKErrorCode, SDKLogger, EventBus, SDKEventType } from '@runanywhere/web';
import { LlamaCppBridge } from '../Foundation/LlamaCppBridge';
import { Offsets } from '../Foundation/LlamaCppOffsets';
import {
  DiffusionScheduler,
  DiffusionMode,
  type DiffusionGenerationOptions,
  type DiffusionGenerationResult,
} from './DiffusionTypes';

export {
  DiffusionScheduler,
  DiffusionModelVariant,
  DiffusionMode,
  type DiffusionGenerationOptions,
  type DiffusionGenerationResult,
  type DiffusionProgressCallback,
} from './DiffusionTypes';

const logger = new SDKLogger('Diffusion');

const RAC_DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS = 0;
const RAC_DIFFUSION_SCHEDULER_DPMPP_2M = 1;
const RAC_DIFFUSION_SCHEDULER_DDIM = 3;
const RAC_DIFFUSION_SCHEDULER_EULER = 4;
const RAC_DIFFUSION_SCHEDULER_EULER_ANCESTRAL = 5;
const RAC_DIFFUSION_SCHEDULER_PNDM = 6;
const RAC_DIFFUSION_SCHEDULER_LMS = 7;

const RAC_DIFFUSION_MODE_TEXT_TO_IMAGE = 0;
const RAC_DIFFUSION_MODE_IMAGE_TO_IMAGE = 1;
const RAC_DIFFUSION_MODE_INPAINTING = 2;

function toRacDiffusionScheduler(scheduler?: DiffusionScheduler): number {
  switch (scheduler) {
    case DiffusionScheduler.DIFFUSION_SCHEDULER_DPMPP_2M:
      return RAC_DIFFUSION_SCHEDULER_DPMPP_2M;
    case DiffusionScheduler.DIFFUSION_SCHEDULER_DDIM:
      return RAC_DIFFUSION_SCHEDULER_DDIM;
    case DiffusionScheduler.DIFFUSION_SCHEDULER_EULER:
      return RAC_DIFFUSION_SCHEDULER_EULER;
    case DiffusionScheduler.DIFFUSION_SCHEDULER_EULER_A:
      return RAC_DIFFUSION_SCHEDULER_EULER_ANCESTRAL;
    case DiffusionScheduler.DIFFUSION_SCHEDULER_PNDM:
      return RAC_DIFFUSION_SCHEDULER_PNDM;
    case DiffusionScheduler.DIFFUSION_SCHEDULER_LMS:
      return RAC_DIFFUSION_SCHEDULER_LMS;
    case DiffusionScheduler.DIFFUSION_SCHEDULER_UNSPECIFIED:
    case DiffusionScheduler.DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS:
    case DiffusionScheduler.DIFFUSION_SCHEDULER_DDPM:
    case DiffusionScheduler.DIFFUSION_SCHEDULER_LCM:
    case DiffusionScheduler.UNRECOGNIZED:
    case undefined:
    default:
      return RAC_DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS;
  }
}

function fromRacDiffusionScheduler(scheduler: number): DiffusionScheduler {
  switch (scheduler) {
    case RAC_DIFFUSION_SCHEDULER_DPMPP_2M:
      return DiffusionScheduler.DIFFUSION_SCHEDULER_DPMPP_2M;
    case RAC_DIFFUSION_SCHEDULER_DDIM:
      return DiffusionScheduler.DIFFUSION_SCHEDULER_DDIM;
    case RAC_DIFFUSION_SCHEDULER_EULER:
      return DiffusionScheduler.DIFFUSION_SCHEDULER_EULER;
    case RAC_DIFFUSION_SCHEDULER_EULER_ANCESTRAL:
      return DiffusionScheduler.DIFFUSION_SCHEDULER_EULER_A;
    case RAC_DIFFUSION_SCHEDULER_PNDM:
      return DiffusionScheduler.DIFFUSION_SCHEDULER_PNDM;
    case RAC_DIFFUSION_SCHEDULER_LMS:
      return DiffusionScheduler.DIFFUSION_SCHEDULER_LMS;
    case RAC_DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS:
    default:
      return DiffusionScheduler.DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS;
  }
}

function toRacDiffusionMode(mode?: DiffusionMode): number {
  switch (mode) {
    case DiffusionMode.DIFFUSION_MODE_IMAGE_TO_IMAGE:
      return RAC_DIFFUSION_MODE_IMAGE_TO_IMAGE;
    case DiffusionMode.DIFFUSION_MODE_INPAINTING:
      return RAC_DIFFUSION_MODE_INPAINTING;
    case DiffusionMode.DIFFUSION_MODE_UNSPECIFIED:
    case DiffusionMode.DIFFUSION_MODE_TEXT_TO_IMAGE:
    case DiffusionMode.UNRECOGNIZED:
    case undefined:
    default:
      return RAC_DIFFUSION_MODE_TEXT_TO_IMAGE;
  }
}

// ---------------------------------------------------------------------------
// Diffusion Extension
// ---------------------------------------------------------------------------

class DiffusionImpl {
  readonly extensionName = 'Diffusion';
  private _diffusionComponentHandle = 0;

  private requireBridge(): LlamaCppBridge {
    if (!RunAnywhere.isInitialized) throw SDKException.notInitialized();
    return LlamaCppBridge.shared;
  }

  private ensureDiffusionComponent(): number {
    if (this._diffusionComponentHandle !== 0) return this._diffusionComponentHandle;

    const bridge = this.requireBridge();
    const m = bridge.module;
    const handlePtr = m._malloc(4);
    const result = bridge.callFunction<number>('rac_diffusion_component_create', 'number', ['number'], [handlePtr]);

    if (result !== 0) {
      m._free(handlePtr);
      bridge.checkResult(result, 'rac_diffusion_component_create');
    }

    this._diffusionComponentHandle = m.getValue(handlePtr, 'i32');
    m._free(handlePtr);
    logger.debug('Diffusion component created');
    return this._diffusionComponentHandle;
  }

  /**
   * Load a diffusion model.
   */
  async loadModel(modelPath: string, modelId: string, modelName?: string): Promise<void> {
    const bridge = this.requireBridge();
    const m = bridge.module;
    const handle = this.ensureDiffusionComponent();

    logger.info(`Loading diffusion model: ${modelId} from ${modelPath}`);
    EventBus.shared.emit('model.loadStarted', SDKEventType.Model, { modelId, component: 'diffusion' });

    const pathPtr = bridge.allocString(modelPath);
    const idPtr = bridge.allocString(modelId);
    const namePtr = bridge.allocString(modelName ?? modelId);

    try {
      const result = m.ccall(
        'rac_diffusion_component_load_model', 'number',
        ['number', 'number', 'number', 'number'],
        [handle, pathPtr, idPtr, namePtr],
      ) as number;
      bridge.checkResult(result, 'rac_diffusion_component_load_model');
      logger.info(`Diffusion model loaded: ${modelId}`);
      EventBus.shared.emit('model.loadCompleted', SDKEventType.Model, { modelId, component: 'diffusion' });
    } finally {
      bridge.free(pathPtr);
      bridge.free(idPtr);
      bridge.free(namePtr);
    }
  }

  /** Unload the diffusion model. */
  async unloadModel(): Promise<void> {
    if (this._diffusionComponentHandle === 0) return;
    const bridge = this.requireBridge();
    const result = bridge.module.ccall(
      'rac_diffusion_component_unload', 'number', ['number'], [this._diffusionComponentHandle],
    ) as number;
    bridge.checkResult(result, 'rac_diffusion_component_unload');
    logger.info('Diffusion model unloaded');
  }

  /** Check if a diffusion model is loaded. */
  get isModelLoaded(): boolean {
    if (this._diffusionComponentHandle === 0) return false;
    try {
      return (LlamaCppBridge.shared.module.ccall(
        'rac_diffusion_component_is_loaded', 'number', ['number'], [this._diffusionComponentHandle],
      ) as number) === 1;
    } catch { return false; }
  }

  get isDiffusionModelLoaded(): boolean {
    return this.isModelLoaded;
  }

  /**
   * Generate an image from a text prompt.
   */
  async generate(options: DiffusionGenerationOptions): Promise<DiffusionGenerationResult> {
    const bridge = this.requireBridge();
    const m = bridge.module;
    const handle = this.ensureDiffusionComponent();

    if (!this.isModelLoaded) {
      throw new SDKException(SDKErrorCode.ModelNotLoaded, 'No diffusion model loaded. Call loadModel() first.');
    }

    logger.info(`Generating image: "${options.prompt.substring(0, 50)}..."`);

    // Build rac_diffusion_options_t
    const optSize = m._rac_wasm_sizeof_diffusion_options();
    const optPtr = m._malloc(optSize);
    for (let i = 0; i < optSize; i++) m.setValue(optPtr + i, 0, 'i8');

    const promptPtr = bridge.allocString(options.prompt);
    let negPromptPtr = 0;

    const dOpt = Offsets.diffusionOptions;
    m.setValue(optPtr + dOpt.prompt, promptPtr, '*');
    if (options.negativePrompt) {
      negPromptPtr = bridge.allocString(options.negativePrompt);
      m.setValue(optPtr + dOpt.negativePrompt, negPromptPtr, '*');
    }
    m.setValue(optPtr + dOpt.width, options.width ?? 0, 'i32');
    m.setValue(optPtr + dOpt.height, options.height ?? 0, 'i32');
    m.setValue(optPtr + dOpt.steps, options.numInferenceSteps ?? 0, 'i32');
    m.setValue(optPtr + dOpt.guidanceScale, options.guidanceScale ?? -1, 'float');
    // seed is int64 — write low and high 32-bit halves
    const seed = options.seed ?? -1;
    m.setValue(optPtr + dOpt.seed, seed & 0xFFFFFFFF, 'i32');
    m.setValue(optPtr + dOpt.seed + 4, seed < 0 ? -1 : 0, 'i32');
    const scheduler = toRacDiffusionScheduler(options.scheduler);
    m.setValue(optPtr + dOpt.scheduler, scheduler, 'i32');
    m.setValue(optPtr + dOpt.mode, toRacDiffusionMode(options.mode), 'i32');
    m.setValue(optPtr + dOpt.denoiseStrength, 0.75, 'float');
    m.setValue(optPtr + dOpt.reportIntermediate, 0, 'i32');
    m.setValue(optPtr + dOpt.progressStride, 1, 'i32');

    // Result struct: rac_diffusion_result_t
    const resSize = m._rac_wasm_sizeof_diffusion_result();
    const resPtr = m._malloc(resSize);

    try {
      const r = m.ccall(
        'rac_diffusion_component_generate', 'number',
        ['number', 'number', 'number'],
        [handle, optPtr, resPtr],
      ) as number;
      bridge.checkResult(r, 'rac_diffusion_component_generate');

      // Read rac_diffusion_result_t (offsets from compiler via StructOffsets)
      const dRes = Offsets.diffusionResult;
      const imageDataPtr = m.getValue(resPtr + dRes.imageData, '*');
      const imageSize = m.getValue(resPtr + dRes.imageSize, 'i32');
      const width = m.getValue(resPtr + dRes.width, 'i32');
      const height = m.getValue(resPtr + dRes.height, 'i32');
      const seedUsed = m.getValue(resPtr + dRes.seedUsed, 'i32'); // low 32 bits of int64
      const generationTimeMs = m.getValue(resPtr + dRes.generationTimeMs, 'i32'); // low 32 bits
      const safetyFlagged = m.getValue(resPtr + dRes.safetyFlagged, 'i32') === 1;

      // Copy RGBA image data
      const imageData = new Uint8Array(imageSize);
      if (imageDataPtr && imageSize > 0) {
        imageData.set(bridge.readBytes(imageDataPtr, imageSize));
      }

      // Free C result
      m.ccall('rac_diffusion_result_free', null, ['number'], [resPtr]);

      EventBus.shared.emit('diffusion.generated', SDKEventType.Generation, {
        width, height, generationTimeMs,
      });

      return {
        imageData,
        width,
        height,
        seedUsed,
        totalTimeMs: generationTimeMs,
        safetyFlag: safetyFlagged,
        usedScheduler: fromRacDiffusionScheduler(scheduler),
        errorMessage: undefined,
        errorCode: 0,
      };
    } finally {
      bridge.free(promptPtr);
      if (negPromptPtr) bridge.free(negPromptPtr);
      m._free(optPtr);
    }
  }

  async generateImage(
    prompt: string,
    options: Partial<DiffusionGenerationOptions> = {},
  ): Promise<DiffusionGenerationResult> {
    return this.generate({ ...options, prompt });
  }

  async unloadDiffusionModel(): Promise<void> {
    return this.unloadModel();
  }

  /** Cancel in-progress generation. */
  cancel(): void {
    if (this._diffusionComponentHandle === 0) return;
    LlamaCppBridge.shared.module.ccall(
      'rac_diffusion_component_cancel', 'number', ['number'], [this._diffusionComponentHandle],
    );
  }

  cancelImageGeneration(): void {
    this.cancel();
  }

  /** Clean up the diffusion component. */
  cleanup(): void {
    if (this._diffusionComponentHandle !== 0) {
      try {
        LlamaCppBridge.shared.module.ccall(
          'rac_diffusion_component_destroy', null, ['number'], [this._diffusionComponentHandle],
        );
      } catch { /* ignore */ }
      this._diffusionComponentHandle = 0;
    }
  }
}

export const Diffusion = new DiffusionImpl();
