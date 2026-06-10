import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { InferenceFramework } from "./model_types";
import { SDKComponent } from "./sdk_events";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * Request: ask commons which frameworks can serve a given SDK component.
 * Maps to the engine-router plugin registry (not the model registry); this
 * answers "which engines CAN run this capability on this host" independent
 * of whether any matching model has been registered yet.
 * ---------------------------------------------------------------------------
 */
export interface FrameworksForCapabilityRequest {
    component: SDKComponent;
}
/**
 * ---------------------------------------------------------------------------
 * Response: ordered list of inference frameworks. Ordering matches the
 * engine-router's priority-descending scan of registered plugins for the
 * primitive(s) mapped from `component`. Duplicates are removed while
 * preserving first-seen order.
 * ---------------------------------------------------------------------------
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
