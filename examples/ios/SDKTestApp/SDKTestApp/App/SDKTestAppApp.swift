//
//  SDKTestAppApp.swift
//  SDKTestApp - Minimal app to test RunAnywhere SDK.
//

import SwiftUI
import RunAnywhere
import LlamaCPPRuntime
import ONNXRuntime
import os

@main
struct SDKTestAppApp: App {
    private let logger = Logger(subsystem: "com.runanywhere.SDKTestApp", category: "App")
    @State private var isInitialized = false
    @State private var initError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if isInitialized {
                    ContentView()
                } else if let error = initError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                        Text("SDK init failed")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ProgressView("Initializing SDK…")
                }
            }
            .task { await initializeSDK() }
        }
    }

    private func initializeSDK() async {
        do {
            logger.info("Initializing RunAnywhere SDK…")
            try RunAnywhere.initialize()
            LlamaCPP.register(priority: 100)
            ONNX.register(priority: 100)
            await registerSampleModels()
            await MainActor.run { isInitialized = true }
            logger.info("SDK initialized successfully")
        } catch {
            logger.error("SDK init failed: \(error.localizedDescription)")
            await MainActor.run { initError = error.localizedDescription }
        }
    }

    @MainActor
    private func registerSampleModels() async {
        // LLM models (language) – list and download from Chat tab
        if let url = URL(string: "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf") {
            RunAnywhere.registerModel(
                id: "qwen2.5-0.5b-instruct-q6_k",
                name: "Qwen 2.5 0.5B Instruct",
                url: url,
                framework: .llamaCpp,
                memoryRequirement: 600_000_000
            )
        }
        if let url = URL(string: "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf") {
            RunAnywhere.registerModel(
                id: "smollm2-360m-q8_0",
                name: "SmolLM2 360M Q8_0",
                url: url,
                framework: .llamaCpp,
                memoryRequirement: 500_000_000
            )
        }
        if let url = URL(string: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf") {
            RunAnywhere.registerModel(
                id: "lfm2-350m-q4_k_m",
                name: "LFM2 350M Q4_K_M",
                url: url,
                framework: .llamaCpp,
                memoryRequirement: 250_000_000
            )
        }
        // TTS models (speech synthesis) – list and download from TTS tab
        if let url = URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz") {
            RunAnywhere.registerModel(
                id: "vits-piper-en_US-lessac-medium",
                name: "Piper TTS (US English - Medium)",
                url: url,
                framework: .onnx,
                modality: .speechSynthesis,
                artifactType: .archive(.tarGz, structure: .nestedDirectory),
                memoryRequirement: 65_000_000
            )
        }
        if let url = URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz") {
            RunAnywhere.registerModel(
                id: "vits-piper-en_GB-alba-medium",
                name: "Piper TTS (British English)",
                url: url,
                framework: .onnx,
                modality: .speechSynthesis,
                artifactType: .archive(.tarGz, structure: .nestedDirectory),
                memoryRequirement: 65_000_000
            )
        }
        // STT model (for reference; Chat tab lists LLMs, TTS tab lists TTS)
        if let url = URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz") {
            RunAnywhere.registerModel(
                id: "sherpa-onnx-whisper-tiny.en",
                name: "Whisper Tiny (ONNX)",
                url: url,
                framework: .onnx,
                modality: .speechRecognition,
                artifactType: .archive(.tarGz, structure: .nestedDirectory),
                memoryRequirement: 75_000_000
            )
        }
    }
}
