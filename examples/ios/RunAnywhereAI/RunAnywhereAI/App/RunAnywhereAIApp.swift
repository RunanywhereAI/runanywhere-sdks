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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(modelManager)
                .task {
                    // Initialize SDK and bundled models on app launch
                    await initializeSDK()
                    await initializeBundledModels()
                }
        }
    }

    private func initializeSDK() async {
        do {
            // Create configuration for the SDK
            var config = Configuration(
                apiKey: "demo-api-key", // For demo purposes
                enableRealTimeDashboard: false,
                telemetryConsent: .denied
            )

            // Configure additional settings
            config.routingPolicy = .preferDevice
            config.privacyMode = .standard
            config.memoryThreshold = 2_000_000_000 // 2GB

            // Register framework adapters before initializing SDK
            RunAnywhereSDK.shared.registerFrameworkAdapter(LLMSwiftAdapter())
            RunAnywhereSDK.shared.registerFrameworkAdapter(FoundationModelsAdapter())

            // Initialize the SDK
            try await RunAnywhereSDK.shared.initialize(configuration: config)
            print("SDK initialized successfully")
        } catch {
            print("Failed to initialize SDK: \(error)")
        }
    }

    private func initializeBundledModels() async {
        // Bundled models functionality removed - models are downloaded on demand
    }
}
