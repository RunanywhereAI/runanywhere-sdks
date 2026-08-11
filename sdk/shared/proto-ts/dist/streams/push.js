"use strict";
/**
 * Hand-authored push → AsyncIterable helpers for Web / React Native / Electron.
 *
 * Kept in a file that `idl/codegen/generate_streams.sh` does NOT touch (that
 * script only writes `*_service_stream.ts`). Generated wrappers live beside
 * this file and import `_streamFactory.ts`.
 *
 * Constraints preserved across all three SDKs:
 *   - Lazy start: the producer runs on the first `next()`, not on construction.
 *   - Cancel/cleanup on iterator `return()`.
 *   - Hermes-safe: consumers may drive via manual `iterator.next()` loops;
 *     nothing here requires `for await...of` over a Nitro iterable.
 *   - Electron `contextBridge`-safe: iterators are plain object literals with
 *     `next` / `return` / `throw` / `Symbol.asyncIterator` as OWN properties
 *     (prototype methods are stripped by contextBridge).
 *   - No platform APIs (no Worker, JSI, Node built-ins).
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.AsyncQueue = exports.bridgeStream = void 0;
exports.pushStream = pushStream;
exports.iterableFromSubscription = iterableFromSubscription;
exports.mapStream = mapStream;
exports.deferStream = deferStream;
exports.forEachStream = forEachStream;
exports.streamOf = streamOf;
exports.collect = collect;
/**
 * Own-property AsyncIterableIterator that survives Electron `contextBridge`.
 *
 * `Symbol.asyncIterator` closes over `iterator` rather than returning `this`,
 * because a bridged copy is a different object.
 */
function bridgeIterator(next, finish) {
    const iterator = {
        [Symbol.asyncIterator]: () => iterator,
        next,
        return: finish,
        async throw(error) {
            await finish();
            throw error;
        },
    };
    return iterator;
}
const doneResult = () => ({
    value: undefined,
    done: true,
});
/**
 * Adapt a push-style producer into a lazily consumed AsyncIterableIterator.
 *
 * `producer` starts on the first `next()`. If it returns a Promise, the sink
 * auto-`end()`s when that Promise settles (Electron pattern); a synchronous
 * producer must call `end()` / `fail()` itself (RN pattern). Breaking the
 * consumer loop calls `onCancel` and drains waiters.
 */
function pushStream(producer, onCancel) {
    const queue = [];
    let done = false;
    let failure = null;
    let started = false;
    let cancelled = false;
    let wake = null;
    const signal = () => {
        const w = wake;
        wake = null;
        if (w)
            w();
    };
    const sink = {
        get closed() {
            return done || cancelled;
        },
        push(value) {
            if (cancelled || done)
                return;
            queue.push(value);
            signal();
        },
        end() {
            if (done)
                return;
            done = true;
            signal();
        },
        fail(error) {
            if (done)
                return;
            failure = error;
            done = true;
            signal();
        },
    };
    const start = () => {
        if (started)
            return;
        started = true;
        try {
            const maybe = producer(sink);
            if (maybe != null && typeof maybe.then === 'function') {
                maybe.then(() => sink.end(), (e) => sink.fail(e));
            }
        }
        catch (e) {
            sink.fail(e);
        }
    };
    const finish = async () => {
        if (!cancelled) {
            cancelled = true;
            queue.length = 0;
            // Wake a parked `next()` so cancel from outside the consumer loop
            // (Stop button / unmount) does not hang forever.
            signal();
            if (started && onCancel) {
                try {
                    await onCancel();
                }
                catch {
                    // Cancel is best-effort; the consumer already stopped listening.
                }
            }
        }
        return doneResult();
    };
    return bridgeIterator(async () => {
        start();
        for (;;) {
            if (queue.length > 0)
                return { value: queue.shift(), done: false };
            if (failure !== null) {
                const error = failure;
                failure = null;
                throw error;
            }
            if (done || cancelled)
                return doneResult();
            await new Promise((resolve) => {
                wake = resolve;
            });
        }
    }, finish);
}
/** Alias matching Electron's historical name. */
exports.bridgeStream = pushStream;
/**
 * Build an AsyncIterable over a push subscription (EventBus pattern).
 *
 * The subscription is created on the first `next()` and released via
 * `return()`. Multiple concurrent `next()` waiters resolve in FIFO order.
 */
