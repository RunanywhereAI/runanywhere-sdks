//
//  SettingsViewModel.swift
//  RunAnywhereAI
//
//  Centralized ViewModel for all Settings functionality
//  Follows MVVM pattern - all business logic is here
//

import Foundation
import SwiftUI
import RunAnywhere
import Combine
import os

@MainActor
class SettingsViewModel: ObservableObject {
    // MARK: - Published Properties

    // Generation Settings
    @Published var temperature: Double = 0.7
    @Published var maxTokens: Int = 10000
    @Published var systemPrompt: String = "You are a helpful, concise AI assistant."
    @Published var thinkingModeEnabled: Bool = false
    @Published private(set) var loadedModelSupportsThinking: Bool = false

    // API Configuration
    @Published var apiKey: String = ""
    @Published var baseURL: String = ""
    @Published var isApiKeyConfigured: Bool = false
    @Published var isBaseURLConfigured: Bool = false

    // Private model downloads
    @Published var hfToken: String = ""
    @Published var isHfTokenConfigured: Bool = false
    @Published var isSavingHfToken: Bool = false
    @Published var hfTokenMessage: String?
    @Published var hfTokenMessageIsError: Bool = false

    // Logging Configuration
    @Published var analyticsLogToLocal: Bool = false

    // Storage Overview
    @Published var totalStorageSize: Int64 = 0
    @Published var availableSpace: Int64 = 0
    @Published var modelStorageSize: Int64 = 0
    @Published var storedModels: [RAModelStorageMetrics] = []

    // UI State
    @Published var showApiKeyEntry: Bool = false
    @Published var isLoadingStorage: Bool = false
    @Published var errorMessage: String?
    @Published var showRestartAlert: Bool = false

