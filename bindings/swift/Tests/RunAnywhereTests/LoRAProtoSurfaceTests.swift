//
//  LoRAProtoSurfaceTests.swift
//  RunAnywhere SDK
//
//  Focused tests for generated RALora* public surface.
//
//  idl/lora_options.proto's "lora-delete-download-import-bookkeeping" edit
//  renamed RALoRA* -> RALora*, deleted LoraAdapterDownloadCompletedRequest/
//  Result and LoraAdapterImportRequest/Result outright (no replacement --
//  adapter files are acquired exclusively through the models domain's
//  download/import verbs now, see RunAnywhere+LoRADownload.swift), and
//  shrunk LoraAdapterCatalogEntry to {id, name, compatibleModels,
//  defaultScale, tags, localPath} -- url/filename/isDownloaded/isImported
//  all deleted ("everything generic about the artifact ... lives on the
//  ModelInfo record for this adapter" now).
//

import XCTest

@testable import RunAnywhere

final class LoRAProtoSurfaceTests: XCTestCase {
    func testLoRARuntimeSurfaceUsesGeneratedProtoTypes() {
        let apply: (RALoraApplyRequest) async throws -> RALoraApplyResult = RunAnywhere.lora.apply
        let remove: (RALoraRemoveRequest) async throws -> RALoraState = RunAnywhere.lora.remove
        let list: () async throws -> LoraState = RunAnywhere.lora.list
        let state: () async throws -> RALoraState = RunAnywhere.lora.state
        let checkCompatibility: (RALoraAdapterConfig) async -> RALoraCompatibilityResult =
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
        let adaptersForModel: (String) async throws -> [RALoraAdapterCatalogEntry] =
            RunAnywhere.lora.adaptersForModel
        let allRegistered: () async throws -> [RALoraAdapterCatalogEntry] = RunAnywhere.lora.allRegistered

        _ = (
            register,
            listCatalog,
            queryCatalog,
            getCatalogEntry,
            adaptersForModel,
            allRegistered
        )
    }

    func testGeneratedLoRARequestsCarryCanonicalFields() {
        var config = RALoraAdapterConfig()
        config.adapterID = "adapter-a"
        config.adapterPath = "/models/adapter-a.gguf"
        config.scale = 0.75

        var applyRequest = RALoraApplyRequest()
        applyRequest.requestID = "apply-1"
        applyRequest.adapters = [config]
        applyRequest.keepExisting = true

        XCTAssertEqual(applyRequest.requestID, "apply-1")
        XCTAssertEqual(applyRequest.adapters.first?.adapterID, "adapter-a")
        XCTAssertEqual(applyRequest.adapters.first?.adapterPath, "/models/adapter-a.gguf")
        XCTAssertEqual(applyRequest.adapters.first?.scale, 0.75)
        XCTAssertTrue(applyRequest.keepExisting)

        var removeRequest = RALoraRemoveRequest()
        removeRequest.adapterIds = ["adapter-a"]
        removeRequest.clearAll_p = false

        XCTAssertEqual(removeRequest.adapterIds, ["adapter-a"])
        XCTAssertFalse(removeRequest.clearAll_p)
    }

    func testGeneratedLoRAStateAndApplyResultCarryCanonicalFields() {
        var adapter = RALoraAdapterInfo()
        adapter.adapterID = "adapter-a"
        adapter.adapterPath = "/models/adapter-a.gguf"
        adapter.scale = 0.5
        adapter.applied = true
        adapter.rank = 16
        adapter.alpha = 32

        var result = RALoraApplyResult()
        result.requestID = "apply-1"
        result.adapters = [adapter]

        XCTAssertEqual(result.requestID, "apply-1")
        XCTAssertEqual(result.adapters.first?.adapterID, "adapter-a")
        XCTAssertEqual(result.adapters.first?.rank, 16)
        XCTAssertFalse(result.hasError)

        var state = RALoraState()
        state.loadedAdapters = [adapter]
        state.baseModelID = "base-model"

        XCTAssertEqual(state.loadedAdapters.first?.adapterPath, "/models/adapter-a.gguf")
        XCTAssertEqual(state.baseModelID, "base-model")
    }

    func testGeneratedLoRACatalogEntriesCarryCanonicalFields() {
        var entry = RALoraAdapterCatalogEntry()
        entry.id = "adapter-a"
        entry.name = "Adapter A"
        entry.compatibleModels = ["base-model"]
        entry.defaultScale = 1.0
        entry.tags = ["chat"]
        entry.localPath = "/models/adapter-a.gguf"

        var query = RALoraAdapterCatalogQuery()
        query.adapterID = "adapter-a"
        query.modelID = "base-model"
        query.downloadedOnly = true
        query.tags = ["chat"]

        var listRequest = RALoraAdapterCatalogListRequest()
        listRequest.query = query

        var listResult = RALoraAdapterCatalogListResult()
        listResult.entries = [entry]
        listResult.totalCount = 1
        listResult.downloadedCount = 1

        var getRequest = RALoraAdapterCatalogGetRequest()
        getRequest.adapterID = "adapter-a"

        var getResult = RALoraAdapterCatalogGetResult()
        getResult.found = true
        getResult.entry = entry

        XCTAssertEqual(listRequest.query.modelID, "base-model")
        XCTAssertTrue(listRequest.query.downloadedOnly)
        XCTAssertEqual(listResult.entries.first?.localPath, "/models/adapter-a.gguf")
        XCTAssertEqual(listResult.downloadedCount, 1)
        XCTAssertEqual(getRequest.adapterID, "adapter-a")
        XCTAssertTrue(getResult.found)
        // Non-empty local_path is the single definition of "downloaded" now
        // (isDownloaded/isImported were deleted outright).
        XCTAssertFalse(getResult.entry.localPath.isEmpty)
    }
}
