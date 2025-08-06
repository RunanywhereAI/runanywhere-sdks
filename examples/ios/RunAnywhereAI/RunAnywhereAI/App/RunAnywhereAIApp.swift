//
//  RunAnywhereAIApp.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/21/25.
//

import SwiftUI
import RunAnywhereSDK

@main
struct RunAnywhereAIApp: App {
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
                            print("🎉 RunAnywhereAI: App is ready to use!")
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
                print("🏁 RunAnywhereAI: App launched, initializing SDK...")
                await initializeSDK()
                await initializeBundledModels()
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
            RunAnywhereSDK.shared.registerFrameworkAdapter(FoundationModelsAdapter())

            // Initialize the SDK
            let startTime = Date()
            print("🚀 RunAnywhereSDK: Starting initialization...")
            print("📋 Configuration: API Key: \(config.apiKey.prefix(8))..., Routing: \(config.routingPolicy), Privacy: \(config.privacyMode)")

            try await RunAnywhereSDK.shared.initialize(configuration: config)

            let initTime = Date().timeIntervalSince(startTime)
            print("✅ RunAnywhereSDK: Successfully initialized!")
            print("⏱️  Initialization time: \(String(format: "%.2f", initTime)) seconds")
            print("📊 SDK Status: Ready for on-device AI inference")
            print("🔧 Registered frameworks: LLMSwift, FoundationModels")

            // Mark as initialized
            await MainActor.run {
                isSDKInitialized = true
            }
        } catch {
            print("❌ RunAnywhereSDK: Initialization failed!")
            print("🔍 Error: \(error)")
            print("💡 Tip: Check your API key and network connection")
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
