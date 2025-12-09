/**
 * DownloadProgress.ts
 *
 * Download progress information
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Models/Downloading/DownloadProgress.swift
 */

import { DownloadState } from './DownloadState';

/**
 * Download progress information
 */
export interface DownloadProgress {
  readonly bytesDownloaded: number; // Int64
  readonly totalBytes: number; // Int64
  readonly state: DownloadState;
  readonly speed: number | null; // bytes per second
  readonly estimatedTimeRemaining: number | null; // seconds
}

