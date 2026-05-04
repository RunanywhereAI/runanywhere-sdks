import _m0 from "protobufjs/minimal";
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
}
export interface DownloadPlanRequest {
    modelId: string;
    model?: ModelInfo | undefined;
    resumeExisting: boolean;
    availableStorageBytes: number;
    allowMeteredNetwork: boolean;
}
export interface DownloadFilePlan {
    file?: ModelFileDescriptor | undefined;
    storageKey: string;
    destinationPath: string;
    expectedBytes: number;
    requiresExtraction: boolean;
    checksumSha256: string;
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
}
export interface DownloadStartRequest {
    modelId: string;
    plan?: DownloadPlanResult | undefined;
    resume: boolean;
}
export interface DownloadStartResult {
    accepted: boolean;
    taskId: string;
    modelId: string;
    initialProgress?: DownloadProgress | undefined;
    errorMessage: string;
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
}
export interface DownloadResumeRequest {
    taskId: string;
    modelId: string;
    resumeFromBytes: number;
}
export interface DownloadResumeResult {
    accepted: boolean;
    taskId: string;
    modelId: string;
    initialProgress?: DownloadProgress | undefined;
    errorMessage: string;
}
export declare const DownloadSubscribeRequest: {
    encode(message: DownloadSubscribeRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DownloadSubscribeRequest;
    fromJSON(object: any): DownloadSubscribeRequest;
    toJSON(message: DownloadSubscribeRequest): unknown;
    create<I extends Exact<DeepPartial<DownloadSubscribeRequest>, I>>(base?: I): DownloadSubscribeRequest;
    fromPartial<I extends Exact<DeepPartial<DownloadSubscribeRequest>, I>>(object: I): DownloadSubscribeRequest;
};
export declare const DownloadProgress: {
    encode(message: DownloadProgress, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DownloadProgress;
    fromJSON(object: any): DownloadProgress;
    toJSON(message: DownloadProgress): unknown;
    create<I extends Exact<DeepPartial<DownloadProgress>, I>>(base?: I): DownloadProgress;
    fromPartial<I extends Exact<DeepPartial<DownloadProgress>, I>>(object: I): DownloadProgress;
};
export declare const DownloadPlanRequest: {
    encode(message: DownloadPlanRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DownloadPlanRequest;
    fromJSON(object: any): DownloadPlanRequest;
    toJSON(message: DownloadPlanRequest): unknown;
    create<I extends Exact<DeepPartial<DownloadPlanRequest>, I>>(base?: I): DownloadPlanRequest;
    fromPartial<I extends Exact<DeepPartial<DownloadPlanRequest>, I>>(object: I): DownloadPlanRequest;
};
export declare const DownloadFilePlan: {
    encode(message: DownloadFilePlan, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DownloadFilePlan;
    fromJSON(object: any): DownloadFilePlan;
    toJSON(message: DownloadFilePlan): unknown;
    create<I extends Exact<DeepPartial<DownloadFilePlan>, I>>(base?: I): DownloadFilePlan;
    fromPartial<I extends Exact<DeepPartial<DownloadFilePlan>, I>>(object: I): DownloadFilePlan;
};
export declare const DownloadPlanResult: {
    encode(message: DownloadPlanResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DownloadPlanResult;
    fromJSON(object: any): DownloadPlanResult;
    toJSON(message: DownloadPlanResult): unknown;
    create<I extends Exact<DeepPartial<DownloadPlanResult>, I>>(base?: I): DownloadPlanResult;
    fromPartial<I extends Exact<DeepPartial<DownloadPlanResult>, I>>(object: I): DownloadPlanResult;
};
export declare const DownloadStartRequest: {
    encode(message: DownloadStartRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DownloadStartRequest;
    fromJSON(object: any): DownloadStartRequest;
    toJSON(message: DownloadStartRequest): unknown;
    create<I extends Exact<DeepPartial<DownloadStartRequest>, I>>(base?: I): DownloadStartRequest;
    fromPartial<I extends Exact<DeepPartial<DownloadStartRequest>, I>>(object: I): DownloadStartRequest;
};
export declare const DownloadStartResult: {
    encode(message: DownloadStartResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DownloadStartResult;
    fromJSON(object: any): DownloadStartResult;
    toJSON(message: DownloadStartResult): unknown;
    create<I extends Exact<DeepPartial<DownloadStartResult>, I>>(base?: I): DownloadStartResult;
    fromPartial<I extends Exact<DeepPartial<DownloadStartResult>, I>>(object: I): DownloadStartResult;
};
export declare const DownloadCancelRequest: {
    encode(message: DownloadCancelRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DownloadCancelRequest;
    fromJSON(object: any): DownloadCancelRequest;
    toJSON(message: DownloadCancelRequest): unknown;
    create<I extends Exact<DeepPartial<DownloadCancelRequest>, I>>(base?: I): DownloadCancelRequest;
    fromPartial<I extends Exact<DeepPartial<DownloadCancelRequest>, I>>(object: I): DownloadCancelRequest;
};
export declare const DownloadCancelResult: {
    encode(message: DownloadCancelResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DownloadCancelResult;
    fromJSON(object: any): DownloadCancelResult;
    toJSON(message: DownloadCancelResult): unknown;
    create<I extends Exact<DeepPartial<DownloadCancelResult>, I>>(base?: I): DownloadCancelResult;
    fromPartial<I extends Exact<DeepPartial<DownloadCancelResult>, I>>(object: I): DownloadCancelResult;
};
export declare const DownloadResumeRequest: {
    encode(message: DownloadResumeRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DownloadResumeRequest;
    fromJSON(object: any): DownloadResumeRequest;
    toJSON(message: DownloadResumeRequest): unknown;
    create<I extends Exact<DeepPartial<DownloadResumeRequest>, I>>(base?: I): DownloadResumeRequest;
    fromPartial<I extends Exact<DeepPartial<DownloadResumeRequest>, I>>(object: I): DownloadResumeRequest;
};
export declare const DownloadResumeResult: {
    encode(message: DownloadResumeResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DownloadResumeResult;
    fromJSON(object: any): DownloadResumeResult;
    toJSON(message: DownloadResumeResult): unknown;
    create<I extends Exact<DeepPartial<DownloadResumeResult>, I>>(base?: I): DownloadResumeResult;
    fromPartial<I extends Exact<DeepPartial<DownloadResumeResult>, I>>(object: I): DownloadResumeResult;
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
//# sourceMappingURL=download_service.d.ts.map