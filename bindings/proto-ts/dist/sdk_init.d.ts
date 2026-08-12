import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
import { SDKEnvironment } from "./model_types";
export declare const protobufPackage = "runanywhere.v1";
/**
 * The only platform-supplied values commons cannot derive itself. Platform
 * adapter callbacks are registered separately through rac_platform_adapter_t
 * before this call; this message is purely the data envelope.
 */
export interface SdkInitPhase1Request {
    /**
     * model_types.proto's SDKEnvironment is the single environment vocabulary.
     * Its zero is UNSPECIFIED, so an omitted field means unset, not
     * "development": commons must fail closed rather than pick an environment.
     */
    environment: SDKEnvironment;
    /** May be empty in development mode. */
    apiKey: string;
    /** May be empty in development mode. */
    baseUrl: string;
    /** Platform-resolved, e.g. a Keychain UUID. */
    deviceId: string;
    platform: string;
    sdkVersion: string;
    /**
     * Caller override for NetworkDefaults.request_timeout_ms. Unset = the pool
     * default (60000). openai-python / anthropic-python `timeout`.
     */
    requestTimeoutMs?: number | undefined;
    /**
     * Caller override for NetworkDefaults.max_retries. Unset = the pool
     * default (3). openai-python / anthropic-python `max_retries`; 0 disables
     * retries.
     */
    maxRetries?: number | undefined;
}
/**
 * The one value that legitimately varies between a dev build and a release.
 * Telemetry flushing and registry/local-file reconciliation are commons
 * behaviour, not per-call hints.
 */
export interface SdkInitPhase2Request {
    /** Dev-mode device registration token. */
    buildToken: string;
}
/**
 * Returned by Phase 1, Phase 2, and retryHTTP.
 *
 * A successful Phase 2 may still carry a warning: HTTP/auth setup is allowed
 * to fail in offline mode, in which case error is unset and warning holds the
 * offline notice while the SDK continues on cached models.
 */
export interface SdkInitResult {
    error?: SDKError | undefined;
    /** Registry rows that linked to local files. */
    linkedModelsCount: number;
    warning: string;
    /**
     * The cross-phase latched bit that survives between calls. SDKs read this
     * to decide whether an authenticated call can proceed without a retryHTTP.
     */
    hasCompletedHttpSetup: boolean;
    /**
     * Whether this configuration has a usable credential and URL pair at all.
     * Local-only development builds set it false so platform SDKs stop
     * retrying HTTP on every guarded call.
     */
    httpApplicable: boolean;
}
export declare const SdkInitPhase1Request: MessageFns<SdkInitPhase1Request>;
export declare const SdkInitPhase2Request: MessageFns<SdkInitPhase2Request>;
export declare const SdkInitResult: MessageFns<SdkInitResult>;
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
