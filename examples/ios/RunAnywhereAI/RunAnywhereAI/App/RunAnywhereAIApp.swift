//
//  RunAnywhereAIApp.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/21/25.
//

import SwiftUI
import RunAnywhere
import LlamaCPPRuntime
import ONNXRuntime
import FluidAudioDiarization
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

                // Register modules and models for development
                await registerModulesAndModels()

            } else {
                // Production Mode - Real API key required
                let apiKey = "prod_api_key"  // TODO: Get from secure storage
                let baseURL = "https://api.runanywhere.ai"

                try RunAnywhere.initialize(
                    apiKey: apiKey,
                    baseURL: baseURL,
                    environment: .production
                )
                logger.info("✅ SDK initialized in PRODUCTION mode")

                // Register modules and models for production
                await registerModulesAndModels()
            }

            let initTime = Date().timeIntervalSince(startTime)
            logger.info("✅ SDK successfully initialized !")
            logger.info("⚡ Initialization time: \(String(format: "%.3f", initTime * 1000), privacy: .public)ms (FAST!)")
            logger.info("🎯 SDK Status: \(RunAnywhere.isActive() ? "Active" : "Inactive")")
            logger.info("🔧 Environment: \(RunAnywhere.getCurrentEnvironment()?.description ?? "Unknown")")
            logger.info("📱 Device registration: Will happen on first API call (lazy loading)")
            logger.info("🚀 Ready for on-device AI inference with lazy device registration!")

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

    /// Register modules with their associated models
    /// Each module explicitly owns its models - the framework is determined by the module
    @MainActor
    private func registerModulesAndModels() async {
        logger.info("📦 Registering modules with their models...")

        // LlamaCPP module with LLM models
        // Using explicit IDs ensures models are recognized after download across app restarts
        LlamaCPP.register()
        LlamaCPP.addModel(id: "smollm2-360m-q8_0",
                          name: "SmolLM2 360M Q8_0",
                          url: "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
                          memoryRequirement: 500_000_000)
        LlamaCPP.addModel(id: "llama-2-7b-chat-q4_k_m",
                          name: "Llama 2 7B Chat Q4_K_M",
                          url: "https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf",
                          memoryRequirement: 4_000_000_000)
        LlamaCPP.addModel(id: "mistral-7b-instruct-q4_k_m",
                          name: "Mistral 7B Instruct Q4_K_M",
                          url: "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf",
                          memoryRequirement: 4_000_000_000)
        LlamaCPP.addModel(id: "qwen2.5-0.5b-instruct-q6_k",
                          name: "Qwen 2.5 0.5B Instruct Q6_K",
                          url: "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
                          memoryRequirement: 600_000_000)
        LlamaCPP.addModel(id: "lfm2-350m-q4_k_m",
                          name: "LiquidAI LFM2 350M Q4_K_M",
                          url: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
                          memoryRequirement: 250_000_000)
        LlamaCPP.addModel(id: "lfm2-350m-q8_0",
                          name: "LiquidAI LFM2 350M Q8_0",
                          url: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf",
                          memoryRequirement: 400_000_000)
        logger.info("✅ LlamaCPP module registered with LLM models")

        // ONNX module with STT and TTS models
        // Using tar.gz format hosted on RunanywhereAI/sherpa-onnx for fast native extraction
        // Using explicit IDs ensures models are recognized after download across app restarts
        ONNX.register()
        // STT Models (Sherpa-ONNX Whisper)
        ONNX.addModel(id: "sherpa-onnx-whisper-tiny.en",
                      name: "Sherpa Whisper Tiny (ONNX)",
                      url: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz",
                      modality: .speechRecognition,
                      artifactType: .tarGzArchive(structure: .nestedDirectory),
                      memoryRequirement: 75_000_000)
        ONNX.addModel(id: "sherpa-onnx-whisper-small.en",
                      name: "Sherpa Whisper Small (ONNX)",
                      url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.en.tar.bz2",
                      modality: .speechRecognition,
                      artifactType: .tarBz2Archive(structure: .nestedDirectory),
                      memoryRequirement: 250_000_000)
        // TTS Models (Piper VITS)
        ONNX.addModel(id: "vits-piper-en_US-lessac-medium",
                      name: "Piper TTS (US English - Medium)",
                      url: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz",
                      modality: .speechSynthesis,
                      artifactType: .tarGzArchive(structure: .nestedDirectory),
                      memoryRequirement: 65_000_000)
        ONNX.addModel(id: "vits-piper-en_GB-alba-medium",
                      name: "Piper TTS (British English)",
                      url: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz",
                      modality: .speechSynthesis,
                      artifactType: .tarGzArchive(structure: .nestedDirectory),
                      memoryRequirement: 65_000_000)
        logger.info("✅ ONNX module registered with STT/TTS models")

        // FluidAudio module (no models - provides speaker diarization service)
        FluidAudio.register()
        logger.info("✅ FluidAudio module registered (Speaker Diarization)")

        // Foundation Models for iOS 26+ and macOS 26+
        // Built-in model is automatically registered by the module
        #if canImport(FoundationModelsAdapter)
        if #available(iOS 26.0, macOS 26.0, *) {
            AppleAI.register()
            logger.info("✅ AppleAI module registered (Foundation Models)")
        }
        #endif

        logger.info("🎉 All modules and models registered")
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
