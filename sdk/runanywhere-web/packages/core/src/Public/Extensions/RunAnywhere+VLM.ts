/**
 * RunAnywhere Web SDK - Vision Language Model Extension
 *
 * Adds VLM capabilities for image understanding + text generation.
 * Uses the RACommons rac_vlm_component_* C API (llama.cpp mtmd backend).
 *
 * Mirrors: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VLM/
 *
 * Usage:
 *   import { VLM } from '@runanywhere/web';
 *
 *   await VLM.loadModel('/models/qwen2-vl.gguf', '/models/qwen2-vl-mmproj.gguf', 'qwen2-vl');
 *   const result = await VLM.process(imageData, 'Describe this image');
 *   console.log(result.text);
 */

import { RunAnywhere } from '../RunAnywhere';
import { WASMBridge } from '../../Foundation/WASMBridge';
import { SDKError, SDKErrorCode } from '../../Foundation/ErrorTypes';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { EventBus } from '../../Foundation/EventBus';
import { SDKEventType } from '../../types/enums';

const logger = new SDKLogger('VLM');

let _vlmComponentHandle = 0;
let _vlmBackendRegistered = false;

function requireBridge(): WASMBridge {
  if (!RunAnywhere.isInitialized) throw SDKError.notInitialized();
  return WASMBridge.shared;
}

/**
 * Ensure the llama.cpp VLM backend is registered with the service registry.
 * Must be called before creating the VLM component so it can find a provider.
 */
function ensureVLMBackendRegistered(): void {
  if (_vlmBackendRegistered) return;

  const bridge = requireBridge();
  const m = bridge.module;

  // Check if the backend registration function exists (only when built with --vlm)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const fn = (m as any)['_rac_backend_llamacpp_vlm_register'];
  if (!fn) {
    throw new SDKError(
      SDKErrorCode.BackendNotAvailable,
      'VLM backend not available. Rebuild WASM with --vlm flag.',
    );
  }

  const result = m.ccall('rac_backend_llamacpp_vlm_register', 'number', [], []) as number;
  if (result !== 0) {
    bridge.checkResult(result, 'rac_backend_llamacpp_vlm_register');
  }

  _vlmBackendRegistered = true;
  logger.info('VLM backend (llama.cpp mtmd) registered');
}

function ensureVLMComponent(): number {
  if (_vlmComponentHandle !== 0) return _vlmComponentHandle;

  // Register the VLM backend first
  ensureVLMBackendRegistered();

  const bridge = requireBridge();
  const m = bridge.module;
  const handlePtr = m._malloc(4);
  const result = m.ccall('rac_vlm_component_create', 'number', ['number'], [handlePtr]) as number;

  if (result !== 0) {
    m._free(handlePtr);
    bridge.checkResult(result, 'rac_vlm_component_create');
  }

  _vlmComponentHandle = m.getValue(handlePtr, 'i32');
  m._free(handlePtr);
  logger.debug('VLM component created');
  return _vlmComponentHandle;
}

// ---------------------------------------------------------------------------
// VLM Types
// ---------------------------------------------------------------------------

export enum VLMImageFormat {
  FilePath = 0,
  RGBPixels = 1,
  Base64 = 2,
}

export enum VLMModelFamily {
  Auto = 0,
  Qwen2VL = 1,
  SmolVLM = 2,
  LLaVA = 3,
  Custom = 99,
}

export interface VLMImage {
  format: VLMImageFormat;
  /** File path in WASM virtual FS (for FilePath format) */
  filePath?: string;
  /** Raw RGB pixel data (for RGBPixels format) */
  pixelData?: Uint8Array;
  /** Base64-encoded image (for Base64 format) */
  base64Data?: string;
  width?: number;
  height?: number;
}

export interface VLMGenerationOptions {
  maxTokens?: number;
  temperature?: number;
  topP?: number;
  systemPrompt?: string;
  modelFamily?: VLMModelFamily;
  streaming?: boolean;
}

export interface VLMGenerationResult {
  text: string;
  promptTokens: number;
  imageTokens: number;
  completionTokens: number;
  totalTokens: number;
  timeToFirstTokenMs: number;
  imageEncodeTimeMs: number;
  totalTimeMs: number;
  tokensPerSecond: number;
}

export interface VLMStreamingResult {
  result: Promise<VLMGenerationResult>;
  tokens: AsyncIterable<string>;
  cancel: () => void;
}

