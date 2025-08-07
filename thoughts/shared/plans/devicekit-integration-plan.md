# DeviceKit Integration Plan for RunAnywhere Swift SDK

## Executive Summary

This plan outlines the integration of DeviceKit into the RunAnywhere Swift SDK to replace the current hardcoded device detection system. DeviceKit will provide accurate, maintainable device identification and hardware capability detection, enabling better model selection and performance optimization.

### Current Problems
- Hardcoded processor detection that fails for new devices (M3, M4, A18)

- Generic device names ("iPhone", "iPad") instead of specific models
- Simplified Neural Engine detection missing nuanced capabilities
- No thermal state monitoring or battery optimization
- Manual maintenance required for each new Apple device

### Solution Benefits
- Automatic support for all current and future Apple devices
- Precise hardware capability detection (Neural Engine, Face ID, LiDAR)
- Real-time thermal and battery monitoring
- Device-specific performance optimization
- Zero maintenance for new device releases

---

## Current State Analysis

### 1. ProcessorDetector.swift Issues (DeviceCapability/Services/ProcessorDetector.swift)

```swift
// Current hardcoded detection - lines 105-117
private func detectAppleSiliconName(coreCount: Int) -> String {
    // Simple heuristic based on core count
    // In production, would use IOKit to get actual chip info
    if coreCount >= 10 {
        return "Apple M2 Pro/Max"  // WRONG for M3, M4!
    } else if coreCount >= 8 {
        return "Apple M1 Pro/M2"   // WRONG for M3, M4!
    } else if coreCount >= 4 {
        return "Apple M1/A14+"
    } else {
        return "Apple A-series"
    }
}
```

**Problems:**
- Relies on core count heuristics that break with new chips
- No differentiation between Pro/Max/Ultra variants
- Missing A18, M3, M4 support
- Returns generic strings instead of specific chip names
- No actual chip identification, just guesswork

### 2. Current Device Detection Architecture

The codebase has the following device detection structure:

