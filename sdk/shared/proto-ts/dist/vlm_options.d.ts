import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { ChatMessage } from "./chat";
import { SDKError } from "./errors";
import { LLMGenerationOptions } from "./llm_options";
import { TokenUsage } from "./token_usage";
export declare const protobufPackage = "runanywhere.v1";
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
    /**
     * VLM_STREAM_EVENT_KIND_IMAGE_ENCODED - Emitted when the vision encoder finishes and decoding begins -- the
     * cue for a UI to switch from "analysing image" to "writing". Emitted
     * where the backend measures the encode boundary
     * (VLMResult.image_encode_time_ms comes from the same measurement).
     */
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
/**
 * Pixel buffers are tightly packed with NO row padding: RGB is 3 bytes/px,
 * RGBA is 4, and width * height * channels MUST equal the buffer length or
 * the request is rejected. raw_rgba drops alpha at the boundary.
 */
export interface VLMImage {
    /** Local file. The on-device analogue of a cloud Files-API file_id. */
    filePath?: string | undefined;
    /**
     * Compressed container bytes -- image/jpeg, image/png, image/webp.
     * Decoded by commons. Set media_type alongside. Same slot name and
     * meaning as ChatAttachment.data and Anthropic source.data.
     */
    data?: Uint8Array | undefined;
    /** 3 bytes/px */
    rawRgb?: Uint8Array | undefined;
    /** same container formats as `data`, base64-encoded */
    base64?: string | undefined;
    /** 4 bytes/px; commons drops alpha */
    rawRgba?: Uint8Array | undefined;
    /** required for raw_rgb / raw_rgba */
    width: number;
    /** required for raw_rgb / raw_rgba */
    height: number;
    /**
     * MIME type of `data`/`base64`. Required when either is set. An open
     * string, as everywhere in the industry, so adding HEIC is not a proto
     * change.
     */
    mediaType: string;
}
export interface VLMGenerationRequest {
    requestId: string;
    images: VLMImage[];
    /**
     * Ordered conversation. A follow-up question about the same picture is
     * just another turn; images ride as ChatMessage.attachments.
     */
    messages: ChatMessage[];
    /** The question about the image, for the single-turn quickstart path. */
    prompt: string;
    /**
     * One options set for all text generation, image or not -- same names,
     * same defaults, same validation as the text API. Carries
     * structured_output, which is how OCR / field extraction / bounding
     * boxes are expressed (deliberately no ocr() or detect() verb).
     */
    options?: LLMGenerationOptions | undefined;
    /** Only the knobs that have no text-generation meaning. */
    vision?: VLMVisionOptions | undefined;
    modelId?: string | undefined;
}
/**
 * The four genuinely vision-specific knobs. Everything else in the old
 * VLMGenerationOptions was either a copy of LLMGenerationOptions or dead.
 */
export interface VLMVisionOptions {
    modelFamily: VLMModelFamily;
    /**
     * Live end-to-end (commons converts it, llama.cpp applies it); it is
     * simply not surfaced by the v3 facades yet.
     */
    customChatTemplate?: VLMChatTemplate | undefined;
    imageMarkerOverride?: string | undefined;
    /**
     * Per-image vision-token budget -- the unit that actually drives
     * prefill (cf. llama.cpp --image-max-tokens, Gemini media_resolution).
     * 0 = the bundle's compiled default. The value actually used is
     * reported back as VLMResult.image_tokens.
     */
    maxImageTokens: number;
}
export interface VLMResult {
    text: string;
    /**
     * Wall-clock for the whole call, image encode included. int64 ms is the
     * unit for every duration on this surface; the _ms suffix stays explicit.
     */
    totalTimeMs: number;
    imageTokens: number;
    /** canonical spelling (usage = 15) */
    imageEncodeTimeMs: number;
    /**
     * Produced by commons on both the one-shot and the streaming path, with
     * the LLM domain's vocabulary: "stop" | "length" | "stop_sequence".
     */
    finishReason: string;
    usage?: TokenUsage | undefined;
    error?: SDKError | undefined;
}
export interface VLMStreamEvent {
    timestampUs: number;
    requestId: string;
    /** The single terminal discriminator: COMPLETED or ERROR ends the stream. */
    kind: VLMStreamEventKind;
    token: string;
    tokenIndex: number;
    /**
     * Rate comes from result.usage.tokens_per_second on the terminal event,
     * in TokenUsage's own type. No second copy, no second scalar type.
     */
    result?: VLMResult | undefined;
    error?: SDKError | undefined;
}
export declare const VLMChatTemplate: MessageFns<VLMChatTemplate>;
export declare const VLMImage: MessageFns<VLMImage>;
export declare const VLMGenerationRequest: MessageFns<VLMGenerationRequest>;
export declare const VLMVisionOptions: MessageFns<VLMVisionOptions>;
export declare const VLMResult: MessageFns<VLMResult>;
export declare const VLMStreamEvent: MessageFns<VLMStreamEvent>;
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
