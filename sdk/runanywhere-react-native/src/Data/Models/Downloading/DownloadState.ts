/**
 * DownloadState.ts
 *
 * Download state enumeration
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Models/Downloading/DownloadState.swift
 */

/**
 * Download state enumeration
 */
export enum DownloadState {
  Pending = 'pending',
  Downloading = 'downloading',
  Paused = 'paused',
  Completed = 'completed',
  Failed = 'failed',
  Cancelled = 'cancelled',
}

