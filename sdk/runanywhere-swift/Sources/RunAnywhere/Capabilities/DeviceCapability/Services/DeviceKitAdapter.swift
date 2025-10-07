//
//  DeviceKitAdapter.swift
//  RunAnywhere SDK
//
//  Bridges DeviceKit functionality to RunAnywhere SDK
//

import Foundation
import DeviceKit
#if os(iOS) || os(tvOS)
import UIKit
#endif
#if os(watchOS)
import WatchKit
#endif

/// Bridges DeviceKit functionality to RunAnywhere SDK
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public final class DeviceKitAdapter {

    // MARK: - Properties

    private let device: Device
    private let logger = SDKLogger(category: "DeviceKitAdapter")

    // MARK: - Initialization

    public init() {
        self.device = Device.current
    }

    // MARK: - Processor Information

    /// Get detailed processor information
    public func getProcessorInfo() -> ProcessorInfo {
        #if os(iOS) || os(tvOS) || os(watchOS)
        // Get CPU from device identifier
        let cpuInfo = detectCPUFromDevice()
        let spec = DeviceSpecifications.getSpec(for: cpuInfo.cpu, variant: cpuInfo.variant)

        return ProcessorInfo(
            chipName: spec.name,
            coreCount: spec.coreCount,
            performanceCores: spec.performanceCores,
            efficiencyCores: spec.efficiencyCores,
            architecture: "ARM64",
            hasARM64E: true,
            clockFrequency: spec.estimatedClockSpeed,
            neuralEngineCores: spec.neuralEngineCores,
            estimatedTops: spec.estimatedTops
        )
        #else
        // macOS handling
        return getMacProcessorInfo()
        #endif
    }

    /// Get device name and model
    public func getDeviceInfo() -> (name: String, model: String) {
        #if os(iOS) || os(tvOS) || os(watchOS)
        return (device.description, getDeviceIdentifier())
        #else
        return ("Mac", getMacModelName())
        #endif
    }

    private func getDeviceIdentifier() -> String {
        #if os(iOS) || os(tvOS) || os(watchOS)
        // Get the raw device identifier string
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
        #else
        return getMacModelName()
        #endif
    }

    /// Get device capabilities
    public func getDeviceCapabilities() -> DeviceCapabilities {
        let processorInfo = getProcessorInfo()
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let availableMemory = getAvailableMemory()

        return DeviceCapabilities(
            totalMemory: Int64(totalMemory),
            availableMemory: availableMemory,
            hasNeuralEngine: processorInfo.neuralEngineCores > 0,
            hasGPU: true, // All modern Apple devices have GPU
            processorCount: processorInfo.coreCount,
            processorType: getProcessorType(),
            supportedAccelerators: getSupportedAccelerators(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersion,
            modelIdentifier: getDeviceIdentifier()
        )
    }

    /// Get optimization profile based on device
    public func getOptimizationProfile() -> OptimizationProfile {
        let battery = getBatteryInfo()
        let thermalState = ProcessInfo.processInfo.thermalState

        // Check constraints
        if let batteryLevel = battery?.level, batteryLevel < 0.2 {
            return .powerEfficient
        }

        if thermalState == .critical || thermalState == .serious {
            return .powerEfficient
        }

        // Device-specific optimization
        #if os(iOS) || os(tvOS)
        switch device {
        case .iPhone15Pro, .iPhone15ProMax, .iPhone16Pro, .iPhone16ProMax:
            return .highPerformance
        case _ where device.description.contains("iPad Pro"):
            return .highPerformance
        case _ where device.isPad:
            return .balanced
        default:
            return .balanced
        }
        #else
        // Mac always high performance when not constrained
        return .highPerformance
        #endif
    }

    /// Get battery information
    public func getBatteryInfo() -> BatteryInfo? {
        #if os(iOS) || os(watchOS)
        #if os(iOS)
        let wasBatteryMonitoringEnabled = UIDevice.current.isBatteryMonitoringEnabled
        if !wasBatteryMonitoringEnabled {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        #elseif os(watchOS)
        let wasBatteryMonitoringEnabled = WKInterfaceDevice.current().isBatteryMonitoringEnabled
        if !wasBatteryMonitoringEnabled {
            WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        }
        #endif

        let level = device.batteryLevel.map { Float($0) / 100.0 }
        let state = mapBatteryState(device.batteryState)

        return BatteryInfo(
            level: level,
            state: state,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        #else
        return nil // No battery on macOS/tvOS
        #endif
    }

    /// Enable battery monitoring
    public func enableBatteryMonitoring() {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        logger.debug("[DeviceKit] Battery monitoring enabled")
        #elseif os(watchOS)
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        logger.debug("[DeviceKit] Battery monitoring enabled")
        #endif
    }

    // MARK: - Private Methods

    private func detectCPUFromDevice() -> (cpu: CPUType, variant: ProcessorVariant) {
        #if os(iOS) || os(tvOS) || os(watchOS)
        // Map device to CPU type based on known configurations
        switch device {
        // A18 Pro devices
        case .iPhone16Pro, .iPhone16ProMax:
            return (.a18Pro, .standard)

        // A18 devices
        case .iPhone16, .iPhone16Plus:
            return (.a18, .standard)

        // A17 Pro devices
        case .iPhone15Pro, .iPhone15ProMax:
            return (.a17Pro, .standard)

        // A16 devices
        case .iPhone15, .iPhone15Plus, .iPhone14Pro, .iPhone14ProMax:
            return (.a16Bionic, .standard)

        // A15 devices
        case .iPhone14, .iPhone14Plus, .iPhone13, .iPhone13Mini, .iPhone13Pro, .iPhone13ProMax, .iPhoneSE3:
            return (.a15Bionic, .standard)

        // iPad M4
        case .iPadPro13M4, .iPadPro11M4:
            return (.m4, .standard)

        // iPad M2
        case .iPadPro12Inch6, .iPadPro11Inch4, .iPadAir11M2, .iPadAir13M2:
            return (.m2, .standard)

        // iPad M1
        case .iPadPro12Inch5, .iPadPro11Inch3, .iPadAir5:
            return (.m1, .standard)

        // Older iPads with A-series
        case .iPad10:
            return (.a14Bionic, .standard)

        case .iPadMini6:
            return (.a15Bionic, .standard)

        default:
            // Fallback detection based on device age/type
            if device.isPad {
                return (.a14Bionic, .standard) // Conservative fallback for iPads
            } else {
                return (.a15Bionic, .standard) // Conservative fallback for iPhones
            }
        }
        #else
        return (.unknown, .standard)
        #endif
    }

    private func getMacProcessorInfo() -> ProcessorInfo {
        #if os(macOS)
        // Detect Mac processor using system info
        let cpuInfo = detectMacCPU()
        let spec = DeviceSpecifications.getSpec(for: cpuInfo.cpu, variant: cpuInfo.variant)

        return ProcessorInfo(
            chipName: spec.name,
            coreCount: spec.coreCount,
            performanceCores: spec.performanceCores,
            efficiencyCores: spec.efficiencyCores,
            architecture: "ARM64",
            hasARM64E: true,
            clockFrequency: spec.estimatedClockSpeed,
            neuralEngineCores: spec.neuralEngineCores,
            estimatedTops: spec.estimatedTops
        )
        #else
        return ProcessorInfo(
            coreCount: ProcessInfo.processInfo.processorCount,
            performanceCores: 2,
            efficiencyCores: 2,
            architecture: "Unknown",
            hasARM64E: false,
            clockFrequency: 0.0
        )
        #endif
    }

    private func detectMacCPU() -> (cpu: CPUType, variant: ProcessorVariant) {
        #if os(macOS)
        // Use sysctlbyname to get chip info
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)

        var cpuBrand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &cpuBrand, &size, nil, 0)
        let brandString = String(cString: cpuBrand)

        // Parse brand string to determine chip
        if brandString.contains("M4") {
            if brandString.contains("Max") {
                return (.m4, .max)
            } else if brandString.contains("Pro") {
                return (.m4, .pro)
            } else {
                return (.m4, .standard)
            }
        } else if brandString.contains("M3") {
            if brandString.contains("Max") {
                return (.m3, .max)
            } else if brandString.contains("Pro") {
                return (.m3, .pro)
            } else if brandString.contains("Ultra") {
                return (.m3, .ultra)
            } else {
                return (.m3, .standard)
            }
        } else if brandString.contains("M2") {
            if brandString.contains("Max") {
                return (.m2, .max)
            } else if brandString.contains("Pro") {
                return (.m2, .pro)
            } else if brandString.contains("Ultra") {
                return (.m2, .ultra)
            } else {
                return (.m2, .standard)
            }
        } else if brandString.contains("M1") {
            if brandString.contains("Max") {
                return (.m1, .max)
            } else if brandString.contains("Pro") {
                return (.m1, .pro)
            } else if brandString.contains("Ultra") {
                return (.m1, .ultra)
            } else {
                return (.m1, .standard)
            }
        } else if brandString.contains("Intel") {
            return (.intel, .standard)
        }

        // Fallback to core count detection
        let coreCount = ProcessInfo.processInfo.processorCount
        if coreCount >= 20 {
            return (.m2, .ultra) // Ultra chips have 20+ cores
        } else if coreCount >= 14 {
            return (.m3, .max) // Max chips have 14-16 cores
        } else if coreCount >= 10 {
            return (.m3, .pro) // Pro chips have 10-12 cores
        } else {
            return (.m2, .standard) // Conservative fallback
        }
        #else
        return (.unknown, .standard)
        #endif
    }

    private func getMacModelName() -> String {
        #if os(macOS)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)

        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)

        return String(cString: model)
        #else
        return "Unknown"
        #endif
    }

    private func getProcessorType() -> ProcessorType {
        let cpuInfo = detectCPUFromDevice()

        switch cpuInfo.cpu {
        case .a14Bionic: return .a14Bionic
        case .a15Bionic: return .a15Bionic
        case .a16Bionic: return .a16Bionic
        case .a17Pro: return .a17Pro
        case .a18: return .a18
        case .a18Pro: return .a18Pro
        case .m1:
            switch cpuInfo.variant {
            case .pro: return .m1Pro
            case .max: return .m1Max
            case .ultra: return .m1Ultra
            default: return .m1
            }
        case .m2:
            switch cpuInfo.variant {
            case .pro: return .m2Pro
            case .max: return .m2Max
            case .ultra: return .m2Ultra
            default: return .m2
            }
        case .m3:
            switch cpuInfo.variant {
            case .pro: return .m3Pro
            case .max: return .m3Max
            default: return .m3
            }
        case .m4:
            switch cpuInfo.variant {
            case .pro: return .m4Pro
            case .max: return .m4Max
            default: return .m4
            }
        case .intel: return .intel
        default: return .unknown
        }
    }

    private func getSupportedAccelerators() -> [HardwareAcceleration] {
        var accelerators: [HardwareAcceleration] = [.cpu]

        let processorInfo = getProcessorInfo()

        if processorInfo.neuralEngineCores > 0 {
            accelerators.append(.neuralEngine)
        }

        accelerators.append(.gpu) // All Apple devices have GPU

        return accelerators
    }

    private func getAvailableMemory() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        let used = result == KERN_SUCCESS ? Int64(info.resident_size) : 0
        return Int64(ProcessInfo.processInfo.physicalMemory) - used
    }

    #if os(iOS) || os(watchOS)
    private func mapBatteryState(_ state: Device.BatteryState?) -> BatteryState {
        guard let state = state else { return .unknown }

        switch state {
        case .full:
            return .full
        case .charging(_):
            return .charging
        case .unplugged:
            return .unplugged
        }
    }
    #endif
}

// MARK: - Supporting Types

public enum OptimizationProfile {
    case highPerformance
    case balanced
    case powerEfficient
}

public enum CPUType {
    case a14Bionic
    case a15Bionic
    case a16Bionic
    case a17Pro
    case a18
    case a18Pro
    case m1
    case m2
    case m3
    case m4
    case intel
    case unknown
}

public enum ProcessorVariant {
    case standard
    case pro
    case max
    case ultra
}
