# Pulse Framework Integration Plan for RunAnywhere Swift SDK (Simplified)

## Executive Summary

This document outlines a simplified implementation plan for integrating the Pulse framework into the RunAnywhere Swift SDK. The focus is on enhancing network request logging and performance monitoring for model downloads and API calls, without adding unnecessary UI components or complexity.

## Current State Analysis

### Existing Implementations to Replace

1. **Logging System**
   - `Foundation/Logging/Logger/SDKLogger.swift` - Basic os.Logger wrapper
   - `Foundation/Logging/Services/LoggingManager.swift` - Custom log management
   - `Foundation/Logging/Services/RemoteLogger.swift` - Basic remote submission
   - `Foundation/Logging/Services/LogBatcher.swift` - Log batching implementation

2. **Monitoring System**
   - `Capabilities/Monitoring/Services/MonitoringService.swift` - Performance tracking
   - `Capabilities/GenerationAnalytics/Tracking/PerformanceTracker.swift` - Generation metrics
   - `Capabilities/Monitoring/Services/SystemMetricsCollector.swift` - System metrics

3. **Network Logging**
   - No automatic network request logging currently exists
   - Manual logging in `Data/Network/Services/APIClient.swift`

## Key Benefits (What We're Actually Using)

1. **Model Download Debugging**: Automatic logging of download progress, failures, and network issues
2. **Performance Analysis**: Structured logging of generation performance metrics
3. **Network Transparency**: All network requests (downloads, API calls) are automatically logged
4. **Production Debugging**: Export detailed logs with full context when issues occur
5. **Minimal Overhead**: Pulse uses compression and efficient storage (90% less space)

## Implementation Approach (Simplified)

### Core Components Only

1. **PulseSDKLogger**: Drop-in replacement for SDKLogger with enhanced metadata support
2. **PulseConfiguration**: Minimal setup with sensible defaults
3. **Network Logging**: Automatic capture via URLSessionProxyDelegate
4. **Performance Logging**: Structured metrics for generation analytics

### What We're NOT Including

- ❌ Debug UI/Views (PulseDebugMenu)
- ❌ Complex configuration options
- ❌ Remote logging features
- ❌ Export UI components
- ❌ Debug-only features

## Implementation Phases

### Phase 1: Core Integration (Completed)

#### 1.1 Add Pulse Dependency

**File: `Package.swift`**
```swift
dependencies: [
    .package(url: "https://github.com/kean/Pulse", from: "4.0.0"),
    // ... existing dependencies
],
targets: [
    .target(
        name: "RunAnywhere",
        dependencies: [
            "Pulse",  // Core logging only, no PulseUI
            // ... existing dependencies
        ]
    )
]
```

#### 1.2 Minimal Pulse Configuration

**File: `Foundation/Logging/Services/Pulse/PulseConfiguration.swift`**
```swift
import Foundation
import Pulse

final class PulseConfiguration {
    static func configure(with config: Configuration) {
        // Basic configuration with sensible defaults
        LoggerStore.shared.configuration = LoggerStore.Configuration(
            sizeLimit: 50_000_000, // 50MB
            maximumSessionAge: TimeInterval(7 * 24 * 60 * 60), // 7 days
            sweepInterval: TimeInterval(60 * 60) // 1 hour
        )

        // Enable network logging for model downloads
        NetworkLogger.Configuration.shared = NetworkLogger.Configuration(
            isEnabled: true,
            isFiltered: true,
            allowedHosts: Set([
                "huggingface.co",
                "*.huggingface.co",
                "github.com",
                "*.github.com"
            ]),
            sensitiveDataRedaction: .automatic
        )
    }
}
```

#### 1.3 Create Pulse-based Logger Implementation

**New File: `Foundation/Logging/Logger/PulseSDKLogger.swift`**
```swift
import Foundation
import Pulse
import os

public final class PulseSDKLogger: SDKLoggerProtocol {
    private let category: String
    private let pulseLogger: LoggerStore

    init(category: String) {
        self.category = category
        self.pulseLogger = LoggerStore.shared
    }

    func log(level: LogLevel, message: String, error: Error? = nil, metadata: [String: Any]? = nil) {
        var pulseMetadata: [String: Any] = metadata ?? [:]
        pulseMetadata["category"] = category

        if let error = error {
            pulseMetadata["error"] = error.localizedDescription
            pulseMetadata["errorType"] = String(describing: type(of: error))
        }

        let pulseLevel: LoggerStore.Level = {
            switch level {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .warning
            case .error: return .error
            case .critical: return .critical
            }
        }()

        pulseLogger.log(
            level: pulseLevel,
            message: message,
            metadata: pulseMetadata,
            label: category
        )
    }

    func logGenerationStart(_ options: GenerationOptions, metadata: [String: Any]? = nil) {
        var enrichedMetadata = metadata ?? [:]
        enrichedMetadata["generationOptions"] = [
            "maxTokens": options.maxTokens,
            "temperature": options.temperature,
            "systemPrompt": options.systemPrompt ?? "",
            "tokenBudget": options.tokenBudget?.available ?? 0
        ]
        enrichedMetadata["event"] = "generation_start"

        log(level: .info, message: "Generation started", metadata: enrichedMetadata)
    }

    func logGenerationComplete(_ result: GenerationResult, metadata: [String: Any]? = nil) {
        var enrichedMetadata = metadata ?? [:]
        enrichedMetadata["generationResult"] = [
            "executionTarget": result.executionTarget.rawValue,
            "tokensUsed": result.tokensUsed,
            "costBreakdown": [
                "totalCost": result.costBreakdown.totalCost,
                "savedCost": result.costBreakdown.savedCost
            ],
            "performanceMetrics": [
                "timeToFirstToken": result.performanceMetrics.timeToFirstToken,
                "tokensPerSecond": result.performanceMetrics.tokensPerSecond,
                "totalDuration": result.performanceMetrics.totalDuration
            ]
        ]
        enrichedMetadata["event"] = "generation_complete"

        log(level: .info, message: "Generation completed", metadata: enrichedMetadata)
    }
}
```

