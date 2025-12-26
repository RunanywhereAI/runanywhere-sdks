//
//  RunAnywhereAIApp.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/21/25.
//

import SwiftUI
import RunAnywhere
import FluidAudioDiarization
import ONNXRuntime
import LlamaCPPRuntime
#if canImport(UIKit)
import UIKit
#endif
import os
#if os(macOS)
import AppKit
#endif
// Import Foundation Models adapter from SDK (requires iOS 26+ / macOS 26+)
#if canImport(FoundationModelsAdapter)
import FoundationModelsAdapter
#endif

@main
struct RunAnywhereAIApp: App {
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "RunAnywhereAIApp")
    #if os(macOS)
    private let memoryPressureSource: DispatchSourceMemoryPressure
    #endif
    @StateObject private var modelManager = ModelManager.shared
    @State private var isSDKInitialized = false
    @State private var initializationError: Error?

    init() {
        #if os(macOS)
        // Setup macOS memory pressure monitoring
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        memoryPressureSource.setEventHandler { [logger] in
            logger.warning("⚠️ macOS memory pressure detected, cleaning up cached services")
        }
        memoryPressureSource.resume()
        #endif
    }

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
                let apiKey = "prod_api_key"  // Get from secure storage in production
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

        // Register LlamaCPP Core with curated LLM models
        // 3 best models: Fast (SmolLM2), Balanced (Qwen), Quality (LFM2)
        await RunAnywhere.registerFramework(
            LlamaCPPCoreAdapter(),
            models: [
                try! ModelRegistration(
                    url: "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
                    framework: .llamaCpp,
                    modality: .textToText,
                    id: "qwen-2.5-0.5b-instruct-q6-k",
                    name: "Smart Assistant",
                    memoryRequirement: 600_000_000
                ),
                try! ModelRegistration(
                    url: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf",
                    framework: .llamaCpp,
                    modality: .textToText,
                    id: "lfm2-350m-q8-0",
                    name: "Quality Assistant",
                    memoryRequirement: 400_000_000
                ),
                try! ModelRegistration(
                    url: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
                    framework: .llamaCpp,
                    modality: .textToText,
                    id: "lfm2-350m-q4-k-m",
                    name: "Balanced Assistant",
                    memoryRequirement: 250_000_000
                ),
            ]
        )
        logger.info("✅ LlamaCPP Core registered with curated models")

        // Register ONNX Runtime with STT and TTS models
        await RunAnywhere.registerFramework(
            ONNXAdapter.shared,
            models: [
                // STT Model - Single best option
                try! ModelRegistration(
                    url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2",
                    framework: .onnx,
                    modality: .voiceToText,
                    id: "sherpa-whisper-tiny-onnx",
                    name: "Voice Recognition",
                    format: .onnx,
                    memoryRequirement: 75_000_000
                ),
                // TTS Models - Natural voice options
                try! ModelRegistration(
                    url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2",
                    framework: .onnx,
                    modality: .textToVoice,
                    id: "piper-en-us-lessac-medium",
                    name: "Natural Voice (US)",
                    format: .onnx,
                    memoryRequirement: 65_000_000
                ),
                try! ModelRegistration(
                    url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-alba-medium.tar.bz2",
                    framework: .onnx,
                    modality: .textToVoice,
                    id: "piper-en-gb-alba-medium",
                    name: "Natural Voice (British)",
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
        #if canImport(FoundationModelsAdapter)
        if #available(iOS 26.0, macOS 26.0, *) {
            await RunAnywhere.registerFramework(FoundationModelsAdapter())
            logger.info("✅ Foundation Models registered")
        }
        #endif

        logger.info("🎉 All adapters registered for development")
    }

    private func registerAdaptersForProduction() async {
        logger.info("📦 Registering adapters for PRODUCTION mode")

        // Register LlamaCPP Core with curated LLM models (same as development)
        await RunAnywhere.registerFramework(
            LlamaCPPCoreAdapter(),
            models: [
                try! ModelRegistration(
                    url: "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
                    framework: .llamaCpp,
                    modality: .textToText,
                    id: "qwen-2.5-0.5b-instruct-q6-k",
                    name: "Smart Assistant",
                    memoryRequirement: 600_000_000
                ),
                try! ModelRegistration(
                    url: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf",
                    framework: .llamaCpp,
                    modality: .textToText,
                    id: "lfm2-350m-q8-0",
                    name: "Quality Assistant",
                    memoryRequirement: 400_000_000
                )
            ]
        )
        logger.info("✅ LlamaCPP Core registered with curated models")

        // Register ONNX Runtime with STT and TTS models (same as development)
        await RunAnywhere.registerFramework(
            ONNXAdapter.shared,
            models: [
                try! ModelRegistration(
                    url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2",
                    framework: .onnx,
                    modality: .voiceToText,
                    id: "sherpa-whisper-tiny-onnx",
                    name: "Voice Recognition",
                    format: .onnx,
                    memoryRequirement: 75_000_000
                ),
                try! ModelRegistration(
                    url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2",
                    framework: .onnx,
                    modality: .textToVoice,
                    id: "piper-en-us-lessac-medium",
                    name: "Natural Voice (US)",
                    format: .onnx,
                    memoryRequirement: 65_000_000
                ),
                try! ModelRegistration(
                    url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-alba-medium.tar.bz2",
                    framework: .onnx,
                    modality: .textToVoice,
                    id: "piper-en-gb-alba-medium",
                    name: "Natural Voice (British)",
                    format: .onnx,
                    memoryRequirement: 65_000_000
                )
            ]
        )
        logger.info("✅ ONNX Runtime registered with curated models")

        // Register FluidAudioDiarization
        await FluidAudioDiarizationProvider.register()
        logger.info("✅ FluidAudioDiarization registered")

        // Register Foundation Models adapter for iOS 26+ and macOS 26+
        #if canImport(FoundationModelsAdapter)
        if #available(iOS 26.0, macOS 26.0, *) {
            await RunAnywhere.registerFramework(FoundationModelsAdapter())
            logger.info("✅ Foundation Models registered")
        }
        #endif

        logger.info("🎉 All adapters registered for production with hardcoded models")
        logger.info("📡 Backend can dynamically add more models via console API")
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

            Text("Setting Up Your AI")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Preparing your private AI assistant...")
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
