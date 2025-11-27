//
//  RunAnywhereAIApp.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/21/25.
//

import SwiftUI
import RunAnywhere
import LLMSwift
import WhisperKitTranscription
import FluidAudioDiarization
import ONNXRuntime
#if canImport(UIKit)
import UIKit
#endif
import os

@main
struct RunAnywhereAIApp: App {
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "RunAnywhereAIApp")
    @StateObject private var modelManager = ModelManager.shared
    @State private var isSDKInitialized = false
    @State private var initializationError: Error?

    var body: some Scene {
        WindowGroup {
            Group {
                if isSDKInitialized {
                    ContentView()
                        .environmentObject(modelManager)
                        .onAppear {
                            logger.info("🎉 App is ready to use!")
                        }
                } else if let error = initializationError {
                    InitializationErrorView(error: error) {
                        // Retry initialization
                        Task {
                            await retryInitialization()
                        }
                    }
                } else {
                    InitializationLoadingView()
                }
            }
            .task {
                logger.info("🏁 App launched, initializing SDK...")
                await initializeSDK()
            }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                logger.warning("⚠️ Memory warning received, cleaning up cached services")
                Task {
                    await WhisperKitAdapter.shared.forceCleanup()
                }
            }
            #endif
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentSize)
        #endif
    }

    private func initializeSDK() async {
        do {
            // Clear any previous error
            await MainActor.run { initializationError = nil }

            logger.info("🎯 Initializing SDK...")

            let startTime = Date()

            // Determine environment based on build configuration
            #if DEBUG
            let environment = SDKEnvironment.development
            logger.info("🛠️ Using DEVELOPMENT mode - No API key required!")
            #else
            let environment = SDKEnvironment.production
            logger.info("🚀 Using PRODUCTION mode")
            #endif

            // Initialize SDK based on environment
            if environment == .development {
                // Development Mode - No API key needed!
                // Note: baseURL is required for cross-platform consistency with Kotlin SDK
                // In development mode, dev analytics are automatically sent to Supabase internally
                try RunAnywhere.initialize(
                    apiKey: "dev",  // Any string works in dev mode
                    baseURL: "localhost",  // Required but not used
                    environment: .development
                )
                logger.info("✅ SDK initialized in DEVELOPMENT mode (dev analytics enabled)")

                // Register adapters WITH custom models for development
                await registerAdaptersForDevelopment()

            } else {
                // Production Mode - Real API key required
                let apiKey = "testing_api_key"  // TODO: Get from secure storage
                let baseURL = "https://api.runanywhere.ai"

                try RunAnywhere.initialize(
                    apiKey: apiKey,
                    baseURL: baseURL,
                    environment: .production
                )
                logger.info("✅ SDK initialized in PRODUCTION mode")

                // Register adapters without custom models (uses console-managed models)
                await registerAdaptersForProduction()
            }

            let initTime = Date().timeIntervalSince(startTime)
            logger.info("✅ SDK successfully initialized !")
            logger.info("⚡ Initialization time: \(String(format: "%.3f", initTime * 1000), privacy: .public)ms (FAST!)")
            logger.info("🎯 SDK Status: \(RunAnywhere.isActive() ? "Active" : "Inactive")")
            logger.info("🔧 Environment: \(RunAnywhere.getCurrentEnvironment()?.description ?? "Unknown")")
            logger.info("📱 Device registration: Will happen on first API call (lazy loading)")
            logger.info("🆔 Device registered: \(RunAnywhere.isDeviceRegistered() ? "Yes" : "No (will register lazily)")")
            logger.info("🚀 Ready for on-device AI inference with lazy device registration!")

            // Note: User settings are now applied per-request, not globally

            // Mark as initialized
            await MainActor.run {
                isSDKInitialized = true
            }

            // Don't auto-load models - let user select
            logger.info("💡 Models registered, user can now download and select models")
        } catch {
            logger.error("❌ SDK initialization failed!")
            logger.error("🔍 Error: \(error, privacy: .public)")
            logger.error("💡 Tip: Check your API key and network connection")
            await MainActor.run {
                initializationError = error
            }
        }
    }

    private func retryInitialization() async {
        await MainActor.run {
            initializationError = nil
        }
        await initializeSDK()
    }

    private func registerAdaptersForDevelopment() async {
        logger.info("📦 Registering adapters with custom models for DEVELOPMENT mode")

        // Register LLMSwift (llama.cpp) with LLM models
        await RunAnywhere.registerFramework(
            LLMSwiftAdapter(),
            models: [
                try! ModelRegistration(
                    url: "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
                    framework: .llamaCpp,
                    modality: .textToText,
                    id: "smollm2-360m-q8-0",
                    name: "SmolLM2 360M Q8_0",
                    memoryRequirement: 500_000_000
                ),
                try! ModelRegistration(
                    url: "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
                    framework: .llamaCpp,
                    modality: .textToText,
                    id: "qwen-2.5-0.5b-instruct-q6-k",
                    name: "Qwen 2.5 0.5B Instruct Q6_K",
                    memoryRequirement: 600_000_000
                ),
                try! ModelRegistration(
                    url: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q6_K.gguf",
                    framework: .llamaCpp,
                    modality: .textToText,
                    id: "llama-3.2-1b-instruct-q6-k",
                    name: "Llama 3.2 1B Instruct Q6_K",
                    memoryRequirement: 1_200_000_000
                ),
                try! ModelRegistration(
                    url: "https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q6_K_L.gguf",
                    framework: .llamaCpp,
                    modality: .textToText,
                    id: "smollm2-1.7b-instruct-q6-k-l",
                    name: "SmolLM2 1.7B Instruct Q6_K_L",
                    memoryRequirement: 1_800_000_000
                ),
                try! ModelRegistration(
                    url: "https://huggingface.co/ZeroWw/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct.q6_k.gguf",
                    framework: .llamaCpp,
                    modality: .textToText,
                    id: "qwen-2.5-1.5b-instruct-q6-k",
                    name: "Qwen 2.5 1.5B Instruct Q6_K",
                    memoryRequirement: 1_600_000_000
                ),
                try! ModelRegistration(
                    url: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
                    framework: .llamaCpp,
                    modality: .textToText,
                    id: "lfm2-350m-q4-k-m",
                    name: "LiquidAI LFM2 350M Q4_K_M",
                    memoryRequirement: 250_000_000
                ),
                try! ModelRegistration(
                    url: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf",
                    framework: .llamaCpp,
                    modality: .textToText,
                    id: "lfm2-350m-q8-0",
                    name: "LiquidAI LFM2 350M Q8_0",
                    memoryRequirement: 400_000_000
                )
            ]
        )
        logger.info("✅ LLMSwift registered")

        // Register WhisperKit with STT models
        await RunAnywhere.registerFramework(
            WhisperKitAdapter.shared,
            models: [
                try! ModelRegistration(
                    url: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-tiny.en",
                    framework: .whisperKit,
                    modality: .voiceToText,
                    id: "whisper-tiny",
                    name: "Whisper Tiny",
                    format: .mlmodel,
                    memoryRequirement: 39_000_000
                ),
                try! ModelRegistration(
                    url: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-base",
                    framework: .whisperKit,
                    modality: .voiceToText,
                    id: "whisper-base",
                    name: "Whisper Base",
                    format: .mlmodel,
                    memoryRequirement: 74_000_000
                )
            ]
        )
        logger.info("✅ WhisperKit registered")

        // Register ONNX Runtime with STT and TTS models
        await RunAnywhere.registerFramework(
            ONNXAdapter.shared,
            models: [
                // STT Models
                // NOTE: tar.bz2 extraction is not fully supported on iOS due to lack of native bz2 library
                // These models will download but fail at extraction on iOS
                // TODO: Replace with ZIP format models or provide pre-extracted models
                try! ModelRegistration(
                    url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17.tar.bz2",
                    framework: .onnx,
                    modality: .voiceToText,
                    id: "zipformer-en-20m",
                    name: "Zipformer English 20M (ONNX) [macOS only]",
                    format: .onnx,
                    memoryRequirement: 20_000_000
                ),
                try! ModelRegistration(
                    url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2",
                    framework: .onnx,
                    modality: .voiceToText,
                    id: "sherpa-whisper-tiny-onnx",
                    name: "Sherpa Whisper Tiny (ONNX) [macOS only]",
                    format: .onnx,
                    memoryRequirement: 75_000_000
                ),
                try! ModelRegistration(
                    url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.en.tar.bz2",
                    framework: .onnx,
                    modality: .voiceToText,
                    id: "sherpa-whisper-small-onnx",
                    name: "Sherpa Whisper Small (ONNX) [macOS only]",
                    format: .onnx,
                    memoryRequirement: 250_000_000
                ),
                // TTS Models - Using sherpa-onnx tar.bz2 packages (includes model, tokens, and espeak-ng-data)
                try! ModelRegistration(
                    url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2",
                    framework: .onnx,
                    modality: .textToVoice,
                    id: "piper-en-us-lessac-medium",
                    name: "Piper TTS (US English - Medium)",
                    format: .onnx,
                    memoryRequirement: 65_000_000
                ),
                try! ModelRegistration(
                    url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-alba-medium.tar.bz2",
                    framework: .onnx,
                    modality: .textToVoice,
                    id: "piper-en-gb-alba-medium",
                    name: "Piper TTS (British English)",
                    format: .onnx,
                    memoryRequirement: 65_000_000
                )
            ]
        )
        logger.info("✅ ONNX Runtime registered (includes STT and TTS providers)")

        // Register FluidAudioDiarization
        await FluidAudioDiarizationProvider.register()
        logger.info("✅ FluidAudioDiarization registered")

        // Register Foundation Models adapter for iOS 26+ and macOS 26+
        if #available(iOS 26.0, macOS 26.0, *) {
            await RunAnywhere.registerFramework(FoundationModelsAdapter())
            logger.info("✅ Foundation Models registered")
        }

        logger.info("🎉 All adapters registered for development")
    }

    private func registerAdaptersForProduction() async {
        logger.info("📦 Registering adapters for PRODUCTION mode")
        logger.info("📡 Models will be fetched from backend console via API")

        // Register adapters (models come from backend)
        await RunAnywhere.registerFramework(WhisperKitAdapter.shared)
        logger.info("✅ WhisperKit registered")

        await RunAnywhere.registerFramework(LLMSwiftAdapter())
        logger.info("✅ LLMSwift registered")

        await RunAnywhere.registerFramework(ONNXAdapter.shared)
        logger.info("✅ ONNX Runtime registered (includes STT and TTS providers)")

        // Register FluidAudioDiarization
        await FluidAudioDiarizationProvider.register()
        logger.info("✅ FluidAudioDiarization registered")

        // Register Foundation Models adapter for iOS 26+ and macOS 26+
        if #available(iOS 26.0, macOS 26.0, *) {
            await RunAnywhere.registerFramework(FoundationModelsAdapter())
            logger.info("✅ Foundation Models registered")
        }

        logger.info("🎉 All adapters registered for production")
    }
}

// MARK: - Loading Views

struct InitializationLoadingView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "brain")
                .font(.system(size: 60))
                .foregroundColor(.blue)
                .scaleEffect(isAnimating ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)

            Text("Initializing RunAnywhere AI")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Setting up AI models and services...")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.2)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .background(Color(.systemBackground))
        #else
        .background(Color(NSColor.windowBackgroundColor))
        #endif
        .onAppear {
            isAnimating = true
        }
    }
}

struct InitializationErrorView: View {
    let error: Error
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Initialization Failed")
                .font(.title2)
                .fontWeight(.semibold)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                retryAction()
            }
            .buttonStyle(.borderedProminent)
            .font(.headline)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .background(Color(.systemBackground))
        #else
        .background(Color(NSColor.windowBackgroundColor))
        #endif
    }
}