### Phase 2: Network Integration (Week 1-2)

#### 2.1 Update APIClient for Automatic Network Logging

**Modified File: `Data/Network/Services/APIClient.swift`**
```swift
import Foundation
import Alamofire
import Pulse

final class APIClient {
    private let session: Session

    init() {
        // Configure URLSession with Pulse proxy
        let configuration = URLSessionConfiguration.default
        configuration.urlSessionDelegate = URLSessionProxyDelegate()

        self.session = Session(
            configuration: configuration,
            interceptor: PulseNetworkInterceptor()
        )
    }

    // ... existing implementation
}

// Custom interceptor for additional logging
final class PulseNetworkInterceptor: RequestInterceptor {
    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var request = urlRequest

        // Add custom headers for tracking
        request.setValue("RunAnywhereSDK", forHTTPHeaderField: "X-SDK-Client")

        completion(.success(request))
    }

    func retry(_ request: Request, for session: Session, dueTo error: Error, completion: @escaping (RetryResult) -> Void) {
        // Log retry attempts
        LoggerStore.shared.log(
            level: .warning,
            message: "Network request retry",
            metadata: [
                "url": request.request?.url?.absoluteString ?? "",
                "error": error.localizedDescription,
                "retryCount": request.retryCount
            ],
            label: "APIClient"
        )

        completion(.doNotRetry)
    }
}
```

#### 2.2 Update Download Service

**Modified File: `Capabilities/Downloading/Services/AlamofireDownloadService.swift`**
```swift
import Pulse

extension AlamofireDownloadService {
    private func setupNetworkLogging() {
        // Configure download-specific logging
        NetworkLogger.Configuration.shared.includedHosts.insert("*.huggingface.co")
        NetworkLogger.Configuration.shared.includedHosts.insert("*.github.com")

        // Add progress logging
        session.sessionConfiguration.urlSessionDelegate = URLSessionProxyDelegate()
    }

    private func logDownloadProgress(_ progress: DownloadProgress) {
        LoggerStore.shared.log(
            level: .debug,
            message: "Download progress",
            metadata: [
                "modelId": progress.modelId,
                "bytesDownloaded": progress.bytesDownloaded,
                "totalBytes": progress.totalBytes,
                "progress": progress.progress,
                "speed": progress.downloadSpeed
            ],
            label: "DownloadService"
        )
    }
}
```


### Phase 3: Performance Monitoring Integration (Week 2)

#### 3.1 Create Pulse-based Performance Logger

**New File: `Capabilities/GenerationAnalytics/Services/PulsePerformanceLogger.swift`**
```swift
import Foundation
import Pulse

final class PulsePerformanceLogger {
    static let shared = PulsePerformanceLogger()

    func logGenerationPerformance(_ performance: GenerationPerformance) {
        let metadata: [String: Any] = [
            "modelId": performance.modelId,
            "executionTarget": performance.executionTarget.rawValue,
            "metrics": [
                "timeToFirstToken": performance.timeToFirstToken,
                "tokensPerSecond": performance.tokensPerSecond,
                "totalDuration": performance.totalDuration,
                "memoryUsed": performance.memoryUsed,
                "cpuUsage": performance.cpuUsage,
                "gpuUsage": performance.gpuUsage ?? 0
            ],
            "cost": [
                "totalCost": performance.totalCost,
                "savedCost": performance.savedCost
            ],
            "type": "performance_metrics"
        ]

        LoggerStore.shared.log(
            level: .info,
            message: "Generation performance",
            metadata: metadata,
            label: "Performance"
        )
    }

    func logSystemMetrics(_ metrics: SystemMetrics) {
        let metadata: [String: Any] = [
            "memory": [
                "used": metrics.memoryUsed,
                "available": metrics.memoryAvailable,
                "pressure": metrics.memoryPressure.rawValue
            ],
            "cpu": metrics.cpuUsage,
            "thermal": metrics.thermalState.rawValue,
            "battery": metrics.batteryLevel,
            "type": "system_metrics"
        ]

        LoggerStore.shared.log(
            level: .debug,
            message: "System metrics",
            metadata: metadata,
            label: "System"
        )
    }
}
```

