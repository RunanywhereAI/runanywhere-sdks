import _m0 from "protobufjs/minimal";
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
export declare const FrameworksForCapabilityRequest: {
    encode(message: FrameworksForCapabilityRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): FrameworksForCapabilityRequest;
    fromJSON(object: any): FrameworksForCapabilityRequest;
    toJSON(message: FrameworksForCapabilityRequest): unknown;
    create<I extends Exact<DeepPartial<FrameworksForCapabilityRequest>, I>>(base?: I): FrameworksForCapabilityRequest;
    fromPartial<I extends Exact<DeepPartial<FrameworksForCapabilityRequest>, I>>(object: I): FrameworksForCapabilityRequest;
};
export declare const FrameworksForCapabilityResponse: {
    encode(message: FrameworksForCapabilityResponse, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): FrameworksForCapabilityResponse;
    fromJSON(object: any): FrameworksForCapabilityResponse;
    toJSON(message: FrameworksForCapabilityResponse): unknown;
    create<I extends Exact<DeepPartial<FrameworksForCapabilityResponse>, I>>(base?: I): FrameworksForCapabilityResponse;
    fromPartial<I extends Exact<DeepPartial<FrameworksForCapabilityResponse>, I>>(object: I): FrameworksForCapabilityResponse;
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
//# sourceMappingURL=router.d.ts.map