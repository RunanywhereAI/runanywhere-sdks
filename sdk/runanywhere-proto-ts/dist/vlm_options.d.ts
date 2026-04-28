import _m0 from "protobufjs/minimal";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * VLM image input format — union across all SDKs and the C ABI.
 *
 * SDK ↔ proto enum mapping pre-IDL:
 *   C ABI  / Kotlin / RN / Web all expose three numeric formats (FILE_PATH=0,
 *          RGB_PIXELS=1, BASE64=2). Mapped to FILE_PATH, RAW_RGB, BASE64.
 *   Swift  Format enum adds Apple-only cases uiImage / pixelBuffer that are
 *          flattened to RAW_RGB before crossing the C ABI (see VLMTypes.swift
 *          lines 70-89). RAW_RGBA is reserved for SDKs that pass straight
 *          RGBA pixel buffers without the BGRA→RGB downsample step.
 *   Dart   sealed class with the same three formats (filePath / rgbPixels /
 *          base64); Flutter adapter passes RGB pixels through to the C ABI.
 *
 * JPEG / PNG / WEBP are container hints carried in the encoded `bytes`
 * payload (no current SDK declares these as enum cases — they are
 * reserved here so we can disambiguate decoded vs encoded sources without a
 * schema migration once a backend exposes container detection).
 * ---------------------------------------------------------------------------
 */
export declare enum VLMImageFormat {
    VLM_IMAGE_FORMAT_UNSPECIFIED = 0,
    /** VLM_IMAGE_FORMAT_JPEG - reserved — encoded JPEG bytes */
    VLM_IMAGE_FORMAT_JPEG = 1,
    /** VLM_IMAGE_FORMAT_PNG - reserved — encoded PNG bytes */
    VLM_IMAGE_FORMAT_PNG = 2,
    /** VLM_IMAGE_FORMAT_WEBP - reserved — encoded WebP bytes */
    VLM_IMAGE_FORMAT_WEBP = 3,
    /** VLM_IMAGE_FORMAT_RAW_RGB - Swift rgbPixels / Kotlin RGB_PIXELS / */
    VLM_IMAGE_FORMAT_RAW_RGB = 4,
    /**
     * VLM_IMAGE_FORMAT_RAW_RGBA - RN RGBPixels / Web RGBPixels /
     * C ABI RAC_VLM_IMAGE_FORMAT_RGB_PIXELS
     */
    VLM_IMAGE_FORMAT_RAW_RGBA = 5,
    /**
     * VLM_IMAGE_FORMAT_BASE64 - (Swift UIImage path produces RGBA
     * before downsample; pre-IDL no SDK
     * exposes RGBA over the C ABI)
     */
    VLM_IMAGE_FORMAT_BASE64 = 6,
    /**
     * VLM_IMAGE_FORMAT_FILE_PATH - Dart base64 / RN Base64 /
     * Web Base64 /
     * C ABI RAC_VLM_IMAGE_FORMAT_BASE64
     */
    VLM_IMAGE_FORMAT_FILE_PATH = 7,
    UNRECOGNIZED = -1
}
export declare function vLMImageFormatFromJSON(object: any): VLMImageFormat;
export declare function vLMImageFormatToJSON(object: VLMImageFormat): string;
/**
 * ---------------------------------------------------------------------------
 * VLM error codes — canonical SDK-facing surface.
 * Sources pre-IDL:
 *   Swift  CppBridge+VLM.swift:184  (notInitialized=1, modelLoadFailed=2,
 *                                    processingFailed=3, invalidImage=4,
 *                                    cancelled=5)
 *   Dart   vlm_types.dart:164       (notInitialized=1, modelLoadFailed=2,
 *                                    processingFailed=3, invalidImage=4,
 *                                    cancelled=5)
 *   RN     VLMTypes.ts:44           (NotInitialized=1, ModelLoadFailed=2,
 *                                    ProcessingFailed=3, InvalidImage=4,
 *                                    Cancelled=5)
 *   Kotlin / Web                    (no enum declared pre-IDL)
 *
 * The canonicalized set below narrows the surface to image-specific failure
 * modes that the C ABI can distinguish at the boundary; transport / lifecycle
 * errors (notInitialized, modelLoadFailed, processingFailed, cancelled) are
 * folded back into the shared rac_result_t error codes in rac_error.h and do
 * not appear here.
 * ---------------------------------------------------------------------------
 */
