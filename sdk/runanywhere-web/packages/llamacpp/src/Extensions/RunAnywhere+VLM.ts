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

import { RunAnywhere, WASMBridge, Offsets, SDKError, SDKErrorCode, SDKLogger, EventBus, SDKEventType, HardwareAcceleration } from '@runanywhere/web';
import { VLMImageFormat, VLMModelFamily } from './VLMTypes';
import type { VLMImage, VLMGenerationOptions, VLMGenerationResult } from './VLMTypes';

const logger = new SDKLogger('VLM');

export type { VLMImage, VLMGenerationOptions, VLMGenerationResult, VLMStreamingResult } from './VLMTypes';
export { VLMImageFormat, VLMModelFamily } from './VLMTypes';

// ---------------------------------------------------------------------------
// VLM Extension
// ---------------------------------------------------------------------------

class VLMImpl {
  readonly extensionName = 'VLM';
  private _vlmComponentHandle = 0;
  private _vlmBackendRegistered = false;

  private requireBridge(): WASMBridge {
    if (!RunAnywhere.isInitialized) throw SDKError.notInitialized();
    return WASMBridge.shared;
  }

  /**
   * Ensure the llama.cpp VLM backend is registered with the service registry.
   * Must be called before creating the VLM component so it can find a provider.
   */
  private ensureVLMBackendRegistered(): void {
    if (this._vlmBackendRegistered) return;

    const bridge = this.requireBridge();
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

    this._vlmBackendRegistered = true;
    logger.info('VLM backend (llama.cpp mtmd) registered');
  }