    // MARK: - Private Properties

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "Settings")
    private var cancellables = Set<AnyCancellable>()
    private let keychainService = KeychainService.shared
    private let apiKeyStorageKey = "runanywhere_api_key"
    private let baseURLStorageKey = "runanywhere_base_url"
    private let hfTokenStorageKey = "runanywhere_hf_token"
    private let temperatureDefaultsKey = "defaultTemperature"
    private let maxTokensDefaultsKey = "defaultMaxTokens"
    private let systemPromptDefaultsKey = "defaultSystemPrompt"
    private let thinkingModeKey = "thinkingModeEnabled"
    private let analyticsLogKey = "analyticsLogToLocal"
    private let deviceRegisteredKey = "com.runanywhere.sdk.deviceRegistered"

    // MARK: - Static helpers for app initialization
    static let shared = SettingsViewModel()

    /// Get stored API key (for use at app launch)
    static func getStoredApiKey() -> String? {
        guard let data = try? KeychainService.shared.retrieve(key: "runanywhere_api_key"),
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Get stored base URL (for use at app launch)
    /// Automatically adds https:// if no scheme is present
    static func getStoredBaseURL() -> String? {
        guard let data = try? KeychainService.shared.retrieve(key: "runanywhere_base_url"),
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        // Normalize URL by adding https:// if no scheme present
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    /// Get stored Hugging Face token (for private model downloads at launch)
    nonisolated static func getStoredHfToken() -> String? {
        guard let data = try? KeychainService.shared.retrieve(key: "runanywhere_hf_token"),
              let value = String(data: data, encoding: .utf8),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Check if custom configuration is set
    static var hasCustomConfiguration: Bool {
        getStoredApiKey() != nil && getStoredBaseURL() != nil
    }

    // MARK: - Initialization

    init() {
        loadSettings()
        setupObservers()
        subscribeToModelNotifications()
    }

    private func subscribeToModelNotifications() {
        // The SDK's typed lifecycle stream covers every LLM load source
        // (chat, voice agent, RAG) with one subscription.
        RunAnywhere.events.modelLifecycle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                Task { @MainActor in
                    self?.handleModelLifecycle(change)
                }
            }
            .store(in: &cancellables)
    }

    private func handleModelLifecycle(_ change: RAModelLifecycleChange) {
        guard change.component == .llm || change.event.category == .llm else { return }

        switch change.kind {
        case .loaded:
            if let model = ModelListViewModel.shared.availableModels.first(where: { $0.id == change.modelID }) {
                loadedModelSupportsThinking = model.supportsThinking
                logger.info("LLM loaded (\(change.modelID)), supportsThinking: \(model.supportsThinking)")
            } else {
                loadedModelSupportsThinking = false
                logger.warning("LLM loaded (\(change.modelID)), but it was not found in the registry")
            }
        case .unloaded:
            loadedModelSupportsThinking = false
            logger.info("LLM unloaded, thinking mode disabled")
        }
    }

    // MARK: - Setup

    private func setupObservers() {
        // Auto-save temperature changes
        $temperature
            .debounce(for: 0.5, scheduler: DispatchQueue.main)
            .dropFirst() // Skip initial value to avoid saving on init
            .sink { [weak self] newValue in
                self?.saveTemperature(newValue)
            }
            .store(in: &cancellables)

        // Auto-save max tokens changes
        $maxTokens
            .debounce(for: 0.5, scheduler: DispatchQueue.main)
            .dropFirst() // Skip initial value to avoid saving on init
            .sink { [weak self] newValue in
                self?.saveMaxTokens(newValue)
            }
            .store(in: &cancellables)

        // Auto-save system prompt changes
        $systemPrompt
            .debounce(for: 0.5, scheduler: DispatchQueue.main)
            .dropFirst() // Skip initial value to avoid saving on init
            .sink { [weak self] newValue in
                self?.saveSystemPrompt(newValue)
            }
            .store(in: &cancellables)

        // Auto-save thinking mode preference
        $thinkingModeEnabled
            .dropFirst()
            .sink { [weak self] newValue in
                self?.saveThinkingModePreference(newValue)
            }
            .store(in: &cancellables)

        // Auto-save analytics logging preference
        $analyticsLogToLocal
            .dropFirst() // Skip initial value to avoid saving on init
            .sink { [weak self] newValue in
                self?.saveAnalyticsLogPreference(newValue)
            }
            .store(in: &cancellables)
    }

    // MARK: - Settings Management

    /// Load all settings from storage
    func loadSettings() {
        loadGenerationSettings()
        loadApiKeyConfiguration()
        loadHfTokenConfiguration()
        loadLoggingConfiguration()
    }

    private func loadGenerationSettings() {
        // Load temperature — use object(forKey:) to distinguish unset (nil) from explicit 0.0
        let savedTemperature = UserDefaults.standard.object(forKey: temperatureDefaultsKey) as? Double
        temperature = savedTemperature ?? 0.7

        // Load max tokens
        let savedMaxTokens = UserDefaults.standard.integer(forKey: maxTokensDefaultsKey)
        maxTokens = savedMaxTokens > 0 ? savedMaxTokens : 10000

        // Load system prompt — fall back to the default when the key has never been set
        let defaultPrompt = "You are a helpful, concise AI assistant."
        systemPrompt = UserDefaults.standard.string(forKey: systemPromptDefaultsKey) ?? defaultPrompt
        // Persist the default so that other ViewModels reading UserDefaults directly always find a value
        if UserDefaults.standard.string(forKey: systemPromptDefaultsKey) == nil {
            UserDefaults.standard.set(systemPrompt, forKey: systemPromptDefaultsKey)
        }

        // Load thinking mode
        thinkingModeEnabled = UserDefaults.standard.bool(forKey: thinkingModeKey)
    }

    private func loadApiKeyConfiguration() {
        // Load API key from keychain
        if let apiKeyData = try? keychainService.retrieve(key: apiKeyStorageKey),
           let savedApiKey = String(data: apiKeyData, encoding: .utf8),
           !savedApiKey.isEmpty {
            apiKey = savedApiKey
            isApiKeyConfigured = true
        } else {
            apiKey = ""
            isApiKeyConfigured = false
        }

        // Load Base URL from keychain
        if let baseURLData = try? keychainService.retrieve(key: baseURLStorageKey),
           let savedBaseURL = String(data: baseURLData, encoding: .utf8),
           !savedBaseURL.isEmpty {
            baseURL = savedBaseURL
            isBaseURLConfigured = true
        } else {
            baseURL = ""
            isBaseURLConfigured = false
        }
    }

    private func loadHfTokenConfiguration() {
        if let tokenData = try? keychainService.retrieve(key: hfTokenStorageKey),
           let savedToken = String(data: tokenData, encoding: .utf8),
           !savedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hfToken = savedToken
            isHfTokenConfigured = true
        } else {
            hfToken = ""
            isHfTokenConfigured = false
        }
    }

    private func loadLoggingConfiguration() {
        analyticsLogToLocal = keychainService.loadBool(key: analyticsLogKey, defaultValue: false)
    }

    // MARK: - Generation Settings

    private func saveTemperature(_ value: Double) {
        UserDefaults.standard.set(value, forKey: temperatureDefaultsKey)
        print("Settings: Saved temperature: \(value)")
    }

    private func saveMaxTokens(_ value: Int) {
        UserDefaults.standard.set(value, forKey: maxTokensDefaultsKey)
        print("Settings: Saved max tokens: \(value)")
    }

    private func saveSystemPrompt(_ value: String) {
        UserDefaults.standard.set(value, forKey: systemPromptDefaultsKey)
        print("Settings: Saved system prompt (\(value.count) chars)")
    }

    private func saveThinkingModePreference(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: thinkingModeKey)
        print("Settings: Thinking mode set to: \(value)")
    }

    /// Get current generation configuration for SDK usage
    func getGenerationConfiguration() -> GenerationConfiguration {
        GenerationConfiguration(
            temperature: temperature,
            maxTokens: maxTokens,
            systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt,
            thinkingModeEnabled: thinkingModeEnabled
        )
    }

    // MARK: - API Configuration Management

    /// Normalize base URL by adding https:// if no scheme is present
    private func normalizeBaseURL(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return trimmed
        }

        // Check if URL already has a scheme
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }

        // Add https:// prefix
        return "https://\(trimmed)"
    }

    /// Save API key and Base URL to secure storage
    func saveApiConfiguration() {
        var hasError = false

        // Save API key if provided
        if !apiKey.isEmpty {
            if let apiKeyData = apiKey.data(using: .utf8) {
                do {
                    try keychainService.save(key: apiKeyStorageKey, data: apiKeyData)
                    isApiKeyConfigured = true
                    print("Settings: API key saved successfully")
                } catch {
                    errorMessage = "Failed to save API key: \(error.localizedDescription)"
                    hasError = true
                }
            }
        }

        // Save Base URL if provided (normalize to add https:// if missing)
        if !baseURL.isEmpty {
            let normalizedURL = normalizeBaseURL(baseURL)
            baseURL = normalizedURL  // Update the displayed value too

            if let baseURLData = normalizedURL.data(using: .utf8) {
                do {
                    try keychainService.save(key: baseURLStorageKey, data: baseURLData)
                    isBaseURLConfigured = true
                    print("Settings: Base URL saved successfully: \(normalizedURL)")
                } catch {
                    errorMessage = "Failed to save Base URL: \(error.localizedDescription)"
                    hasError = true
                }
            }
        }

        if !hasError {
            showApiKeyEntry = false
            errorMessage = nil
            // Show restart alert
            showRestartAlert = true
        }
    }

    /// Delete API configuration from secure storage
    func clearApiConfiguration() {
        do {
            try keychainService.delete(key: apiKeyStorageKey)
            try keychainService.delete(key: baseURLStorageKey)
            apiKey = ""
            baseURL = ""
            isApiKeyConfigured = false
            isBaseURLConfigured = false
            errorMessage = nil

            // Also clear device registration so it re-registers with new config
            clearDeviceRegistration()

            print("Settings: API configuration cleared successfully")
            showRestartAlert = true
        } catch {
            errorMessage = "Failed to clear API configuration: \(error.localizedDescription)"
        }
    }

    /// Clear device registration status (forces re-registration on next launch)
    func clearDeviceRegistration() {
        UserDefaults.standard.removeObject(forKey: deviceRegisteredKey)
        print("Settings: Device registration cleared - will re-register on next launch")
    }

    /// Show the API configuration sheet
    func showApiKeySheet() {
        showApiKeyEntry = true
    }

    /// Cancel API key entry
    func cancelApiKeyEntry() {
        // Reload the saved configuration if canceling
        loadApiKeyConfiguration()
        showApiKeyEntry = false
    }

    /// Check if API configuration is complete (both key and URL set)
    var isApiConfigurationComplete: Bool {
        isApiKeyConfigured && isBaseURLConfigured
    }

    // MARK: - Private Download Configuration

    func saveHfToken() {
        let trimmed = hfToken.trimmingCharacters(in: .whitespacesAndNewlines)
        isSavingHfToken = true
        hfTokenMessage = nil
        hfTokenMessageIsError = false

        do {
            if trimmed.isEmpty {
                try keychainService.delete(key: hfTokenStorageKey)
                hfToken = ""
                isHfTokenConfigured = false
                RunAnywhere.setHfToken("")
                hfTokenMessage = "Hugging Face token cleared"
            } else if let tokenData = trimmed.data(using: .utf8) {
                try keychainService.save(key: hfTokenStorageKey, data: tokenData)
                hfToken = trimmed
                isHfTokenConfigured = true
                RunAnywhere.setHfToken(trimmed)
                hfTokenMessage = "Hugging Face token saved"
            }

            Task {
                await ModelListViewModel.shared.loadModelsFromRegistry()
            }
        } catch {
            hfTokenMessage = trimmed.isEmpty
                ? "Could not clear Hugging Face token"
                : "Could not save Hugging Face token"
            hfTokenMessageIsError = true
        }

        isSavingHfToken = false
    }

    func clearHfToken() {
        hfToken = ""
        saveHfToken()
    }

    // MARK: - Logging Configuration

    private func saveAnalyticsLogPreference(_ value: Bool) {
        try? keychainService.saveBool(key: analyticsLogKey, value: value)
        print("Settings: Analytics logging set to: \(value)")
    }

    // MARK: - Storage Management

    // Storage state and SDK storage calls live in StorageViewModel.shared
    // (single owner); the Settings section just projects its state.

    /// Load storage information
    func loadStorageData() async {
        isLoadingStorage = true
        errorMessage = nil

        let storage = StorageViewModel.shared
        await storage.loadData()
        if let storageError = storage.errorMessage {
            errorMessage = storageError
        } else {
            totalStorageSize = storage.totalStorageSize
            availableSpace = storage.availableSpace
            modelStorageSize = storage.modelStorageSize
            storedModels = storage.storedModels
        }

        isLoadingStorage = false
    }

    /// Refresh storage information
    func refreshStorageData() async {
        await loadStorageData()
    }

    /// Clear cache
    func clearCache() async {
        await StorageViewModel.shared.clearCache()
        await loadStorageData()
    }

    /// Clean temporary files
    func cleanTempFiles() async {
        await StorageViewModel.shared.cleanTempFiles()
        await loadStorageData()
    }

    /// Delete a stored model
    func deleteModel(_ model: RAModelStorageMetrics) async {
        await StorageViewModel.shared.deleteModel(model)
        await loadStorageData()
    }

    // MARK: - Helper Methods

    /// Format bytes to human-readable string
    func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Format bytes to memory string
    func formatMemory(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    /// Check if storage data is available
    var hasStorageData: Bool {
        totalStorageSize > 0
    }

    /// Get storage usage percentage
    var storageUsagePercentage: Double {
        guard availableSpace > 0 else { return 0 }
        let totalDevice = totalStorageSize + availableSpace
        return Double(totalStorageSize) / Double(totalDevice)
    }
}

// MARK: - Supporting Types

struct GenerationConfiguration {
    let temperature: Double
    let maxTokens: Int
    let systemPrompt: String?
    let thinkingModeEnabled: Bool
}
