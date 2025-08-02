#if os(iOS) || os(tvOS)
import UIKit
import Darwin

/// iOS-specific hardware detector with accurate device identification
public class iOSHardwareDetector: HardwareDetector {

    public init() {}

    public func detectCapabilities() -> DeviceCapabilities {
        return DeviceCapabilities(
            totalMemory: Int64(ProcessInfo.processInfo.physicalMemory),
            availableMemory: getAvailableMemory(),
            hasNeuralEngine: detectNeuralEngine(),
            hasGPU: detectGPU(),
            processorCount: ProcessInfo.processInfo.processorCount,
            processorType: detectProcessorType(),
            supportedAccelerators: detectSupportedAccelerators(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersion,
            modelIdentifier: getModelIdentifier()
        )
    }

    public func getAvailableMemory() -> Int64 {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<natural_t>.stride)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return Int64(ProcessInfo.processInfo.physicalMemory) / 2
        }

        let pageSize = UInt64(vm_kernel_page_size)
        return Int64(UInt64(info.free_count + info.inactive_count) * pageSize)
    }

    public func getTotalMemory() -> Int64 {
        Int64(ProcessInfo.processInfo.physicalMemory)
    }

    public func hasNeuralEngine() -> Bool {
        let modelId = getModelIdentifier()

        // iPhone models with Neural Engine (A11 and later)
        let neuralEngineModels = [
            "iPhone10,", "iPhone11,", "iPhone12,", "iPhone13,",
            "iPhone14,", "iPhone15,", "iPhone16,", "iPhone17,"
        ]

        return neuralEngineModels.contains { modelId.hasPrefix($0) }
    }

    public func hasGPU() -> Bool {
        return true // All iOS devices have GPU
    }

    public func getProcessorInfo() -> ProcessorInfo {
        let modelId = getModelIdentifier()
        let processorName = mapModelToProcessor(modelId)
        let (performanceCores, efficiencyCores) = getCoreConfiguration(modelId)

        return ProcessorInfo(
            name: processorName,
            architecture: "ARM64",
            coreCount: ProcessInfo.processInfo.processorCount,
            performanceCoreCount: performanceCores,
            efficiencyCoreCount: efficiencyCores,
            hasARM64E: true
        )
    }

    public func getThermalState() -> ProcessInfo.ThermalState {
        return ProcessInfo.processInfo.thermalState
    }

    public func getBatteryInfo() -> BatteryInfo? {
        UIDevice.current.isBatteryMonitoringEnabled = true

        return BatteryInfo(
            level: UIDevice.current.batteryLevel,
            state: UIDevice.current.batteryState.toBatteryState(),
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    // MARK: - Private Methods

    private func getModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }
    }

    private func detectProcessorType() -> DeviceCapabilities.ProcessorType {
        let modelId = getModelIdentifier()

        if modelId.contains("iPhone17,") { return .a18Pro }
        if modelId.contains("iPhone16,") { return .a18 }
        if modelId.contains("iPhone15,") { return .a17Pro }
        if modelId.contains("iPhone14,") { return .a16Bionic }
        if modelId.contains("iPhone13,") { return .a15Bionic }
        if modelId.contains("iPhone12,") { return .a14Bionic }
        if modelId.contains("iPad16,") { return .m4 }
        if modelId.contains("iPad15,") { return .m4 }
        if modelId.contains("iPad14,") { return .m2 }
        if modelId.contains("iPad13,") { return .m1 }

        return .unknown
    }

    private func detectNeuralEngine() -> Bool {
        return hasNeuralEngine()
    }

    private func detectGPU() -> Bool {
        return hasGPU()
    }

    private func detectSupportedAccelerators() -> [HardwareAcceleration] {
        var accelerators: [HardwareAcceleration] = [.cpu]

        if hasGPU() {
            accelerators.append(.gpu)
            accelerators.append(.metal)
        }

        if hasNeuralEngine() {
            accelerators.append(.neuralEngine)
            accelerators.append(.coreML)
        }

        return accelerators
    }

    private func mapModelToProcessor(_ modelId: String) -> String {
        let processorMap: [String: String] = [
            "iPhone17,": "A18 Pro",
            "iPhone16,": "A18",
            "iPhone15,": "A17 Pro",
            "iPhone14,": "A16 Bionic",
            "iPhone13,": "A15 Bionic",
            "iPhone12,": "A14 Bionic",
            "iPad16,": "M4",
            "iPad15,": "M4",
            "iPad14,": "M2",
            "iPad13,": "M1"
        ]

        for (prefix, processor) in processorMap {
            if modelId.hasPrefix(prefix) {
                return processor
            }
        }

        return "Unknown Processor"
    }

    private func getCoreConfiguration(_ modelId: String) -> (performance: Int, efficiency: Int) {
        // Core configuration based on chip type
        if modelId.contains("iPhone17,") { return (2, 4) } // A18 Pro
        if modelId.contains("iPhone16,") { return (2, 4) } // A18
        if modelId.contains("iPhone15,") { return (2, 4) } // A17 Pro
        if modelId.contains("iPhone14,") { return (2, 4) } // A16 Bionic
        if modelId.contains("iPhone13,") { return (2, 4) } // A15 Bionic
        if modelId.contains("iPhone12,") { return (2, 4) } // A14 Bionic
        if modelId.contains("iPad16,") { return (4, 6) }   // M4 (varies by model)
        if modelId.contains("iPad15,") { return (4, 6) }   // M4 (varies by model)
        if modelId.contains("iPad14,") { return (4, 4) }   // M2
        if modelId.contains("iPad13,") { return (4, 4) }   // M1

        // Default fallback
        let totalCores = ProcessInfo.processInfo.processorCount
        return (totalCores / 2, totalCores / 2)
    }
}

// MARK: - Extensions

private extension UIDevice.BatteryState {
    func toBatteryState() -> BatteryInfo.BatteryState {
        switch self {
        case .unknown: return .unknown
        case .unplugged: return .unplugged
        case .charging: return .charging
        case .full: return .full
        @unknown default: return .unknown
        }
    }
}

#endif
