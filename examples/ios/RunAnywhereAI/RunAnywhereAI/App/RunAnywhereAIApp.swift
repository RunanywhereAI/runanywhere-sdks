//
//  RunAnywhereAIApp.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/21/25.
//

import SwiftUI
import RunAnywhere
#if canImport(LlamaCPPRuntime)
import LlamaCPPRuntime
#endif
import MLXRuntime
#if canImport(ONNXRuntime)
import ONNXRuntime
#endif
// Deferred diffusion backend paths are excluded from the
// Swift v1 build. See `thoughts/shared/plans/curious-greeting-panda.md`.
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
    #if os(iOS)
    @StateObject private var flowSession = FlowSessionManager.shared
    @State private var showFlowActivation = false
    #endif
    @State private var isSDKInitialized = false
    @State private var initializationError: Error?
    @Environment(\.scenePhase)
    private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if isSDKInitialized {
                    ContentView()
                        #if os(iOS)
                        .environmentObject(flowSession)
                        .onOpenURL { url in
                            guard url.scheme == SharedConstants.urlScheme,
                                  url.host == "startFlow" else { return }
                            logger.info("Received startFlow deep link")
                            showFlowActivation = true
                            Task { await flowSession.handleStartFlow() }
                        }
                        .fullScreenCover(isPresented: $showFlowActivation) {
                            FlowActivationView(isPresented: $showFlowActivation)
                                .environmentObject(flowSession)
                        }
                        #endif
                        .onAppear {
                            logger.info("__RUNANYWHERE_AI_READY__")
                        }
                } else if let error = initializationError {
                    InitializationErrorView(error: error) {
                        Task { await retryInitialization() }
                    }
                } else {
                    InitializationLoadingView()
                }
            }
            .task {
                _ = SettingsViewModel.shared
                await initializeSDK()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, !isSDKInitialized, initializationError == nil else { return }
                Task {
                    _ = SettingsViewModel.shared
                    await initializeSDK()
                }
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
            #if canImport(LlamaCPPRuntime)
            LlamaCPP.register(priority: 100)
            #endif
            MLX.register(priority: 100)
            #if canImport(ONNXRuntime)
            ONNX.register(priority: 100)
            #endif

            await MainActor.run { initializationError = nil }

            let startTime = Date()
            try runSDKInitialize()
            _ = HybridDeviceState.setProvider(AppleDeviceStateProvider())
            if let hfToken = SettingsViewModel.getStoredHfToken() {
                RunAnywhere.setHfToken(hfToken)
            }

            await ModelCatalogBootstrap.registerAll()
            await refreshSDKCatalogs()

            let initTime = Date().timeIntervalSince(startTime)
            logger.info("SDK initialized in \(String(format: "%.3f", initTime * 1000), privacy: .public)ms")

            await MainActor.run { isSDKInitialized = true }
        } catch {
            logger.error("SDK initialization failed: \(error, privacy: .public)")
            await MainActor.run { initializationError = error }
        }
    }

    /// Initializes the SDK with either custom credentials (from Settings) or
    /// build-configuration-driven defaults. Release builds without credentials fail loud.
    private func runSDKInitialize() throws {
        if let credentials = storedCredentials() ?? bundledCredentials() {
            try RunAnywhere.initialize(
                apiKey: credentials.apiKey,
                baseURL: credentials.baseURL,
                environment: .production
            )
        } else {
            #if DEBUG
            try RunAnywhere.initialize()
            #else
            fatalError(
                "Release builds require RUNANYWHERE_API_KEY and RUNANYWHERE_BASE_URL via xcconfig or Settings; " +
                "set in Settings.bundle or .xcconfig before shipping."
            )
            #endif
        }
    }

    private func storedCredentials() -> (apiKey: String, baseURL: String)? {
        credentials(
            apiKey: SettingsViewModel.getStoredApiKey(),
            baseURL: SettingsViewModel.getStoredBaseURL()
        )
    }

    private func bundledCredentials() -> (apiKey: String, baseURL: String)? {
        if let localSecrets = localSecretsPlist(),
           let credentials = credentials(
               apiKey: localSecrets["apiKey"],
               baseURL: localSecrets["baseURL"]
           ) {
            return credentials
        }

        return credentials(
            apiKey: Bundle.main.object(forInfoDictionaryKey: "RUNANYWHERE_API_KEY") as? String,
            baseURL: Bundle.main.object(forInfoDictionaryKey: "RUNANYWHERE_BASE_URL") as? String
        )
    }

    private func localSecretsPlist() -> [String: String]? {
        guard let url = Bundle.main.url(forResource: "RunAnywhereLocalSecrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = object as? [String: String] else {
            return nil
        }
        return dictionary
    }

    private func credentials(apiKey: String?, baseURL: String?) -> (apiKey: String, baseURL: String)? {
        guard let apiKey = sanitizedConfigValue(apiKey),
              let baseURL = sanitizedConfigValue(baseURL),
              isUsableHTTPURL(baseURL) else {
            return nil
        }
        return (apiKey, baseURL)
    }

    private func sanitizedConfigValue(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, !looksLikePlaceholder(trimmed) else { return nil }
        return trimmed
    }

    private func looksLikePlaceholder(_ value: String) -> Bool {
        value.range(
            of: "YOUR_|<your|REPLACE_ME|PLACEHOLDER|\\$\\(",
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
        await MainActor.run { initializationError = nil }
        await initializeSDK()
    }

    @MainActor
    private func refreshSDKCatalogs() async {
        logger.info("Refreshing SDK model registry...")

        await RunAnywhere.refreshModelRegistry()

        let listResult = await RunAnywhere.listModels()
        if listResult.success {
            let models = listResult.models.models
            let downloaded = models.filter(\.isDownloaded).count
            let available = models.filter(\.isAvailableForUse).count
            logger.info(
                "Model registry: registered=\(models.count), downloaded=\(downloaded), available=\(available)"
            )
        } else {
            let message = listResult.errorMessage.isEmpty ? "unknown error" : listResult.errorMessage
            logger.warning("Model registry refresh incomplete: \(message, privacy: .public)")
        }

        do {
            let adapters = try await RunAnywhere.lora.allRegistered()
            logger.info("LoRA registry: \(adapters.count) entries")
        } catch {
            logger.warning("LoRA catalog unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }
}
