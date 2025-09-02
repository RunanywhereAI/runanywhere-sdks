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

            // Register framework adapters before initializing SDK
            RunAnywhere.registerFrameworkAdapter(LLMSwiftAdapter())

            // Register Foundation Models adapter for iOS 26+ and macOS 26+
            if #available(iOS 26.0, macOS 26.0, *) {
                RunAnywhere.registerFrameworkAdapter(FoundationModelsAdapter())
            }

            // Register voice framework adapter (self-contained with models and download strategy)
            logger.info("🎤 Registering self-contained WhisperKitAdapter...")
            RunAnywhere.registerFrameworkAdapter(WhisperKitAdapter.shared)
            logger.info("✅ WhisperKitAdapter registered with models and download strategy")

            // Initialize the SDK with just API key
            let startTime = Date()
            logger.info("🚀 Starting SDK initialization...")
            logger.debug("📋 Configuration: API Key: demo-api-key...")

            try await RunAnywhere.initialize(
                apiKey: "demo-api-key",
                baseURL: "https://api.runanywhere.ai",
                environment: .development
            )

            let initTime = Date().timeIntervalSince(startTime)
            logger.info("✅ SDK successfully initialized!")
            logger.info("⏱️  Initialization time: \(String(format: "%.2f", initTime), privacy: .public) seconds")
            logger.info("📊 SDK Status: Ready for on-device AI inference")
            logger.info("🔧 Registered frameworks: LLMSwift, FoundationModels, WhisperKit (self-contained)")

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
