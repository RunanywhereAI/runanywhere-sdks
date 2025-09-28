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
                await initializeBundledModels()
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
                try RunAnywhere.initialize(
                    apiKey: "dev",  // Any string works
                    baseURL: "localhost",  // Not used in dev mode
                    environment: .development
                )
                logger.info("✅ SDK initialized in DEVELOPMENT mode")

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

            // Auto-load first available model
            await autoLoadFirstModel()
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
        await initializeBundledModels()
    }

    private func registerAdaptersForDevelopment() async {
        logger.info("📦 Registering adapters with custom models for DEVELOPMENT mode")

        do {
            // Register LLMSwift with custom GGUF models
            LLMSwiftServiceProvider.register()
            try await RunAnywhere.registerFrameworkAdapter(
                LLMSwiftAdapter(),
                models: [
                    // Small, fast model for quick testing
                    try! ModelRegistration(
                        url: "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
                        framework: .llamaCpp,
                        id: "tinyllama-1b",
                        name: "TinyLlama 1.1B Chat"
                    ),
                    // Medium model for better quality
                    try! ModelRegistration(
                        url: "https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf",
                        framework: .llamaCpp,
                        id: "llama2-7b-chat",
                        name: "Llama 2 7B Chat"
                    ),
                    // Code generation model
                    try! ModelRegistration(
                        url: "https://huggingface.co/TheBloke/CodeLlama-7B-Instruct-GGUF/resolve/main/codellama-7b-instruct.Q4_K_M.gguf",
                        framework: .llamaCpp,
                        id: "codellama-7b",
                        name: "CodeLlama 7B Instruct"
                    )
                ],
                options: .development  // Auto-download, show progress, etc.
            )
            logger.info("✅ LLMSwift registered with custom models")

            // Register WhisperKit with custom models
            WhisperKitServiceProvider.register()
            try await RunAnywhere.registerFrameworkAdapter(
                WhisperKitAdapter.shared,
                models: [
                    // Whisper models for speech-to-text
                    try! ModelRegistration(
                        url: "https://huggingface.co/openai/whisper-base/resolve/main/pytorch_model.bin",
                        framework: .whisperKit,
                        id: "whisper-base",
                        name: "Whisper Base"
                    ),
                    try! ModelRegistration(
                        url: "https://huggingface.co/openai/whisper-small/resolve/main/pytorch_model.bin",
                        framework: .whisperKit,
                        id: "whisper-small",
                        name: "Whisper Small"
                    )
                ],
                options: .development
            )
            logger.info("✅ WhisperKit registered with custom models")

            // Register FluidAudioDiarization
            FluidAudioDiarizationProvider.register()
            logger.info("✅ FluidAudioDiarization registered")

            // Register Foundation Models adapter for iOS 26+ and macOS 26+
            if #available(iOS 26.0, macOS 26.0, *) {
                try await RunAnywhere.registerFrameworkAdapter(FoundationModelsAdapter())
                logger.info("✅ Foundation Models registered")
            }

            logger.info("🎉 All adapters registered with custom models for development")

        } catch {
            logger.error("❌ Failed to register adapters: \(error)")
        }
    }

    private func registerAdaptersForProduction() async {
        logger.info("📦 Registering adapters for PRODUCTION mode")

        // Register WhisperKit for Speech-to-Text
        WhisperKitServiceProvider.register()
        do {
            try await RunAnywhere.registerFrameworkAdapter(WhisperKitAdapter.shared)
            logger.info("✅ WhisperKit registered")
        } catch {
            logger.error("Failed to register WhisperKit: \(error)")
        }

        // Register LLMSwift for Language Models
        LLMSwiftServiceProvider.register()
        do {
            try await RunAnywhere.registerFrameworkAdapter(LLMSwiftAdapter())
            logger.info("✅ LLMSwift registered")
        } catch {
            logger.error("Failed to register LLMSwift: \(error)")
        }

        // Register FluidAudioDiarization
        FluidAudioDiarizationProvider.register()
        logger.info("✅ FluidAudioDiarization registered")

        // Register Foundation Models adapter for iOS 26+ and macOS 26+
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                try await RunAnywhere.registerFrameworkAdapter(FoundationModelsAdapter())
                logger.info("✅ Foundation Models registered")
            } catch {
                logger.error("Failed to register Foundation Models: \(error)")
            }
        }

        logger.info("🎉 All adapters registered for production")
    }

    private func initializeBundledModels() async {
        // Bundled models functionality removed - models are downloaded on demand
    }

    private func autoLoadFirstModel() async {
        logger.info("🤖 Auto-loading first available model...")

        do {
            // Get available models from SDK
            let availableModels = try await RunAnywhere.availableModels()

            // Filter for Llama CPP compatible models first, then any model
            let llamaCppModels = availableModels.filter { $0.compatibleFrameworks.contains(.llamaCpp) && $0.localPath != nil }
            let anyDownloadedModels = availableModels.filter { $0.localPath != nil }

            // Prefer Llama CPP models, fallback to any downloaded model
            let modelToLoad = llamaCppModels.first ?? anyDownloadedModels.first

            if let model = modelToLoad {
                logger.info("✅ Found model to auto-load: \(model.name, privacy: .public) (Framework: \(model.compatibleFrameworks.first?.displayName ?? "Unknown", privacy: .public))")

                // Load the model
                _ = try await RunAnywhere.loadModel(model.id)

                logger.info("🎉 Successfully auto-loaded model: \(model.name, privacy: .public)")

                // Update ModelListViewModel to reflect the loaded model
                await ModelListViewModel.shared.setCurrentModel(model)

                // Notify the app that a model was loaded
                NotificationCenter.default.post(name: Notification.Name("ModelLoaded"), object: model)

            } else {
                logger.info("ℹ️ No downloaded models available for auto-loading")
                logger.info("💡 User will need to download and select a model manually")
            }

        } catch {
            logger.warning("⚠️ Failed to auto-load model: \(error, privacy: .public)")
            logger.info("💡 User will need to select a model manually")
        }
    }

    // User settings are now stored locally and applied per-request
    // This method is no longer needed with the new event-based architecture
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
