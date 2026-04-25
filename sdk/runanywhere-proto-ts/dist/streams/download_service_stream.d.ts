import type { DownloadSubscribeRequest } from "../download_service";
import type { DownloadProgress } from "../download_service";
export interface DownloadStreamTransport {
    subscribe(req: DownloadSubscribeRequest, onMessage: (msg: DownloadProgress) => void, onError: (err: Error) => void, onDone: () => void): () => void;
}
/**
 * Wrap the platform `transport.subscribe` callback into an
 * `AsyncIterable<DownloadProgress>`. Cancellation is propagated by
 * `break`-ing out of `for await` (the iterator's `return()` calls the
 * transport's cancel function).
 */
export declare function subscribeDownload(transport: DownloadStreamTransport, req: DownloadSubscribeRequest): AsyncIterable<DownloadProgress>;
//# sourceMappingURL=download_service_stream.d.ts.map