export declare enum VLMErrorCode {
    VLM_ERROR_CODE_UNSPECIFIED = 0,
    /** VLM_ERROR_CODE_INVALID_IMAGE - Swift/Dart/RN invalidImage */
    VLM_ERROR_CODE_INVALID_IMAGE = 1,
    /** VLM_ERROR_CODE_MODEL_NOT_LOADED - Swift/Dart/RN notInitialized + */
    VLM_ERROR_CODE_MODEL_NOT_LOADED = 2,
    /** VLM_ERROR_CODE_UNSUPPORTED_FORMAT - modelLoadFailed */
    VLM_ERROR_CODE_UNSUPPORTED_FORMAT = 3,
    /** VLM_ERROR_CODE_IMAGE_TOO_LARGE - backend cannot decode */
    VLM_ERROR_CODE_IMAGE_TOO_LARGE = 4,
    UNRECOGNIZED = -1
}
export declare function vLMErrorCodeFromJSON(object: any): VLMErrorCode;
export declare function vLMErrorCodeToJSON(object: VLMErrorCode): string;
/**
 * ---------------------------------------------------------------------------
 * VLM image input.
 *
 * `source` is a oneof so that exactly one of {file_path, encoded, raw_rgb,
 * base64} can be supplied per request. `width` / `height` are required for
 * non-encoded formats (raw_rgb, raw_rgba) where the consumer cannot infer
 * dimensions from a container header. `format` disambiguates encoded `bytes`
 * payloads (JPEG / PNG / WEBP) and explicitly tags raw / file-path / base64
 * sources.
 * ---------------------------------------------------------------------------
 */
export interface VLMImage {
    /** VLM_IMAGE_FORMAT_FILE_PATH */
    filePath?: string | undefined;
    /** VLM_IMAGE_FORMAT_{JPEG,PNG,WEBP} container bytes */
    encoded?: Uint8Array | undefined;
    /** VLM_IMAGE_FORMAT_RAW_RGB / RAW_RGBA pixel buffer */
    rawRgb?: Uint8Array | undefined;
    /** VLM_IMAGE_FORMAT_BASE64 (UTF-8 string) */
    base64?: string | undefined;
    /**
     * Required for VLM_IMAGE_FORMAT_RAW_RGB and VLM_IMAGE_FORMAT_RAW_RGBA
     * (consumers cannot infer dimensions for raw pixel buffers). Optional
     * for encoded / file_path / base64 sources where the decoder reads
     * dimensions from the container.
     */
    width: number;
    height: number;
    format: VLMImageFormat;
}
/**
 * ---------------------------------------------------------------------------
 * VLM component configuration.
 * Sources pre-IDL:
 *   Kotlin VLMTypes.kt:163        (modelId, contextLength, temperature,
 *                                  maxTokens, systemPrompt, streamingEnabled,
 *                                  preferredFramework)
 *   C ABI  rac_vlm_types.h:224    (model_id, preferred_framework,
 *                                  context_length, temperature, max_tokens,
 *                                  system_prompt, streaming_enabled)
 *
 * Per the canonicalization brief, only the load-bearing identification +
 * limits cross the IDL boundary here: model_id, max_image_size_px, max_tokens.
 * Per-request sampling parameters live on VLMGenerationOptions; runtime
 * streaming toggles and chat-template selection stay backend-private.
 * ---------------------------------------------------------------------------
 */
export interface VLMConfiguration {
    modelId: string;
    /** Kotlin maxImageSize / C ABI max_image_size */
    maxImageSizePx: number;
    /** (0 = backend default) */
    maxTokens: number;
}
/**
 * ---------------------------------------------------------------------------
 * VLM generation options — per-request sampling + prompt parameters.
 * Sources pre-IDL:
 *   Kotlin VLMTypes.kt:103        (maxTokens, temperature, topP, systemPrompt,
 *                                  maxImageSize, nThreads, useGpu)
 *   Dart   vlm_types.dart:127     (maxTokens, temperature, topP, systemPrompt,
 *                                  maxImageSize, nThreads, useGpu)
 *   RN     VLMTypes.ts:21         (maxTokens, temperature, topP)
 *   Web    VLMTypes.ts:28         (maxTokens, temperature, topP, systemPrompt,
 *                                  modelFamily, streaming)
 *   C ABI  rac_vlm_types.h:143    (max_tokens, temperature, top_p,
 *                                  stop_sequences, num_stop_sequences,
 *                                  streaming_enabled, system_prompt,
 *                                  max_image_size, n_threads, use_gpu,
 *                                  model_family, custom_chat_template,
 *                                  image_marker_override)
 *
 * top_k is included to align with the other text generation services
 * (LLM / chat) even though no current VLM SDK exposes it; the C ABI's
 * llama.cpp backend already supports top_k internally.
 * ---------------------------------------------------------------------------
 */