  private ensureVLMComponent(): number {
    if (this._vlmComponentHandle !== 0) return this._vlmComponentHandle;

    // Register the VLM backend first
    this.ensureVLMBackendRegistered();

    const bridge = this.requireBridge();
    const m = bridge.module;
    const handlePtr = m._malloc(4);
    const result = m.ccall('rac_vlm_component_create', 'number', ['number'], [handlePtr]) as number;

    if (result !== 0) {
      m._free(handlePtr);
      bridge.checkResult(result, 'rac_vlm_component_create');
    }

    this._vlmComponentHandle = m.getValue(handlePtr, 'i32');
    m._free(handlePtr);
    logger.debug('VLM component created');
    return this._vlmComponentHandle;
  }

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
    const bridge = this.requireBridge();
    const m = bridge.module;
    const handle = this.ensureVLMComponent();

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
  }

  /** Unload the VLM model. */
  async unloadModel(): Promise<void> {
    if (this._vlmComponentHandle === 0) return;
    const bridge = this.requireBridge();
    const result = bridge.module.ccall(
      'rac_vlm_component_unload', 'number', ['number'], [this._vlmComponentHandle],
    ) as number;
    bridge.checkResult(result, 'rac_vlm_component_unload');
    logger.info('VLM model unloaded');
  }

  /** Check if a VLM model is loaded. */
  get isModelLoaded(): boolean {
    if (this._vlmComponentHandle === 0) return false;
    try {
      return (WASMBridge.shared.module.ccall(
        'rac_vlm_component_is_loaded', 'number', ['number'], [this._vlmComponentHandle],
      ) as number) === 1;
    } catch { return false; }
  }

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
    const bridge = this.requireBridge();
    const m = bridge.module;
    const handle = this.ensureVLMComponent();

    if (!this.isModelLoaded) {
      throw new SDKError(SDKErrorCode.ModelNotLoaded, 'No VLM model loaded. Call loadModel() first.');
    }

    logger.debug(`VLM process: "${prompt.substring(0, 50)}..."`);

    // Build rac_vlm_image_t struct
    const imageSize = m._rac_wasm_sizeof_vlm_image();
    const imagePtr = m._malloc(imageSize);
    for (let i = 0; i < imageSize; i++) m.setValue(imagePtr + i, 0, 'i8');

    let filePathPtr = 0;
    let base64Ptr = 0;
    let pixelPtr = 0;

    const vi = Offsets.vlmImage;
    m.setValue(imagePtr + vi.format, image.format, 'i32');

    if (image.format === VLMImageFormat.FilePath && image.filePath) {
      filePathPtr = bridge.allocString(image.filePath);
      m.setValue(imagePtr + vi.filePath, filePathPtr, '*');
    } else if (image.format === VLMImageFormat.Base64 && image.base64Data) {
      base64Ptr = bridge.allocString(image.base64Data);
      m.setValue(imagePtr + vi.base64Data, base64Ptr, '*');
    } else if (image.format === VLMImageFormat.RGBPixels && image.pixelData) {
      pixelPtr = m._malloc(image.pixelData.length);
      bridge.writeBytes(image.pixelData, pixelPtr);
      m.setValue(imagePtr + vi.pixelData, pixelPtr, '*');
    }

    m.setValue(imagePtr + vi.width, image.width ?? 0, 'i32');
    m.setValue(imagePtr + vi.height, image.height ?? 0, 'i32');

    // data_size: use pixel data length for RGB, base64 string length for base64
    const dataSize = image.pixelData?.length ?? image.base64Data?.length ?? 0;
    m.setValue(imagePtr + vi.dataSize, dataSize, 'i32');

    // Build rac_vlm_options_t
    const optSize = m._rac_wasm_sizeof_vlm_options();
    const optPtr = m._malloc(optSize);
    for (let i = 0; i < optSize; i++) m.setValue(optPtr + i, 0, 'i8');

    const vo = Offsets.vlmOptions;
    m.setValue(optPtr + vo.maxTokens, options.maxTokens ?? 512, 'i32');
    m.setValue(optPtr + vo.temperature, options.temperature ?? 0.7, 'float');
    m.setValue(optPtr + vo.topP, options.topP ?? 0.9, 'float');
    m.setValue(optPtr + vo.streamingEnabled, options.streaming ? 1 : 0, 'i32');

    let sysPtr = 0;
    if (options.systemPrompt) {
      sysPtr = bridge.allocString(options.systemPrompt);
      m.setValue(optPtr + vo.systemPrompt, sysPtr, '*');
    }

    m.setValue(optPtr + vo.modelFamily, options.modelFamily ?? VLMModelFamily.Auto, 'i32');

    const promptPtr = bridge.allocString(prompt);

    // Result struct
    const resSize = m._rac_wasm_sizeof_vlm_result();
    const resPtr = m._malloc(resSize);

    try {
      const r = m.ccall(
        'rac_vlm_component_process', 'number',
        ['number', 'number', 'number', 'number', 'number'],
        [handle, imagePtr, promptPtr, optPtr, resPtr],
      ) as number;
      bridge.checkResult(r, 'rac_vlm_component_process');

      // Read rac_vlm_result_t (offsets from compiler via StructOffsets)
      const vr = Offsets.vlmResult;
      const textPtr = m.getValue(resPtr + vr.text, '*');
      const vlmResult: VLMGenerationResult = {
        text: bridge.readString(textPtr),
        promptTokens: m.getValue(resPtr + vr.promptTokens, 'i32'),
        imageTokens: m.getValue(resPtr + vr.imageTokens, 'i32'),
        completionTokens: m.getValue(resPtr + vr.completionTokens, 'i32'),
        totalTokens: m.getValue(resPtr + vr.totalTokens, 'i32'),
        timeToFirstTokenMs: m.getValue(resPtr + vr.timeToFirstTokenMs, 'i32'),
        imageEncodeTimeMs: m.getValue(resPtr + vr.imageEncodeTimeMs, 'i32'),
        totalTimeMs: m.getValue(resPtr + vr.totalTimeMs, 'i32'),
        tokensPerSecond: m.getValue(resPtr + vr.tokensPerSecond, 'float'),
        hardwareUsed: bridge.accelerationMode as HardwareAcceleration,
      };

      m.ccall('rac_vlm_result_free', null, ['number'], [resPtr]);

      EventBus.shared.emit('vlm.processed', SDKEventType.Generation, {
        tokensPerSecond: vlmResult.tokensPerSecond,
        totalTokens: vlmResult.totalTokens,
        hardwareUsed: vlmResult.hardwareUsed,
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
  }

  /** Cancel in-progress VLM generation. */
  cancel(): void {
    if (this._vlmComponentHandle === 0) return;
    WASMBridge.shared.module.ccall(
      'rac_vlm_component_cancel', 'number', ['number'], [this._vlmComponentHandle],
    );
  }

  /** Clean up the VLM component and unregister backend. */
  cleanup(): void {
    if (this._vlmComponentHandle !== 0) {
      try {
        WASMBridge.shared.module.ccall(
          'rac_vlm_component_destroy', null, ['number'], [this._vlmComponentHandle],
        );
      } catch { /* ignore */ }
      this._vlmComponentHandle = 0;
    }

    if (this._vlmBackendRegistered) {
      try {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const fn = (WASMBridge.shared.module as any)['_rac_backend_llamacpp_vlm_unregister'];
        if (fn) {
          WASMBridge.shared.module.ccall('rac_backend_llamacpp_vlm_unregister', 'number', [], []);
        }
      } catch { /* ignore */ }
      this._vlmBackendRegistered = false;
    }
  }
}

export const VLM = new VLMImpl();
