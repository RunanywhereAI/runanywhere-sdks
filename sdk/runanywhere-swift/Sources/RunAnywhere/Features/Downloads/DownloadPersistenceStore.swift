//
//  DownloadPersistenceStore.swift
//  RunAnywhere SDK
//
//  Everything a background download leaves on disk so it can be picked up by a
//  later attempt — or by a later *process*. Split out from
//  `BackgroundDownloadCoordinator` because the two answer different questions:
//  the coordinator decides when a transfer starts, stops, or is thrown away,
//  and this decides how that decision survives the app being killed. Keeping
//  the filename conventions in one type is also what stops a stale artifact
//  from being missed by one cleanup path and found by another.
//
//  Three artifacts per model, all under Application Support:
//
//    <model>.plan         the commons download plan, so a restored transfer
//                         knows its file list and destinations without replanning
//    <model|file>.resume  CFNetwork's opaque resume blob for one file
//    <model|file>.resumebytes  how far that file had got (see `ResumeCheckpoint`)
//

import Foundation

/// How many bytes an interrupted attempt left recoverable for one file.
///
/// This exists because the resume blob cannot answer the question itself. It
/// used to be a readable property list with an `NSURLSessionResumeBytesReceived`
/// key, but it is now an `NSKeyedArchiver` archive of CFNetwork's private resume
/// state — there is no supported way to read a byte count out of it, and reaching
/// into a private archive Apple is free to re-shape would break on an OS update
/// rather than at compile time. So the coordinator writes down the last byte
/// count it actually observed for that file, next to the blob it belongs to.
private struct ResumeCheckpoint: Codable {
    let bytesOnDisk: Int64
}

/// On-disk custody for interrupted background downloads. Stateless: every method
/// is a filesystem operation keyed by model id, so it is safe to call from the
/// URLSession delegate queue and from the cancelling task at the same time.
struct DownloadPersistenceStore: Sendable {

    private enum Artifact: String {
        case plan
        case resume
        /// Deliberately not an extension of `resume`: `clearResumeData` matches on
        /// the extension, and a suffix that merely started with "resume" would
        /// make "did I delete both?" a substring question instead of an equality one.
        case resumeBytes = "resumebytes"
    }

    // MARK: - Locations

    private func directory() -> URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let dir = base.appendingPathComponent("RunAnywhereDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Percent-encoding every non-alphanumeric byte makes the transform lossless,
    /// so `interruptedModelIDs` can read the model id straight back out of a
    /// filename instead of needing a second index file to map them.
    private func storageKey(_ value: String) -> String? {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
    }

    private func url(modelID: String, artifact: Artifact) -> URL? {
        guard let name = storageKey(modelID) else { return nil }
        return directory()?.appendingPathComponent("\(name).\(artifact.rawValue)")
    }

    /// Resume artifacts are keyed per *file*, not per model: a multi-file model can
    /// be interrupted with some files finished and one mid-flight.
    private func url(modelID: String, destinationPath: String, artifact: Artifact) -> URL? {
        guard let name = storageKey("\(modelID)|\(destinationPath)") else { return nil }
        return directory()?.appendingPathComponent("\(name).\(artifact.rawValue)")
    }

    // MARK: - Plan

    func persistPlan(_ plan: RADownloadPlanResult, modelID: String) {
        guard let url = url(modelID: modelID, artifact: .plan),
              let data = try? plan.serializedData() else { return }
        try? data.write(to: url, options: .atomic)
    }

    func loadPlan(modelID: String) -> RADownloadPlanResult? {
        guard let url = url(modelID: modelID, artifact: .plan),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? RADownloadPlanResult(serializedBytes: data)
    }

    func clearPlan(modelID: String) {
        guard let url = url(modelID: modelID, artifact: .plan) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Every model with a plan still on disk — that is, every download that was
    /// started and never reached a terminal state. A plan is written when a
    /// transfer begins and removed when it completes or fails unrecoverably, so
    /// its presence *is* the record of an interrupted download.
    func interruptedModelIDs() -> [String] {
        contents()
            .filter { $0.pathExtension == Artifact.plan.rawValue }
            .compactMap { $0.deletingPathExtension().lastPathComponent.removingPercentEncoding }
    }

    // MARK: - Resume data

    /// `URLSessionDownloadTask` keeps its partial bytes in a private temp file and
    /// deletes them on a plain `cancel()`. `cancel(byProducingResumeData:)` instead
    /// hands back an opaque blob that a later `downloadTask(withResumeData:)`
    /// continues from, and that blob is what has to be kept.
    ///
    /// It is written to disk rather than held in memory because the case that
    /// matters most is the app being killed: a 3 GB model interrupted at 90% must
    /// cost the remaining 10% on next launch, not the whole file again.
    ///
    /// `bytesOnDisk` is the caller's last observed byte count for the file, or 0
    /// when it never saw one; the checkpoint is skipped in that case rather than
    /// recording a zero that would later read as "nothing recoverable".
    func storeResumeData(_ data: Data, modelID: String, destinationPath: String, bytesOnDisk: Int64) {
        guard let blobURL = url(modelID: modelID, destinationPath: destinationPath, artifact: .resume) else {
            return
        }
        try? data.write(to: blobURL, options: .atomic)

        guard bytesOnDisk > 0,
              let checkpointURL = url(
                  modelID: modelID, destinationPath: destinationPath, artifact: .resumeBytes
              ),
              let encoded = try? JSONEncoder().encode(ResumeCheckpoint(bytesOnDisk: bytesOnDisk)) else {
            return
        }
        try? encoded.write(to: checkpointURL, options: .atomic)
    }

    func loadResumeData(modelID: String, destinationPath: String) -> Data? {
        guard let url = url(modelID: modelID, destinationPath: destinationPath, artifact: .resume) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    func resumeCheckpoint(modelID: String, destinationPath: String) -> Int64? {
        guard let url = url(modelID: modelID, destinationPath: destinationPath, artifact: .resumeBytes),
              let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode(ResumeCheckpoint.self, from: data))?.bytesOnDisk
    }

    /// Drop one file's resume artifacts, used once that file has landed intact.
    func clearResumeData(modelID: String, destinationPath: String) {
        for artifact in [Artifact.resume, .resumeBytes] {
            guard let url = url(
                modelID: modelID, destinationPath: destinationPath, artifact: artifact
            ) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Drop every resume artifact for a model, used once it is fully downloaded or
    /// has failed for a reason a resume cannot fix.
    func clearResumeData(modelID: String) {
        guard let prefix = storageKey("\(modelID)|") else { return }
        let resumeExtensions = [Artifact.resume.rawValue, Artifact.resumeBytes.rawValue]
        for entry in contents()
        where resumeExtensions.contains(entry.pathExtension)
            && entry.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private func contents() -> [URL] {
        guard let dir = directory(),
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: nil
              ) else { return [] }
        return entries
    }
}
