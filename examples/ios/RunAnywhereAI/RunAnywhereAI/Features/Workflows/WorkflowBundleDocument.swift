//
//  WorkflowBundleDocument.swift
//  RunAnywhereAI
//
//  The file a user exports and shares: serialized runanywhere.v1.WorkflowBundle
//  bytes, carrying one or more workflows plus every node pack they reference.
//  Commons assembles and reads the payload; this type only moves it in and out
//  of a file the user chose.
//

import Foundation
import RunAnywhere
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Derived from the extension rather than declared in Info.plist. The app
    /// exports no document type, so the system hands back a dynamic identifier
    /// for `.rawf`, which is enough for the save and open panels to filter on
    /// and for a bundle to round-trip between two copies of this app.
    static let runAnywhereWorkflowBundle: UTType =
        UTType(
            filenameExtension: WorkflowBundleDocument.fileExtension,
            conformingTo: .data
        ) ?? .data
}

struct WorkflowBundleDocument: FileDocument {
    static let fileExtension = "rawf"

    static var readableContentTypes: [UTType] { [.runAnywhereWorkflowBundle] }

    let payload: Data

    init(payload: Data) {
        self.payload = payload
    }

    init(bundle: RAWorkflowBundle) throws {
        payload = try bundle.serializedData()
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        payload = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: payload)
    }

    func bundle() throws -> RAWorkflowBundle {
        try RAWorkflowBundle(serializedBytes: payload)
    }
}

/// A bundle read off disk, waiting for the user to say which of its items to
/// take. An import is deliberately per item rather than all-or-nothing: a
/// bundle of five workflows is usually shared for one of them.
struct WorkflowBundleImportRequest: Identifiable {
    let id = UUID()
    let fileName: String
    let bundle: RAWorkflowBundle

    var itemCount: Int { bundle.workflows.count + bundle.packs.count }

    /// A script pack has to be reviewed whatever else the bundle holds, so a
    /// one-item bundle carrying one still goes through the picker.
    var needsReview: Bool {
        itemCount > 1 || bundle.packs.contains(where: \.isScript)
    }
}

/// What actually happened, per item. A partly successful import says so rather
/// than reading as a clean success.
struct WorkflowImportOutcome: Identifiable {
    let id = UUID()
    var workflows: [String]
    var packs: [String]
    var skipped: [RABundleImportIssue]
    var declinedPacks: [String]

    var importedCount: Int { workflows.count + packs.count }
    var isClean: Bool { skipped.isEmpty && declinedPacks.isEmpty }
}

extension RABundleImportIssue {
    var kindLabel: String {
        switch kind {
        case .workflow: return "Workflow"
        case .pack: return "Node pack"
        case .unspecified, .UNRECOGNIZED: return "Item"
        }
    }
}
