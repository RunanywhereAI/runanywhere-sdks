import { type StreamTransport } from "./_streamFactory";
import type { DownloadSubscribeRequest } from "../download_service";
import type { DownloadProgress } from "../download_service";
export interface DownloadStreamTransport extends StreamTransport<DownloadSubscribeRequest, DownloadProgress> {
}
export declare function subscribeDownload(transport: DownloadStreamTransport, req: DownloadSubscribeRequest): AsyncIterable<DownloadProgress>;
