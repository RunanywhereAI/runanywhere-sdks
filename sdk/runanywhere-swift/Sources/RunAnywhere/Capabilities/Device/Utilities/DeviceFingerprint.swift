//
//  DeviceFingerprint.swift
//  RunAnywhere SDK
//
//  Internal utilities for device fingerprint generation
//

import CommonCrypto
import Foundation

/// Internal utilities for device fingerprint generation
enum DeviceFingerprintUtility {

    /// Generate a device fingerprint based on stable device characteristics
    static func generateFingerprint() -> String {
        var components: [String] = []

        // Memory (doesn't change)
        let processInfo = ProcessInfo.processInfo
        components.append("mem:\(processInfo.physicalMemory)")

        // Architecture
        #if arch(arm64)
        components.append("arch:arm64")
        #elseif arch(x86_64)
        components.append("arch:x86_64")
        #else
        components.append("arch:unknown")
        #endif

        // Processor count (doesn't change)
        components.append("cores:\(processInfo.processorCount)")

        // OS major version only
        let osVersion = processInfo.operatingSystemVersion
        components.append("os:\(osVersion.majorVersion)")

        // Create fingerprint hash
        let fingerprintString = components.joined(separator: "|")
        return sha256(fingerprintString)
    }

    /// Generate SHA-256 hash of a string
    static func sha256(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }

        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
