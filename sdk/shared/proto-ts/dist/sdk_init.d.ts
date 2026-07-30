import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
export declare const protobufPackage = "runanywhere.v1";
export declare enum SdkInitPhase {
    SDK_INIT_PHASE_UNSPECIFIED = 0,
    /** SDK_INIT_PHASE_ONE - Synchronous core init, no network */
    SDK_INIT_PHASE_ONE = 1,
    /** SDK_INIT_PHASE_TWO - Async services init, network */
    SDK_INIT_PHASE_TWO = 2,
    /** SDK_INIT_PHASE_RETRY_HTTP - HTTP/auth retry after an offline init */
    SDK_INIT_PHASE_RETRY_HTTP = 3,
    UNRECOGNIZED = -1
}
export declare function sdkInitPhaseFromJSON(object: any): SdkInitPhase;
export declare function sdkInitPhaseToJSON(object: SdkInitPhase): string;
/**
 * PRODUCTION is 2 because 1 was a staging value in shipped commons and
 * xcframework builds. Do not renumber.
 */
export declare enum SdkInitEnvironment {
    SDK_INIT_ENVIRONMENT_DEVELOPMENT = 0,
    SDK_INIT_ENVIRONMENT_PRODUCTION = 2,
    UNRECOGNIZED = -1
}
export declare function sdkInitEnvironmentFromJSON(object: any): SdkInitEnvironment;
export declare function sdkInitEnvironmentToJSON(object: SdkInitEnvironment): string;
/**
 * The only platform-supplied values commons cannot derive itself. Platform
 * adapter callbacks are registered separately through rac_platform_adapter_t
 * before this call; this message is purely the data envelope.
 */
export interface SdkInitPhase1Request {
    environment: SdkInitEnvironment;
    /** May be empty in development mode. */
    apiKey: string;
    /** May be empty in development mode. */
    baseUrl: string;
    /** Platform-resolved, e.g. a Keychain UUID. */
    deviceId: string;
    platform: string;
    sdkVersion: string;
}
/**
 * Most state is already resident in commons after Phase 1; these are the
 * per-call hints that stay SDK-owned.
 */
export interface SdkInitPhase2Request {
    /** Dev-mode device registration token. */
    buildToken: string;
    forceRefreshAssignments: boolean;
    flushTelemetry: boolean;
    /** Reconcile registry rows with local files. */
    discoverDownloadedModels: boolean;
    rescanLocalModels: boolean;
}
/**
 * Returned by Phase 1, Phase 2, and retryHTTP.
 *
 * A successful Phase 2 may still carry a warning: HTTP/auth setup is allowed
 * to fail in offline mode, in which case success=true, http_configured=false,
 * and warning holds the offline notice while the SDK continues on cached
 * models.
 */
export interface SdkInitResult {
    phase: SdkInitPhase;
    /** The phase reached its terminal step. */
    success: boolean;
    error?: SDKError | undefined;
    /** HTTP transport wired at this call site. */
    httpConfigured: boolean;
    deviceRegistered: boolean;
    /** Registry rows that linked to local files. */
    linkedModelsCount: number;
    /** On-disk folders with no registry row. */
    discoveredOrphans: number;
    warning: string;
    durationMs: number;
    /**
     * The cross-phase latched bit that survives between calls, as opposed to
     * http_configured, which describes only the calling phase. SDKs read this
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
