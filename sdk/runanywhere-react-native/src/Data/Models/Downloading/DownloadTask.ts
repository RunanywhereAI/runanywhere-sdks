/**
 * DownloadTask.ts
 *
 * Download task information
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Models/Downloading/DownloadTask.swift
 */

import type { DownloadProgress } from './DownloadProgress';

/**
 * Download task information
 */
export interface DownloadTask {
  readonly id: string;
  readonly modelId: string;
  readonly progress: AsyncGenerator<DownloadProgress, void, unknown>;
  readonly result: Promise<string>; // URL as string
}

