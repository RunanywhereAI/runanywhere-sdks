import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { InferenceFramework } from "./model_types";
import { ReasoningOptions } from "./thinking_tag_pattern";
export declare const protobufPackage = "runanywhere.v1";
/**
 * The JPEG/PNG/WEBP and RAW_RGBA values are reserved: no backend detects
 * containers yet, and no SDK passes straight RGBA. Swift's Apple-only uiImage
 * and pixelBuffer cases flatten to RAW_RGB before crossing the C ABI.
 */
export declare enum VLMImageFormat {
    VLM_IMAGE_FORMAT_UNSPECIFIED = 0,
    VLM_IMAGE_FORMAT_JPEG = 1,
    VLM_IMAGE_FORMAT_PNG = 2,
    VLM_IMAGE_FORMAT_WEBP = 3,
    VLM_IMAGE_FORMAT_RAW_RGB = 4,
    VLM_IMAGE_FORMAT_RAW_RGBA = 5,
    VLM_IMAGE_FORMAT_BASE64 = 6,
    VLM_IMAGE_FORMAT_FILE_PATH = 7,
    UNRECOGNIZED = -1
}
export declare function vLMImageFormatFromJSON(object: any): VLMImageFormat;
export declare function vLMImageFormatToJSON(object: VLMImageFormat): string;
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
export interface VLMChatTemplate {
    templateText: string;
    imageMarker?: string | undefined;
    defaultSystemPrompt?: string | undefined;
}
export interface VLMImage {
    filePath?: string | undefined;
    /** JPEG/PNG/WEBP container bytes */
    encoded?: Uint8Array | undefined;
    /** RAW_RGB or RAW_RGBA pixel buffer */
    rawRgb?: Uint8Array | undefined;
    base64?: string | undefined;
    width: number;
    height: number;
    format: VLMImageFormat;
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
export interface VLMConfiguration {
    modelId: string;
    maxImageSizePx: number;
    maxTokens: number;
    contextLength: number;
    temperature: number;
    systemPrompt?: string | undefined;
    streamingEnabled: boolean;
    preferredFramework?: InferenceFramework | undefined;
}
export interface VLMGenerationOptions {
    prompt: string;
    maxOutputTokens: number;
    temperature: number;
    topP: number;
    topK: number;
    stopSequences: string[];
    systemPrompt?: string | undefined;
    maxImageSize: number;
    nThreads: number;
    useGpu: boolean;
    modelFamily: VLMModelFamily;
    /**
     * Commons does not convert this field on the VLM proto path, so the
     * llama.cpp template support behind it is currently unreachable from here.
     */
    customChatTemplate?: VLMChatTemplate | undefined;
    imageMarkerOverride?: string | undefined;
    seed: number;
    repetitionPenalty: number;
    minP: number;
    emitImageEmbeddings: boolean;
    reasoning?: ReasoningOptions | undefined;
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
export interface VLMResult {
    text: string;
    inputTokens: number;
    outputTokens: number;
    totalTokens: number;
    processingTimeMs: number;
    tokensPerSecond: number;
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
