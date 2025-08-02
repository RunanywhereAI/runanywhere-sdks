import Foundation
import Metal
#if canImport(UIKit)
import UIKit
#endif

/// Service for checking device and system requirements
class RequirementChecker {
    private let logger = SDKLogger(category: "RequirementChecker")

    func checkDeviceSupport(for framework: LLMFramework) -> DeviceSupport {
        guard let capability = FrameworkCapabilities.getCapability(for: framework) else {
            return DeviceSupport(isSupported: false, issues: ["Framework not found"])
        }

        var issues: [String] = []

        // Check OS version
        if !isOSVersionSupported(minimumVersion: capability.minimumOS) {
            issues.append("Requires iOS \(capability.minimumOS) or later")
        }

        // Check architecture
        if !isArchitectureSupported(supportedArchitectures: capability.supportedArchitectures) {
            issues.append("Requires one of: \(capability.supportedArchitectures.joined(separator: ", "))")
        }

        // Check framework-specific requirements
        let frameworkIssues = checkFrameworkSpecificRequirements(framework: framework)
        issues.append(contentsOf: frameworkIssues)

        return DeviceSupport(
            isSupported: issues.isEmpty,
            issues: issues
        )
    }

    func checkModelRequirements(model: ModelInfo, framework: LLMFramework) -> RequirementResult {
        var issues: [String] = []
        var warnings: [String] = []

        // Check device support first
        let deviceSupport = checkDeviceSupport(for: framework)
        if !deviceSupport.isSupported {
            issues.append(contentsOf: deviceSupport.issues)
        }

        // Check model-specific requirements
        for requirement in model.hardwareRequirements {
            let result = checkHardwareRequirement(requirement)
            if !result.satisfied {
                if result.critical {
                    issues.append(result.message)
                } else {
                    warnings.append(result.message)
                }
            }
        }

        // Check memory requirements
        let memoryResult = checkMemoryRequirements(modelSize: model.estimatedMemory)
        if !memoryResult.sufficient {
            if memoryResult.critical {
                issues.append("Insufficient memory: requires \(ByteCountFormatter.string(fromByteCount: model.estimatedMemory, countStyle: .binary))")
            } else {
                warnings.append("Limited memory: performance may be affected")
            }
        }

        return RequirementResult(
            satisfied: issues.isEmpty,
            issues: issues,
            warnings: warnings
        )
    }

    private func isOSVersionSupported(minimumVersion: String) -> Bool {
        guard let minimumVersion = parseVersion(minimumVersion) else {
            return false
        }

        let currentVersion = parseVersion(getCurrentOSVersion())
        guard let currentVersion = currentVersion else {
            return false
        }

        return currentVersion >= minimumVersion
    }

    private func isArchitectureSupported(supportedArchitectures: [String]) -> Bool {
        let currentArchitecture = getCurrentArchitecture()
        return supportedArchitectures.contains(currentArchitecture)
    }

    private func checkFrameworkSpecificRequirements(framework: LLMFramework) -> [String] {
        var issues: [String] = []

        switch framework {
        case .foundationModels:
            // Check for Foundation Models availability
            if !isFoundationModelsAvailable() {
                issues.append("Foundation Models not available on this device")
            }

        case .coreML:
            // Core ML is available on all supported iOS versions
            break

        case .mlx:
            // MLX requires Apple Silicon
            if !isAppleSilicon() {
                issues.append("MLX requires Apple Silicon (M1/M2/A-series chips)")
            }

        case .tensorFlowLite:
            // Check if Metal is available for GPU acceleration
            if !isMetalAvailable() {
                issues.append("Metal not available for GPU acceleration")
            }

        default:
            break
        }

        return issues
    }

    private func checkHardwareRequirement(_ requirement: HardwareRequirement) -> HardwareRequirementResult {
        switch requirement {
        case .minimumMemory(let required):
            let available = getAvailableMemory()
            return HardwareRequirementResult(
                satisfied: available >= required,
                critical: true,
                message: "Requires \(ByteCountFormatter.string(fromByteCount: required, countStyle: .binary)) memory"
            )

        case .requiresNeuralEngine:
            let hasNE = hasNeuralEngine()
            return HardwareRequirementResult(
                satisfied: hasNE,
                critical: false,
                message: hasNE ? "" : "Neural Engine not available - will use CPU"
            )

        case .requiresGPU:
            let hasGPU = isMetalAvailable()
            return HardwareRequirementResult(
                satisfied: hasGPU,
                critical: false,
                message: hasGPU ? "" : "GPU not available - will use CPU"
            )

        case .specificChip(let chip):
            let currentChip = getCurrentChip()
            let isCompatible = isChipCompatible(current: currentChip, required: chip)
            return HardwareRequirementResult(
                satisfied: isCompatible,
                critical: true,
                message: isCompatible ? "" : "Requires \(chip) or compatible chip"
            )
        }
    }

    private func checkMemoryRequirements(modelSize: Int64) -> MemoryRequirementResult {
        let availableMemory = getAvailableMemory()
        let requiredMemory = modelSize + 1_000_000_000 // Add 1GB overhead

        if availableMemory >= requiredMemory {
            return MemoryRequirementResult(sufficient: true, critical: false)
        } else if availableMemory >= modelSize {
            return MemoryRequirementResult(sufficient: false, critical: false) // Warning
        } else {
            return MemoryRequirementResult(sufficient: false, critical: true) // Error
        }
    }

    // MARK: - System Information

    private func getCurrentOSVersion() -> String {
        return UIDevice.current.systemVersion
    }

    private func getCurrentArchitecture() -> String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }

        // Map machine identifier to architecture
        if machine.hasPrefix("iPhone") || machine.hasPrefix("iPad") {
            return "arm64"
        } else if machine.hasPrefix("arm64") {
            return "arm64e"
        } else {
            return machine
        }
    }

    private func getAvailableMemory() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            return Int64(info.resident_size)
        } else {
            return 4_000_000_000 // Default to 4GB if unable to determine
        }
    }

    private func hasNeuralEngine() -> Bool {
        // Check if Neural Engine is available (A11 and later)
        let architecture = getCurrentArchitecture()
        return architecture.contains("arm64")
    }

    private func isMetalAvailable() -> Bool {
        return MTLCreateSystemDefaultDevice() != nil
    }

    private func isAppleSilicon() -> Bool {
        let architecture = getCurrentArchitecture()
        return architecture.contains("arm64")
    }

    private func isFoundationModelsAvailable() -> Bool {
        // Foundation Models require iOS 18.0+
        return isOSVersionSupported(minimumVersion: "18.0")
    }

    private func getCurrentChip() -> String {
        // This would need more sophisticated chip detection
        // For now, return a generic identifier
        return "A-series"
    }

    private func isChipCompatible(current: String, required: String) -> Bool {
        // Simplified compatibility check
        return current.contains("A") && required.contains("A")
    }

    private func parseVersion(_ version: String) -> [Int]? {
        let components = version.split(separator: ".").compactMap { Int($0) }
        return components.isEmpty ? nil : components
    }
}

/// Device support result
struct DeviceSupport {
    let isSupported: Bool
    let issues: [String]
}

/// Requirement check result
struct RequirementResult {
    let satisfied: Bool
    let issues: [String]
    let warnings: [String]
}

/// Hardware requirement check result
private struct HardwareRequirementResult {
    let satisfied: Bool
    let critical: Bool
    let message: String
}

/// Memory requirement check result
private struct MemoryRequirementResult {
    let sufficient: Bool
    let critical: Bool
}
