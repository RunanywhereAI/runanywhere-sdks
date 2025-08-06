# Pulse Framework Integration Plan for RunAnywhere Swift SDK

## Executive Summary

This document outlines the implementation plan for integrating the Pulse framework into the RunAnywhere Swift SDK to replace existing logging and monitoring implementations. The integration will enhance debugging capabilities, provide automatic network monitoring, and improve developer experience while maintaining backward compatibility.

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

## Implementation Phases

### Phase 1: Core Pulse Integration (Week 1)

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
            "Pulse",
            "PulseUI",
            // ... existing dependencies
        ]
    )
]
```

#### 1.2 Create Pulse Configuration Service

**New File: `Foundation/Logging/Services/PulseConfiguration.swift`**
```swift
import Foundation
import Pulse

final class PulseConfiguration {
    static func configure(with config: SDKConfiguration) {
        // Configure LoggerStore
        LoggerStore.shared.configuration = LoggerStore.Configuration(
            sizeLimit: config.loggingConfiguration.maxStorageSize ?? 50_000_000, // 50MB default
            maximumSessionAge: TimeInterval(7 * 24 * 60 * 60), // 7 days
            sweepInterval: TimeInterval(60 * 60) // 1 hour
        )

        // Configure NetworkLogger
        NetworkLogger.Configuration.shared = NetworkLogger.Configuration(
            isEnabled: config.analyticsConfiguration.isEnabled,
            isFiltered: true,
            allowedHosts: Set(config.loggingConfiguration.allowedHosts ?? []),
            blockedHosts: Set(config.loggingConfiguration.blockedHosts ?? []),
            sensitiveDataRedaction: .automatic
        )

        // Configure RemoteLogger for development
        #if DEBUG
        RemoteLogger.shared.enable(
            serverIP: config.loggingConfiguration.remoteLoggerHost,
            port: config.loggingConfiguration.remoteLoggerPort ?? 8080
        )
        #endif
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

### Phase 4: UI Integration (Week 2-3)

#### 4.1 Create Debug Console Integration

**New File: `Public/Debug/PulseDebugMenu.swift`**
```swift
#if DEBUG
import SwiftUI
import PulseUI

public struct PulseDebugMenu: View {
    @State private var isPresented = false

    public var body: some View {
        Button("Open Debug Console") {
            isPresented = true
        }
        .sheet(isPresented: $isPresented) {
            NavigationView {
                ConsoleView()
            }
        }
    }
}

// UIKit support
public class PulseDebugViewController: UIViewController {
    public static func present(from viewController: UIViewController) {
        let consoleVC = UIHostingController(rootView:
            NavigationView { ConsoleView() }
        )
        viewController.present(consoleVC, animated: true)
    }
}
#endif
```

#### 4.2 Add Debug Configuration

**Modified File: `Public/Configuration/SDKConfiguration.swift`**
```swift
public struct SDKConfiguration {
    // ... existing properties

    /// Debug configuration for development builds
    public struct DebugConfiguration {
        /// Enable Pulse debug console
        public let enableDebugConsole: Bool

        /// Enable remote logging to Pulse Pro
        public let enableRemoteLogging: Bool

        /// Remote logger host (for Pulse Pro)
        public let remoteLoggerHost: String?

        /// Remote logger port
        public let remoteLoggerPort: Int?

        public init(
            enableDebugConsole: Bool = true,
            enableRemoteLogging: Bool = false,
            remoteLoggerHost: String? = nil,
            remoteLoggerPort: Int? = 8080
        ) {
            self.enableDebugConsole = enableDebugConsole
            self.enableRemoteLogging = enableRemoteLogging
            self.remoteLoggerHost = remoteLoggerHost
            self.remoteLoggerPort = remoteLoggerPort
        }
    }

    #if DEBUG
    public let debugConfiguration: DebugConfiguration
    #endif
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

## Success Criteria

1. **Functionality**
   - All existing logging functionality maintained
   - Network requests automatically logged
   - Performance metrics captured accurately
   - Debug console accessible in development

2. **Performance**
   - No regression in app launch time
   - Memory usage within 5% of current
   - Logging overhead < 1% CPU usage

3. **Developer Experience**
   - Real-time log streaming working
   - Network inspector functional
   - Export functionality operational
   - Documentation updated

## Risk Mitigation

1. **Dependency Management**
   - Pin to specific Pulse version
   - Regular updates and testing
   - Fallback to basic logging if needed

2. **Platform Compatibility**
   - Pulse requires iOS 15+ for UI
   - Core logging works on iOS 13+
   - Graceful degradation for older versions

3. **Privacy Compliance**
   - All logs stored locally by default
   - Sensitive data redaction configured
   - Remote logging only in debug builds

## Timeline Summary

- **Week 1**: Core Pulse integration and network monitoring setup
- **Week 2**: Performance monitoring and UI integration
- **Week 3**: ServiceContainer updates and legacy cleanup

Total Duration: 3 weeks

## Conclusion

This implementation plan provides a comprehensive approach to integrating Pulse into the RunAnywhere Swift SDK. The phased approach ensures minimal disruption while delivering significant improvements in debugging capabilities, network monitoring, and developer experience. The plan maintains backward compatibility while setting up the SDK for future enhancements.
