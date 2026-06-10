import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * Phase identifiers — used by SdkInitResult.phase to indicate which phase the
 * result describes. Mirrors the SDK_INIT_* analytics events (started /
 * completed / failed) that exist in sdk_events.proto.
 * ---------------------------------------------------------------------------
 */
export declare enum SdkInitPhase {
    SDK_INIT_PHASE_UNSPECIFIED = 0,
    /** SDK_INIT_PHASE_ONE - Synchronous core init (~1-5ms, no network) */
    SDK_INIT_PHASE_ONE = 1,
    /** SDK_INIT_PHASE_TWO - Async services init (~100-500ms, network) */
    SDK_INIT_PHASE_TWO = 2,
    /** SDK_INIT_PHASE_RETRY_HTTP - HTTP/auth retry after offline init */
    SDK_INIT_PHASE_RETRY_HTTP = 3,
    UNRECOGNIZED = -1
}
export declare function sdkInitPhaseFromJSON(object: any): SdkInitPhase;
export declare function sdkInitPhaseToJSON(object: SdkInitPhase): string;
/**
 * ---------------------------------------------------------------------------
 * Environment values — must match RAC_ENV_* in
 * sdk/runanywhere-commons/include/rac/infrastructure/network/rac_environment.h
 * (development=0, staging=1, production=2). Numeric values are part of the
 * wire format; do not reorder.
 *
 * The prior attempt to
 * add SDK_INIT_ENVIRONMENT_UNSPECIFIED=0 and bump the tristate to 1/2/3 broke
 * Swift iOS at runtime — the shipped librac_commons.a in
 * sdk/runanywhere-swift/Binaries/RACommons.xcframework was compiled with the
 * original 0/1/2 layout, so Swift sending the regenerated enum value 1
 * (DEVELOPMENT) was decoded as STAGING by the old C++ side, which then failed
 * validation with RAC_ERROR_INVALID_ARGUMENT ("API key required"). The other
 * SDKs (Kotlin / Flutter / RN / Web) were never regenerated for the bumped
 * layout either, so reverting to the original 0/1/2 wire-format restores
 * cross-SDK consistency without requiring a coordinated xcframework rebuild.
 * Re-introducing UNSPECIFIED=0 must be paired with a synchronized rebuild of
 * every prebuilt commons binary AND regeneration of all five SDK bindings.
 * ---------------------------------------------------------------------------
 */
export declare enum SdkInitEnvironment {
    SDK_INIT_ENVIRONMENT_DEVELOPMENT = 0,
    SDK_INIT_ENVIRONMENT_STAGING = 1,
    SDK_INIT_ENVIRONMENT_PRODUCTION = 2,
    UNRECOGNIZED = -1
}
export declare function sdkInitEnvironmentFromJSON(object: any): SdkInitEnvironment;
export declare function sdkInitEnvironmentToJSON(object: SdkInitEnvironment): string;
/**
 * ---------------------------------------------------------------------------
 * Phase 1 input — synchronous core initialization. Carries the only
 * platform-supplied values commons cannot derive on its own: API credentials
 * + environment + device id (resolved by platform Keychain/Keystore lookup).
 *
 * Platform adapter callbacks (file I/O, secure storage, HTTP transport, log,
 * memory) are registered separately via rac_platform_adapter_t prior to
 * calling this entry point. This message is purely the data envelope.
 * ---------------------------------------------------------------------------
 */
export interface SdkInitPhase1Request {
    environment: SdkInitEnvironment;
    /** May be empty in development mode. */
    apiKey: string;
    /** May be empty in development mode. */
    baseUrl: string;
    /** Resolved by platform (Keychain UUID, etc.). */
    deviceId: string;
    /** SDK/platform identity used in auth/device metadata. */
    platform: string;
    /** SDK version reported to backend services. */
    sdkVersion: string;
}
/**
 * ---------------------------------------------------------------------------
 * Phase 2 input — async services initialization. Most state is already
 * resident in commons after Phase 1; this envelope carries the few per-call
 * hints that remain SDK-owned while the deterministic orchestration lives in
 * commons.
 * ---------------------------------------------------------------------------
 */
export interface SdkInitPhase2Request {
    /** Optional dev-mode device registration token. */
    buildToken: string;
    /** Bypass cached model assignments. */
    forceRefreshAssignments: boolean;
    /** Flush the registered telemetry sink. */
    flushTelemetry: boolean;
    /** Reconcile registry rows with local files. */
    discoverDownloadedModels: boolean;
    /** Ask discovery/refresh to rescan model dirs. */
    rescanLocalModels: boolean;
}
/**
 * ---------------------------------------------------------------------------
 * Result envelope returned by Phase 1 / Phase 2 / retryHTTP. Mirrors the
 * Swift RunAnywhere.swift Phase 2 logging shape (phase + duration + outcome
 * counts) so each SDK reports the same structured result to its consumer.
 *
 * success = true when the phase reached its terminal step. Even successful
 * Phase 2 results may carry warnings: HTTP/auth setup is allowed to fail in
 * offline mode; the SDK continues with cached/local models. In that case
 * success=true, http_configured=false, and warning carries the offline-mode
 * notice.
 * ---------------------------------------------------------------------------
 */
export interface SdkInitResult {
    /** Which phase produced this result. */
    phase: SdkInitPhase;
    /** True when the phase reached its terminal step. */
    success: boolean;
    /** Set when success=false (validation/init failure). */
    error?: SDKError | undefined;
    /** Phase 2 / retryHTTP: HTTP transport wired up. */
    httpConfigured: boolean;
    /** Phase 2: device registration callback returned RAC_SUCCESS. */
    deviceRegistered: boolean;
    /** Phase 2: count of registry rows that linked to local files. */
    linkedModelsCount: number;
    /** Phase 2: count of on-disk folders without registry rows. */
    discoveredOrphans: number;
    /** Optional non-fatal note (e.g. "offline mode", "auth deferred"). */
    warning: string;
    /** Wall-clock duration for this phase. */
    durationMs: number;
    /**
     * Explicit two-phase HTTP-setup completion flag,
     * decoupled from services-init completion so SDKs that initialize
     * offline (no connectivity) can still report success=true with
     * has_completed_http_setup=false and retry HTTP later via the
     * SDK_INIT_PHASE_RETRY_HTTP path. Mirrors RunAnywhere.swift:37
     * (`internal static var hasCompletedHTTPSetup`) and is the canonical
     * signal Flutter / Web / RN consume to decide whether the next
     * download/authenticated call can proceed without a retryHTTP step.
     *
     * Distinct from `http_configured` (field 4) which historically meant
     * "HTTP transport wired up at this phase's call site"; this field is
     * the cross-phase latched bit that survives between phase calls.
     */
    hasCompletedHttpSetup: boolean;
    /**
     * True when this SDK configuration has a usable network credential/url
     * pair and therefore HTTP/auth setup can eventually succeed. Local-only
     * development builds without baked-in Supabase config set this false so
     * platform SDKs do not retry HTTP on every guarded API call.
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
