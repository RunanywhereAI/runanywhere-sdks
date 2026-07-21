import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
export interface VocoderRequest {
    /** Contiguous IEEE-754 float32 little-endian data in [B, M, T] order. */
    melSpectrogramF32Le: Uint8Array;
    batchSize: number;
    melBinCount: number;
    frameCount: number;
}
export interface VocoderResult {
    /** Contiguous IEEE-754 float32 little-endian data in [B, C, S] order. */
    samplesF32Le: Uint8Array;
    batchSize: number;
    channelCount: number;
    sampleCount: number;
    sampleRateHz: number;
    hopLength: number;
    processingTimeMs: number;
    modelId: string;
}
export declare const VocoderRequest: MessageFns<VocoderRequest>;
export declare const VocoderResult: MessageFns<VocoderResult>;
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
