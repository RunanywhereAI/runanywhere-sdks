// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Compile-only smoke tests — prove every feature flow the iOS sample
// drives resolves against the current SDK signatures. Each stub never
// runs (returns early) so the tests focus entirely on typechecking.
// Add new call sites here when the app starts exercising a new API so
// breakage surfaces at build time, not after a long launch.

import XCTest
@testable import RunAnywhere

@MainActor
final class APISurfaceCompileTests: XCTestCase {

    func test_chat_surface_compiles() async throws {
        if #available(iOS 17, macOS 14, *) {
            RunAnywhere.registerTool(
                ToolDefinition(name: "t", description: "", parameters: [], category: "x"),
                executor: { _ in ["result": .string("ok")] }
            )
            _ = RunAnywhere.getRegisteredTools() as [ToolDefinition]
            await RunAnywhere.clearTools()

            _ = RunAnywhere.isModelLoaded
            _ = RunAnywhere.getCurrentModelId()
            try await RunAnywhere.unloadModel()

            _ = try await RunAnywhere.generateStream("hi",
                options: LLMGenerationOptions(maxTokens: 1, temperature: 0))
        }
    }

    func test_voice_surface_compiles() async throws {
        if #available(iOS 17, macOS 14, *) {
            let _: VoiceSessionConfig = VoiceSessionConfig(
                continuousMode: false, thinkingModeEnabled: false, maxTokens: 64)
        }
    }

    func test_stt_surface_compiles() async throws {
        _ = try await RunAnywhere.transcribe(Data([0, 0, 0, 0]))
    }

    func test_tts_surface_compiles() async throws {
        _ = TTSOptions(rate: 1.0, pitch: 0.0)
        _ = TTSResult(pcm: [], sampleRateHz: 16000)
    }

    func test_vad_surface_compiles() async throws {
        _ = try RunAnywhere.detectSpeech(in: [Float]())
        _ = RunAnywhere.currentVADModel
    }

    func test_vlm_surface_compiles() async throws {
        let img = VLMImage(bytes: Data(count: 4), width: 1, height: 1)
        _ = RunAnywhere.processImageStream(image: img, prompt: "hi", maxTokens: 4)
    }

    func test_rag_surface_compiles() async throws {
        _ = RAGConfiguration(
            embeddingModelPath: "/tmp/e", llmModelPath: "/tmp/l")
        _ = ThinkingContentParser.extract(from: "abc")
        _ = ThinkingContentParser.strip(from: "abc")
    }

    func test_diffusion_surface_compiles() async throws {
        let cfg = DiffusionConfiguration(modelVariant: .sdxs,
                                          enableSafetyChecker: false,
                                          reduceMemory: true)
        _ = cfg
        _ = DiffusionGenerationOptions(prompt: "x",
                                         width: 512, height: 512,
                                         steps: 10, guidanceScale: 0,
                                         seed: 42)
    }

    func test_models_surface_compiles() async throws {
        _ = RunAnywhere.availableModels as [ModelInfo]
        _ = RunAnywhere.getStorageInfo()
        _ = RunAnywhere.deleteStoredModel("id", framework: .llamaCpp)
    }

    func test_download_surface_compiles() async throws {
        let stream: AsyncStream<DownloadProgress> =
            try await RunAnywhere.downloadModel("nonexistent-id")
        var iter = stream.makeAsyncIterator()
        _ = await iter.next()
    }
}
