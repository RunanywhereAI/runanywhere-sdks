import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
/**
 * Packed 8-bit pixel layouts accepted at the SDK boundary. Rows are tightly
 * packed; callers must not include per-row padding.
 */
export declare enum SegmentationPixelFormat {
    SEGMENTATION_PIXEL_FORMAT_UNSPECIFIED = 0,
    SEGMENTATION_PIXEL_FORMAT_RGB8 = 1,
    SEGMENTATION_PIXEL_FORMAT_RGBA8 = 2,
    SEGMENTATION_PIXEL_FORMAT_BGRA8 = 3,
    UNRECOGNIZED = -1
}
export declare function segmentationPixelFormatFromJSON(object: any): SegmentationPixelFormat;
export declare function segmentationPixelFormatToJSON(object: SegmentationPixelFormat): string;
export interface SegmentationImage {
    data: Uint8Array;
    width: number;
    height: number;
    pixelFormat: SegmentationPixelFormat;
}
export interface SegmentationOptions {
    /**
     * When true, also return a deterministic class-colour RGBA image. The
     * canonical class_mask_u16_le remains the machine-readable result.
     */
    includeDiagnosticRgba: boolean;
}
export interface SegmentationRequest {
    image?: SegmentationImage | undefined;
    options?: SegmentationOptions | undefined;
}
export interface SegmentationClassSummary {
    classId: number;
    pixelCount: number;
    fraction: number;
    label: string;
}
export interface SegmentationResult {
    /**
     * Both masks always describe the source image dimensions, not the model's
     * internal 512x512 input or 128x128 logits grid.
     */
    width: number;
    height: number;
    classMaskU16Le: Uint8Array;
    diagnosticRgba?: Uint8Array | undefined;
    classSummaries: SegmentationClassSummary[];
    processingTimeMs: number;
    modelId: string;
}
export declare const SegmentationImage: MessageFns<SegmentationImage>;
export declare const SegmentationOptions: MessageFns<SegmentationOptions>;
export declare const SegmentationRequest: MessageFns<SegmentationRequest>;
export declare const SegmentationClassSummary: MessageFns<SegmentationClassSummary>;
export declare const SegmentationResult: MessageFns<SegmentationResult>;
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
