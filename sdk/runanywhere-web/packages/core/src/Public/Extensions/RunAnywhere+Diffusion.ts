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

import { RunAnywhere } from '../RunAnywhere';
import { WASMBridge } from '../../Foundation/WASMBridge';
import { Offsets } from '../../Foundation/StructOffsets';
import { SDKError, SDKErrorCode } from '../../Foundation/ErrorTypes';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { EventBus } from '../../Foundation/EventBus';
import { SDKEventType } from '../../types/enums';
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

let _diffusionComponentHandle = 0;

function requireBridge(): WASMBridge {
  if (!RunAnywhere.isInitialized) throw SDKError.notInitialized();
  return WASMBridge.shared;
}

function ensureDiffusionComponent(): number {
  if (_diffusionComponentHandle !== 0) return _diffusionComponentHandle;

  const bridge = requireBridge();
  const m = bridge.module;
  const handlePtr = m._malloc(4);
  const result = m.ccall('rac_diffusion_component_create', 'number', ['number'], [handlePtr]) as number;

  if (result !== 0) {
    m._free(handlePtr);
    bridge.checkResult(result, 'rac_diffusion_component_create');
  }

  _diffusionComponentHandle = m.getValue(handlePtr, 'i32');
  m._free(handlePtr);
  logger.debug('Diffusion component created');
  return _diffusionComponentHandle;
}

// ---------------------------------------------------------------------------
// Diffusion Extension
// ---------------------------------------------------------------------------

export const Diffusion = {
  /**
   * Load a diffusion model.
   */
  async loadModel(modelPath: string, modelId: string, modelName?: string): Promise<void> {
    const bridge = requireBridge();
    const m = bridge.module;
    const handle = ensureDiffusionComponent();

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
  },

  /** Unload the diffusion model. */
  async unloadModel(): Promise<void> {
    if (_diffusionComponentHandle === 0) return;
    const bridge = requireBridge();
    const result = bridge.module.ccall(
      'rac_diffusion_component_unload', 'number', ['number'], [_diffusionComponentHandle],
    ) as number;
    bridge.checkResult(result, 'rac_diffusion_component_unload');
    logger.info('Diffusion model unloaded');
  },

  /** Check if a diffusion model is loaded. */
  get isModelLoaded(): boolean {
    if (_diffusionComponentHandle === 0) return false;
    try {
      return (WASMBridge.shared.module.ccall(
        'rac_diffusion_component_is_loaded', 'number', ['number'], [_diffusionComponentHandle],
      ) as number) === 1;
    } catch { return false; }
  },

  /**
   * Generate an image from a text prompt.
   */
  async generate(options: DiffusionGenerationOptions): Promise<DiffusionGenerationResult> {
    const bridge = requireBridge();
    const m = bridge.module;
    const handle = ensureDiffusionComponent();

    if (!Diffusion.isModelLoaded) {
      throw new SDKError(SDKErrorCode.ModelNotLoaded, 'No diffusion model loaded. Call loadModel() first.');
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
    m.setValue(optPtr + dOpt.width, options.width ?? 512, 'i32');
    m.setValue(optPtr + dOpt.height, options.height ?? 512, 'i32');
    m.setValue(optPtr + dOpt.steps, options.steps ?? 28, 'i32');
    m.setValue(optPtr + dOpt.guidanceScale, options.guidanceScale ?? 7.5, 'float');
    // seed is int64 — write low and high 32-bit halves
    const seed = options.seed ?? -1;
    m.setValue(optPtr + dOpt.seed, seed & 0xFFFFFFFF, 'i32');
    m.setValue(optPtr + dOpt.seed + 4, seed < 0 ? -1 : 0, 'i32');
    m.setValue(optPtr + dOpt.scheduler, options.scheduler ?? DiffusionScheduler.DPM_PP_2M_Karras, 'i32');
    m.setValue(optPtr + dOpt.mode, options.mode ?? DiffusionMode.TextToImage, 'i32');
    m.setValue(optPtr + dOpt.denoiseStrength, options.denoiseStrength ?? 0.75, 'float');
    m.setValue(optPtr + dOpt.reportIntermediate, options.reportIntermediateImages ? 1 : 0, 'i32');
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
      const imageData = new Uint8ClampedArray(imageSize);
      if (imageDataPtr && imageSize > 0) {
        imageData.set(bridge.readBytes(imageDataPtr, imageSize));
      }

      // Free C result
      m.ccall('rac_diffusion_result_free', null, ['number'], [resPtr]);

      EventBus.shared.emit('diffusion.generated', SDKEventType.Generation, {
        width, height, generationTimeMs,
      });

      return { imageData, width, height, seedUsed, generationTimeMs, safetyFlagged };
    } finally {
      bridge.free(promptPtr);
      if (negPromptPtr) bridge.free(negPromptPtr);
      m._free(optPtr);
    }
  },

  /** Cancel in-progress generation. */
  cancel(): void {
    if (_diffusionComponentHandle === 0) return;
    WASMBridge.shared.module.ccall(
      'rac_diffusion_component_cancel', 'number', ['number'], [_diffusionComponentHandle],
    );
  },

  /** Clean up the diffusion component. */
  cleanup(): void {
    if (_diffusionComponentHandle !== 0) {
      try {
        WASMBridge.shared.module.ccall(
          'rac_diffusion_component_destroy', null, ['number'], [_diffusionComponentHandle],
        );
      } catch { /* ignore */ }
      _diffusionComponentHandle = 0;
    }
  },
};
