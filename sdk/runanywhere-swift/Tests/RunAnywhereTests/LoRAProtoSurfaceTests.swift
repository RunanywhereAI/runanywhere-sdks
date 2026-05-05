//
//  LoRAProtoSurfaceTests.swift
//  RunAnywhere SDK
//
//  Focused tests for generated RALoRA* public surface.
//

import XCTest

@testable import RunAnywhere

final class LoRAProtoSurfaceTests: XCTestCase {
    func testLoRARuntimeSurfaceUsesGeneratedProtoTypes() {
        let apply: (RALoRAApplyRequest) async throws -> RALoRAApplyResult = RunAnywhere.lora.apply
        let remove: (RALoRARemoveRequest) async throws -> RALoRAState = RunAnywhere.lora.remove
        let list: () async throws -> RALoRAState = RunAnywhere.lora.list
        let state: () async throws -> RALoRAState = RunAnywhere.lora.state
        let checkCompatibility: (RALoRAAdapterConfig) async -> RALoraCompatibilityResult =
            RunAnywhere.lora.checkCompatibility

        _ = (apply, remove, list, state, checkCompatibility)
    }

    func testLoRACatalogSurfaceUsesGeneratedCatalogEntries() {
        let register: (RALoraAdapterCatalogEntry) async throws -> RALoraAdapterCatalogEntry =
            RunAnywhere.lora.register
        let listCatalog: (RALoraAdapterCatalogListRequest) async throws -> RALoraAdapterCatalogListResult =
            RunAnywhere.lora.listCatalog
        let queryCatalog: (RALoraAdapterCatalogQuery) async throws -> RALoraAdapterCatalogListResult =
            RunAnywhere.lora.queryCatalog
        let getCatalogEntry: (RALoraAdapterCatalogGetRequest) async throws -> RALoraAdapterCatalogGetResult =
            RunAnywhere.lora.getCatalogEntry
        let markDownloadCompleted:
            (RALoraAdapterDownloadCompletedRequest) async throws -> RALoraAdapterDownloadCompletedResult =
            RunAnywhere.lora.markDownloadCompleted
        let markImportCompleted:
            (RALoraAdapterDownloadCompletedRequest) async throws -> RALoraAdapterDownloadCompletedResult =
            RunAnywhere.lora.markImportCompleted
        let adaptersForModel: (String) async throws -> [RALoraAdapterCatalogEntry] =
            RunAnywhere.lora.adaptersForModel
        let allRegistered: () async throws -> [RALoraAdapterCatalogEntry] = RunAnywhere.lora.allRegistered

        _ = (
            register,
            listCatalog,
            queryCatalog,
            getCatalogEntry,
            markDownloadCompleted,
            markImportCompleted,
            adaptersForModel,
            allRegistered
        )
    }

    func testGeneratedLoRARequestsCarryCanonicalFields() {
        var config = RALoRAAdapterConfig()
        config.adapterID = "adapter-a"
        config.adapterPath = "/models/adapter-a.gguf"
        config.scale = 0.75
        config.targetModules = ["q_proj", "v_proj"]

        var applyRequest = RALoRAApplyRequest()
        applyRequest.requestID = "apply-1"
        applyRequest.adapters = [config]
        applyRequest.replaceExisting = true

        XCTAssertEqual(applyRequest.requestID, "apply-1")
        XCTAssertEqual(applyRequest.adapters.first?.adapterID, "adapter-a")
        XCTAssertEqual(applyRequest.adapters.first?.adapterPath, "/models/adapter-a.gguf")
        XCTAssertEqual(applyRequest.adapters.first?.scale, 0.75)
        XCTAssertEqual(applyRequest.adapters.first?.targetModules, ["q_proj", "v_proj"])
        XCTAssertTrue(applyRequest.replaceExisting)

        var removeRequest = RALoRARemoveRequest()
        removeRequest.requestID = "remove-1"
        removeRequest.adapterIds = ["adapter-a"]
        removeRequest.adapterPaths = ["/models/adapter-a.gguf"]

        XCTAssertEqual(removeRequest.requestID, "remove-1")
        XCTAssertEqual(removeRequest.adapterIds, ["adapter-a"])
        XCTAssertEqual(removeRequest.adapterPaths, ["/models/adapter-a.gguf"])
    }

    func testGeneratedLoRAStateAndApplyResultCarryCanonicalFields() {
        var adapter = RALoRAAdapterInfo()
        adapter.adapterID = "adapter-a"
        adapter.adapterPath = "/models/adapter-a.gguf"
        adapter.scale = 0.5
        adapter.applied = true

        var result = RALoRAApplyResult()
        result.requestID = "apply-1"
        result.adapters = [adapter]
        result.success = true

        XCTAssertEqual(result.requestID, "apply-1")
        XCTAssertEqual(result.adapters.first?.adapterID, "adapter-a")
        XCTAssertTrue(result.success)

        var state = RALoRAState()
        state.loadedAdapters = [adapter]
        state.hasActiveAdapters_p = true
        state.baseModelID = "base-model"

        XCTAssertEqual(state.loadedAdapters.first?.adapterPath, "/models/adapter-a.gguf")
        XCTAssertTrue(state.hasActiveAdapters_p)
        XCTAssertEqual(state.baseModelID, "base-model")
    }

    func testGeneratedLoRACatalogCompletionTypesCarryCanonicalFields() {
        var entry = RALoraAdapterCatalogEntry()
        entry.id = "adapter-a"
        entry.name = "Adapter A"
        entry.url = "https://example.com/adapter-a.gguf"
        entry.filename = "adapter-a.gguf"
        entry.compatibleModels = ["base-model"]
        entry.localPath = "/models/adapter-a.gguf"
        entry.isDownloaded = true
        entry.isImported = true

        var query = RALoraAdapterCatalogQuery()
        query.adapterID = "adapter-a"
        query.modelID = "base-model"
        query.downloadedOnly = true
        query.tags = ["chat"]

        var listRequest = RALoraAdapterCatalogListRequest()
        listRequest.query = query
        listRequest.includeCounts = true

        var listResult = RALoraAdapterCatalogListResult()
        listResult.success = true
        listResult.entries = [entry]
        listResult.totalCount = 1
        listResult.filteredCount = 1
        listResult.downloadedCount = 1

        var getRequest = RALoraAdapterCatalogGetRequest()
        getRequest.adapterID = "adapter-a"

        var getResult = RALoraAdapterCatalogGetResult()
        getResult.found = true
        getResult.entry = entry

        var completed = RALoraAdapterDownloadCompletedRequest()
        completed.adapterID = "adapter-a"
        completed.localPath = "/models/adapter-a.gguf"
        completed.sizeBytes = 42
        completed.completedAtUnixMs = 1_774_000_000_000
        completed.imported = true

        var completedResult = RALoraAdapterDownloadCompletedResult()
        completedResult.success = true
        completedResult.persisted = true
        completedResult.entry = entry

        XCTAssertEqual(listRequest.query.modelID, "base-model")
        XCTAssertTrue(listRequest.query.downloadedOnly)
        XCTAssertEqual(listResult.entries.first?.localPath, "/models/adapter-a.gguf")
        XCTAssertEqual(listResult.downloadedCount, 1)
        XCTAssertEqual(getRequest.adapterID, "adapter-a")
        XCTAssertTrue(getResult.found)
        XCTAssertEqual(completed.adapterID, "adapter-a")
        XCTAssertEqual(completed.sizeBytes, 42)
        XCTAssertTrue(completed.imported)
        XCTAssertTrue(completedResult.persisted)
        XCTAssertTrue(completedResult.entry.isDownloaded)
    }
}