**DeviceCapability Module** (`/Capabilities/DeviceCapability/`):
- **Models/**
  - `DeviceInfo.swift` - Basic device info with hardcoded detection
  - `DeviceCapabilities.swift` - Device capabilities with ProcessorType enum
  - `ProcessorInfo.swift` - Processor details with core counts
  - `BatteryInfo.swift` - Battery state information
- **Services/**
  - `ProcessorDetector.swift` - Hardcoded processor detection
  - `HardwareDetectionService.swift` - Main hardware detection facade
  - `BatteryMonitorService.swift` - Battery monitoring
  - `ThermalMonitorService.swift` - Thermal state monitoring
  - `CapabilityAnalyzer.swift` - Capability analysis
  - `RequirementMatcher.swift` - Requirement matching

**Problems:**
- ProcessorType enum has hardcoded list that needs manual updates
- DeviceInfo returns generic "iPhone", "iPad", "Mac" instead of specific models
- No actual chip detection - just heuristics based on core counts
- Neural Engine detection is oversimplified (just returns true for iOS/tvOS)

### 3. DeviceInfo.swift Generic Names (DeviceCapability/Models/DeviceInfo.swift)

```swift
// Current implementation - lines 66-72
private static func getDeviceModel() -> String {
    #if os(iOS) || os(tvOS)
    return UIDevice.current.model  // Returns "iPhone", "iPad", etc.
    #else
    return "Mac"
    #endif
}

// Current output
model: "iPhone"      // Should be "iPhone 15 Pro"
osVersion: "17.2.0"  // No device-specific identification
```

### 4. Existing Models to Update

**ProcessorInfo.swift** (needs enhancement):
- Add chip name field
- Add Neural Engine core count
- Add performance metrics (TOPS)
- Add generation/variant info

**DeviceCapabilities.swift** (needs ProcessorType updates):
- ProcessorType enum is hardcoded with specific chips
- Needs to be replaced with dynamic detection
- Missing newer chips (M3 Ultra, M4 variants, A18)

---

## DeviceKit Integration Architecture

### 1. Core Integration Points

```
RunAnywhere SDK
    ├── Capabilities/DeviceCapability/
    │   ├── Services/
    │   │   ├── DeviceKitAdapter.swift (NEW - main adapter)
    │   │   ├── HardwareDetectionService.swift (MODIFIED - use adapter)
    │   │   ├── ProcessorDetector.swift (REPLACED - use DeviceKit)
    │   │   ├── BatteryMonitorService.swift (KEEP - already good)
    │   │   ├── ThermalMonitorService.swift (KEEP - already good)
    │   │   ├── CapabilityAnalyzer.swift (MODIFIED - use DeviceKit)
    │   │   └── RequirementMatcher.swift (KEEP - logic is good)
    │   ├── Models/
    │   │   ├── DeviceSpecifications.swift (NEW - processor specs DB)
    │   │   ├── ProcessorInfo.swift (ENHANCED - add more fields)
    │   │   ├── DeviceInfo.swift (MODIFIED - use DeviceKit names)
    │   │   ├── DeviceCapabilities.swift (MODIFIED - remove hardcoded ProcessorType)
    │   │   └── BatteryInfo.swift (KEEP - already good)
    │   └── Data/
    │       └── ProcessorDatabase.swift (NEW - specs database)
    └── Package.swift (MODIFIED - add DeviceKit dependency)
```

### 2. Legacy Code to Remove

The following hardcoded logic needs to be replaced:

1. **ProcessorDetector.swift**:
   - `detectAppleSiliconName()` - Replace with DeviceKit CPU detection
   - Hardcoded core count heuristics

2. **DeviceInfo.swift**:
   - `getDeviceModel()` - Replace UIDevice.current.model with DeviceKit
   - `hasAppleNeuralEngine()` - Replace with actual chip detection

3. **DeviceCapabilities.swift**:
   - `ProcessorType` enum - Replace with dynamic detection
   - Hardcoded chip list that needs manual updates

### 3. DeviceKitAdapter Design

```swift
import DeviceKit

/// Adapts DeviceKit to RunAnywhere SDK needs
class DeviceKitAdapter {
    private let device = Device.current

    func getProcessorInfo() -> ProcessorInfo {
        return ProcessorInfo(
            chipName: mapCPUToChipName(device.cpu),
            coreCount: getEstimatedCoreCount(device.cpu),
            performanceLevel: determinePerformanceLevel(device.cpu),
            neuralEngineGeneration: getNeuralEngineGeneration(device.cpu),
            estimatedTops: getEstimatedTops(device.cpu)
        )
    }

    func getDeviceCapabilities() -> DeviceCapabilities {
        return DeviceCapabilities(
            modelName: device.description,
            modelIdentifier: device.identifier,
            hasNeuralEngine: device.cpu.hasNeuralEngine,
            hasFaceID: device.hasFaceID,
            hasTouchID: device.hasTouchID,
            hasLiDAR: device.hasLidarSensor,
            supportsWirelessCharging: device.supportsWirelessCharging,
            batteryLevel: device.batteryLevel,
            thermalState: device.thermalState,
            isSimulator: device.isSimulator
        )
    }

    func getOptimizationProfile() -> OptimizationProfile {
        // Device-specific optimization recommendations
        switch device {
        case .iPhone15Pro, .iPhone15ProMax, .iPhone16Pro, .iPhone16ProMax:
            return .highPerformance
        case _ where device.isPad && device.cpu.isAppleSilicon:
            return .balanced
        default:
            return .powerEfficient
        }
    }
}
```

### 4. Device Specifications Database

```swift
/// Detailed hardware specifications for ML workloads
struct DeviceSpecifications {
    static let specifications: [Device.CPU: ProcessorSpec] = [
        .a17Pro: ProcessorSpec(
            name: "A17 Pro",
            coreCount: 6,
            performanceCores: 2,
            efficiencyCores: 4,
            neuralEngineCores: 16,
            estimatedTops: 35,
            maxMemoryBandwidth: 90, // GB/s
            supportedFrameworks: [.coreML, .onnx, .tflite],
            thermalDesignPower: 8.5
        ),
        .m3: ProcessorSpec(
            name: "M3",
            coreCount: 8,
            performanceCores: 4,
            efficiencyCores: 4,
            neuralEngineCores: 16,
            estimatedTops: 18,
            maxMemoryBandwidth: 100,
            supportedFrameworks: [.coreML, .onnx, .mlx, .tflite],
            thermalDesignPower: 20
        ),
        // ... more specifications
    ]
}
```

---

## Implementation Plan

### Phase 1: Foundation (Day 1-2)

#### 1.1 Add DeviceKit Dependency

**File:** `Package.swift`
```swift
dependencies: [
    .package(url: "https://github.com/devicekit/DeviceKit.git", from: "5.6.0"),
    // existing dependencies...
]

targets: [
    .target(
        name: "RunAnywhere",
        dependencies: [
            "DeviceKit",
            // existing dependencies...
        ]
    )
]
```

#### 1.2 Create DeviceKitAdapter

**File:** `Sources/RunAnywhere/Capabilities/DeviceCapability/Services/DeviceKitAdapter.swift`
```swift
import Foundation
import DeviceKit

/// Bridges DeviceKit functionality to RunAnywhere SDK
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
final class DeviceKitAdapter {

    private let device: Device
    private let logger: SDKLogger

    init(logger: SDKLogger = SDKLogger.shared) {
        self.device = Device.current
        self.logger = logger
        logger.debug("DeviceKit initialized: \(device.description)")
    }

    // MARK: - Processor Information

    func getProcessorInfo() -> ProcessorInfo {
        guard let cpu = device.cpu else {
            logger.warning("Unable to detect CPU, using fallback")
            return getFallbackProcessorInfo()
        }

        let spec = DeviceSpecifications.getSpec(for: cpu)

        return ProcessorInfo(
            chipName: spec.name,
            coreCount: spec.coreCount,
            performanceCores: spec.performanceCores,
            efficiencyCores: spec.efficiencyCores,
            neuralEngineCores: spec.neuralEngineCores,
            estimatedTops: spec.estimatedTops,
            generation: mapToGeneration(cpu),
            hasNeuralEngine: spec.neuralEngineCores > 0
        )
    }

    // MARK: - Device Capabilities

    func getDeviceCapabilities() -> DeviceCapabilities {
        return DeviceCapabilities(
            deviceInfo: DeviceInfo(
                deviceName: device.description,
                deviceModel: device.identifier ?? "Unknown",
                systemName: device.systemName ?? "Unknown",
                systemVersion: device.systemVersion ?? "Unknown"
            ),
            batteryInfo: getBatteryInfo(),
            hardwareConfiguration: getHardwareConfiguration(),
            hardwareAcceleration: getHardwareAcceleration()
        )
    }

    private func getBatteryInfo() -> BatteryInfo? {
        guard device.isBatteryMonitoringEnabled else { return nil }

        return BatteryInfo(
            level: device.batteryLevel.map { Float($0) / 100.0 },
            state: mapBatteryState(device.batteryState),
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    private func getHardwareConfiguration() -> HardwareConfiguration {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let spec = device.cpu.flatMap { DeviceSpecifications.getSpec(for: $0) }

        return HardwareConfiguration(
            totalMemory: totalMemory,
            availableMemory: getAvailableMemory(),
            processorCount: ProcessInfo.processInfo.processorCount,
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount,
            thermalState: ProcessInfo.processInfo.thermalState,
            memoryBandwidth: spec?.maxMemoryBandwidth,
            supportedFrameworks: spec?.supportedFrameworks ?? []
        )
    }

    // MARK: - Performance Optimization

    func getOptimizationProfile() -> ModelOptimizationProfile {
        let batteryLevel = device.batteryLevel ?? 100
        let thermalState = ProcessInfo.processInfo.thermalState

        // High-end devices with good conditions
        if isHighPerformanceDevice() && batteryLevel > 30 && thermalState == .nominal {
            return .highPerformance(
                maxTokensPerSecond: 50,
                maxBatchSize: 8,
                useQuantization: .none,
                preferredFramework: .coreML
            )
        }

        // Battery or thermal constraints
        if batteryLevel < 20 || thermalState == .critical {
            return .powerEfficient(
                maxTokensPerSecond: 10,
                maxBatchSize: 1,
                useQuantization: .int4,
                preferredFramework: .coreML
            )
        }

        // Default balanced mode
        return .balanced(
            maxTokensPerSecond: 25,
            maxBatchSize: 4,
            useQuantization: .int8,
            preferredFramework: determineOptimalFramework()
        )
    }

    private func isHighPerformanceDevice() -> Bool {
        // M-series Macs and recent Pro iPhones/iPads
        switch device {
        case .iPhone15Pro, .iPhone15ProMax, .iPhone16Pro, .iPhone16ProMax:
            return true
        case _ where device.isPad:
            if let cpu = device.cpu,
               [.m1, .m2, .m3, .m4, .a17Pro, .a18Pro].contains(cpu) {
                return true
            }
        case _ where device.isMac:
            return true // All Apple Silicon Macs
        default:
            return false
        }
    }

    // MARK: - Helper Methods

    private func mapToGeneration(_ cpu: Device.CPU) -> ProcessorGeneration {
        switch cpu {
        case .a14Bionic, .m1: return .generation1
        case .a15Bionic, .m2: return .generation2
        case .a16Bionic, .m3: return .generation3
        case .a17Pro, .m4: return .generation4
        case .a18, .a18Pro: return .generation5
        default: return .unknown
        }
    }

    private func determineOptimalFramework() -> LLMFramework {
        guard let cpu = device.cpu else { return .coreML }

        // MLX for M-series Macs
        if device.isMac && cpu.isAppleSilicon {
            return .mlx
        }

        // Default to Core ML for iOS devices
        return .coreML
    }
}
```

#### 1.3 Create Device Specifications

**File:** `Sources/RunAnywhere/Capabilities/DeviceCapability/Data/DeviceSpecifications.swift`
```swift
import DeviceKit

struct ProcessorSpec {
    let name: String
    let coreCount: Int
    let performanceCores: Int
    let efficiencyCores: Int
    let neuralEngineCores: Int
    let estimatedTops: Float
    let maxMemoryBandwidth: Int // GB/s
    let supportedFrameworks: [LLMFramework]
    let thermalDesignPower: Float // Watts
}

enum DeviceSpecifications {
    static func getSpec(for cpu: Device.CPU) -> ProcessorSpec {
        switch cpu {
        // A-Series Chips
        case .a14Bionic:
            return ProcessorSpec(
                name: "A14 Bionic",
                coreCount: 6,
                performanceCores: 2,
                efficiencyCores: 4,
                neuralEngineCores: 16,
                estimatedTops: 11,
                maxMemoryBandwidth: 60,
                supportedFrameworks: [.coreML, .tflite],
                thermalDesignPower: 6
            )

        case .a15Bionic:
            return ProcessorSpec(
                name: "A15 Bionic",
                coreCount: 6,
                performanceCores: 2,
                efficiencyCores: 4,
                neuralEngineCores: 16,
                estimatedTops: 15.8,
                maxMemoryBandwidth: 70,
                supportedFrameworks: [.coreML, .tflite],
                thermalDesignPower: 6.5
            )

        case .a16Bionic:
            return ProcessorSpec(
                name: "A16 Bionic",
                coreCount: 6,
                performanceCores: 2,
                efficiencyCores: 4,
                neuralEngineCores: 16,
                estimatedTops: 17,
                maxMemoryBandwidth: 80,
                supportedFrameworks: [.coreML, .tflite],
                thermalDesignPower: 7
            )

        case .a17Pro:
            return ProcessorSpec(
                name: "A17 Pro",
                coreCount: 6,
                performanceCores: 2,
                efficiencyCores: 4,
                neuralEngineCores: 16,
                estimatedTops: 35,
                maxMemoryBandwidth: 90,
                supportedFrameworks: [.coreML, .onnx, .tflite],
                thermalDesignPower: 8.5
            )

        case .a18, .a18Pro:
            return ProcessorSpec(
                name: cpu == .a18 ? "A18" : "A18 Pro",
                coreCount: 6,
                performanceCores: 2,
                efficiencyCores: 4,
                neuralEngineCores: 16,
                estimatedTops: cpu == .a18 ? 38 : 45,
                maxMemoryBandwidth: 100,
                supportedFrameworks: [.coreML, .onnx, .tflite],
                thermalDesignPower: 9
            )

        // M-Series Chips
        case .m1:
            return ProcessorSpec(
                name: "M1",
                coreCount: 8,
                performanceCores: 4,
                efficiencyCores: 4,
                neuralEngineCores: 16,
                estimatedTops: 11,
                maxMemoryBandwidth: 68,
                supportedFrameworks: [.coreML, .onnx, .mlx, .tflite],
                thermalDesignPower: 15
            )

        case .m2:
            return ProcessorSpec(
                name: "M2",
                coreCount: 8,
                performanceCores: 4,
                efficiencyCores: 4,
                neuralEngineCores: 16,
                estimatedTops: 15.8,
                maxMemoryBandwidth: 100,
                supportedFrameworks: [.coreML, .onnx, .mlx, .tflite],
                thermalDesignPower: 15
            )

        case .m3:
            return ProcessorSpec(
                name: "M3",
                coreCount: 8,
                performanceCores: 4,
                efficiencyCores: 4,
                neuralEngineCores: 16,
                estimatedTops: 18,
                maxMemoryBandwidth: 100,
                supportedFrameworks: [.coreML, .onnx, .mlx, .tflite],
                thermalDesignPower: 20
            )

        case .m4:
            return ProcessorSpec(
                name: "M4",
                coreCount: 10,
                performanceCores: 4,
                efficiencyCores: 6,
                neuralEngineCores: 16,
                estimatedTops: 38,
                maxMemoryBandwidth: 120,
                supportedFrameworks: [.coreML, .onnx, .mlx, .tflite],
                thermalDesignPower: 20
            )

        // Pro/Max/Ultra variants would be added here

        default:
            // Fallback for unknown/older processors
            return ProcessorSpec(
                name: "Unknown",
                coreCount: ProcessInfo.processInfo.processorCount,
                performanceCores: 2,
                efficiencyCores: ProcessInfo.processInfo.processorCount - 2,
                neuralEngineCores: 0,
                estimatedTops: 0,
                maxMemoryBandwidth: 50,
                supportedFrameworks: [.coreML],
                thermalDesignPower: 10
            )
        }
    }
}
```

### Phase 2: Core Integration (Day 3-4)

#### 2.1 Update HardwareDetectionService

**File:** `Sources/RunAnywhere/Capabilities/DeviceCapability/Services/HardwareDetectionService.swift`
```swift
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public final class HardwareDetectionService: HardwareDetector {

    private let deviceKitAdapter: DeviceKitAdapter
    private let logger: SDKLogger

    public init(logger: SDKLogger = SDKLogger.shared) {
        self.logger = logger
        self.deviceKitAdapter = DeviceKitAdapter(logger: logger)
    }

    // MARK: - HardwareDetector Protocol

    public func detectCapabilities() async -> DeviceCapabilities {
        logger.debug("[HardwareDetection] Starting capability detection with DeviceKit")

        let capabilities = deviceKitAdapter.getDeviceCapabilities()

        logger.info("""
            [HardwareDetection] Detected:
            - Device: \(capabilities.deviceInfo.deviceName)
            - Processor: \(capabilities.processorInfo.chipName)
            - Neural Engine: \(capabilities.hardwareAcceleration.neuralEngine ? "Yes (\(capabilities.processorInfo.neuralEngineCores) cores)" : "No")
            - Memory: \(formatBytes(capabilities.hardwareConfiguration.totalMemory))
            - Thermal State: \(capabilities.hardwareConfiguration.thermalState)
            """)

        return capabilities
    }

    public func detectProcessorInfo() async -> ProcessorInfo {
        return deviceKitAdapter.getProcessorInfo()
    }

    public func checkRequirements(_ requirements: HardwareRequirement) async -> Bool {
        let capabilities = await detectCapabilities()

        // Check minimum memory
        if let minMemory = requirements.minimumMemory,
           capabilities.hardwareConfiguration.totalMemory < minMemory {
            logger.warning("Memory requirement not met: \(formatBytes(capabilities.hardwareConfiguration.totalMemory)) < \(formatBytes(minMemory))")
            return false
        }

        // Check Neural Engine requirement
        if requirements.requiresNeuralEngine && !capabilities.hardwareAcceleration.neuralEngine {
            logger.warning("Neural Engine required but not available")
            return false
        }

        // Check minimum OS version
        if let minOSVersion = requirements.minimumOSVersion {
            let currentVersion = capabilities.deviceInfo.systemVersion
            if !isVersionSufficient(current: currentVersion, minimum: minOSVersion) {
                logger.warning("OS version requirement not met: \(currentVersion) < \(minOSVersion)")
                return false
            }
        }

        return true
    }

    // MARK: - Real-time Monitoring

    public func startMonitoring() {
        // Enable battery monitoring
        deviceKitAdapter.enableBatteryMonitoring()

        // Start thermal state monitoring
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateDidChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )

        logger.info("[HardwareDetection] Started real-time monitoring")
    }

    @objc private func thermalStateDidChange(_ notification: Notification) {
        let thermalState = ProcessInfo.processInfo.thermalState
        logger.warning("[HardwareDetection] Thermal state changed: \(thermalState)")

        // Notify optimization service
        if thermalState == .critical {
            NotificationCenter.default.post(
                name: .deviceThrottling,
                object: nil,
                userInfo: ["thermalState": thermalState]
            )
        }
    }
}
```

#### 2.2 Update ProcessorInfo Model

**File:** `Sources/RunAnywhere/Capabilities/DeviceCapability/Models/ProcessorInfo.swift`
```swift
public struct ProcessorInfo: Codable, Sendable {
    public let chipName: String
    public let coreCount: Int
    public let performanceCores: Int
    public let efficiencyCores: Int
    public let neuralEngineCores: Int
    public let estimatedTops: Float
    public let generation: ProcessorGeneration
    public let hasNeuralEngine: Bool

    // New computed properties
    public var performanceTier: PerformanceTier {
        switch estimatedTops {
        case 35...: return .flagship
        case 15...: return .high
        case 10...: return .medium
        default: return .entry
        }
    }

    public var recommendedBatchSize: Int {
        switch performanceTier {
        case .flagship: return 8
        case .high: return 4
        case .medium: return 2
        case .entry: return 1
        }
    }

    public var supportsConcurrentInference: Bool {
        performanceCores >= 4 && neuralEngineCores >= 16
    }
}

public enum ProcessorGeneration: String, Codable, CaseIterable {
    case generation1 = "gen1" // A14, M1
    case generation2 = "gen2" // A15, M2
    case generation3 = "gen3" // A16, M3
    case generation4 = "gen4" // A17 Pro, M4
    case generation5 = "gen5" // A18, A18 Pro
    case unknown = "unknown"
}

public enum PerformanceTier: String, Codable {
    case flagship
    case high
    case medium
    case entry
}
```

### Phase 3: Model Updates and Testing (Day 5)

#### 3.1 Model Selection Enhancement

**File:** `Sources/RunAnywhere/Capabilities/Routing/Services/RoutingService.swift`
```swift
extension RoutingService {

    private func selectOptimalExecution(
        for request: GenerationRequest,
        with capabilities: DeviceCapabilities
    ) -> RoutingDecision {

        let optimizationProfile = deviceKitAdapter.getOptimizationProfile()

        // Check thermal throttling
        if capabilities.hardwareConfiguration.thermalState == .critical {
            logger.warning("Device thermally throttled, routing to cloud")
            return RoutingDecision(
                target: .cloud,
                reason: .thermalThrottling,
                confidence: 0.95
            )
        }

        // Check battery constraints
        if let battery = capabilities.batteryInfo,
           let level = battery.level,
           level < 0.15 && battery.state != .charging {
            logger.warning("Low battery (\(Int(level * 100))%), routing to cloud")
            return RoutingDecision(
                target: .cloud,
                reason: .batteryConstraint,
                confidence: 0.9
            )
        }

        // Device-specific routing
        switch capabilities.processorInfo.performanceTier {
        case .flagship:
            // Can handle large models on-device
            if request.estimatedTokens < 1000 {
                return RoutingDecision(
                    target: .onDevice,
                    reason: .performanceOptimal,
                    confidence: 0.95,
                    suggestedModel: "llama-3.2-3b-q4"
                )
            }

        case .high:
            // Medium models for moderate workloads
            if request.estimatedTokens < 500 {
                return RoutingDecision(
                    target: .onDevice,
                    reason: .balanced,
                    confidence: 0.85,
                    suggestedModel: "llama-3.2-1b-q4"
                )
            }

        case .medium, .entry:
            // Prefer cloud for better experience
            return RoutingDecision(
                target: .cloud,
                reason: .deviceLimitations,
                confidence: 0.8
            )
        }

        // Default to cloud for large requests
        return RoutingDecision(
            target: .cloud,
            reason: .requestComplexity,
            confidence: 0.7
        )
    }
}
```

#### 3.2 Performance Optimization

**File:** `Sources/RunAnywhere/Capabilities/DeviceCapability/Services/PerformanceOptimizer.swift`
```swift
import DeviceKit

class PerformanceOptimizer {
    private let deviceKitAdapter: DeviceKitAdapter

    func optimizeModelLoading(for model: ModelInfo) -> ModelLoadingConfiguration {
        let device = Device.current
        let optimization = deviceKitAdapter.getOptimizationProfile()

        return ModelLoadingConfiguration(
            quantization: optimization.useQuantization,
            batchSize: optimization.maxBatchSize,
            contextLength: determineOptimalContextLength(device),
            useMemoryMapping: device.isPad || device.isMac,
            enableMetalPerformanceShaders: device.cpu?.supportsMetalPerformanceShaders ?? false,
            neuralEngineEnabled: device.cpu?.hasNeuralEngine ?? false
        )
    }

    private func determineOptimalContextLength(_ device: Device) -> Int {
        // Adjust context length based on available memory
        let totalMemory = ProcessInfo.processInfo.physicalMemory

        switch device {
        case _ where device.isPad && totalMemory > 8_000_000_000:
            return 4096 // iPad with 8GB+ RAM
        case _ where totalMemory > 6_000_000_000:
            return 2048 // 6GB+ RAM
        case _ where totalMemory > 4_000_000_000:
            return 1024 // 4GB+ RAM
        default:
            return 512  // Conservative default
        }
    }
}
```

### Phase 4: Cleanup and Documentation (Day 6)

#### 4.1 Framework Selection

**File:** `Sources/RunAnywhere/Capabilities/Compatibility/Services/FrameworkRecommender.swift`
```swift
extension FrameworkRecommender {

    func recommendFramework(
        for model: ModelInfo,
        on device: Device
    ) -> LLMFramework {

        // MLX for M-series Macs
        if device.isMac,
           let cpu = device.cpu,
           cpu.isAppleSilicon,
           model.supportedFrameworks.contains(.mlx) {
            return .mlx
        }

        // Core ML for iOS with Neural Engine
        if device.isPhone || device.isPad,
           device.cpu?.hasNeuralEngine ?? false,
           model.supportedFrameworks.contains(.coreML) {
            return .coreML
        }

        // ONNX for cross-platform compatibility
        if model.supportedFrameworks.contains(.onnx) {
            return .onnx
        }

        // TensorFlow Lite as fallback
        return .tflite
    }
}
```

#### 4.2 Update ServiceContainer

**File:** `Sources/RunAnywhere/Foundation/DependencyInjection/ServiceContainer.swift`
```swift
extension ServiceContainer {

    private func registerHardwareServices() {
        // Register DeviceKit adapter
        register(DeviceKitAdapter.self) { _ in
            DeviceKitAdapter(logger: self.logger)
        }
        .inObjectScope(.singleton)

        // Update hardware detection to use DeviceKit
        register(HardwareDetector.self) { resolver in
            HardwareDetectionService(
                logger: self.logger,
                deviceKitAdapter: resolver.resolve(DeviceKitAdapter.self)!
            )
        }
        .inObjectScope(.singleton)

        // Register performance optimizer
        register(PerformanceOptimizer.self) { resolver in
            PerformanceOptimizer(
                deviceKitAdapter: resolver.resolve(DeviceKitAdapter.self)!,
                logger: self.logger
            )
        }
        .inObjectScope(.singleton)
    }
}
```

### Phase 5: Final Testing and Validation (Day 7)

#### 5.1 Performance Validation

**Validation Steps:**
1. **Device Detection Performance**
   - Measure detection time across different devices
   - Ensure <10ms detection latency
   - Verify memory usage stays under 1MB increase

2. **Battery Impact Testing**
   - Monitor battery drain with monitoring enabled
   - Ensure negligible impact on battery life
   - Test thermal state monitoring efficiency

3. **App Size Analysis**
   - Measure binary size increase
   - Ensure increase stays under 500KB
   - Verify dead code stripping works properly

#### 5.2 Documentation Updates

**Files to Update:**
- `README.md` - Add DeviceKit integration notes
- `ARCHITECTURE.md` - Update device detection architecture
- `API_REFERENCE.md` - Document new device capability APIs
- `MIGRATION_GUIDE.md` - Guide for migrating from old detection

### Migration Strategy

#### 1. Feature Flag Implementation

```swift
struct FeatureFlags {
    static var useDeviceKit: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "feature.useDeviceKit")
        #else
        return true // Enabled in production after testing
        #endif
    }
}
```

#### 2. Gradual Rollout

```swift
class HardwareDetectionService {
    func detectCapabilities() async -> DeviceCapabilities {
        if FeatureFlags.useDeviceKit {
            return deviceKitAdapter.getDeviceCapabilities()
        } else {
            return legacyDetection() // Old implementation
        }
    }
}
```

#### 3. Backward Compatibility

```swift
extension ProcessorInfo {
    // Maintain old initializer for compatibility
    init(chipName: String, coreCount: Int) {
        self.init(
            chipName: chipName,
            coreCount: coreCount,
            performanceCores: coreCount / 2,
            efficiencyCores: coreCount / 2,
            neuralEngineCores: 0,
            estimatedTops: 0,
            generation: .unknown,
            hasNeuralEngine: false
        )
    }
}
```

---

## Risk Mitigation

### 1. Dependency Management

**Risk:** DeviceKit updates might break compatibility
**Mitigation:**
- Pin to specific version (5.6.0)
- Create abstraction layer (DeviceKitAdapter)
- Maintain fallback detection logic
- Add comprehensive tests

### 2. Performance Impact

**Risk:** Additional framework might increase app size
**Mitigation:**
- DeviceKit is lightweight (~200KB)
- Use dead code stripping
- Lazy load device detection
- Cache detection results

### 3. Platform Support

**Risk:** DeviceKit might not support all platforms
**Mitigation:**
- Conditional compilation for unsupported platforms
- Fallback to ProcessInfo on macOS if needed
- Maintain legacy detection as backup

---

## Success Criteria

### Functional Requirements
- [ ] All current Apple devices correctly identified
- [ ] Processor specifications accurate for A14-A18, M1-M4
- [ ] Neural Engine detection works correctly
- [ ] Thermal and battery monitoring functional
- [ ] No regression in existing functionality

### Performance Requirements
- [ ] Device detection completes in <10ms
- [ ] No increase in memory usage >1MB
- [ ] Battery monitoring has negligible impact
- [ ] App size increase <500KB

### Quality Requirements
- [ ] Zero crashes in device detection
- [ ] Graceful fallbacks for edge cases
- [ ] Clear logging for debugging
- [ ] Comprehensive documentation updated

---

## Implementation Timeline (1 Week Sprint)

### Phase 1: Foundation (Day 1-2)
✅ DeviceKit already added to Package.swift
- [ ] Create DeviceKitAdapter.swift in DeviceCapability/Services/
- [ ] Create DeviceSpecifications.swift in DeviceCapability/Data/
- [ ] Create ProcessorDatabase.swift with chip specifications
- [ ] Initial DeviceKit integration testing

### Phase 2: Core Integration (Day 3-4)
- [ ] Update ProcessorInfo.swift with new fields (chipName, neuralEngineCores, estimatedTops)
- [ ] Update DeviceInfo.swift to use DeviceKit for model names
- [ ] Replace ProcessorDetector implementation with DeviceKit
- [ ] Update HardwareDetectionService to use DeviceKitAdapter

### Phase 3: Model Updates and Testing (Day 5)
- [ ] Update DeviceCapabilities.swift - remove hardcoded ProcessorType enum
- [ ] Update CapabilityAnalyzer to use DeviceKit data
- [ ] Test on simulator and physical devices
- [ ] Verify all device detection works correctly

### Phase 4: Cleanup and Documentation (Day 6)
- [ ] Remove legacy hardcoded detection logic
- [ ] Update API documentation
- [ ] Update ARCHITECTURE_V2.md with DeviceKit integration
- [ ] Create migration guide for existing code

### Phase 5: Final Testing and Validation (Day 7)
- [ ] Performance benchmarking
- [ ] Memory impact analysis
- [ ] Full integration testing
- [ ] Release preparation

---

## Key Implementation Notes

### Current Status
- ✅ DeviceKit dependency already added to Package.swift (line 26)
- 🔧 Need to create DeviceKitAdapter to bridge DeviceKit with our models
- 🔧 ProcessorDetector needs complete replacement
- 🔧 DeviceInfo needs update to return specific device names
- 🔧 DeviceCapabilities ProcessorType enum needs replacement with dynamic detection

### Priority Order
1. **DeviceKitAdapter** - Core adapter implementation
2. **DeviceSpecifications** - Processor specs database
3. **Model Updates** - ProcessorInfo, DeviceInfo, DeviceCapabilities
4. **Service Integration** - Update existing services to use adapter
5. **Legacy Removal** - Clean up hardcoded detection logic

### Files to Modify
- `DeviceCapability/Services/ProcessorDetector.swift` - Replace implementation
- `DeviceCapability/Services/HardwareDetectionService.swift` - Use adapter
- `DeviceCapability/Services/CapabilityAnalyzer.swift` - Use DeviceKit data
- `DeviceCapability/Models/DeviceInfo.swift` - Use DeviceKit names
- `DeviceCapability/Models/ProcessorInfo.swift` - Add new fields
- `DeviceCapability/Models/DeviceCapabilities.swift` - Remove hardcoded enum

### Files to Create
- `DeviceCapability/Services/DeviceKitAdapter.swift` - Main adapter
- `DeviceCapability/Data/DeviceSpecifications.swift` - Specs database
- `DeviceCapability/Data/ProcessorDatabase.swift` - Processor info DB

## Conclusion

This DeviceKit integration will transform the RunAnywhere SDK's device detection from a maintenance burden to a robust, future-proof system. The integration is already partially prepared (DeviceKit dependency added), and the implementation focuses on creating an adapter layer that preserves the existing API while providing accurate device detection.

Key benefits:
- Automatic support for all current and future Apple devices
- Accurate processor identification (no more "M2" detected as "M1 Pro/M2")
- Specific device names ("iPhone 15 Pro" instead of "iPhone")
- Real Neural Engine detection instead of assumptions
- Zero maintenance for new device releases
