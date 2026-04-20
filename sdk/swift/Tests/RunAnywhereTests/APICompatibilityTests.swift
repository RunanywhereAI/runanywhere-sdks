// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Compile-time verification that the legacy public API shapes sample
// apps depend on still resolve on the v2 SDK. Most tests assert TYPE
// existence and call-shape only; no runtime behaviour is expected here
// because we're testing the adapter surface, not the underlying engines.

import XCTest
import Foundation
@testable import RunAnywhere

@MainActor
final class APICompatibilityTests: XCTestCase {

    // MARK: - ModelCatalog types

    func testModelArtifactTypeArchiveNewShape() {
        // Sample apps write: `artifactType: .archive(.tarGz, structure: .nestedDirectory)`
        let artifact: ModelArtifactType = .archive(.tarGz, structure: .nestedDirectory)
        if case .archive(let f, let s) = artifact {
            XCTAssertEqual(f, .tarGz)
            XCTAssertEqual(s, .nestedDirectory)
        } else {
            XCTFail("expected .archive case")
        }
    }

    func testModelArtifactTypeArchiveLegacyStringShape() {
        // Back-compat: legacy `.archive(format: "zip")` still compiles.
        let artifact: ModelArtifactType = .archive(format: "zip")
        if case .archive(let f, _) = artifact {
            XCTAssertEqual(f, .zip)
        } else {
            XCTFail("expected .archive case")
        }
    }

    func testModalityEnumExists() {
        // Sample apps use `modality: .speechRecognition` etc.
        let m: Modality = .speechRecognition
        XCTAssertEqual(m.category, .stt)
        XCTAssertEqual(Modality.speechSynthesis.category, .tts)
        XCTAssertEqual(Modality.voiceActivityDetection.category, .vad)
        XCTAssertEqual(Modality.embedding.category, .embedding)
        XCTAssertEqual(Modality.multimodal.category, .vlm)
        XCTAssertEqual(Modality.imageGeneration.category, .diffusion)
    }

    func testInferenceFrameworkLegacyCases() {
        // .whisperKitCoreML + .metalrt aliases must compile.
        _ = InferenceFramework.whisperKitCoreML
        _ = InferenceFramework.metalrt
        _ = InferenceFramework.metalRT
        _ = InferenceFramework.foundationModels
    }

    func testModelFileDescriptorFilenameInit() {
        // Legacy initializer with `filename:`.
        let url = URL(string: "https://example.com/model.gguf")!
        let desc = ModelFileDescriptor(url: url, filename: "model.gguf")
        XCTAssertEqual(desc.relativePath, "model.gguf")
        XCTAssertEqual(desc.filename, "model.gguf")
    }

