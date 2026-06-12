import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { InferenceFramework } from "./model_types";
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
 * VLM model family for chat-template selection.
 * Mirrors rac_vlm_model_family_t.
 * ---------------------------------------------------------------------------
 */
export declare enum VLMModelFamily {
    VLM_MODEL_FAMILY_UNSPECIFIED = 0,
    VLM_MODEL_FAMILY_AUTO = 1,
    VLM_MODEL_FAMILY_QWEN2_VL = 2,
    VLM_MODEL_FAMILY_SMOLVLM = 3,
    VLM_MODEL_FAMILY_LLAVA = 4,
    VLM_MODEL_FAMILY_CUSTOM = 99,
    UNRECOGNIZED = -1
}
export declare function vLMModelFamilyFromJSON(object: any): VLMModelFamily;
export declare function vLMModelFamilyToJSON(object: VLMModelFamily): string;
export declare enum VLMStreamEventKind {
    VLM_STREAM_EVENT_KIND_UNSPECIFIED = 0,
    VLM_STREAM_EVENT_KIND_STARTED = 1,
    VLM_STREAM_EVENT_KIND_IMAGE_ENCODED = 2,
    VLM_STREAM_EVENT_KIND_TOKEN = 3,
    VLM_STREAM_EVENT_KIND_COMPLETED = 4,
    VLM_STREAM_EVENT_KIND_ERROR = 5,
    UNRECOGNIZED = -1
}
export declare function vLMStreamEventKindFromJSON(object: any): VLMStreamEventKind;
export declare function vLMStreamEventKindToJSON(object: VLMStreamEventKind): string;
/**
 * ---------------------------------------------------------------------------
 * Custom VLM chat template.
 * Mirrors rac_vlm_chat_template_t.
 * ---------------------------------------------------------------------------
 */
export interface VLMChatTemplate {
    templateText: string;
    imageMarker?: string | undefined;
    defaultSystemPrompt?: string | undefined;
}
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
    /**
     * Optional source metadata. Adapters may populate this after camera/file
     * picker capture without exposing native APIs to core.
     */
    mediaType?: string | undefined;
    name?: string | undefined;
    sizeBytes: number;
    metadata: {
        [key: string]: string;
    };
}
export interface VLMImage_MetadataEntry {
    key: string;
    value: string;
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
    /** Additional component-level fields from rac_vlm_config_t. */
    contextLength: number;
    temperature: number;
    systemPrompt?: string | undefined;
    streamingEnabled: boolean;
    preferredFramework?: InferenceFramework | undefined;
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
    /** Full rac_vlm_options_t coverage. */
    stopSequences: string[];
    streamingEnabled: boolean;
    systemPrompt?: string | undefined;
    maxImageSize: number;
    nThreads: number;
    useGpu: boolean;
    modelFamily: VLMModelFamily;
    customChatTemplate?: VLMChatTemplate | undefined;
    imageMarkerOverride?: string | undefined;
    /** Additional llama.cpp sampling knobs and result controls. */
    seed: number;
    repetitionPenalty: number;
    minP: number;
    emitImageEmbeddings: boolean;
}
export interface VLMGenerationRequest {
    requestId: string;
    images: VLMImage[];
    options?: VLMGenerationOptions | undefined;
    modelId?: string | undefined;
    metadata: {
        [key: string]: string;
    };
}
export interface VLMGenerationRequest_MetadataEntry {
    key: string;
    value: string;
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
 * Streaming note: the VLM service emits VLMStreamEvent messages for
 * per-token deltas and terminal results; this aggregate result is carried on
 * the unary Generate RPC and on terminal stream events.
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
    /** Detailed VLM metrics from Kotlin/Web/C ABI. */
    imageTokens: number;
    timeToFirstTokenMs: number;
    imageEncodeTimeMs: number;
    hardwareUsed?: string | undefined;
    errorMessage?: string | undefined;
    errorCode: number;
    finishReason: string;
    imagesProcessed: number;
}
export interface VLMStreamEvent {
    seq: number;
    timestampUs: number;
    requestId: string;
    kind: VLMStreamEventKind;
    token: string;
    tokenIndex: number;
    isFinal: boolean;
    tokensPerSecond: number;
    result?: VLMResult | undefined;
    errorMessage?: string | undefined;
    errorCode: number;
}
export interface VLMServiceState {
    isReady: boolean;
    currentModel?: string | undefined;
    contextLength: number;
    supportsStreaming: boolean;
    supportsMultipleImages: boolean;
    visionEncoderType?: string | undefined;
    errorMessage?: string | undefined;
    errorCode: number;
}
/**
 * ---------------------------------------------------------------------------
 * VLM load-resolved-artifacts request / response.
 *
 * Replaces the legacy trio `rac_vlm_create` + `rac_vlm_initialize` +
 * `rac_vlm_destroy` (on error) with a single proto-backed call. Consumers
 * pass the already-resolved model paths (primary model + optional mmproj
 * vision projector) together with an optional model_id for telemetry. The
 * response carries the resulting native handle as an opaque uint64; callers
 * store the handle and use it for subsequent process/cancel/destroy calls.
 * ---------------------------------------------------------------------------
 */
export interface VLMLoadResolvedArtifactsRequest {
    modelId: string;
    primaryModelPath: string;
    mmprojPath?: string | undefined;
}
export interface VLMLoadResolvedArtifactsResponse {
    /** opaque native handle (0 on failure) */
    handle: number;
    /** RAC_SUCCESS or error code */
    resultCode: number;
    errorMessage?: string | undefined;
}
export declare const VLMChatTemplate: MessageFns<VLMChatTemplate>;
export declare const VLMImage: MessageFns<VLMImage>;
export declare const VLMImage_MetadataEntry: MessageFns<VLMImage_MetadataEntry>;
export declare const VLMConfiguration: MessageFns<VLMConfiguration>;
export declare const VLMGenerationOptions: MessageFns<VLMGenerationOptions>;
export declare const VLMGenerationRequest: MessageFns<VLMGenerationRequest>;
export declare const VLMGenerationRequest_MetadataEntry: MessageFns<VLMGenerationRequest_MetadataEntry>;
export declare const VLMResult: MessageFns<VLMResult>;
export declare const VLMStreamEvent: MessageFns<VLMStreamEvent>;
export declare const VLMServiceState: MessageFns<VLMServiceState>;
export declare const VLMLoadResolvedArtifactsRequest: MessageFns<VLMLoadResolvedArtifactsRequest>;
export declare const VLMLoadResolvedArtifactsResponse: MessageFns<VLMLoadResolvedArtifactsResponse>;
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
export interface MessageFns<T> {
    encode(message: T, writer?: BinaryWriter): BinaryWriter;
    decode(input: BinaryReader | Uint8Array, length?: number): T;
    fromJSON(object: any): T;
    toJSON(message: T): unknown;
    create<I extends Exact<DeepPartial<T>, I>>(base?: I): T;
    fromPartial<I extends Exact<DeepPartial<T>, I>>(object: I): T;
}
export {};
