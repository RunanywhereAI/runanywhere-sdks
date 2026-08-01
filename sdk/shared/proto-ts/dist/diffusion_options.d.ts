import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
import { InferenceFramework } from "./model_types";
export declare const protobufPackage = "runanywhere.v1";
export declare enum DiffusionMode {
    DIFFUSION_MODE_UNSPECIFIED = 0,
    DIFFUSION_MODE_TEXT_TO_IMAGE = 1,
    DIFFUSION_MODE_IMAGE_TO_IMAGE = 2,
    DIFFUSION_MODE_INPAINTING = 3,
    UNRECOGNIZED = -1
}
export declare function diffusionModeFromJSON(object: any): DiffusionMode;
export declare function diffusionModeToJSON(object: DiffusionMode): string;
/** DDPM and LCM are forward-looking; no SDK exposes them. */
export declare enum DiffusionScheduler {
    DIFFUSION_SCHEDULER_UNSPECIFIED = 0,
    DIFFUSION_SCHEDULER_DPMPP_2M = 1,
    /** DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS - recommended default */
    DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS = 2,
    DIFFUSION_SCHEDULER_DDIM = 3,
    DIFFUSION_SCHEDULER_DDPM = 4,
    DIFFUSION_SCHEDULER_EULER = 5,
    /** DIFFUSION_SCHEDULER_EULER_A - Euler Ancestral */
    DIFFUSION_SCHEDULER_EULER_A = 6,
    DIFFUSION_SCHEDULER_PNDM = 7,
    DIFFUSION_SCHEDULER_LMS = 8,
    DIFFUSION_SCHEDULER_LCM = 9,
    DIFFUSION_SCHEDULER_DPMPP_2M_SDE = 10,
    UNRECOGNIZED = -1
}
export declare function diffusionSchedulerFromJSON(object: any): DiffusionScheduler;
export declare function diffusionSchedulerToJSON(object: DiffusionScheduler): string;
export declare enum DiffusionModelVariant {
    DIFFUSION_MODEL_VARIANT_UNSPECIFIED = 0,
    DIFFUSION_MODEL_VARIANT_SD_1_5 = 1,
    DIFFUSION_MODEL_VARIANT_SD_2_1 = 2,
    DIFFUSION_MODEL_VARIANT_SDXL = 3,
    DIFFUSION_MODEL_VARIANT_SDXL_TURBO = 4,
    DIFFUSION_MODEL_VARIANT_SDXS = 5,
    /** DIFFUSION_MODEL_VARIANT_LCM - Latent Consistency Model */
    DIFFUSION_MODEL_VARIANT_LCM = 6,
    UNRECOGNIZED = -1
}
export declare function diffusionModelVariantFromJSON(object: any): DiffusionModelVariant;
export declare function diffusionModelVariantToJSON(object: DiffusionModelVariant): string;
export declare enum DiffusionTokenizerSourceKind {
    DIFFUSION_TOKENIZER_SOURCE_KIND_UNSPECIFIED = 0,
    /** DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15 - CLIP ViT-L/14 */
    DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15 = 1,
    /** DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2 - OpenCLIP ViT-H/14 */
    DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2 = 2,
    /** DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL - dual tokenizers */
    DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL = 3,
    DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM = 4,
    UNRECOGNIZED = -1
}
export declare function diffusionTokenizerSourceKindFromJSON(object: any): DiffusionTokenizerSourceKind;
export declare function diffusionTokenizerSourceKindToJSON(object: DiffusionTokenizerSourceKind): string;
export declare enum DiffusionStreamEventKind {
    DIFFUSION_STREAM_EVENT_KIND_UNSPECIFIED = 0,
    DIFFUSION_STREAM_EVENT_KIND_STARTED = 1,
    DIFFUSION_STREAM_EVENT_KIND_PROGRESS = 2,
    DIFFUSION_STREAM_EVENT_KIND_INTERMEDIATE_IMAGE = 3,
    DIFFUSION_STREAM_EVENT_KIND_COMPLETED = 4,
    DIFFUSION_STREAM_EVENT_KIND_ERROR = 5,
    UNRECOGNIZED = -1
}
export declare function diffusionStreamEventKindFromJSON(object: any): DiffusionStreamEventKind;
export declare function diffusionStreamEventKindToJSON(object: DiffusionStreamEventKind): string;
export interface DiffusionTokenizerSource {
    kind: DiffusionTokenizerSourceKind;
    customPath?: string | undefined;
    autoDownload: boolean;
}
export interface DiffusionConfiguration {
    modelVariant: DiffusionModelVariant;
    tokenizerSource?: DiffusionTokenizerSource | undefined;
    enableSafetyChecker: boolean;
    maxMemoryMb: number;
    modelId?: string | undefined;
    preferredFramework?: InferenceFramework | undefined;
}
export interface DiffusionGenerationOptions {
    prompt: string;
    negativePrompt: string;
    /** 0 = backend default, for width, height, steps, and guidance_scale. */
    width: number;
    height: number;
    steps: number;
    guidanceScale: number;
    /** -1 = random. */
    seed: number;
    scheduler: DiffusionScheduler;
    mode: DiffusionMode;
    /** For IMAGE_TO_IMAGE and INPAINTING. */
    inputImage?: Uint8Array | undefined;
    maskImage?: Uint8Array | undefined;
    denoiseStrength: number;
    reportIntermediateImages: boolean;
    progressStride: number;
    inputImageWidth: number;
    inputImageHeight: number;
    inputImageMediaType?: string | undefined;
    maskImageMediaType?: string | undefined;
    /** 0 = one image. */
    batchSize: number;
    returnLatents: boolean;
}
export interface DiffusionGenerationRequest {
    requestId: string;
    options?: DiffusionGenerationOptions | undefined;
    modelId?: string | undefined;
    metadata: {
        [key: string]: string;
    };
}
export interface DiffusionGenerationRequest_MetadataEntry {
    key: string;
    value: string;
}
export interface DiffusionProgress {
    progressPercent: number;
    currentStep: number;
    totalSteps: number;
    stage: string;
    intermediateImageData?: Uint8Array | undefined;
    intermediateImageWidth: number;
    intermediateImageHeight: number;
    timestampMs: number;
    etaMs: number;
    intermediateImageMediaType?: string | undefined;
}
export interface DiffusionResult {
    imageData: Uint8Array;
    width: number;
    height: number;
    /** The resolved seed, so a run can be reproduced when seed was -1. */
    seedUsed: number;
    totalTimeMs: number;
    safetyFlag: boolean;
    usedScheduler: DiffusionScheduler;
    imageMediaType?: string | undefined;
    batchImages: Uint8Array[];
    imagesGenerated: number;
    error?: SDKError | undefined;
}
export interface DiffusionStreamEvent {
    timestampUs: number;
    requestId: string;
    kind: DiffusionStreamEventKind;
    progress?: DiffusionProgress | undefined;
    result?: DiffusionResult | undefined;
    error?: SDKError | undefined;
}
export declare const DiffusionTokenizerSource: MessageFns<DiffusionTokenizerSource>;
export declare const DiffusionConfiguration: MessageFns<DiffusionConfiguration>;
export declare const DiffusionGenerationOptions: MessageFns<DiffusionGenerationOptions>;
export declare const DiffusionGenerationRequest: MessageFns<DiffusionGenerationRequest>;
export declare const DiffusionGenerationRequest_MetadataEntry: MessageFns<DiffusionGenerationRequest_MetadataEntry>;
export declare const DiffusionProgress: MessageFns<DiffusionProgress>;
export declare const DiffusionResult: MessageFns<DiffusionResult>;
export declare const DiffusionStreamEvent: MessageFns<DiffusionStreamEvent>;
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
