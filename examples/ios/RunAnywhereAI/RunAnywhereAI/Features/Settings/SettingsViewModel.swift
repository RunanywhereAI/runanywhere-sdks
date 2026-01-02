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

@MainActor
class SettingsViewModel: ObservableObject {
    // MARK: - Published Properties

    // Generation Settings
    @Published var temperature: Double = 0.7
    @Published var maxTokens: Int = 10000

    // API Configuration
    @Published var apiKey: String = ""
    @Published var isApiKeyConfigured: Bool = false

    // Logging Configuration
    @Published var analyticsLogToLocal: Bool = false

    // Storage Overview
    @Published var totalStorageSize: Int64 = 0
    @Published var availableSpace: Int64 = 0
    @Published var modelStorageSize: Int64 = 0
    @Published var storedModels: [StoredModel] = []

    // UI State
    @Published var showApiKeyEntry: Bool = false
    @Published var isLoadingStorage: Bool = false
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private let keychainService = KeychainService.shared
    private let apiKeyStorageKey = "runanywhere_api_key"
    private let temperatureDefaultsKey = "defaultTemperature"
    private let maxTokensDefaultsKey = "defaultMaxTokens"
    private let analyticsLogKey = "analyticsLogToLocal"

    // MARK: - Initialization

    init() {
        loadSettings()
        setupObservers()
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
        loadLoggingConfiguration()
    }

    private func loadGenerationSettings() {
        // Load temperature
        let savedTemperature = UserDefaults.standard.double(forKey: temperatureDefaultsKey)
        temperature = savedTemperature > 0 ? savedTemperature : 0.7

        // Load max tokens
        let savedMaxTokens = UserDefaults.standard.integer(forKey: maxTokensDefaultsKey)
        maxTokens = savedMaxTokens > 0 ? savedMaxTokens : 10000
    }

    private func loadApiKeyConfiguration() {
        // Load API key from keychain
        if let apiKeyData = try? keychainService.retrieve(key: apiKeyStorageKey),
           let savedApiKey = String(data: apiKeyData, encoding: .utf8) {
            apiKey = savedApiKey
            isApiKeyConfigured = true
        } else {
            apiKey = ""
            isApiKeyConfigured = false
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

    /// Get current generation configuration for SDK usage
    func getGenerationConfiguration() -> GenerationConfiguration {
        GenerationConfiguration(
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    // MARK: - API Key Management

    /// Save API key to secure storage
    func saveApiKey() {
        guard !apiKey.isEmpty else {
            errorMessage = "API key cannot be empty"
            return
        }

        if let apiKeyData = apiKey.data(using: .utf8) {
            do {
                try keychainService.save(key: apiKeyStorageKey, data: apiKeyData)
                isApiKeyConfigured = true
                showApiKeyEntry = false
                errorMessage = nil
                print("Settings: API key saved successfully")
            } catch {
                errorMessage = "Failed to save API key: \(error.localizedDescription)"
            }
        }
    }

    /// Delete API key from secure storage
    func deleteApiKey() {
        do {
            try keychainService.delete(key: apiKeyStorageKey)
            apiKey = ""
            isApiKeyConfigured = false
            errorMessage = nil
            print("Settings: API key deleted successfully")
        } catch {
            errorMessage = "Failed to delete API key: \(error.localizedDescription)"
        }
    }

    /// Show the API key entry sheet
    func showApiKeySheet() {
        showApiKeyEntry = true
    }

    /// Cancel API key entry
    func cancelApiKeyEntry() {
        // Reload the saved API key if canceling
        loadApiKeyConfiguration()
        showApiKeyEntry = false
    }

    // MARK: - Logging Configuration

    private func saveAnalyticsLogPreference(_ value: Bool) {
        try? keychainService.saveBool(key: analyticsLogKey, value: value)
        print("Settings: Analytics logging set to: \(value)")
    }

    // MARK: - Storage Management

    /// Load storage information
    func loadStorageData() async {
        isLoadingStorage = true
        errorMessage = nil

        do {
            let storageInfo = await RunAnywhere.getStorageInfo()

            totalStorageSize = storageInfo.appStorage.totalSize
            availableSpace = storageInfo.deviceStorage.freeSpace
            modelStorageSize = storageInfo.totalModelsSize
            storedModels = storageInfo.storedModels

            print("Settings: Loaded storage data - Total: \(totalStorageSize), Available: \(availableSpace)")
        } catch {
            errorMessage = "Failed to load storage data: \(error.localizedDescription)"
        }

        isLoadingStorage = false
    }

    /// Refresh storage information
    func refreshStorageData() async {
        await loadStorageData()
    }

    /// Clear cache
    func clearCache() async {
        do {
            try await RunAnywhere.clearCache()
            await refreshStorageData()
            print("Settings: Cache cleared successfully")
        } catch {
            errorMessage = "Failed to clear cache: \(error.localizedDescription)"
        }
    }

    /// Clean temporary files
    func cleanTempFiles() async {
        do {
            try await RunAnywhere.cleanTempFiles()
            await refreshStorageData()
            print("Settings: Temporary files cleaned successfully")
        } catch {
            errorMessage = "Failed to clean temporary files: \(error.localizedDescription)"
        }
    }

    /// Delete a stored model
    func deleteModel(_ model: StoredModel) async {
        guard let framework = model.framework else {
            errorMessage = "Cannot delete model: unknown framework"
            return
        }

        do {
            try await RunAnywhere.deleteStoredModel(model.id, framework: framework)
            await refreshStorageData()
            print("Settings: Model \(model.name) deleted successfully")
        } catch {
            errorMessage = "Failed to delete model: \(error.localizedDescription)"
        }
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
}