// ---------------------------------------------------------------------------
// VLM Extension
// ---------------------------------------------------------------------------

export const VLM = {
  /**
   * Load a VLM model (GGUF model + multimodal projector).
   *
   * @param modelPath - Path to the GGUF model file in WASM FS
   * @param mmprojPath - Path to the mmproj file in WASM FS
   * @param modelId - Unique model identifier
   * @param modelName - Display name (optional)
   */
  async loadModel(
    modelPath: string,
    mmprojPath: string,
    modelId: string,
    modelName?: string,
  ): Promise<void> {
    const bridge = requireBridge();
    const m = bridge.module;
    const handle = ensureVLMComponent();

    logger.info(`Loading VLM model: ${modelId}`);
    EventBus.shared.emit('model.loadStarted', SDKEventType.Model, { modelId, component: 'vlm' });

    const pathPtr = bridge.allocString(modelPath);
    const projPtr = bridge.allocString(mmprojPath);
    const idPtr = bridge.allocString(modelId);
    const namePtr = bridge.allocString(modelName ?? modelId);

    try {
      const result = m.ccall(
        'rac_vlm_component_load_model', 'number',
        ['number', 'number', 'number', 'number', 'number'],
        [handle, pathPtr, projPtr, idPtr, namePtr],
      ) as number;
      bridge.checkResult(result, 'rac_vlm_component_load_model');
      logger.info(`VLM model loaded: ${modelId}`);
      EventBus.shared.emit('model.loadCompleted', SDKEventType.Model, { modelId, component: 'vlm' });
    } finally {
      bridge.free(pathPtr);
      bridge.free(projPtr);
      bridge.free(idPtr);
      bridge.free(namePtr);
    }
  },

  /** Unload the VLM model. */
  async unloadModel(): Promise<void> {
    if (_vlmComponentHandle === 0) return;
    const bridge = requireBridge();
    const result = bridge.module.ccall(
      'rac_vlm_component_unload', 'number', ['number'], [_vlmComponentHandle],
    ) as number;
    bridge.checkResult(result, 'rac_vlm_component_unload');
    logger.info('VLM model unloaded');
  },

  /** Check if a VLM model is loaded. */
  get isModelLoaded(): boolean {
    if (_vlmComponentHandle === 0) return false;
    try {
      return (WASMBridge.shared.module.ccall(
        'rac_vlm_component_is_loaded', 'number', ['number'], [_vlmComponentHandle],
      ) as number) === 1;
    } catch { return false; }
  },

  /**
   * Process an image with a text prompt.
   *
   * @param image - Image input (file path, pixel data, or base64)
   * @param prompt - Text prompt describing what to do with the image
   * @param options - Generation options
   * @returns VLM generation result
   */
  async process(
    image: VLMImage,
    prompt: string,
    options: VLMGenerationOptions = {},
  ): Promise<VLMGenerationResult> {
    const bridge = requireBridge();
    const m = bridge.module;
    const handle = ensureVLMComponent();

    if (!VLM.isModelLoaded) {
      throw new SDKError(SDKErrorCode.ModelNotLoaded, 'No VLM model loaded. Call loadModel() first.');
    }

    logger.debug(`VLM process: "${prompt.substring(0, 50)}..."`);

    // Build rac_vlm_image_t struct
    const imageSize = 32; // approximate
    const imagePtr = m._malloc(imageSize);
    for (let i = 0; i < imageSize; i++) m.setValue(imagePtr + i, 0, 'i8');

    let filePathPtr = 0;
    let base64Ptr = 0;
    let pixelPtr = 0;

    m.setValue(imagePtr, image.format, 'i32'); // format

    if (image.format === VLMImageFormat.FilePath && image.filePath) {
      filePathPtr = bridge.allocString(image.filePath);
      m.setValue(imagePtr + 4, filePathPtr, '*'); // file_path
    } else if (image.format === VLMImageFormat.Base64 && image.base64Data) {
      base64Ptr = bridge.allocString(image.base64Data);
      m.setValue(imagePtr + 12, base64Ptr, '*'); // base64_data
    } else if (image.format === VLMImageFormat.RGBPixels && image.pixelData) {
      pixelPtr = m._malloc(image.pixelData.length);
      new Uint8Array(m.HEAPU8.buffer, pixelPtr, image.pixelData.length).set(image.pixelData);
      m.setValue(imagePtr + 8, pixelPtr, '*'); // pixel_data
    }

    m.setValue(imagePtr + 16, image.width ?? 0, 'i32');  // width
    m.setValue(imagePtr + 20, image.height ?? 0, 'i32'); // height
    m.setValue(imagePtr + 24, image.pixelData?.length ?? 0, 'i32'); // data_size

    // Build rac_vlm_options_t
    const optSize = 56; // approximate
    const optPtr = m._malloc(optSize);
    for (let i = 0; i < optSize; i++) m.setValue(optPtr + i, 0, 'i8');

    m.setValue(optPtr, options.maxTokens ?? 512, 'i32');       // max_tokens
    m.setValue(optPtr + 4, options.temperature ?? 0.7, 'float'); // temperature
    m.setValue(optPtr + 8, options.topP ?? 0.9, 'float');       // top_p
    m.setValue(optPtr + 28, options.streaming ? 1 : 0, 'i32');  // streaming_enabled

    let sysPtr = 0;
    if (options.systemPrompt) {
      sysPtr = bridge.allocString(options.systemPrompt);
      m.setValue(optPtr + 32, sysPtr, '*'); // system_prompt
    }

    m.setValue(optPtr + 44, options.modelFamily ?? VLMModelFamily.Auto, 'i32'); // model_family

    const promptPtr = bridge.allocString(prompt);

    // Result struct
    const resSize = 40;
    const resPtr = m._malloc(resSize);

    try {
      const r = m.ccall(
        'rac_vlm_component_process', 'number',
        ['number', 'number', 'number', 'number', 'number'],
        [handle, imagePtr, promptPtr, optPtr, resPtr],
      ) as number;
      bridge.checkResult(r, 'rac_vlm_component_process');

      // Read rac_vlm_result_t
      const textPtr = m.getValue(resPtr, '*');
      const vlmResult: VLMGenerationResult = {
        text: bridge.readString(textPtr),
        promptTokens: m.getValue(resPtr + 4, 'i32'),
        imageTokens: m.getValue(resPtr + 8, 'i32'),
        completionTokens: m.getValue(resPtr + 12, 'i32'),
        totalTokens: m.getValue(resPtr + 16, 'i32'),
        timeToFirstTokenMs: m.getValue(resPtr + 20, 'i32'),
        imageEncodeTimeMs: m.getValue(resPtr + 24, 'i32'),
        totalTimeMs: m.getValue(resPtr + 28, 'i32'),
        tokensPerSecond: m.getValue(resPtr + 32, 'float'),
      };

      m.ccall('rac_vlm_result_free', null, ['number'], [resPtr]);

      EventBus.shared.emit('vlm.processed', SDKEventType.Generation, {
        tokensPerSecond: vlmResult.tokensPerSecond,
        totalTokens: vlmResult.totalTokens,
      });

      return vlmResult;
    } finally {
      bridge.free(promptPtr);
      m._free(imagePtr);
      m._free(optPtr);
      if (filePathPtr) bridge.free(filePathPtr);
      if (base64Ptr) bridge.free(base64Ptr);
      if (pixelPtr) m._free(pixelPtr);
      if (sysPtr) bridge.free(sysPtr);
    }
  },

  /** Cancel in-progress VLM generation. */
  cancel(): void {
    if (_vlmComponentHandle === 0) return;
    WASMBridge.shared.module.ccall(
      'rac_vlm_component_cancel', 'number', ['number'], [_vlmComponentHandle],
    );
  },

  /** Clean up the VLM component and unregister backend. */
  cleanup(): void {
    if (_vlmComponentHandle !== 0) {
      try {
        WASMBridge.shared.module.ccall(
          'rac_vlm_component_destroy', null, ['number'], [_vlmComponentHandle],
        );
      } catch { /* ignore */ }
      _vlmComponentHandle = 0;
    }

    if (_vlmBackendRegistered) {
      try {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const fn = (WASMBridge.shared.module as any)['_rac_backend_llamacpp_vlm_unregister'];
        if (fn) {
          WASMBridge.shared.module.ccall('rac_backend_llamacpp_vlm_unregister', 'number', [], []);
        }
      } catch { /* ignore */ }
      _vlmBackendRegistered = false;
    }
  },
};
