import Foundation

/// Service for managing SDK configuration with three-tier system
public actor ConfigurationService: ConfigurationManager {
    private let logger = SDKLogger(category: "ConfigurationService")

    // Storage keys
    private let userOverridesKey = "com.runanywhere.config.userOverrides"
    private let remoteConfigKey = "com.runanywhere.config.remoteSettings"

    // Three tiers of settings
    private var sdkDefaults: DefaultGenerationSettings
    private var remoteSettings: DefaultGenerationSettings?
    private var userOverrides: DefaultGenerationSettings?

    // Callbacks
    private var settingsChangedCallbacks: [(DefaultGenerationSettings) -> Void] = []

    // MARK: - Initialization

    public init(configuration: Configuration) {
        self.sdkDefaults = configuration.defaultGenerationSettings
        Task {
            await loadStoredConfigurations()
            logger.info("ConfigurationService initialized with defaults")
        }
    }

    // MARK: - ConfigurationManager Protocol

    public func getGenerationSettings() -> DefaultGenerationSettings {
        return mergeSettings()
    }

    public func updateRemoteSettings(_ settings: [String: Any]) async {
        guard let newSettings = DefaultGenerationSettings.from(remoteConfig: settings) else {
            logger.error("Failed to parse remote configuration")
            return
        }

        self.remoteSettings = newSettings
        saveRemoteSettings()

        logger.info("Updated remote settings: temperature=\(newSettings.temperature)")
        await notifySettingsChanged()
    }

    public func setTemperature(_ value: Float) {
        setUserOverride(\.temperature, value: value)
    }

    public func setMaxTokens(_ value: Int) {
        setUserOverride(\.maxTokens, value: value)
    }

    public func setTopP(_ value: Float) {
        setUserOverride(\.topP, value: value)
    }

    public func setTopK(_ value: Int) {
        setUserOverride(\.topK, value: value)
    }

    public func clearUserOverrides() {
        userOverrides = nil
        UserDefaults.standard.removeObject(forKey: userOverridesKey)
        logger.info("Cleared all user overrides")
        Task {
            await notifySettingsChanged()
        }
    }

    public var allowUserOverride: Bool {
        return mergeSettings().allowUserOverride
    }

    public func syncUserPreferences() async throws {
        guard let overrides = userOverrides else {
            return
        }

        // This will be implemented when network layer is ready
        logger.info("Would sync user preferences: temperature=\(overrides.temperature)")
    }

    public func onSettingsChanged(_ callback: @escaping (DefaultGenerationSettings) -> Void) {
        settingsChangedCallbacks.append(callback)
    }

    // MARK: - Private Methods

    private func setUserOverride<T>(_ keyPath: WritableKeyPath<DefaultGenerationSettings, T>, value: T) {
        // Check if overrides are allowed
        guard mergeSettings().allowUserOverride else {
            logger.warning("User overrides are disabled by configuration")
            return
        }

        // Initialize user overrides if needed
        if userOverrides == nil {
            userOverrides = DefaultGenerationSettings()
        }

        // Apply the override
        userOverrides?[keyPath: keyPath] = value
        saveUserOverrides()

        logger.debug("User override set")
        Task {
            await notifySettingsChanged()
        }
    }

    private func mergeSettings() -> DefaultGenerationSettings {
        var effective = sdkDefaults

        // Apply remote settings overrides
        if let remote = remoteSettings {
            effective.temperature = remote.temperature
            effective.maxTokens = remote.maxTokens
            effective.topP = remote.topP
            effective.topK = remote.topK
            effective.allowUserOverride = remote.allowUserOverride
        }

        // Apply user overrides (if allowed)
        if effective.allowUserOverride, let user = userOverrides {
            effective.temperature = user.temperature
            effective.maxTokens = user.maxTokens
            effective.topP = user.topP
            effective.topK = user.topK
        }

        return effective
    }

    private func loadStoredConfigurations() {
        // Load remote settings
        if let data = UserDefaults.standard.data(forKey: remoteConfigKey),
           let settings = try? JSONDecoder().decode(DefaultGenerationSettings.self, from: data) {
            self.remoteSettings = settings
            logger.debug("Loaded remote settings from storage")
        }

        // Load user overrides
        if let data = UserDefaults.standard.data(forKey: userOverridesKey),
           let overrides = try? JSONDecoder().decode(DefaultGenerationSettings.self, from: data) {
            self.userOverrides = overrides
            logger.debug("Loaded user overrides from storage")
        }
    }

    private func saveRemoteSettings() {
        guard let settings = remoteSettings,
              let data = try? JSONEncoder().encode(settings) else {
            return
        }
        UserDefaults.standard.set(data, forKey: remoteConfigKey)
    }

    private func saveUserOverrides() {
        guard let overrides = userOverrides,
              let data = try? JSONEncoder().encode(overrides) else {
            return
        }
        UserDefaults.standard.set(data, forKey: userOverridesKey)
    }

    private func notifySettingsChanged() async {
        let effective = mergeSettings()
        for callback in settingsChangedCallbacks {
            callback(effective)
        }
    }
}
