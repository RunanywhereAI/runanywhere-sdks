"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.streamFactory = streamFactory;
function streamFactory(transport, req) {
    return {
        [Symbol.asyncIterator]() {
            const queue = [];
            let resolve = null;
            let reject = null;
            let error = null;
            let done = false;
            const cancel = transport.subscribe(req, (msg) => {
                if (resolve) {
                    const r = resolve;
                    resolve = null;
                    reject = null;
                    r({ value: msg, done: false });
                }
                else {
                    queue.push(msg);
                }
            }, (err) => {
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
            }, () => {
                done = true;
                if (resolve) {
                    const r = resolve;
                    resolve = null;
                    reject = null;
                    r({ value: undefined, done: true });
                }
            });
            return {
                next() {
                    if (queue.length > 0) {
                        return Promise.resolve({ value: queue.shift(), done: false });
                    }
                    if (error)
                        return Promise.reject(error);
                    if (done)
                        return Promise.resolve({ value: undefined, done: true });
                    return new Promise((res, rej) => {
                        resolve = res;
                        reject = rej;
                    });
                },
                return() {
                    cancel();
                    return Promise.resolve({ value: undefined, done: true });
                },
            };
        },
    };
}
