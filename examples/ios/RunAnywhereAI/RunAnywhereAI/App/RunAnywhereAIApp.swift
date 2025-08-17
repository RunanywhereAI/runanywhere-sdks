//
//  RunAnywhereAIApp.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/21/25.
//

import SwiftUI
import RunAnywhereSDK
import UIKit
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
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                logger.warning("⚠️ Memory warning received, cleaning up cached services")
                Task {
                    await WhisperKitAdapter.shared.forceCleanup()
                }
            }
        }
    }

    private func initializeSDK() async {
        do {
            // Clear any previous error
            await MainActor.run { initializationError = nil }

            // Create configuration for the SDK
            var config = Configuration(
                apiKey: "demo-api-key", // For demo purposes
                enableRealTimeDashboard: false,
                telemetryConsent: .granted
            )

            // Configure additional settings
            config.routingPolicy = RoutingPolicy.preferDevice
            config.privacyMode = PrivacyMode.standard
            config.memoryThreshold = 2_000_000_000 // 2GB

            // Register framework adapters before initializing SDK
            RunAnywhereSDK.shared.registerFrameworkAdapter(LLMSwiftAdapter())

            // Register Foundation Models adapter for iOS 26+
            if #available(iOS 26.0, *) {
                RunAnywhereSDK.shared.registerFrameworkAdapter(FoundationModelsAdapter())
            }

            // Register voice framework adapter (now uses unified adapter with singleton)
            logger.info("🎤 Registering WhisperKitAdapter...")
            RunAnywhereSDK.shared.registerFrameworkAdapter(WhisperKitAdapter.shared)
            logger.info("✅ WhisperKitAdapter registered")

            // Register WhisperKit download strategy
            logger.info("📥 Registering WhisperKit download strategy...")
            RunAnywhereSDK.shared.registerDownloadStrategy(WhisperKitDownloadStrategy())
            logger.info("✅ WhisperKit download strategy registered")

            // Initialize the SDK
            let startTime = Date()
            logger.info("🚀 Starting SDK initialization...")
            logger.debug("📋 Configuration: API Key: \(String(config.apiKey.prefix(8)), privacy: .public)..., Routing: \(String(describing: config.routingPolicy), privacy: .public), Privacy: \(String(describing: config.privacyMode), privacy: .public)")

            try await RunAnywhereSDK.shared.initialize(configuration: config)

            let initTime = Date().timeIntervalSince(startTime)
            logger.info("✅ SDK successfully initialized!")
            logger.info("⏱️  Initialization time: \(String(format: "%.2f", initTime), privacy: .public) seconds")
            logger.info("📊 SDK Status: Ready for on-device AI inference")
            logger.info("🔧 Registered frameworks: LLMSwift, FoundationModels, WhisperKit")

            // Load and apply user settings before marking as initialized
            await loadAndApplyUserSettings()

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
            let availableModels = try await RunAnywhereSDK.shared.listAvailableModels()

            // Filter for Llama CPP compatible models first, then any model
            let llamaCppModels = availableModels.filter { $0.compatibleFrameworks.contains(.llamaCpp) && $0.localPath != nil }
            let anyDownloadedModels = availableModels.filter { $0.localPath != nil }

            // Prefer Llama CPP models, fallback to any downloaded model
            let modelToLoad = llamaCppModels.first ?? anyDownloadedModels.first

            if let model = modelToLoad {
                logger.info("✅ Found model to auto-load: \(model.name, privacy: .public) (Framework: \(model.compatibleFrameworks.first?.displayName ?? "Unknown", privacy: .public))")

                // Load the model
                try await RunAnywhereSDK.shared.loadModel(model.id)

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

    private func loadAndApplyUserSettings() async {
        logger.info("⚙️ Loading user settings from UserDefaults...")

        // Load temperature setting
        let savedTemperature = UserDefaults.standard.double(forKey: "defaultTemperature")
        let temperature = savedTemperature != 0 ? savedTemperature : 0.7

        // Load max tokens setting
        let savedMaxTokens = UserDefaults.standard.integer(forKey: "defaultMaxTokens")
        let maxTokens = savedMaxTokens != 0 ? savedMaxTokens : 10000

        // Apply settings to SDK
        await RunAnywhereSDK.shared.setTemperature(Float(temperature))
        await RunAnywhereSDK.shared.setMaxTokens(maxTokens)

        logger.info("✅ Applied user settings - Temperature: \(temperature, privacy: .public), MaxTokens: \(maxTokens, privacy: .public)")
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
        .background(Color(.systemBackground))
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
        .background(Color(.systemBackground))
    }
}
