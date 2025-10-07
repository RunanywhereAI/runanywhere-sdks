# Environment Configuration Guide

The RunAnywhere SDK supports environment-specific configuration to control logging behavior, API endpoints, and other settings based on whether you're running in debug, staging, or production environments.

## Overview

The SDK automatically detects the current environment and applies appropriate settings:
- **Debug**: Full logging, console output enabled, sensitive data logging allowed
- **Staging**: File and remote logging, no console output, standard telemetry
- **Production**: Minimal logging (warnings/errors only), remote telemetry, crash reporting

## Configuration Methods

### 1. Automatic Detection (Recommended)

The SDK automatically detects the environment based on build configuration:

```swift
// In DEBUG builds
#if DEBUG
// Automatically uses debug configuration
#endif

// In RELEASE builds
// Automatically uses production configuration
```

### 2. Plist Configuration

Create a `RunAnywhereConfig.plist` file in your app bundle:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>environment</key>
    <string>debug</string>

    <key>logging</key>
    <dict>
        <key>enableConsoleLogging</key>
        <true/>
        <key>enableFileLogging</key>
        <true/>
        <key>enableRemoteLogging</key>
        <false/>
        <key>minimumLogLevel</key>
        <string>debug</string>
        <key>enableSensitiveDataLogging</key>
        <true/>
    </dict>

    <key>api</key>
    <dict>
        <key>baseURL</key>
        <string>https://api-dev.runanywhere.ai</string>
        <key>timeoutSeconds</key>
        <real>30</real>
    </dict>
</dict>
</plist>
```

### 3. Build Configuration Script

Use the provided script to automatically copy the appropriate config file:

1. Add the script as a "Run Script" build phase in Xcode:
   ```bash
   "${SRCROOT}/scripts/copy_environment_config.sh"
   ```

2. Create separate config files:
   - `RunAnywhereConfig-Debug.plist`
   - `RunAnywhereConfig-Release.plist`

3. The script will copy the appropriate file to `RunAnywhereConfig.plist` based on build configuration.

## Logging Behavior by Environment

### Debug Environment
- ✅ Console logging enabled
- ✅ File logging enabled
- ❌ Remote logging disabled
- ✅ All log levels (debug, info, warning, error)
- ✅ Sensitive data logging allowed
- ✅ Performance monitoring enabled

### Staging Environment
- ❌ Console logging disabled
- ✅ File logging enabled
- ✅ Remote logging enabled
- ℹ️ Info level and above
- ❌ Sensitive data logging disabled
- ✅ Performance monitoring enabled

### Production Environment
- ❌ Console logging disabled
- ✅ File logging enabled (limited)
- ✅ Remote logging enabled
- ⚠️ Warning level and above only
- ❌ Sensitive data logging disabled
- ❌ Performance monitoring disabled

## Environment Detection Helpers

The SDK provides several helper methods to detect the runtime environment:

```swift
// Check if running in Xcode
if EnvironmentConfiguration.isRunningInXcode {
    // Development environment
}

// Check if running in TestFlight
if EnvironmentConfiguration.isRunningInTestFlight {
    // Beta testing environment
}

// Check if running unit tests
if EnvironmentConfiguration.isRunningUnitTests {
    // Test environment
}
```

## Testing with Different Configurations

For testing, you can temporarily override the configuration:

```swift
#if DEBUG
// Create a custom configuration for testing
let testConfig = EnvironmentConfiguration(
    environment: .production,
    logging: EnvironmentConfiguration.LoggingConfig(
        enableConsoleLogging: false,
        enableFileLogging: true,
        enableRemoteLogging: true,
        minimumLogLevel: .warning,
        enableSensitiveDataLogging: false,
        maxLogFileSizeMB: 10,
        logRetentionDays: 90
    ),
    api: EnvironmentConfiguration.APIConfig(
        baseURL: "https://api.runanywhere.ai",
        timeoutSeconds: 15,
        enableRequestLogging: false
    ),
    enablePerformanceMonitoring: false,
    enableCrashReporting: true
)

// Apply test configuration
EnvironmentConfiguration.setTestConfiguration(testConfig)

// Run your tests...

// Reset to automatic detection
EnvironmentConfiguration.setTestConfiguration(nil)
#endif
```

## Accessing Current Configuration

You can access the current environment configuration:

```swift
let currentEnv = EnvironmentConfiguration.current

if currentEnv.environment.isDebug {
    // Debug-specific code
}

if currentEnv.logging.enableConsoleLogging {
    // Console logging is enabled
}
```

## Best Practices

1. **Never commit sensitive data in config files** - Use environment variables or secure storage for API keys
2. **Use debug configuration during development** - This ensures you see all logs
3. **Test with production configuration** - Before releasing, test with production settings
4. **Monitor log file sizes** - The SDK respects the `maxLogFileSizeMB` setting
5. **Clean up old logs** - Logs are automatically cleaned based on `logRetentionDays`

## Troubleshooting

### Logs not appearing in console
- Check if you're running a Release build (console logging is disabled)
- Verify `enableConsoleLogging` is `true` in your config
- Check minimum log level setting

### Remote logs not being sent
- Verify `enableRemoteLogging` is `true`
- Check network connectivity
- Ensure API endpoint is configured correctly

### Sensitive data appearing in logs
- Check `enableSensitiveDataLogging` setting
- This should always be `false` in production

## Environment Variables

You can also use environment variables for configuration:

```bash
# Force staging environment
export RUNANYWHERE_STAGING=1

# Custom API endpoint
export RUNANYWHERE_API_URL="https://custom-api.example.com"
```

These can be set in Xcode's scheme editor for different build configurations.
