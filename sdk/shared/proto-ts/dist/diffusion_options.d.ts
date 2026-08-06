import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
export declare const protobufPackage = "runanywhere.v1";
/**
 * Only values with a C carrier are listed. UNSPECIFIED = the model's
 * configured scheduler, which is what every engine does.
 */
export declare enum DiffusionScheduler {
    DIFFUSION_SCHEDULER_UNSPECIFIED = 0,
    DIFFUSION_SCHEDULER_DPMPP_2M = 1,
    /** DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS - recommended default */
    DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS = 2,
    DIFFUSION_SCHEDULER_DDIM = 3,
    DIFFUSION_SCHEDULER_EULER = 4,
    /** DIFFUSION_SCHEDULER_EULER_A - Euler Ancestral */
    DIFFUSION_SCHEDULER_EULER_A = 5,
    DIFFUSION_SCHEDULER_PNDM = 6,
    DIFFUSION_SCHEDULER_LMS = 7,
    DIFFUSION_SCHEDULER_DPMPP_2M_SDE = 8,
    UNRECOGNIZED = -1
}
export declare function diffusionSchedulerFromJSON(object: any): DiffusionScheduler;
export declare function diffusionSchedulerToJSON(object: DiffusionScheduler): string;
/** Encoding of the returned image bytes. */
export declare enum DiffusionOutputFormat {
    /** DIFFUSION_OUTPUT_FORMAT_UNSPECIFIED - = PNG */
    DIFFUSION_OUTPUT_FORMAT_UNSPECIFIED = 0,
    DIFFUSION_OUTPUT_FORMAT_PNG = 1,
    /**
     * DIFFUSION_OUTPUT_FORMAT_JPEG - No JPEG or WEBP encoder exists in this tree yet. Requesting one is
     * rejected outright; it is never silently answered with PNG.
     */
    DIFFUSION_OUTPUT_FORMAT_JPEG = 2,
    DIFFUSION_OUTPUT_FORMAT_WEBP = 3,
    /** DIFFUSION_OUTPUT_FORMAT_RAW_RGBA - Escape hatch: no encode, 4 bytes per pixel, "image/raw-rgba". */
    DIFFUSION_OUTPUT_FORMAT_RAW_RGBA = 4,
    UNRECOGNIZED = -1
}
export declare function diffusionOutputFormatFromJSON(object: any): DiffusionOutputFormat;
export declare function diffusionOutputFormatToJSON(object: DiffusionOutputFormat): string;
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
export interface DiffusionGenerationOptions {
    prompt: string;
    negativePrompt: string;
    /** 0 = backend default, for width, height, steps, and guidance_scale. */
    width: number;
    height: number;
    steps: number;
    guidanceScale: number;
    /**
     * Absent = pick a fresh random seed. Any present value is literal,
     * including 0. The seed actually used comes back on each result image.
     */
    seed?: number | undefined;
    scheduler: DiffusionScheduler;
    /**
     * Source picture. Its presence promotes the request to image-to-image;
     * adding `mask_image` promotes it to inpainting. Must be an encoded
     * PNG or JPEG container.
     */
    image?: Uint8Array | undefined;
    /** White = repaint. Same dimensions as `image`. */
    maskImage?: Uint8Array | undefined;
    /**
     * How far from the source image to travel. Only meaningful with `image`.
     * Effective steps = ceil(steps * strength), so a low value is
     * proportionally cheaper -- on device that is battery.
     */
    strength: number;
    /**
     * Container of the bytes above, as supplied by the caller. Request-side;
     * the result carries its own media type per image.
     */
    imageMediaType?: string | undefined;
    maskImageMediaType?: string | undefined;
    /** How many images to generate for this prompt. Absent = 1. */
    n?: number | undefined;
    /** Encoding of the returned image bytes. */
    outputFormat: DiffusionOutputFormat;
}
export interface DiffusionGenerationRequest {
    options?: DiffusionGenerationOptions | undefined;
    modelId?: string | undefined;
}
export interface DiffusionProgress {
    currentStep: number;
    /** as resolved by the backend */
    totalSteps: number;
    intermediateImageData?: Uint8Array | undefined;
}
/**
 * One generated image. Per-image, because with n > 1 each image has its
 * own seed and its own safety verdict (Stability `seeds`/`finish_reasons`,
 * Diffusers `nsfw_content_detected`).
 */
export interface DiffusionImage {
    data: Uint8Array;
    /** resolved, echoed back */
    width: number;
    height: number;
    /** so "make more like that one" works */
    seedUsed: number;
    /** advisory, in-band, never an error */
    safetyFlag: boolean;
    /** resolved output_format, e.g. "image/png" */
    mediaType: string;
}
export interface DiffusionResult {
    /**
     * One entry per requested image, in request order. commons emits exactly
     * one entry until the C ABI grows a list: rac_diffusion_result_t is a
     * single-image struct with one image_data/image_size pair.
     */
    images: DiffusionImage[];
    totalTimeMs: number;
}
export interface DiffusionStreamEvent {
    /** Generation is single-flight, so the stream itself is the correlation. */
    timestampUs: number;
    kind: DiffusionStreamEventKind;
    progress?: DiffusionProgress | undefined;
    result?: DiffusionResult | undefined;
    error?: SDKError | undefined;
}
export declare const DiffusionGenerationOptions: MessageFns<DiffusionGenerationOptions>;
export declare const DiffusionGenerationRequest: MessageFns<DiffusionGenerationRequest>;
export declare const DiffusionProgress: MessageFns<DiffusionProgress>;
export declare const DiffusionImage: MessageFns<DiffusionImage>;
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
