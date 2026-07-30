import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
/**
 * Mirrors rac_log_level_t exactly so the generated enum round-trips with the
 * platform-adapter log callback without a translation table. 0 is TRACE, not
 * UNSPECIFIED, to keep numeric parity with the C enum.
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
/** Per-environment presets stay in each SDK as factory helpers. */
export interface LoggingConfiguration {
    /** The platform-local sink: os_log, Logcat, or console. */
    enableLocalLogging: boolean;
    /** Records below this level are dropped. */
    minLogLevel: LogLevel;
    includeSourceLocation: boolean;
    /** Device model, OS version, app build. */
    includeDeviceMetadata: boolean;
    enableRemoteLogging: boolean;
}
export interface LogEntry {
    timestampUnixMs: number;
    level: LogLevel;
    /** Subsystem tag, e.g. "STT". */
    category: string;
    message: string;
    metadata: {
        [key: string]: string;
    };
    /**
     * Kotlin carries these as first-class fields; other SDKs leave them empty.
     * 0 means unset for line and error_code.
     */
    file: string;
    line: number;
    function: string;
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
