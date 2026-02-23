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
import WhisperKitRuntime
#if canImport(UIKit)
import UIKit
#endif
import os
#if os(macOS)
import AppKit
#endif

@main
struct RunAnywhereAIApp: App {
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "RunAnywhereAIApp")
    @StateObject private var modelManager = ModelManager.shared
    #if os(iOS)
    @StateObject private var flowSession = FlowSessionManager.shared
    @State private var showFlowActivation = false
    #endif
    @State private var isSDKInitialized = false
    @State private var initializationError: Error?

    var body: some Scene {
        WindowGroup {
            Group {
                if isSDKInitialized {
                    ContentView()
                        .environmentObject(modelManager)
                        #if os(iOS)
                        .environmentObject(flowSession)
                        .onOpenURL { url in
                            guard url.scheme == SharedConstants.urlScheme,
                                  url.host == "startFlow" else { return }
                            logger.info("📲 Received startFlow deep link")
                            showFlowActivation = true
                            Task { await flowSession.handleStartFlow() }
                        }
                        .fullScreenCover(isPresented: $showFlowActivation) {
                            FlowActivationView(isPresented: $showFlowActivation)
                                .environmentObject(flowSession)
                        }
                        #endif
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
            // Register backends with C++ registry FIRST, before any await. Otherwise we can
            // suspend at the next line and another task may run loadModel() → ensureServicesReady()
            // → only Platform is registered → -422 "No provider could handle the request".
            LlamaCPP.register(priority: 100)
            ONNX.register(priority: 100)
            WhisperKitSTT.register(priority: 200)

            // Clear any previous error
            await MainActor.run { initializationError = nil }

            logger.info("🎯 Initializing SDK...")

            let startTime = Date()

            // Check for custom API configuration (stored in Settings)
            let customApiKey = SettingsViewModel.getStoredApiKey()
            let customBaseURL = SettingsViewModel.getStoredBaseURL()

            if let apiKey = customApiKey, let baseURL = customBaseURL {
                // Custom configuration mode - use stored credentials
                // Always use .production for custom backends (model assignment auto-fetch enabled)
                logger.info("🔧 Found custom API configuration")
                logger.info("   Base URL: \(baseURL, privacy: .public)")

                try RunAnywhere.initialize(
                    apiKey: apiKey,
                    baseURL: baseURL,
                    environment: .production
                )
                logger.info("✅ SDK initialized with CUSTOM configuration (production)")
            } else {
                // Default mode based on build configuration
                #if DEBUG
                // Development mode - uses Supabase, no API key needed
                try RunAnywhere.initialize()
                logger.info("✅ SDK initialized in DEVELOPMENT mode")
                #else
                // Production mode - requires API key and backend URL
                // Configure these via Settings screen or set environment variables
                let apiKey = "YOUR_API_KEY_HERE"
                let baseURL = "YOUR_BASE_URL_HERE"

                try RunAnywhere.initialize(
                    apiKey: apiKey,
                    baseURL: baseURL,
                    environment: .production
                )
                logger.info("✅ SDK initialized in PRODUCTION mode")
                #endif
            }

            // Register modules and models
            await registerModulesAndModels()

            // Wait for all registerModel() saves to complete, then scan disk
            // for previously downloaded models. Order matters: flush ensures every
            // model is in the C++ registry so discovery can match files to entries.
            await RunAnywhere.flushPendingRegistrations()
            let discovered = await RunAnywhere.discoverDownloadedModels()
            if discovered > 0 {
                logger.info("📂 Discovered \(discovered) previously downloaded models")
            }

            let initTime = Date().timeIntervalSince(startTime)
            logger.info("✅ SDK successfully initialized!")
            logger.info("⚡ Initialization time: \(String(format: "%.3f", initTime * 1000), privacy: .public)ms")
            logger.info("🎯 SDK Status: \(RunAnywhere.isActive ? "Active" : "Inactive")")
            logger.info("🔧 Environment: \(RunAnywhere.environment?.description ?? "Unknown")")
            logger.info("📱 Services will initialize on first API call")

            // Mark as initialized
            await MainActor.run {
                isSDKInitialized = true
            }

            logger.info("💡 Models registered, user can now download and select models")
        } catch {
            logger.error("❌ SDK initialization failed: \(error, privacy: .public)")
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
    private func registerModulesAndModels() async { // swiftlint:disable:this function_body_length
        logger.info("📦 Registering modules with their models...")

        // NOTE: LlamaCPP, ONNX, and WhisperKitSTT backends are registered once
        // in initializeSDK() before any await. No duplicate registration needed here.

        // Register LLM models using the new RunAnywhere.registerModel API
        // Using explicit IDs ensures models are recognized after download across app restarts
        if let smolLM2URL = URL(string: "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf") {
            RunAnywhere.registerModel(
                id: "smollm2-360m-q8_0",
                name: "SmolLM2 360M Q8_0",
                url: smolLM2URL,
                framework: .llamaCpp,
                memoryRequirement: 500_000_000
            )
        }
        if let llama2URL = URL(string: "https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf") {
            RunAnywhere.registerModel(
                id: "llama-2-7b-chat-q4_k_m",
                name: "Llama 2 7B Chat Q4_K_M",
                url: llama2URL,
                framework: .llamaCpp,
                memoryRequirement: 4_000_000_000
            )
        }
        if let mistralURL = URL(string: "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf") {
            RunAnywhere.registerModel(
                id: "mistral-7b-instruct-q4_k_m",
                name: "Mistral 7B Instruct Q4_K_M",
                url: mistralURL,
                framework: .llamaCpp,
                memoryRequirement: 4_000_000_000
            )
        }
        if let qwenURL = URL(string: "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf") {
            RunAnywhere.registerModel(
                id: "qwen2.5-0.5b-instruct-q6_k",
                name: "Qwen 2.5 0.5B Instruct Q6_K",
                url: qwenURL,
                framework: .llamaCpp,
                memoryRequirement: 600_000_000
            )
        }
        if let lfm2Q4URL = URL(string: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf") {
            RunAnywhere.registerModel(
                id: "lfm2-350m-q4_k_m",
                name: "LiquidAI LFM2 350M Q4_K_M",
                url: lfm2Q4URL,
                framework: .llamaCpp,
                memoryRequirement: 250_000_000
            )
        }
        if let lfm2Q8URL = URL(string: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf") {
            RunAnywhere.registerModel(
                id: "lfm2-350m-q8_0",
                name: "LiquidAI LFM2 350M Q8_0",
                url: lfm2Q8URL,
                framework: .llamaCpp,
                memoryRequirement: 400_000_000
            )
        }

        // Tool Calling Optimized Models
        // LFM2-1.2B-Tool - Designed for concise and precise tool calling (Liquid AI)
        if let lfm2ToolQ4URL = URL(string: "https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q4_K_M.gguf") {
            RunAnywhere.registerModel(
                id: "lfm2-1.2b-tool-q4_k_m",
                name: "LiquidAI LFM2 1.2B Tool Q4_K_M",
                url: lfm2ToolQ4URL,
                framework: .llamaCpp,
                memoryRequirement: 800_000_000
            )
        }
        if let lfm2ToolQ8URL = URL(string: "https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q8_0.gguf") {
            RunAnywhere.registerModel(
                id: "lfm2-1.2b-tool-q8_0",
                name: "LiquidAI LFM2 1.2B Tool Q8_0",
                url: lfm2ToolQ8URL,
                framework: .llamaCpp,
                memoryRequirement: 1_400_000_000
            )
        }

        logger.info("✅ LLM models registered (including tool-calling optimized models)")

        // Register VLM (Vision Language) models
        // VLM models require 2 files: main model + mmproj (vision projector)
        // Bundled as tar.gz archives for easy download/extraction

        // SmolVLM 500M - Ultra-lightweight VLM for mobile (~500MB total)
        if let smolVLMURL = URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-vlm-models-v1/smolvlm-500m-instruct-q8_0.tar.gz") {
            RunAnywhere.registerModel(
                id: "smolvlm-500m-instruct-q8_0",
                name: "SmolVLM 500M Instruct",
                url: smolVLMURL,
                framework: .llamaCpp,
                modality: .multimodal,
                artifactType: .archive(.tarGz, structure: .directoryBased),
                memoryRequirement: 600_000_000
            )
        }
        // Qwen2-VL 2B - Small but capable VLM (~1.6GB total)
        // Uses multi-file download: main model (986MB) + mmproj (710MB)
        // Downloaded separately to avoid memory-intensive tar.gz extraction on iOS
        if let qwenMainURL = URL(string: "https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf"),
           let qwenMmprojURL = URL(string: "https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf") {
            RunAnywhere.registerMultiFileModel(
                id: "qwen2-vl-2b-instruct-q4_k_m",
                name: "Qwen2-VL 2B Instruct",
                files: [
                    ModelFileDescriptor(url: qwenMainURL, filename: "Qwen2-VL-2B-Instruct-Q4_K_M.gguf"),
                    ModelFileDescriptor(url: qwenMmprojURL, filename: "mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf")
                ],
                framework: .llamaCpp,
                modality: .multimodal,
                memoryRequirement: 1_800_000_000
            )
        }
        // LFM2-VL 450M - LiquidAI's compact VLM, ideal for mobile (~600MB total)
        // Uses multi-file download: main model + mmproj from HuggingFace
        if let lfm2MainURL = URL(string: "https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q8_0.gguf"),
           let lfm2MmprojURL = URL(string: "https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/mmproj-LFM2-VL-450M-Q8_0.gguf") {
            RunAnywhere.registerMultiFileModel(
                id: "lfm2-vl-450m-q8_0",
                name: "LFM2-VL 450M",
                files: [
                    ModelFileDescriptor(url: lfm2MainURL, filename: "LFM2-VL-450M-Q8_0.gguf"),
                    ModelFileDescriptor(url: lfm2MmprojURL, filename: "mmproj-LFM2-VL-450M-Q8_0.gguf")
                ],
                framework: .llamaCpp,
                modality: .multimodal,
                memoryRequirement: 600_000_000
            )
        }
        logger.info("✅ VLM models registered")

        // Register ONNX STT and TTS models
        // Using tar.gz format hosted on RunanywhereAI/sherpa-onnx for fast native extraction
        if let whisperURL = URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz") {
            RunAnywhere.registerModel(
                id: "sherpa-onnx-whisper-tiny.en",
                name: "Sherpa Whisper Tiny (ONNX)",
                url: whisperURL,
                framework: .onnx,
                modality: .speechRecognition,
                artifactType: .archive(.tarGz, structure: .nestedDirectory),
                memoryRequirement: 75_000_000
            )
        }
        if let piperUSURL = URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz") {
            RunAnywhere.registerModel(
                id: "vits-piper-en_US-lessac-medium",
                name: "Piper TTS (US English - Medium)",
                url: piperUSURL,
                framework: .onnx,
                modality: .speechSynthesis,
                artifactType: .archive(.tarGz, structure: .nestedDirectory),
                memoryRequirement: 65_000_000
            )
        }
        if let piperGBURL = URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz") {
            RunAnywhere.registerModel(
                id: "vits-piper-en_GB-alba-medium",
                name: "Piper TTS (British English)",
                url: piperGBURL,
                framework: .onnx,
                modality: .speechSynthesis,
                artifactType: .archive(.tarGz, structure: .nestedDirectory),
                memoryRequirement: 65_000_000
            )
        }
        logger.info("✅ ONNX STT/TTS models registered")

        // Register WhisperKit STT models (Apple Neural Engine via Core ML)
        // These run on the ANE, freeing up CPU for other tasks — ideal for background STT on iOS
        if let whisperKitTinyURL = URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v2/whisperkit-tiny.en.tar.gz") {
            RunAnywhere.registerModel(
                id: "whisperkit-tiny.en",
                name: "Whisper Tiny EN (WhisperKit)",
                url: whisperKitTinyURL,
                framework: .whisperKitCoreML,
                modality: .speechRecognition,
                artifactType: .archive(.tarGz, structure: .nestedDirectory),
                memoryRequirement: 70_000_000
            )
        }
        if let whisperKitBaseURL = URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v2/whisperkit-base.en.tar.gz") {
            RunAnywhere.registerModel(
                id: "whisperkit-base.en",
                name: "Whisper Base EN (WhisperKit)",
                url: whisperKitBaseURL,
                framework: .whisperKitCoreML,
                modality: .speechRecognition,
                artifactType: .archive(.tarGz, structure: .nestedDirectory),
                memoryRequirement: 134_000_000
            )
        }
        logger.info("✅ WhisperKit STT models registered")

        // Register Diffusion models (Apple Stable Diffusion / CoreML only; no ONNX)
        // ============================================================================
        // Apple SD 1.5 CoreML: palettized, split_einsum_v2 for Apple Silicon / ANE (~1.5GB)
        if let sd15CoreMLURL = URL(string: "https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized/resolve/main/coreml-stable-diffusion-v1-5-palettized_split_einsum_v2_compiled.zip") {
            RunAnywhere.registerModel(
                id: "sd15-coreml-palettized",
                name: "Stable Diffusion 1.5 (CoreML)",
                url: sd15CoreMLURL,
                framework: .coreml,
                modality: .imageGeneration,
                artifactType: .archive(.zip, structure: .nestedDirectory),
                memoryRequirement: 1_600_000_000  // ~1.6GB
            )
        }

        logger.info("✅ Diffusion models registered (Apple Stable Diffusion / CoreML only)")

        logger.info("🎉 All modules and models registered")
    }
}

// MARK: - Loading Views

struct InitializationLoadingView: View {
    @State private var isAnimating = false
    @State private var progress: Double = 0.0

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // RunAnywhere Logo
            Image("runanywhere_logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .scaleEffect(isAnimating ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)

            VStack(spacing: 12) {
                Text("Setting Up Your AI")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Preparing your private AI assistant...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Loading Bar
            VStack(spacing: 8) {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(AppColors.primaryAccent)
                    .frame(width: 240)

                Text("Initializing SDK...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
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
            startProgressAnimation()
        }
    }

    private func startProgressAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
            if progress < 1.0 {
                progress += 0.01
            } else {
                // Reset and start again
                progress = 0.0
            }
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
            .tint(AppColors.primaryAccent)
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
