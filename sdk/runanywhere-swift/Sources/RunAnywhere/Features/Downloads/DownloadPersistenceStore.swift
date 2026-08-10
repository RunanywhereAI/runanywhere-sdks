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
//    <digest>.plan         the commons download plan plus the model id it
//                          belongs to, so a restored transfer knows its file
//                          list and destinations without replanning
//    <digest>.resume       CFNetwork's opaque resume blob for one file
//    <digest>.resumebytes  how far that file had got (see `ResumeCheckpoint`)
//
//  ## Why the names are digests
//
//  They used to be the key percent-encoded, which is lossless and let a model
//  id be read straight back out of a filename. It was also silently broken for
//  every real download. The resume artifacts are keyed per *file*, so the key
//  is "<model id>|<absolute destination path>"; percent-encoding every
//  non-alphanumeric byte of that tripled the length of an already ~270-byte
//  path and produced a ~400-byte filename. `NAME_MAX` is 255, so every write
//  failed with ENAMETOOLONG behind a `try?`, `loadResumeData` always returned
//  nil, and a cancelled multi-gigabyte download always restarted from zero
//  while its partial bytes stayed stranded in CFNetwork's temp directory.
//
//  A SHA-256 digest is a fixed 64 characters no matter how long the key or how
//  deep the container path, which is the only property that actually matters
//  here. It is not reversible, so the model id a `.plan` belongs to is stored
//  *inside* the plan record rather than recovered from its filename.
//

import CryptoKit
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

/// A persisted plan and the model it belongs to.
///
/// The model id rides inside the record because the filename is a digest: it
/// is what `interruptedModelIDs` reads, and carrying it here means a model id
/// of any length or character set is storable, which a filename-derived scheme
/// could never promise.
private struct PersistedPlan: Codable {
    let modelID: String
    let planBytes: Data
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

    /// A fixed-length, filesystem-safe name for an arbitrary key. See the file
    /// header for why length — not reversibility — is the property that matters.
    private func storageKey(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func url(modelID: String, artifact: Artifact) -> URL? {
        directory()?.appendingPathComponent("\(storageKey(modelID)).\(artifact.rawValue)")
    }

    /// Resume artifacts are keyed per *file*, not per model: a multi-file model can
    /// be interrupted with some files finished and one mid-flight.
    private func url(modelID: String, destinationPath: String, artifact: Artifact) -> URL? {
        directory()?.appendingPathComponent(
            "\(storageKey("\(modelID)|\(destinationPath)")).\(artifact.rawValue)"
        )
    }

    // MARK: - Plan

    func persistPlan(_ plan: RADownloadPlanResult, modelID: String) {
        guard let url = url(modelID: modelID, artifact: .plan),
              let planBytes = try? plan.serializedData(),
              let data = try? JSONEncoder().encode(
                  PersistedPlan(modelID: modelID, planBytes: planBytes)
              ) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func loadPlan(modelID: String) -> RADownloadPlanResult? {
        guard let url = url(modelID: modelID, artifact: .plan) else { return nil }
        return decodePlan(at: url)?.plan
    }

    func clearPlan(modelID: String) {
        guard let url = url(modelID: modelID, artifact: .plan) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Every model with a plan still on disk — that is, every download that was
    /// started and never reached a terminal state. A plan is written when a
    /// transfer begins and removed when it completes or fails unrecoverably, so
    /// its presence *is* the record of an interrupted download.
    ///
    /// A record that no longer decodes is deleted rather than skipped. It cannot
    /// be resumed by anything, and leaving it behind would keep the directory —
    /// and `hasRecoverableState`, which gates the orphan sweep — permanently
    /// pinned by a file nobody can use.
    func interruptedModelIDs() -> [String] {
        contents()
            .filter { $0.pathExtension == Artifact.plan.rawValue }
            .compactMap { url in
                guard let record = decodePlan(at: url) else {
                    try? FileManager.default.removeItem(at: url)
                    return nil
                }
                return record.modelID
            }
    }

    private func decodePlan(at url: URL) -> (modelID: String, plan: RADownloadPlanResult)? {
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(PersistedPlan.self, from: data),
              let plan = try? RADownloadPlanResult(serializedBytes: record.planBytes) else { return nil }
        return (record.modelID, plan)
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
    ///
    /// Returns whether the blob actually landed. The caller reports that, because
    /// a failure here is the difference between a retry costing the remainder and
    /// costing the whole file — exactly the failure that hid behind a `try?` for
    /// as long as the filenames were too long to write.
    @discardableResult
    func storeResumeData(
        _ data: Data, modelID: String, destinationPath: String, bytesOnDisk: Int64
    ) -> Bool {
        guard let blobURL = url(modelID: modelID, destinationPath: destinationPath, artifact: .resume) else {
            return false
        }
        do {
            try data.write(to: blobURL, options: .atomic)
        } catch {
            return false
        }

        guard bytesOnDisk > 0,
              let checkpointURL = url(
                  modelID: modelID, destinationPath: destinationPath, artifact: .resumeBytes
              ),
              let encoded = try? JSONEncoder().encode(ResumeCheckpoint(bytesOnDisk: bytesOnDisk)) else {
            return true
        }
        try? encoded.write(to: checkpointURL, options: .atomic)
        return true
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

    /// Every resume blob a model still holds, so the caller can hand each one
    /// back to CFNetwork before deleting it. Deleting a blob without releasing it
    /// strands the partial file it points at, which is how a discarded 3 GB
    /// download leaks 3 GB of temp storage nothing will ever collect.
    func resumeBlobs(modelID: String, destinationPaths: [String]) -> [Data] {
        destinationPaths.compactMap { loadResumeData(modelID: modelID, destinationPath: $0) }
    }

    /// Drop every resume artifact for a model, used once it is fully downloaded or
    /// has failed for a reason a resume cannot fix.
    func clearResumeData(modelID: String, destinationPaths: [String]) {
        for path in destinationPaths {
            clearResumeData(modelID: modelID, destinationPath: path)
        }
    }

    /// Whether anything here could still continue a download.
    ///
    /// Answers the one question the orphan sweep must be sure of before it
    /// deletes a partial file it cannot attribute: if there is no plan and no
    /// blob, there is no attempt this SDK could resume, so nothing it deletes
    /// can cost a user bytes they would otherwise have kept.
    func hasRecoverableState() -> Bool {
        contents().contains {
            $0.pathExtension == Artifact.plan.rawValue || $0.pathExtension == Artifact.resume.rawValue
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