function iterableFromSubscription(subscribe) {
    const queue = [];
    const waiters = [];
    let closed = false;
    let unsubscribe = null;
    const ensureSubscribed = () => {
        if (unsubscribe !== null || closed)
            return;
        unsubscribe = subscribe((value) => {
            if (waiters.length > 0) {
                waiters.shift()({ value, done: false });
            }
            else {
                queue.push(value);
            }
        });
    };
    return bridgeIterator(() => {
        ensureSubscribed();
        if (queue.length > 0) {
            return Promise.resolve({ value: queue.shift(), done: false });
        }
        if (closed)
            return Promise.resolve(doneResult());
        return new Promise((resolve) => {
            waiters.push(resolve);
        });
    }, () => {
        closed = true;
        if (unsubscribe !== null) {
            unsubscribe();
            unsubscribe = null;
        }
        const result = doneResult();
        for (const waiter of waiters.splice(0)) {
            waiter(result);
        }
        return Promise.resolve(result);
    });
}
/**
 * Project every value of a stream through `transform`, dropping the ones it
 * maps to `undefined`.
 */
function mapStream(source, transform) {
    const iterator = source[Symbol.asyncIterator]();
    return bridgeIterator(async () => {
        for (;;) {
            const step = await iterator.next();
            if (step.done)
                return doneResult();
            const mapped = transform(step.value);
            if (mapped !== undefined)
                return { value: mapped, done: false };
        }
    }, async () => {
        await iterator.return?.();
        return doneResult();
    });
}
/**
 * Flatten a stream that can only be built after an async preflight into a
 * plain AsyncIterable, so consumers never await before iterating.
 */
function deferStream(factory) {
    let inner = null;
    const ensureInner = async () => {
        if (!inner) {
            inner = (await factory())[Symbol.asyncIterator]();
        }
        return inner;
    };
    return bridgeIterator(async () => (await ensureInner()).next(), async () => {
        if (inner)
            await inner.return?.();
        return doneResult();
    });
}
/**
 * Drive an AsyncIterable to completion with a manual `next()` loop.
 *
 * Hermes cannot iterate Nitro-backed streams with `for await...of`, so
 * SDK-internal consumers should prefer this helper (or an equivalent loop).
 */
async function forEachStream(source, handle) {
    const iterator = source[Symbol.asyncIterator]();
    try {
        for (;;) {
            const step = await iterator.next();
            if (step.done)
                return;
            await handle(step.value);
        }
    }
    finally {
        await iterator.return?.();
    }
}
/** Wrap a ready array as a bridge-safe stream (synthetic events / tests). */
function streamOf(values) {
    return pushStream((sink) => {
        for (const v of values)
            sink.push(v);
        sink.end();
    });
}
/** Drain a stream, returning every item. Uses {@link forEachStream} (Hermes-safe). */
async function collect(source) {
    const out = [];
    await forEachStream(source, (item) => {
        out.push(item);
    });
    return out;
}
/**
 * A push queue that is also an AsyncIterable. Unlike {@link pushStream},
 * `push` works before the consumer ever calls `next()` — nothing is lost when
 * a producer starts feeding it before the caller starts reading.
 */
class AsyncQueue {
    buffer = [];
    wake = null;
    ended = false;
    failure = null;
    /**
     * Own property (not a prototype method) so a queue handed to
     * `contextBridge` keeps its iterability.
     */
    [Symbol.asyncIterator] = () => this.stream();
    /** Enqueue one item. A no-op once the queue has ended. */
    push(value) {
        if (this.ended)
            return;
        this.buffer.push(value);
        this.signal();
    }
    /** End the queue with a terminal error; the next `next()` throws it. */
    fail(error) {
        if (this.ended)
            return;
        this.failure = error;
        this.ended = true;
        this.signal();
    }
    /** End the queue normally once every buffered item has been read. */
    complete() {
        if (this.ended)
            return;
        this.ended = true;
        this.signal();
    }
    signal() {
        const wake = this.wake;
        this.wake = null;
        if (wake)
            wake();
    }
    /** Bridge-safe view that drains this queue's buffer. */
    stream() {
        return bridgeIterator(async () => {
            for (;;) {
                if (this.buffer.length > 0) {
                    return { value: this.buffer.shift(), done: false };
                }
                if (this.failure !== null) {
                    const error = this.failure;
                    this.failure = null;
                    throw error;
                }
                if (this.ended)
                    return doneResult();
                await new Promise((resolve) => {
                    this.wake = resolve;
                });
            }
        },
        // Walking away stops delivery but does not end the queue: the producer
        // is outside it and may still be pushing.
        async () => doneResult());
    }
}
exports.AsyncQueue = AsyncQueue;
