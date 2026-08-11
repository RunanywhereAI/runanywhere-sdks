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
/** Sink handed to a push-style stream producer. */
export interface StreamSink<T> {
    /** Deliver one value to the consumer. */
    push(value: T): void;
    /** End the stream normally. */
    end(): void;
    /** Throw into the consumer and end the stream. */
    fail(error: unknown): void;
    /** True once the stream has ended or been cancelled. */
    readonly closed: boolean;
}
/** Alias kept for RN call-site familiarity (`StreamController`). */
export type StreamController<T> = StreamSink<T>;
/**
 * Adapt a push-style producer into a lazily consumed AsyncIterableIterator.
 *
 * `producer` starts on the first `next()`. If it returns a Promise, the sink
 * auto-`end()`s when that Promise settles (Electron pattern); a synchronous
 * producer must call `end()` / `fail()` itself (RN pattern). Breaking the
 * consumer loop calls `onCancel` and drains waiters.
 */
export declare function pushStream<T>(producer: (sink: StreamSink<T>) => void | Promise<void>, onCancel?: () => void | Promise<void>): AsyncIterableIterator<T>;
/** Alias matching Electron's historical name. */
export declare const bridgeStream: typeof pushStream;
/**
 * Build an AsyncIterable over a push subscription (EventBus pattern).
 *
 * The subscription is created on the first `next()` and released via
 * `return()`. Multiple concurrent `next()` waiters resolve in FIFO order.
 */
export declare function iterableFromSubscription<T>(subscribe: (listener: (value: T) => void) => () => void): AsyncIterableIterator<T>;
/**
 * Project every value of a stream through `transform`, dropping the ones it
 * maps to `undefined`.
 */
export declare function mapStream<T, U>(source: AsyncIterable<T>, transform: (value: T) => U | undefined): AsyncIterableIterator<U>;
/**
 * Flatten a stream that can only be built after an async preflight into a
 * plain AsyncIterable, so consumers never await before iterating.
 */
export declare function deferStream<T>(factory: () => Promise<AsyncIterable<T>>): AsyncIterableIterator<T>;
/**
 * Drive an AsyncIterable to completion with a manual `next()` loop.
 *
 * Hermes cannot iterate Nitro-backed streams with `for await...of`, so
 * SDK-internal consumers should prefer this helper (or an equivalent loop).
 */
export declare function forEachStream<T>(source: AsyncIterable<T>, handle: (value: T) => void | Promise<void>): Promise<void>;
/** Wrap a ready array as a bridge-safe stream (synthetic events / tests). */
export declare function streamOf<T>(values: readonly T[]): AsyncIterableIterator<T>;
/** Drain a stream, returning every item. Uses {@link forEachStream} (Hermes-safe). */
export declare function collect<T>(source: AsyncIterable<T>): Promise<T[]>;
/**
 * A push queue that is also an AsyncIterable. Unlike {@link pushStream},
 * `push` works before the consumer ever calls `next()` — nothing is lost when
 * a producer starts feeding it before the caller starts reading.
 */
export declare class AsyncQueue<T> implements AsyncIterable<T> {
    private readonly buffer;
    private wake;
    private ended;
    private failure;
    /**
     * Own property (not a prototype method) so a queue handed to
     * `contextBridge` keeps its iterability.
     */
    readonly [Symbol.asyncIterator]: () => AsyncIterableIterator<T>;
    /** Enqueue one item. A no-op once the queue has ended. */
    push(value: T): void;
    /** End the queue with a terminal error; the next `next()` throws it. */
    fail(error: unknown): void;
    /** End the queue normally once every buffered item has been read. */
    complete(): void;
    private signal;
    /** Bridge-safe view that drains this queue's buffer. */
    stream(): AsyncIterableIterator<T>;
}
