//
//  DownloadProgressSample.swift
//  RunAnywhere SDK
//
//  One byte-count observation turned into the `RADownloadProgress` a caller sees.
//
//  Split out from `BackgroundDownloadCoordinator` because it is the one part of
//  the background path with no I/O in it at all: given how many bytes exist, how
//  long they took, and where they sit in the plan, the answer is arithmetic. It
//  is also the part that has to agree with the *other* transfer path — commons
//  emits the same proto from `download_orchestrator.cpp` — so having it in one
//  named place makes "do the two paths report the same thing?" a question that
//  can be answered by reading a single file.
//

import Foundation

/// A measurement of a transfer at one instant, before it becomes a proto.
struct DownloadProgressSample {
    let modelID: String
    /// Bytes on disk across the whole plan, including files that were already
    /// complete before this transfer began.
    let bytesDone: Int64
    /// Bytes the plan expects in total. 0 when unknown.
    let bytesTotal: Int64
    /// 0-based position of the file that produced this sample.
    let fileIndex: Int
    let fileCount: Int
    /// Name of the file this sample is about, so a caller can say which of a
    /// multi-file model is moving instead of only "file 2 of 3".
    let fileName: String
    /// How long this transfer has been running.
    let elapsed: TimeInterval
    /// Bytes *this* transfer actually moved — total on disk minus what was already
    /// complete when it started, minus what a resumed task inherited from an
    /// earlier attempt. Kept separate from `bytesDone` because it is the only
    /// figure a throughput average may be computed from: a download resumed at
    /// 1.4 GB would otherwise report several gigabytes per second for one sample.
    let bytesMoved: Int64
    /// Which phase produced this sample.
    ///
    /// Carried rather than assumed `.downloading` because the bytes landing is
    /// not the end of the work: this path still has to checksum a file that can
    /// be several gigabytes, and a UI told only "100%" for the length of that
    /// hash reads as a freeze. Commons reports the same phase through the same
    /// field on its own transfer path, so both paths stay legible to one switch.
    var state: RADownloadState = .downloading

    /// Fraction complete, 0...1.
    var fraction: Double {
        guard bytesTotal > 0 else { return 0 }
        return Double(bytesDone) / Double(bytesTotal)
    }

    /// Render as the wire type both transfer paths report.
    ///
    /// Throughput is a whole-transfer average rather than a windowed rate, which
    /// is the same choice commons makes: on a multi-gigabyte download a windowed
    /// rate reads as jitter rather than as information. Speed and ETA are left
    /// unset until there is something real to divide, so a caller can distinguish
    /// "not measured yet" from a genuine zero and show nothing instead of "0 B/s"
    /// while the connection is still opening.
    func asProto() -> RADownloadProgress {
        var progress = RADownloadProgress()
        progress.modelID = modelID
        // RADownloadStage was folded into RADownloadState
        // (idl/download_service.proto); `.state` alone now carries what
        // `.stage` used to.
        progress.state = state
        progress.bytesDownloaded = bytesDone
        progress.totalBytes = bytesTotal
        progress.totalFiles = Int32(fileCount)
        progress.currentFileIndex = Int32(fileIndex)
        progress.currentFileName = fileName
        progress.overallProgress = Float(fraction)

        // A rate and a finish time describe bytes in flight. Once the transfer
        // has moved to verification nothing is moving, so reporting the last
        // measured speed would claim the connection is still working and the
        // ETA would count down to a moment that has already passed.
        guard state == .downloading, elapsed > 0, bytesMoved > 0 else { return progress }
        let speed = Double(bytesMoved) / elapsed
        progress.bytesPerSecond = Float(speed)
        if bytesTotal > bytesDone {
            progress.etaSeconds = Int64(Double(bytesTotal - bytesDone) / speed)
        }
        return progress
    }
}
