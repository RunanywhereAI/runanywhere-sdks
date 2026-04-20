// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Sample-facing download state enumeration + DownloadProgress helper.

import Foundation

/// Coarse-grained download lifecycle stage, as seen by the sample UI
/// progress indicator. Maps one-to-one onto `DownloadProgress.State`.
public enum DownloadStage: String, Sendable, Codable {
    case pending
    case downloading
    case extracting
    case complete
    case failed
    case cancelled

    /// Sample-UI alias used by progress indicators.
    public static var completed: DownloadStage { .complete }

    public var displayName: String {
        switch self {
        case .pending:     return "Pending"
        case .downloading: return "Downloading"
        case .extracting:  return "Extracting"
        case .complete:    return "Complete"
        case .failed:      return "Failed"
        case .cancelled:   return "Cancelled"
        }
    }
}

// DownloadProgress.overallProgress and .stage are defined directly on
// DownloadProgress in ModelCatalog.swift. Here we only expose the String-
// enum `DownloadStage` so sample UIs that compare against `.completed`
// on the promoted value continue to work via `DownloadProgress.Stage`
// (defined next to DownloadProgress).

public extension DownloadProgress.State {
    /// Sample UI spelling — maps to the canonical `.complete(localPath:)`
    /// case with an empty path when only the completion fact is needed.
    static var completed: DownloadProgress.State { .complete(localPath: "") }
}
