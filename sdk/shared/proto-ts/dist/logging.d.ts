import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * Severity, mirroring the C ABI `rac_log_level_t`. Larger value = more severe.
 * 0 is TRACE (not UNSPECIFIED) to keep numeric parity with the C enum — the
 * same C-ABI-aligned convention used by HttpDownloadStatus (0=OK) and
 * SdkInitEnvironment (0=DEVELOPMENT).
 * ---------------------------------------------------------------------------
 */
export declare enum LogLevel {
    LOG_LEVEL_TRACE = 0,
    LOG_LEVEL_DEBUG = 1,
    LOG_LEVEL_INFO = 2,
    LOG_LEVEL_WARNING = 3,
    LOG_LEVEL_ERROR = 4,
    LOG_LEVEL_FATAL = 5,
    UNRECOGNIZED = -1
}
export declare function logLevelFromJSON(object: any): LogLevel;
export declare function logLevelToJSON(object: LogLevel): string;
/**
 * ---------------------------------------------------------------------------
 * SDK logging configuration. Union of the fields the per-SDK
 * LoggingConfiguration structs carry today; per-environment presets
 * (development/staging/production) stay in each SDK as factory helpers.
 * ---------------------------------------------------------------------------
 */
export interface LoggingConfiguration {
    /** Write logs to the platform-local sink (os_log / Logcat / console). */
    enableLocalLogging: boolean;
    /** Minimum severity emitted. Messages below this level are dropped. */
    minLogLevel: LogLevel;
    /** Attach file:line:function source location to each record. */
    includeSourceLocation: boolean;
    /** Attach device/build metadata (model, os version, app build) to records. */
    includeDeviceMetadata: boolean;
    /** Forward records to the remote logging pipeline. */
    enableRemoteLogging: boolean;
    /** Forward error/fatal records to Sentry. */
    enableSentryLogging: boolean;
}
/**
 * ---------------------------------------------------------------------------
 * A single structured log record. Mirrors the per-SDK LogEntry shape.
 * ---------------------------------------------------------------------------
 */
export interface LogEntry {
    /** Wall-clock epoch milliseconds. */
    timestampUnixMs: number;
    level: LogLevel;
    /** Subsystem/tag (e.g. "STT", "Download"). */
    category: string;
    message: string;
    /** Optional structured context. */
    metadata: {
        [key: string]: string;
    };
    /**
     * Optional source location + context (Kotlin LogEntry carries these as
     * first-class fields; other SDKs leave them empty). `line`/`error_code`
     * use 0 as "unset".
     */
    file: string;
    line: number;
    function: string;
    /** SDKError code, when the record describes an error. */
    errorCode: number;
    modelId: string;
    framework: string;
}
export interface LogEntry_MetadataEntry {
    key: string;
    value: string;
}
export declare const LoggingConfiguration: MessageFns<LoggingConfiguration>;
export declare const LogEntry: MessageFns<LogEntry>;
export declare const LogEntry_MetadataEntry: MessageFns<LogEntry_MetadataEntry>;
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
