# RunAnywhere SDK Configuration Guide

**Last Updated:** October 14, 2025
**SDK Version:** 1.0.0

---

## Table of Contents

1. [Overview](#overview)
2. [Three-Layer Configuration Architecture](#three-layer-configuration-architecture)
3. [Layer 1: Build-Time Constants](#layer-1-build-time-constants)
4. [Layer 2: SDK Initialization](#layer-2-sdk-initialization)
5. [Layer 3: Runtime Configuration](#layer-3-runtime-configuration)
6. [Configuration Presets](#configuration-presets)
7. [Common Configuration Scenarios](#common-configuration-scenarios)
8. [Configuration Precedence](#configuration-precedence)
9. [API Reference](#api-reference)
10. [Troubleshooting](#troubleshooting)

---

## Overview

The RunAnywhere SDK uses a **three-layer configuration system** that separates concerns and provides flexibility for different deployment scenarios:

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: Build-Time Constants                              │
│  Purpose: Deployment settings, API URLs, feature flags      │
│  Set Once: At compile time or deployment                    │
│  Source: JSON files or environment variables                │
└─────────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────┐
│  Layer 2: SDK Initialization                                │
│  Purpose: Bootstrap - API key, environment mode             │
│  Set Once: During app startup                               │
│  Source: Provided by developer in code                      │
└─────────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────┐
│  Layer 3: Runtime Configuration                             │
│  Purpose: Dynamic settings - temperature, routing, etc.     │
│  Can Change: At any time during app lifecycle               │
│  Source: Backend API, user preferences, or code             │
└─────────────────────────────────────────────────────────────┘
```

**Why Three Layers?**

- **Separation of Concerns**: Each layer handles a specific type of configuration
- **Flexibility**: Change runtime settings without redeploying
- **Security**: Sensitive deployment settings separate from user preferences
- **Best Practices**: Matches patterns from Firebase, AWS Amplify, and other modern SDKs

---

## Three-Layer Configuration Architecture

### Quick Decision Matrix

| What do you need to configure? | Use Which Layer? | How? |
|--------------------------------|------------------|------|
| API URLs per environment | Layer 1 | Edit `RunAnywhereConfig.json` |
| API key and environment mode | Layer 2 | `RunAnywhere.initialize()` |
| Temperature, max tokens | Layer 3 | `RunAnywhere.setDefaultGenerationSettings()` |
| Routing policy (device vs cloud) | Layer 3 | `RunAnywhere.setRoutingPolicy()` |
| Feature flags | Layer 1 | Edit `RunAnywhereConfig.json` |
| Apply preset (creative, precise) | Layer 3 | `RunAnywhere.updateConfiguration(preset:)` |

---

## Layer 1: Build-Time Constants

### Purpose
Configuration that is set **once during deployment** and doesn't change at runtime. Used for API URLs, feature flags, and deployment-specific settings.

### Configuration File

**Location:** `Configuration/RunAnywhereConfig.json`

**Example:**
```json
{
  "api": {
    "development": "https://dev-api.runanywhere.ai",
    "staging": "https://staging-api.runanywhere.ai",
    "production": "https://api.runanywhere.ai"
  },
  "features": {
    "telemetry": true,
    "debugLogging": false
  },
  "timeouts": {
    "requestTimeout": 30,
    "downloadTimeout": 300
  }
}
```

### How It Works

1. The SDK loads this file at **compile time** via `RunAnywhereConstants`
2. Values are accessed throughout the SDK as constants
3. Can be overridden by environment variables

### Access in Code

```swift
import RunAnywhere

// Accessing Layer 1 constants
let apiURL = RunAnywhereConstants.apiURLs.production
let isTelemetryEnabled = RunAnywhereConstants.features.enableTelemetry
```

### When to Use Layer 1

✅ **Do Use For:**
- API endpoint URLs for different environments
- Feature flags that apply to all users
- Timeout values and retry policies
- Backend service endpoints
- Build-specific configuration

❌ **Don't Use For:**
- User preferences (use Layer 3)
- API keys (use Layer 2)
- Settings that change frequently (use Layer 3)

---

## Layer 2: SDK Initialization

### Purpose
**Bootstrap configuration** provided when the SDK is initialized. Sets up authentication and environment mode.

### Basic Initialization

```swift
import RunAnywhere

// Production mode - full initialization
try RunAnywhere.initialize(
    apiKey: "your-api-key-here",
    baseURL: "https://api.runanywhere.ai",
    environment: .production
)
```

### Development Mode Initialization

```swift
// Development mode - simplified
try RunAnywhere.initialize(
    apiKey: "dev",
    environment: .development
)
```

### Using Convenience Methods

```swift
// Development
let params = SDKInitParams.development()
try RunAnywhere.initialize(with: params)

// Production with constants
let params = try SDKInitParams.production(apiKey: "your-api-key")
try RunAnywhere.initialize(with: params)

// Staging
let params = try SDKInitParams.staging(apiKey: "your-api-key")
try RunAnywhere.initialize(with: params)
```

### Environment Modes

| Mode | Description | API Calls | Telemetry | Logging |
|------|-------------|-----------|-----------|---------|
| `.development` | Local testing | ❌ None | ❌ Disabled | 📝 Debug |
| `.staging` | Integration testing | ✅ Staging API | ⚠️ Limited | 📝 Info |
| `.production` | Live app | ✅ Production API | ✅ Full | ⚠️ Warning |

### When to Use Layer 2

✅ **Do Use For:**
- Setting API authentication (API key)
- Choosing environment mode (dev/staging/prod)
- Providing backend URL
- Initial SDK bootstrap

❌ **Don't Use For:**
- Changing generation settings (use Layer 3)
- Updating routing policy (use Layer 3)
- User preferences (use Layer 3)

---

## Layer 3: Runtime Configuration

### Purpose
**Dynamic settings** that can change during the app's lifecycle. Includes generation parameters, routing policy, and user preferences.

### Configuration Loading

The SDK automatically loads configuration in this order:

1. **Remote Backend** - Fetched from API (production mode only)
2. **Database Cache** - Previously saved configuration
3. **Consumer Overrides** - Settings you set via SDK methods
4. **SDK Defaults** - Fallback values

### Reading Current Configuration

```swift
// Get current generation settings
let settings = await RunAnywhere.getCurrentGenerationSettings()
print("Temperature: \(settings.temperature)")
print("Max Tokens: \(settings.maxTokens)")

// Get routing policy
let policy = await RunAnywhere.getCurrentRoutingPolicy()
print("Routing Policy: \(policy)")

// Get full configuration
let config = await RunAnywhere.getCurrentConfiguration()
```

### Updating Configuration

#### Using Presets

```swift
// Apply creative preset (high temperature, more tokens)
try await RunAnywhere.updateConfiguration(preset: .creative)

// Apply precise preset (low temperature, focused)
try await RunAnywhere.updateConfiguration(preset: .precise)

// Apply privacy-focused preset (device-only)
try await RunAnywhere.updateConfiguration(preset: .privacyFocused)
```

#### Updating Specific Settings

```swift
// Update routing policy
try await RunAnywhere.setRoutingPolicy(.preferDevice)

// Update generation defaults
let settings = DefaultGenerationSettings(
    temperature: 0.8,
    maxTokens: 1024,
    topP: 0.95
)
try await RunAnywhere.setDefaultGenerationSettings(settings)

// Update storage configuration
let storage = StorageConfiguration(
    maxCacheSize: 2_000_000_000,  // 2GB
    evictionPolicy: .lru
)
try await RunAnywhere.setStorageConfiguration(storage)
```

### When to Use Layer 3

✅ **Do Use For:**
- Generation parameters (temperature, max tokens)
- Routing policy (device vs cloud)
- Storage limits
- User preferences
- Feature-specific settings

❌ **Don't Use For:**
- API keys (use Layer 2)
- Environment selection (use Layer 2)
- Deployment settings (use Layer 1)

---

## Configuration Presets

Pre-configured settings for common use cases.

### Available Presets

#### `.creative`
**Best for:** Creative writing, brainstorming, diverse outputs

```swift
try await RunAnywhere.updateConfiguration(preset: .creative)
```

**Settings:**
- Temperature: 0.9 (high randomness)
- Max Tokens: 1024 (longer responses)
- Top-P: 0.95 (diverse vocabulary)
- Routing: Automatic

---

#### `.precise`
**Best for:** Code generation, factual Q&A, structured output

```swift
try await RunAnywhere.updateConfiguration(preset: .precise)
```

**Settings:**
- Temperature: 0.3 (focused, deterministic)
- Max Tokens: 512 (concise responses)
- Top-P: 0.8 (conservative vocabulary)
- Routing: Automatic

---

#### `.balanced`
**Best for:** General-purpose use, default settings

```swift
try await RunAnywhere.updateConfiguration(preset: .balanced)
```

**Settings:**
- Temperature: 0.7 (moderate randomness)
- Max Tokens: 512 (moderate length)
- Top-P: 0.9 (balanced vocabulary)
- Routing: Automatic

---

#### `.privacyFocused`
**Best for:** Sensitive data, offline mode, privacy-conscious apps

```swift
try await RunAnywhere.updateConfiguration(preset: .privacyFocused)
```

**Settings:**
- Temperature: 0.7
- Max Tokens: 512
- **Routing: Device-only** (never uses cloud)

---

#### `.cloudPreferred`
**Best for:** Maximum performance, larger models, internet-connected apps

```swift
try await RunAnywhere.updateConfiguration(preset: .cloudPreferred)
```

**Settings:**
- Temperature: 0.7
- Max Tokens: 1024
- **Routing: Prefer Cloud** (uses cloud when possible)

---

## Common Configuration Scenarios

### Scenario 1: Development Setup

```swift
import RunAnywhere

// In your app's initialization
func setupSDK() async throws {
    // Layer 2: Initialize for development
    try RunAnywhere.initialize(
        apiKey: "dev",
        environment: .development
    )

    // Layer 3: Use privacy-focused preset (no cloud calls)
    try await RunAnywhere.updateConfiguration(preset: .privacyFocused)
}
```

---

### Scenario 2: Production Setup with User Preferences

```swift
import RunAnywhere

func setupSDK(userPreferences: UserPreferences) async throws {
    // Layer 2: Initialize for production
    try RunAnywhere.initialize(
        apiKey: loadAPIKeyFromKeychain(),
        baseURL: "https://api.runanywhere.ai",
        environment: .production
    )

    // Layer 3: Apply user's saved preferences
    if userPreferences.privacyMode {
        try await RunAnywhere.setRoutingPolicy(.deviceOnly)
    }

    if let temperature = userPreferences.temperature {
        var settings = await RunAnywhere.getCurrentGenerationSettings()
        settings.temperature = temperature
        try await RunAnywhere.setDefaultGenerationSettings(settings)
    }
}
```

---

### Scenario 3: Multi-Environment Build Configuration

**Step 1:** Create environment-specific JSON files

- `RunAnywhereConfig-Debug.json`
- `RunAnywhereConfig-Release.json`

**Step 2:** Load appropriate file based on build configuration

```swift
#if DEBUG
let environment = SDKEnvironment.development
let apiKey = "dev"
#else
let environment = SDKEnvironment.production
let apiKey = loadAPIKeyFromKeychain()
#endif

try RunAnywhere.initialize(
    apiKey: apiKey,
    environment: environment
)
```

---

### Scenario 4: Changing Settings Based on User Actions

```swift
class SettingsViewModel: ObservableObject {
    @Published var routingPolicy: RoutingPolicy = .automatic
    @Published var temperature: Double = 0.7

    func applySettings() async throws {
        // Update routing
        try await RunAnywhere.setRoutingPolicy(routingPolicy)

        // Update generation settings
        var settings = await RunAnywhere.getCurrentGenerationSettings()
        settings.temperature = temperature
        try await RunAnywhere.setDefaultGenerationSettings(settings)

        // Sync to backend (if in production)
        try? await RunAnywhere.syncUserPreferences()
    }
}
```

---

## Configuration Precedence

### Layer 3 Runtime Configuration Precedence

When loading Layer 3 configuration, the SDK follows this precedence chain:

```
Highest Priority
     │
     ├──▶ 1. Consumer Overrides
     │    (Set via RunAnywhere.updateConfiguration)
     │
     ├──▶ 2. Remote Backend
     │    (Fetched from API in production)
     │
     ├──▶ 3. Database Cache
     │    (Previously saved configuration)
     │
     └──▶ 4. SDK Defaults
          (Hardcoded fallback values)
Lowest Priority
```

### Example

```swift
// Initial state: SDK defaults
// temperature = 0.7 (from defaults)

// Backend fetches remote config
// temperature = 0.8 (from remote)

// User sets custom preference
try await RunAnywhere.setRoutingPolicy(.deviceOnly)
// temperature = 0.8 (unchanged, from remote)
// routingPolicy = .deviceOnly (consumer override takes precedence)

// User applies preset
try await RunAnywhere.updateConfiguration(preset: .creative)
// temperature = 0.9 (from preset, overrides remote)
// routingPolicy = .automatic (from preset, overrides previous setting)
```

---

## API Reference

### Initialization

```swift
// Basic initialization
RunAnywhere.initialize(
    apiKey: String,
    baseURL: URL,
    environment: SDKEnvironment
) throws

// String URL variant
RunAnywhere.initialize(
    apiKey: String,
    baseURL: String,
    environment: SDKEnvironment
) throws

// Convenience methods
SDKInitParams.development(apiKey: String = "dev-mode") -> SDKInitParams
SDKInitParams.production(apiKey: String) throws -> SDKInitParams
SDKInitParams.staging(apiKey: String) throws -> SDKInitParams
```

### Read Configuration

```swift
// Get generation settings
RunAnywhere.getCurrentGenerationSettings() async -> DefaultGenerationSettings

// Get routing policy
RunAnywhere.getCurrentRoutingPolicy() async -> RoutingPolicy

// Get full configuration
RunAnywhere.getCurrentConfiguration() async -> ConfigurationData
```

### Update Configuration

```swift
// Apply preset
RunAnywhere.updateConfiguration(preset: ConfigurationPreset) async throws

// Update routing policy
RunAnywhere.setRoutingPolicy(_ policy: RoutingPolicy) async throws

// Update generation settings
RunAnywhere.setDefaultGenerationSettings(_ settings: DefaultGenerationSettings) async throws

// Update storage configuration
RunAnywhere.setStorageConfiguration(_ storage: StorageConfiguration) async throws

// Sync to backend
RunAnywhere.syncUserPreferences() async throws
```

### Configuration Presets

```swift
public enum ConfigurationPreset {
    case creative           // High temperature, diverse output
    case precise            // Low temperature, focused output
    case balanced           // Default settings
    case privacyFocused     // Device-only routing
    case cloudPreferred     // Prefer cloud execution
}
```

---

## Troubleshooting

### Configuration Not Loading

**Problem:** `getCurrentGenerationSettings()` returns default values

**Solution:**
1. Configuration loads asynchronously after initialization
2. Wait a moment after `initialize()` before checking configuration
3. Check logs for configuration loading status

```swift
try RunAnywhere.initialize(...)

// Wait for configuration to load
try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

// Now read configuration
let settings = await RunAnywhere.getCurrentGenerationSettings()
```

---

### Changes Not Persisting

**Problem:** Configuration changes are lost after app restart

**Solution:**
- In **development mode**, configuration is not persisted to backend
- In **production mode**, call `syncUserPreferences()` to save changes

```swift
try await RunAnywhere.updateConfiguration(preset: .creative)
try await RunAnywhere.syncUserPreferences()  // Persist changes
```

---

### Different Settings in Dev vs Production

**Problem:** App behaves differently between environments

**Solution:**
- Different environments load different Layer 1 constants
- Explicitly set Layer 3 configuration for consistent behavior

```swift
// After initialization, explicitly set configuration
try RunAnywhere.initialize(...)
try await RunAnywhere.updateConfiguration(preset: .balanced)
```

---

### Routing Policy Not Respected

**Problem:** Cloud routing happens despite setting `.deviceOnly`

**Solution:**
- Check if a preset was applied after setting routing policy
- Presets override individual settings

```swift
// This will be overridden:
try await RunAnywhere.setRoutingPolicy(.deviceOnly)
try await RunAnywhere.updateConfiguration(preset: .cloudPreferred)
// Routing is now .preferCloud (from preset)

// Correct order:
try await RunAnywhere.updateConfiguration(preset: .balanced)
try await RunAnywhere.setRoutingPolicy(.deviceOnly)  // Override routing only
```

---

### API Key Issues

**Problem:** API key errors in production

**Solution:**
- **Layer 2** is for API keys, not Layer 3
- API key must be provided during initialization
- For production, load from secure storage (Keychain)

```swift
// ❌ Wrong - no API key method in Layer 3
try await RunAnywhere.updateConfiguration(...)

// ✅ Correct - API key in Layer 2
try RunAnywhere.initialize(
    apiKey: loadFromKeychain(),
    environment: .production
)
```

---

## Best Practices

### ✅ Do

- **Initialize once** at app startup
- **Use presets** for common scenarios
- **Store API keys** in Keychain (production)
- **Test both environments** (dev and production)
- **Document your configuration** choices
- **Use convenience methods** for initialization

### ❌ Don't

- **Don't initialize multiple times** - SDK is a singleton
- **Don't hardcode API keys** - use secure storage
- **Don't mix layers** - understand which layer to use
- **Don't skip error handling** - configuration can fail
- **Don't assume immediate loading** - configuration is async

---

## Summary

The RunAnywhere SDK configuration system provides flexibility through three distinct layers:

1. **Layer 1**: Build-time constants for deployment settings
2. **Layer 2**: Initialization parameters for API authentication
3. **Layer 3**: Runtime configuration for dynamic settings

Use the right layer for your needs, apply presets for common scenarios, and the SDK will handle configuration loading and persistence automatically.

For more information, see:
- [SDK README](../README.md)
- [Public API Reference](./PUBLIC_API_REFERENCE.md)
- [Architecture Documentation](./ARCHITECTURE_V2.md)

---

**Questions or Issues?**
Open an issue on GitHub: https://github.com/RunanywhereAI/runanywhere-sdks/issues