export interface VLMGenerationOptions {
    prompt: string;
    maxTokens: number;
    temperature: number;
    topP: number;
    topK: number;
}
/**
 * ---------------------------------------------------------------------------
 * VLM generation result.
 * Sources pre-IDL:
 *   Swift  VLMTypes.swift:208     (text, promptTokens, completionTokens,
 *                                  totalTimeMs as Double, tokensPerSecond)
 *   Kotlin VLMTypes.kt:120        (text, promptTokens, imageTokens,
 *                                  completionTokens, totalTokens,
 *                                  timeToFirstTokenMs, imageEncodeTimeMs,
 *                                  totalTimeMs, tokensPerSecond)
 *   Dart   vlm_types.dart:68      (text, promptTokens, completionTokens,
 *                                  totalTimeMs, tokensPerSecond)
 *   RN     VLMTypes.ts:28         (text, promptTokens, completionTokens,
 *                                  totalTimeMs, tokensPerSecond)
 *   Web    VLMTypes.ts:38         (VLMGenerationResult: text, promptTokens,
 *                                  imageTokens, completionTokens, totalTokens,
 *                                  timeToFirstTokenMs, imageEncodeTimeMs,
 *                                  totalTimeMs, tokensPerSecond, hardwareUsed)
 *   C ABI  rac_vlm_types.h:268    (text, prompt_tokens, image_tokens,
 *                                  completion_tokens, total_tokens,
 *                                  time_to_first_token_ms,
 *                                  image_encode_time_ms, total_time_ms,
 *                                  tokens_per_second)
 *
 * Streaming note: streaming results reuse this VLMResult message; per-token
 * text deltas are emitted on the existing LLM stream channel
 * (llm_service.proto streaming surface). No VLM-specific stream-event message
 * is introduced here.
 * ---------------------------------------------------------------------------
 */
export interface VLMResult {
    text: string;
    promptTokens: number;
    completionTokens: number;
    totalTokens: number;
    /** Kotlin/C ABI total_time_ms; */
    processingTimeMs: number;
    /** Swift VLMResult totalTimeMs (Double ms). */
    tokensPerSecond: number;
}
export declare const VLMImage: {
    encode(message: VLMImage, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): VLMImage;
    fromJSON(object: any): VLMImage;
    toJSON(message: VLMImage): unknown;
    create<I extends Exact<DeepPartial<VLMImage>, I>>(base?: I): VLMImage;
    fromPartial<I extends Exact<DeepPartial<VLMImage>, I>>(object: I): VLMImage;
};
export declare const VLMConfiguration: {
    encode(message: VLMConfiguration, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): VLMConfiguration;
    fromJSON(object: any): VLMConfiguration;
    toJSON(message: VLMConfiguration): unknown;
    create<I extends Exact<DeepPartial<VLMConfiguration>, I>>(base?: I): VLMConfiguration;
    fromPartial<I extends Exact<DeepPartial<VLMConfiguration>, I>>(object: I): VLMConfiguration;
};
export declare const VLMGenerationOptions: {
    encode(message: VLMGenerationOptions, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): VLMGenerationOptions;
    fromJSON(object: any): VLMGenerationOptions;
    toJSON(message: VLMGenerationOptions): unknown;
    create<I extends Exact<DeepPartial<VLMGenerationOptions>, I>>(base?: I): VLMGenerationOptions;
    fromPartial<I extends Exact<DeepPartial<VLMGenerationOptions>, I>>(object: I): VLMGenerationOptions;
};
export declare const VLMResult: {
    encode(message: VLMResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): VLMResult;
    fromJSON(object: any): VLMResult;
    toJSON(message: VLMResult): unknown;
    create<I extends Exact<DeepPartial<VLMResult>, I>>(base?: I): VLMResult;
    fromPartial<I extends Exact<DeepPartial<VLMResult>, I>>(object: I): VLMResult;
};
type Builtin = Date | Function | Uint8Array | string | number | boolean | undefined;
export type DeepPartial<T> = T extends Builtin ? T : T extends globalThis.Array<infer U> ? globalThis.Array<DeepPartial<U>> : T extends ReadonlyArray<infer U> ? ReadonlyArray<DeepPartial<U>> : T extends {} ? {
    [K in keyof T]?: DeepPartial<T[K]>;
} : Partial<T>;
type KeysOfUnion<T> = T extends T ? keyof T : never;
export type Exact<P, I extends P> = P extends Builtin ? P : P & {
    [K in keyof P]: Exact<P[K], I[K]>;
} & {
    [K in Exclude<keyof I, KeysOfUnion<P>>]: never;
};
export {};
//# sourceMappingURL=vlm_options.d.ts.map