//
//  WorkflowFileStoreTests.swift
//  RunAnywhereTests
//
//  Storage, held to the layout commons already wrote.
//

@testable import RunAnywhere
import XCTest

final class WorkflowFileStoreTests: XCTestCase {

    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("workflow-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try CppBridge.ModelPaths.setBaseDirectory(base)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func document(id: String, name: String, nodes: Int = 0) -> RAWorkflowDocument {
        var document = RAWorkflowDocument()
        document.id = id
        document.name = name
        document.createdAtMs = 1_700_000_000_000
        document.nodes = (0 ..< nodes).map { index in
            var node = RAWorkflowNode()
            node.id = "n\(index)"
            return node
        }
        return document
    }

    // MARK: - Round trip

    func testASavedWorkflowComesBack() throws {
        try WorkflowFileStore.save(document(id: "alpha", name: "Alpha", nodes: 2))
        let loaded = try WorkflowFileStore.load(id: "alpha")
        XCTAssertEqual(loaded.id, "alpha")
        XCTAssertEqual(loaded.name, "Alpha")
        XCTAssertEqual(loaded.nodes.count, 2)
    }

    func testSavingStampsTheSchemaVersionAndModificationTime() throws {
        // The caller's `updatedAtMs` is deliberately ignored. Copying it meant a
        // caller that never set it stored zero, and every summary then reported
        // the epoch as the last-modified date.
        var stale = document(id: "beta", name: "Beta")
        stale.updatedAtMs = 0
        try WorkflowFileStore.save(stale)

        let loaded = try WorkflowFileStore.load(id: "beta")
        XCTAssertEqual(loaded.schemaVersion, WorkflowFileStore.schemaVersion)
        XCTAssertGreaterThan(loaded.updatedAtMs, 0)
        XCTAssertEqual(loaded.createdAtMs, 1_700_000_000_000, "created is the caller's to set")
    }

    func testLoadingSomethingNeverSavedIsNotFound() {
        XCTAssertThrowsError(try WorkflowFileStore.load(id: "missing"))
    }

    // MARK: - The layout commons wrote

    func testItReadsAFileWrittenByTheCppStore() throws {
        // The whole point of keeping the layout: <base>/Workflows/<id>/
        // workflow.json holding the document as protobuf JSON. Written here by
        // hand, exactly as the C++ would, and it must load.
        let folder = base
            .appendingPathComponent("Workflows", isDirectory: true)
            .appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = #"{"id":"legacy","name":"From C++","schemaVersion":1,"createdAtMs":"42"}"#
        try Data(json.utf8).write(to: folder.appendingPathComponent("workflow.json"))

        let loaded = try WorkflowFileStore.load(id: "legacy")
        XCTAssertEqual(loaded.name, "From C++")
        XCTAssertEqual(loaded.createdAtMs, 42)
    }

    func testADocumentFromANewerBuildIsRefused() throws {
        let folder = base
            .appendingPathComponent("Workflows", isDirectory: true)
            .appendingPathComponent("future", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = #"{"id":"future","name":"Later","schemaVersion":99}"#
        try Data(json.utf8).write(to: folder.appendingPathComponent("workflow.json"))

        XCTAssertThrowsError(try WorkflowFileStore.load(id: "future"))
    }

    // MARK: - Listing

    func testListingSummarisesEveryStoredWorkflow() throws {
        try WorkflowFileStore.save(document(id: "one", name: "One", nodes: 1))
        try WorkflowFileStore.save(document(id: "two", name: "Two", nodes: 3))

        let summaries = try WorkflowFileStore.list().sorted { $0.id < $1.id }
        XCTAssertEqual(summaries.map(\.id), ["one", "two"])
        XCTAssertEqual(summaries.map(\.nodeCount), [1, 3])
        XCTAssertEqual(summaries.map(\.name), ["One", "Two"])
    }

    func testOneUnreadableWorkflowDoesNotHideTheRest() throws {
        try WorkflowFileStore.save(document(id: "good", name: "Good"))

        let broken = base
            .appendingPathComponent("Workflows", isDirectory: true)
            .appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("not json at all".utf8).write(to: broken.appendingPathComponent("workflow.json"))

        // The bad one is skipped rather than throwing, or one corrupt file would
        // leave every workflow unreachable.
        XCTAssertEqual(try WorkflowFileStore.list().map(\.id), ["good"])
    }

    func testAnEmptyStoreListsNothingRatherThanFailing() throws {
        XCTAssertEqual(try WorkflowFileStore.list().count, 0)
    }

    // MARK: - Deleting

    func testDeletingRemovesIt() throws {
        try WorkflowFileStore.save(document(id: "gone", name: "Gone"))
        try WorkflowFileStore.delete(id: "gone")
        XCTAssertThrowsError(try WorkflowFileStore.load(id: "gone"))
    }

    func testDeletingSomethingNeverStoredSucceeds() throws {
        XCTAssertNoThrow(try WorkflowFileStore.delete(id: "never"))
    }

    // MARK: - Identifiers

    func testAnIdThatCouldEscapeTheDirectoryIsRefused() {
        // These become path components. `../` would put a workflow anywhere on
        // disk, and a delete anywhere on disk.
        for bad in ["../escape", "with/slash", "", String(repeating: "x", count: 129), "sp ace"] {
            XCTAssertThrowsError(
                try WorkflowFileStore.save(document(id: bad, name: "Bad")),
                "\(bad) should be refused"
            )
        }
    }
}
