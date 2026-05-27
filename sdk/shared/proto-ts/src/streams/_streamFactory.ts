export interface StreamTransport<TReq, TRsp> {
    subscribe(
        req: TReq,
        onMessage: (msg: TRsp) => void,
        onError: (err: Error) => void,
        onDone: () => void,
    ): () => void;
}

export function streamFactory<TReq, TRsp>(
    transport: StreamTransport<TReq, TRsp>,
    req: TReq,
): AsyncIterable<TRsp> {
    return {
        [Symbol.asyncIterator](): AsyncIterator<TRsp> {
            const queue: TRsp[] = [];
            let resolve: ((v: IteratorResult<TRsp>) => void) | null = null;
            let reject: ((reason: Error) => void) | null = null;
            let error: Error | null = null;
            let done = false;

            const cancel = transport.subscribe(
                req,
                (msg) => {
                    if (resolve) {
                        const r = resolve;
                        resolve = null;
                        reject = null;
                        r({ value: msg, done: false });
                    } else {
                        queue.push(msg);
                    }
                },
                (err) => {
                    // idl-007: surface the error to the current and any subsequent
                    // `next()` waiters by rejecting the pending promise (not resolving
                    // with done:true, which silently ends the iteration before the
                    // consumer ever sees the failure). `error` is sticky and the
                    // `next()` body re-checks it on every subsequent call.
                    error = err;
                    if (reject) {
                        const rej = reject;
                        resolve = null;
                        reject = null;
                        rej(err);
                    }
                },
                () => {
                    done = true;
                    if (resolve) {
                        const r = resolve;
                        resolve = null;
                        reject = null;
                        r({ value: undefined as any, done: true });
                    }
                },
            );

            return {
                next(): Promise<IteratorResult<TRsp>> {
                    if (queue.length > 0) {
                        return Promise.resolve({ value: queue.shift()!, done: false });
                    }
                    if (error) return Promise.reject(error);
                    if (done) return Promise.resolve({ value: undefined as any, done: true });
                    return new Promise((res, rej) => {
                        resolve = res;
                        reject = rej;
                    });
                },
                return(): Promise<IteratorResult<TRsp>> {
                    cancel();
                    return Promise.resolve({ value: undefined as any, done: true });
                },
            };
        },
    };
}