#### 3.2 Update MonitoringService

**Modified File: `Capabilities/Monitoring/Services/MonitoringService.swift`**
```swift
import Pulse

extension MonitoringService {
    private func setupPulseIntegration() {
        // Replace custom logging with Pulse
        metricsCollector.onMetricsCollected = { [weak self] metrics in
            PulsePerformanceLogger.shared.logSystemMetrics(metrics)
            self?.handleMetrics(metrics)
        }

        // Log alerts to Pulse
        alertManager.onAlertTriggered = { alert in
            LoggerStore.shared.log(
                level: .warning,
                message: "Performance alert: \(alert.message)",
                metadata: [
                    "alertType": alert.type.rawValue,
                    "threshold": alert.threshold,
                    "currentValue": alert.currentValue,
                    "recommendation": alert.recommendation
                ],
                label: "Monitoring"
            )
        }
    }
}
```


### Phase 5: ServiceContainer Updates (Week 3)

#### 5.1 Update ServiceContainer

**Modified File: `Foundation/DependencyInjection/ServiceContainer.swift`**
```swift
import Pulse

extension ServiceContainer {
    private func registerLoggingServices() {
        // Configure Pulse
        PulseConfiguration.configure(with: configuration)

        // Register Pulse-based logger factory
        register(SDKLoggerProtocol.self) { container in
            let category = container.resolve(String.self, name: "logCategory") ?? "General"
            return PulseSDKLogger(category: category)
        }

        // Update LoggingManager to use Pulse
        register(LoggingManager.self) { _ in
            PulseLoggingManager()
        }

        // Remove legacy services
        // - RemoteLogger (replaced by Pulse RemoteLogger)
        // - LogBatcher (handled by Pulse internally)
    }

    private func registerMonitoringServices() {
        // Register enhanced monitoring with Pulse
        register(PerformanceMonitor.self) { container in
            PulsePerformanceMonitor(
                logger: container.resolve(SDKLoggerProtocol.self)!
            )
        }
    }
}
```

### Phase 6: Legacy Code Cleanup (Week 3)

#### 6.1 Files to Delete

1. **Logging System**
   - `Foundation/Logging/Logger/SDKLogger.swift`
   - `Foundation/Logging/Services/RemoteLogger.swift`
   - `Foundation/Logging/Services/LogBatcher.swift`
   - `Foundation/Logging/Models/LogBatch.swift`

2. **Custom Implementations**
   - Remove manual network logging from `APIClient`
   - Remove custom performance logging from `MonitoringService`

#### 6.2 Update Imports

**Script: `update_imports.sh`**
```bash
#!/bin/bash

# Find and replace SDKLogger imports
find . -name "*.swift" -type f -exec sed -i '' 's/import SDKLogger/import Pulse/g' {} +

# Update logger initialization
find . -name "*.swift" -type f -exec sed -i '' 's/SDKLogger(/PulseSDKLogger(/g' {} +
```


## Migration Strategy

### Gradual Rollout Plan

1. **Phase 1**: Enable Pulse alongside existing logging
2. **Phase 2**: Migrate critical paths to Pulse
3. **Phase 3**: Monitor and validate in development
4. **Phase 4**: Remove legacy implementations
5. **Phase 5**: Production deployment with feature flags

### Backward Compatibility

```swift
// Temporary bridge for existing code
public typealias SDKLogger = PulseSDKLogger

// Feature flag for gradual rollout
struct FeatureFlags {
    static var usePulseLogging: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: "pulse_logging_enabled")
        #endif
    }
}
```

## Implementation Summary

### What We've Done

1. **Core Logging**: PulseSDKLogger as a drop-in replacement for SDKLogger
2. **Network Monitoring**: Automatic logging for URLSession requests
3. **Performance Tracking**: Structured logging for generation metrics
4. **Download Tracking**: Enhanced logging for model downloads with progress

### Key Benefits Achieved

- ✅ Automatic network request logging (downloads, API calls)
- ✅ Structured performance metrics with compression
- ✅ Enhanced error context for debugging
- ✅ Minimal code changes (typealias for compatibility)
- ✅ Production-ready logging with 7-day retention

### What We Intentionally Skipped

- ❌ UI components (no debug console views)
- ❌ Complex configuration options
- ❌ Remote logging features
- ❌ Export UI (logs can still be accessed programmatically)

## Migration Notes

The implementation uses a compatibility bridge:
```swift
// Temporary bridge for zero code changes
internal typealias SDKLogger = PulseSDKLogger
```

This means all existing `SDKLogger` usage automatically uses Pulse without any code modifications.

## Future Considerations

If needed in the future, we can:
- Add programmatic log export functionality
- Enable remote logging for specific debug builds
- Add more sophisticated filtering rules
- Integrate with crash reporting tools

## Conclusion

This simplified Pulse integration provides powerful network and performance logging capabilities without adding unnecessary complexity. The focus remains on the core benefits: better debugging for model downloads, performance tracking, and production issue diagnosis.
