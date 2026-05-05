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
#if canImport(MetalRTRuntime)
import MetalRTRuntime
#endif
#if canImport(UIKit)
import UIKit
#endif
import os
#if os(macOS)
import AppKit
#endif

// swiftlint:disable type_body_length
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
                _ = SettingsViewModel.shared
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
            #if canImport(MetalRTRuntime)
            MetalRT.register(priority: 100)
            #endif

            // Clear any previous error
            await MainActor.run { initializationError = nil }

            logger.info("🎯 Initializing SDK...")

            let startTime = Date()

            try runSDKInitialize()

            // Refresh generated model/catalog state.
            await refreshSDKCatalogs()

            let initTime = Date().timeIntervalSince(startTime)
            logger.info("✅ SDK successfully initialized!")
            logger.info("⚡ Initialization time: \(String(format: "%.3f", initTime * 1000), privacy: .public)ms")
            logger.info("🎯 SDK Status: \(RunAnywhere.isActive ? "Active" : "Inactive")")
            logger.info("🔧 Environment: \(RunAnywhere.environment?.description ?? "Unknown")")
            logger.info("📱 Services initialized for catalog refresh")

            // Mark as initialized
            await MainActor.run {
                isSDKInitialized = true
            }

            logger.info("💡 Model registry refreshed, user can now download and select models")
        } catch {
            logger.error("❌ SDK initialization failed: \(error, privacy: .public)")
            await MainActor.run {
                initializationError = error
            }
        }
    }

    /// Runs `RunAnywhere.initialize(...)` with either custom credentials
    /// (from Settings) or a default build-configuration-driven mode.
    private func runSDKInitialize() throws {
        // Check for custom API configuration (stored in Settings)
        let customApiKey = SettingsViewModel.getStoredApiKey()
        let customBaseURL = SettingsViewModel.getStoredBaseURL()

        if let apiKey = customApiKey,
           let baseURL = customBaseURL,
           !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !looksLikePlaceholder(apiKey),
           isUsableHTTPURL(baseURL) {
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
            // Release builds must be configured before launch — either via
            // the in-app Settings screen (which writes to Settings.bundle and
            // is read back via SettingsViewModel.getStoredApiKey()/getStoredBaseURL())
            // or via an .xcconfig that injects RUNANYWHERE_API_KEY /
            // RUNANYWHERE_BASE_URL at build time. We deliberately fail loud
            // here so a release build never silently runs against placeholder
            // credentials.
            fatalError("Release builds require RUNANYWHERE_API_KEY and RUNANYWHERE_BASE_URL via xcconfig or Settings; set in Settings.bundle or .xcconfig before shipping.")
            #endif
        }
    }

    private func looksLikePlaceholder(_ value: String) -> Bool {
        value.range(
            of: "YOUR_|<your|REPLACE_ME|PLACEHOLDER",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private func isUsableHTTPURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !looksLikePlaceholder(trimmed),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host,
              !host.isEmpty,
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !host.contains("<"),
              !host.contains(">") else {
            return false
        }
        return true
    }

    private func retryInitialization() async {
        await MainActor.run {
            initializationError = nil
        }
        await initializeSDK()
    }

    @MainActor private func refreshSDKCatalogs() async {
        logger.info("Refreshing SDK model registry...")

        let listResult = await RunAnywhere.listModels()
        if listResult.success {
            let models = listResult.models.models
            let downloaded = models.filter(\.isDownloaded).count
            let available = models.filter(\.isAvailableForUse).count
            logger.info(
                "Model registry refreshed: registered=\(models.count), downloaded=\(downloaded), available=\(available)"
            )
        } else {
            let message = listResult.errorMessage.isEmpty ? "unknown error" : listResult.errorMessage
            logger.warning("Model registry refresh did not complete: \(message, privacy: .public)")
        }

        logger.info("SDK registry now exposes \(listResult.models.models.count) models")

        do {
            let adapters = try await RunAnywhere.lora.allRegistered()
            logger.info("LoRA registry exposes \(adapters.count) adapter entries")
        } catch {
            logger.warning("LoRA catalog list unavailable: \(error.localizedDescription, privacy: .public)")
        }

        logger.info("SDK catalog refresh complete")
    }
}
// swiftlint:enable type_body_length

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
        Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
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
