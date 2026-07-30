import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { InferenceFramework } from "./model_types";
import { SDKComponent } from "./sdk_events";
export declare const protobufPackage = "runanywhere.v1";
/**
 * Answers "which engines can run this capability on this host", from the
 * engine-router plugin registry rather than the model registry, so it is
 * independent of whether a matching model is registered.
 */
export interface FrameworksForCapabilityRequest {
    component: SDKComponent;
}
/**
 * Ordered by the router's priority-descending scan of registered plugins.
 * Duplicates removed, first-seen order preserved.
 */
export interface FrameworksForCapabilityResponse {
    frameworks: InferenceFramework[];
}
export declare const FrameworksForCapabilityRequest: MessageFns<FrameworksForCapabilityRequest>;
export declare const FrameworksForCapabilityResponse: MessageFns<FrameworksForCapabilityResponse>;
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
