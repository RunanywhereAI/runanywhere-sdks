import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { ModelFileDescriptor, ModelInfo } from "./model_types";
export declare const protobufPackage = "runanywhere.v1";
export declare enum DownloadStage {
    DOWNLOAD_STAGE_UNSPECIFIED = 0,
    DOWNLOAD_STAGE_DOWNLOADING = 1,
    DOWNLOAD_STAGE_EXTRACTING = 2,
    DOWNLOAD_STAGE_VALIDATING = 3,
    DOWNLOAD_STAGE_COMPLETED = 4,
    UNRECOGNIZED = -1
}
export declare function downloadStageFromJSON(object: any): DownloadStage;
export declare function downloadStageToJSON(object: DownloadStage): string;
export declare enum DownloadState {
    DOWNLOAD_STATE_UNSPECIFIED = 0,
    DOWNLOAD_STATE_PENDING = 1,
    DOWNLOAD_STATE_DOWNLOADING = 2,
    DOWNLOAD_STATE_EXTRACTING = 3,
    DOWNLOAD_STATE_RETRYING = 4,
    DOWNLOAD_STATE_COMPLETED = 5,
    DOWNLOAD_STATE_FAILED = 6,
    DOWNLOAD_STATE_CANCELLED = 7,
    DOWNLOAD_STATE_PAUSED = 8,
    DOWNLOAD_STATE_RESUMING = 9,
    UNRECOGNIZED = -1
}
export declare function downloadStateFromJSON(object: any): DownloadState;
export declare function downloadStateToJSON(object: DownloadState): string;
/**
 * HTTP transport download status — numeric values MUST match
 * rac_http_download_status_t (RAC_HTTP_DL_*) in
 * sdk/runanywhere-commons/include/rac/infrastructure/http/rac_http_download.h.
 * rac_http_download_execute returns this int directly through the C ABI;
 * every SDK consumes the proto-generated enum so a new RAC_HTTP_DL_* value
 * added in commons fails compilation across all bindings until the enum is
 * extended here. OK = 0 mirrors the C ABI's success sentinel (no separate
 * UNSPECIFIED needed — success is the proto3 zero default).
 */
export declare enum HttpDownloadStatus {
    HTTP_DOWNLOAD_STATUS_OK = 0,
    HTTP_DOWNLOAD_STATUS_NETWORK_ERROR = 1,
    HTTP_DOWNLOAD_STATUS_FILE_ERROR = 2,
    HTTP_DOWNLOAD_STATUS_INSUFFICIENT_STORAGE = 3,
    HTTP_DOWNLOAD_STATUS_INVALID_URL = 4,
    HTTP_DOWNLOAD_STATUS_CHECKSUM_FAILED = 5,
    HTTP_DOWNLOAD_STATUS_CANCELLED = 6,
    HTTP_DOWNLOAD_STATUS_SERVER_ERROR = 7,
    HTTP_DOWNLOAD_STATUS_TIMEOUT = 8,
    HTTP_DOWNLOAD_STATUS_NETWORK_UNAVAILABLE = 9,
    HTTP_DOWNLOAD_STATUS_DNS_ERROR = 10,
    HTTP_DOWNLOAD_STATUS_SSL_ERROR = 11,
    HTTP_DOWNLOAD_STATUS_UNKNOWN = 99,
    UNRECOGNIZED = -1
}
export declare function httpDownloadStatusFromJSON(object: any): HttpDownloadStatus;
export declare function httpDownloadStatusToJSON(object: HttpDownloadStatus): string;
export interface DownloadSubscribeRequest {
    modelId: string;
    taskId: string;
}
export interface DownloadProgress {
    modelId: string;
    stage: DownloadStage;
    bytesDownloaded: number;
    /** 0 if unknown */
    totalBytes: number;
    /** 0.0..1.0 within current stage */
    stageProgress: number;
    overallSpeedBps: number;
    /** -1 if unknown */
    etaSeconds: number;
    state: DownloadState;
    /** 0 on first try */
    retryAttempt: number;
    /** populated when state == FAILED */
    errorMessage: string;
    taskId: string;
    /** 0-based within the planned file list */
    currentFileIndex: number;
    totalFiles: number;
    /** C++ storage identifier, not a platform file handle */
    storageKey: string;
    /** final path once known */
    localPath: string;
    /** 0.0..1.0 across all planned files/stages */
    overallProgress: number;
    startedAtUnixMs: number;
    updatedAtUnixMs: number;
    currentFileName: string;
    /** logical resume marker, not a native handle */
    resumeToken: string;
}
export interface DownloadPlanRequest {
    modelId: string;
    model?: ModelInfo | undefined;
    resumeExisting: boolean;
    availableStorageBytes: number;
    allowMeteredNetwork: boolean;
    storageNamespace: string;
    validateExistingBytes: boolean;
    verifyChecksums: boolean;
    requiredFreeBytesAfterDownload: number;
}
export interface DownloadFilePlan {
    file?: ModelFileDescriptor | undefined;
    storageKey: string;
    destinationPath: string;
    expectedBytes: number;
    requiresExtraction: boolean;
    checksumSha256: string;
    isResumeCandidate: boolean;
}
export interface DownloadPlanResult {
    canStart: boolean;
    modelId: string;
    files: DownloadFilePlan[];
    totalBytes: number;
    requiresExtraction: boolean;
    canResume: boolean;
    resumeFromBytes: number;
    warnings: string[];
    errorMessage: string;
    storageNamespace: string;
    resumeToken: string;
    requiredFreeBytesAfterDownload: number;
}
export interface DownloadStartRequest {
    modelId: string;
    plan?: DownloadPlanResult | undefined;
    resume: boolean;
    resumeToken: string;
    updateRegistryOnCompletion: boolean;
}
export interface DownloadStartResult {
    accepted: boolean;
    taskId: string;
    modelId: string;
    initialProgress?: DownloadProgress | undefined;
    errorMessage: string;
    resumeToken: string;
}
export interface DownloadCancelRequest {
    taskId: string;
    modelId: string;
    deletePartialBytes: boolean;
}
export interface DownloadCancelResult {
    success: boolean;
    taskId: string;
    modelId: string;
    partialBytesDeleted: number;
    errorMessage: string;
    wasRunning: boolean;
    partialBytesPreserved: boolean;
    resumeToken: string;
}
export interface DownloadResumeRequest {
    taskId: string;
    modelId: string;
    resumeFromBytes: number;
    resumeToken: string;
    validatePartialBytes: boolean;
}
export interface DownloadResumeResult {
    accepted: boolean;
    taskId: string;
    modelId: string;
    initialProgress?: DownloadProgress | undefined;
    errorMessage: string;
    resumeToken: string;
}
export declare const DownloadSubscribeRequest: MessageFns<DownloadSubscribeRequest>;
export declare const DownloadProgress: MessageFns<DownloadProgress>;
export declare const DownloadPlanRequest: MessageFns<DownloadPlanRequest>;
export declare const DownloadFilePlan: MessageFns<DownloadFilePlan>;
export declare const DownloadPlanResult: MessageFns<DownloadPlanResult>;
export declare const DownloadStartRequest: MessageFns<DownloadStartRequest>;
export declare const DownloadStartResult: MessageFns<DownloadStartResult>;
export declare const DownloadCancelRequest: MessageFns<DownloadCancelRequest>;
export declare const DownloadCancelResult: MessageFns<DownloadCancelResult>;
export declare const DownloadResumeRequest: MessageFns<DownloadResumeRequest>;
export declare const DownloadResumeResult: MessageFns<DownloadResumeResult>;
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
