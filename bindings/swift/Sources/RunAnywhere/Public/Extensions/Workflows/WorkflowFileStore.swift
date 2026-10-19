//
//  WorkflowFileStore.swift
//  RunAnywhere
//
//  Workflow documents on disk, in the layout commons already wrote.
//

import Foundation

/// Storage for workflow documents.
///
/// Ported from `core/src/agent/workflow_store.cpp` as workflows move out of
/// commons. The layout is deliberately unchanged — `<base>/Workflows/<id>/
/// workflow.json`, holding the document in protobuf's JSON encoding — because
/// anyone who has saved a workflow already has files there, and a migration
/// that quietly loses them is worse than no migration.
enum WorkflowFileStore {

    /// Bumped when the document shape changes in a way an older build cannot
    /// read. A file written by a newer build is refused rather than guessed at.
    static let schemaVersion: UInt32 = 1

    private static let documentFile = "workflow.json"
    private static let root = "Workflows"

    enum Failure: Error {
        case unsafeIdentifier(String)
        case noBaseDirectory
        case notFound(String)
        case tooNew(String)

        var message: String {
            switch self {
            case .unsafeIdentifier(let id):
                "\(id) is not a usable workflow id: 1-128 characters of A-Z, a-z, 0-9, _ or -."
            case .noBaseDirectory:
                "The model paths base directory has not been set."
            case .notFound(let id):
                "No workflow is stored under \(id)."
            case .tooNew(let id):
                "\(id) was written by a newer build than this one."
            }
        }
    }

    // MARK: - Locations

    /// Where workflows live.
    ///
    /// Under the RunAnywhere root, not the host's base directory. Commons
    /// resolves the same folder from `rac_model_paths_get_base_directory`,
    /// which appends `RunAnywhere/`, so reading the raw base put this store one
    /// directory above everything the runner looks in and every run failed as
    /// Not found.
    static func directory() throws -> URL {
        guard let root = try? CppBridge.ModelPaths.runAnywhereRoot() else {
            throw Failure.noBaseDirectory
        }
        return root.appendingPathComponent(WorkflowFileStore.root, isDirectory: true)
    }

    static func directory(for id: String) throws -> URL {
        try requireSafe(id)
        return try directory().appendingPathComponent(id, isDirectory: true)
    }

    // MARK: - Documents

    /// Writes `document`, stamping the schema version and the modification
    /// time.
    ///
    /// The timestamp is set here rather than copied from the caller. Trusting
    /// the caller's value meant anyone who never set it stored zero, and every
    /// summary then reported the epoch as its last-modified date.
    static func save(_ document: RAWorkflowDocument) throws {
        try requireSafe(document.id)

        var stored = document
        stored.schemaVersion = schemaVersion
        stored.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)

        let folder = try directory(for: document.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try stored.jsonUTF8Data().write(to: folder.appendingPathComponent(documentFile), options: .atomic)
    }

    static func load(id: String) throws -> RAWorkflowDocument {
        try requireSafe(id)
        let path = try directory(for: id).appendingPathComponent(documentFile)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw Failure.notFound(id)
        }
        let document = try RAWorkflowDocument(jsonUTF8Data: Data(contentsOf: path))
        guard document.schemaVersion <= schemaVersion else { throw Failure.tooNew(id) }
        return document
    }

    /// One summary per stored workflow.
    ///
    /// A document that will not parse is skipped, not thrown: one bad file must
    /// not make the whole list unopenable, which would leave a reader unable to
    /// reach any of their workflows because of one of them.
    static func list() throws -> [RAWorkflowSummary] {
        let folder = try directory()
        let names = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []

        return names.compactMap { entry in
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  let document = try? load(id: entry.lastPathComponent) else {
                return nil
            }
            var summary = RAWorkflowSummary()
            summary.id = document.id
            summary.name = document.name
            summary.createdAtMs = document.createdAtMs
            summary.updatedAtMs = document.updatedAtMs
            summary.nodeCount = UInt32(document.nodes.count)
            return summary
        }
    }

    /// Removes a workflow and everything filed under it. Deleting an id that
    /// was never stored succeeds, so a caller need not check first.
    static func delete(id: String) throws {
        let folder = try directory(for: id)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    // MARK: - Identifiers

    /// Ids become path components, so anything that could climb out of the
    /// workflows directory is refused before it is joined to a path.
    private static func requireSafe(_ id: String) throws {
        guard (1 ... 128).contains(id.count),
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
        else {
            throw Failure.unsafeIdentifier(id)
        }
    }
}