    func testRegisterModelModalityEnum() {
        // Canonical v2 registration with `modality: .speechRecognition`.
        let url = URL(string: "https://example.com/stt.bin")!
        RunAnywhere.registerModel(
            id: "api-compat-stt",
            name: "Test STT",
            url: url,
            framework: .whisperKitCoreML,
            memoryRequirement: 100_000_000,
            modality: .speechRecognition)
        let found = RunAnywhere.availableModels.first { $0.id == "api-compat-stt" }
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.category, .stt)
    }

    func testRegisterMultiFileModelFilename() {
        let u = URL(string: "https://example.com/x.bin")!
        let files = [ModelFileDescriptor(url: u, filename: "weights.bin")]
        RunAnywhere.registerMultiFileModel(
            id: "api-compat-mf", name: "MF", files: files,
            framework: .coreML, modality: .imageGeneration)
        XCTAssertNotNil(RunAnywhere.availableModels.first { $0.id == "api-compat-mf" })
    }

    // MARK: - RunAnywhere top-level surface

    func testEnvironmentAccessorAvailable() {
        // Both `environment` and `currentEnvironment` must type-check.
        let _: SDKEnvironment? = RunAnywhere.environment
        let _: SDKEnvironment? = RunAnywhere.currentEnvironment
    }

    func testEnvironmentCustomStringConvertible() {
        let d: SDKState.Environment = .development
        XCTAssertEqual("\(d)", "development")
        XCTAssertEqual(SDKState.Environment.production.description, "production")
    }

    func testInitializeNoArgOverload() throws {
        // DEBUG build path in the iOS sample calls `try RunAnywhere.initialize()`.
        try RunAnywhere.initialize()
        XCTAssertTrue(RunAnywhere.isSDKInitialized)
        RunAnywhere.shutdown()
    }

    func testAvailableModelsParenOverload() async {
        let models = await RunAnywhere.availableModels()
        XCTAssertTrue(models is [ModelInfo])
    }

    func testStorageInfoAlias() {
        let info: StorageInfo = RunAnywhere.storageInfo()
        _ = info.totalBytes
        _ = info.freeBytes
    }

    func testDeleteModelAlias() async {
        _ = await RunAnywhere.deleteModel("nonexistent-id")
    }

    func testDownloadModelReturnsAsyncStream() {
        // Type-only check — we're not executing the download.
        let stream: AsyncThrowingStream<DownloadProgress, Error> =
            RunAnywhere.downloadModel("nonexistent-id")
        _ = stream
    }

    func testGenerateImagePromptOptionsOverload() async {
        // Must type-check. Will throw at runtime because no diffusion
        // model is loaded — that's fine; we just need the signature.
        do {
            _ = try await RunAnywhere.generateImage(
                prompt: "test",
                options: DiffusionGenerationOptions())
            XCTFail("expected error")
        } catch {
            // expected
        }
    }

    func testLoRAAdapterCatalogFacade() async {
        await LoRAAdapterCatalog.registerAll()
        _ = LoRAAdapterCatalog.allEntries
    }

    // MARK: - Phase B consumption: new C ABI helpers

    func testFrameworkSupportsBackedByCoreABI() {
        XCTAssertTrue(RunAnywhere.frameworkSupports(.llamaCpp, category: .llm))
        XCTAssertFalse(RunAnywhere.frameworkSupports(.llamaCpp, category: .stt))
        XCTAssertTrue(RunAnywhere.frameworkSupports(.whisperKit, category: .stt))
        XCTAssertTrue(RunAnywhere.frameworkSupports(.onnx, category: .embedding))
    }

    func testDetectModelFormatFromURL() {
        XCTAssertEqual(RunAnywhere.detectModelFormat(from: "x.gguf"),  .gguf)
        XCTAssertEqual(RunAnywhere.detectModelFormat(from: "x.onnx"),  .onnx)
        XCTAssertEqual(RunAnywhere.detectModelFormat(from: "x.xyz"),   .unknown)
    }

    func testInferModelCategoryHeuristic() {
        XCTAssertEqual(RunAnywhere.inferModelCategory(from: "whisper-base"),     .stt)
        XCTAssertEqual(RunAnywhere.inferModelCategory(from: "bge-small-en"),     .embedding)
        XCTAssertEqual(RunAnywhere.inferModelCategory(from: "llava-1.5"),        .vlm)
    }

    func testTelemetryNamespaceBuildsPayload() {
        let payload = Telemetry.defaultPayloadJson()
        XCTAssertTrue(payload.contains("sdk_version"))
        XCTAssertTrue(payload.contains("platform"))
    }

    func testTelemetryTrackReturnsTrue() {
        XCTAssertTrue(Telemetry.track(event: "api-compat-test"))
    }

    func testFileIntegritySha256() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ra-test-\(UUID().uuidString).bin")
        try "hello world".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let hex = FileIntegrity.sha256(ofFile: tmp.path)
        XCTAssertEqual(hex,
            "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9")
        XCTAssertTrue(FileIntegrity.verify(path: tmp.path,
            expectedSha256: "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"))
        XCTAssertFalse(FileIntegrity.verify(path: tmp.path,
            expectedSha256: String(repeating: "0", count: 64)))
    }

    func testStateSessionAuthRequestShapes() {
        let req = SDKState.buildAuthenticateRequest(apiKey: "key-123",
                                                      deviceId: "dev-456")
        XCTAssertTrue(req.contains("\"api_key\":\"key-123\""))
        XCTAssertTrue(req.contains("\"device_id\":\"dev-456\""))
    }
}
