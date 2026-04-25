import _m0 from "protobufjs/minimal";
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
    UNRECOGNIZED = -1
}
export declare function downloadStateFromJSON(object: any): DownloadState;
export declare function downloadStateToJSON(object: DownloadState): string;
export interface DownloadSubscribeRequest {
    modelId: string;
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