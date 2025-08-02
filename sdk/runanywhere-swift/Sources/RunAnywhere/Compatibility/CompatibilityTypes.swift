//
//  CompatibilityTypes.swift
//  RunAnywhere SDK
//
//  Types for model compatibility checking
//

import Foundation

/// Quantization types for models
public enum QuantizationType: String, CaseIterable {
    case none = "none"
    case q2_K = "Q2_K"
    case q3_K_S = "Q3_K_S"
    case q3_K_M = "Q3_K_M"
    case q3_K_L = "Q3_K_L"
    case q4_0 = "Q4_0"
    case q4_K_S = "Q4_K_S"
    case q4_K_M = "Q4_K_M"
    case q5_0 = "Q5_0"
    case q5_K_S = "Q5_K_S"
    case q5_K_M = "Q5_K_M"
    case q6_K = "Q6_K"
    case q8_0 = "Q8_0"
    case f16 = "F16"
    case f32 = "F32"

    public var displayName: String {
        rawValue
    }

    /// Memory multiplier for this quantization
    public var memoryMultiplier: Double {
        switch self {
        case .none, .f32: return 1.0
        case .f16: return 0.5
        case .q8_0: return 0.25
        case .q6_K: return 0.20
        case .q5_0, .q5_K_S, .q5_K_M: return 0.16
        case .q4_0, .q4_K_S, .q4_K_M: return 0.125
        case .q3_K_S, .q3_K_M, .q3_K_L: return 0.10
        case .q2_K: return 0.0625
        }
    }
}

/// Model architectures
public enum ModelArchitecture: String, CaseIterable {
    case llama
    case mistral
    case phi
    case qwen
    case gemma
    case gpt2
    case bert
    case t5
    case falcon
    case starcoder
    case codegen
    case custom

    public var displayName: String {
        switch self {
        case .llama: return "LLaMA"
        case .mistral: return "Mistral"
        case .phi: return "Phi"
        case .qwen: return "Qwen"
        case .gemma: return "Gemma"
        case .gpt2: return "GPT-2"
        case .bert: return "BERT"
        case .t5: return "T5"
        case .falcon: return "Falcon"
        case .starcoder: return "StarCoder"
        case .codegen: return "CodeGen"
        case .custom: return "Custom"
        }
    }
}

/// Framework capability description
public struct FrameworkCapability {
    public let supportedFormats: [ModelFormat]
    public let supportedQuantizations: [QuantizationType]
    public let maxModelSize: Int64
    public let requiresSpecificModels: Bool
    public let minimumOS: String
    public let supportedArchitectures: [String]

    public init(
        supportedFormats: [ModelFormat],
        supportedQuantizations: [QuantizationType],
        maxModelSize: Int64,
        requiresSpecificModels: Bool,
        minimumOS: String,
        supportedArchitectures: [String]
    ) {
        self.supportedFormats = supportedFormats
        self.supportedQuantizations = supportedQuantizations
        self.maxModelSize = maxModelSize
        self.requiresSpecificModels = requiresSpecificModels
        self.minimumOS = minimumOS
        self.supportedArchitectures = supportedArchitectures
    }
}

/// Device information for compatibility checking
public struct DeviceInfo {
    public let model: String
    public let osVersion: String
    public let architecture: String
    public let totalMemory: Int64
    public let availableMemory: Int64
    public let hasNeuralEngine: Bool
    public let gpuFamily: String?

    public init(
        model: String,
        osVersion: String,
        architecture: String,
        totalMemory: Int64,
        availableMemory: Int64,
        hasNeuralEngine: Bool,
        gpuFamily: String? = nil
    ) {
        self.model = model
        self.osVersion = osVersion
        self.architecture = architecture
        self.totalMemory = totalMemory
        self.availableMemory = availableMemory
        self.hasNeuralEngine = hasNeuralEngine
        self.gpuFamily = gpuFamily
    }

    /// Get current device info
    public static var current: DeviceInfo {
        let processInfo = ProcessInfo.processInfo

        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif

        return DeviceInfo(
            model: getDeviceModel(),
            osVersion: processInfo.operatingSystemVersionString,
            architecture: architecture,
            totalMemory: Int64(processInfo.physicalMemory),
            availableMemory: getAvailableMemory(),
            hasNeuralEngine: hasAppleNeuralEngine(),
            gpuFamily: getGPUFamily()
        )
    }

    private static func getDeviceModel() -> String {
        #if os(iOS) || os(tvOS)
        return UIDevice.current.model
        #else
        return "Mac"
        #endif
    }

    private static func getAvailableMemory() -> Int64 {
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

    private static func hasAppleNeuralEngine() -> Bool {
        #if os(iOS) || os(tvOS)
        // Check for A12 Bionic or later (iPhone XS and newer)
        let device = UIDevice.current.model
        // This is simplified - in production would check actual chip
        return true
        #else
        // Check for M1 or later on Mac
        return ProcessInfo.processInfo.processorCount > 4
        #endif
    }

    private static func getGPUFamily() -> String? {
        #if os(iOS) || os(tvOS)
        return "Apple GPU"
        #else
        return "Metal"
        #endif
    }
}

/// Compatibility result
public struct CompatibilityResult {
    public let isCompatible: Bool
    public let reason: String?
    public let warnings: [String]
    public let recommendations: [String]
    public let confidence: CompatibilityConfidence

    public init(
        isCompatible: Bool,
        reason: String? = nil,
        warnings: [String] = [],
        recommendations: [String] = [],
        confidence: CompatibilityConfidence = .high
    ) {
        self.isCompatible = isCompatible
        self.reason = reason
        self.warnings = warnings
        self.recommendations = recommendations
        self.confidence = confidence
    }
}

/// Compatibility confidence level
public enum CompatibilityConfidence {
    case high      // Tested and verified
    case medium    // Should work based on specs
    case low       // Might work but untested
    case unknown   // No information available
}

// Platform-specific imports
#if os(iOS) || os(tvOS)
import UIKit
#endif
