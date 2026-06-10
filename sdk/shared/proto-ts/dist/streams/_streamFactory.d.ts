export interface StreamTransport<TReq, TRsp> {
    subscribe(req: TReq, onMessage: (msg: TRsp) => void, onError: (err: Error) => void, onDone: () => void): () => void;
}
export declare function streamFactory<TReq, TRsp>(transport: StreamTransport<TReq, TRsp>, req: TReq): AsyncIterable<TRsp>;
