//
//  DeviceInfoService.swift
//  RunAnywhereAI
//
//  Service for retrieving device information and capabilities
//

import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import RunAnywhere

@MainActor
class DeviceInfoService: ObservableObject {
    static let shared = DeviceInfoService()

    @Published var deviceInfo: SystemDeviceInfo?
    @Published var isLoading = false

    private init() {
        Task {
            await refreshDeviceInfo()
        }
    }

    // MARK: - Device Info Methods

    func refreshDeviceInfo() async {
        isLoading = true
        defer { isLoading = false }

        // Get device information from SDK and system
        let modelName = await getDeviceModelName()
        let chipName = await getChipName()
        let (totalMemory, availableMemory) = await getMemoryInfo()
        let neuralEngineAvailable = await isNeuralEngineAvailable()
        #if os(iOS) || os(tvOS)
        let osVersion = UIDevice.current.systemVersion
        #else
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #endif
        let appVersion = getAppVersion()

        deviceInfo = SystemDeviceInfo(
            modelName: modelName,
            chipName: chipName,
            totalMemory: totalMemory,
            availableMemory: availableMemory,
            neuralEngineAvailable: neuralEngineAvailable,
            osVersion: osVersion,
            appVersion: appVersion
        )
    }

    // MARK: - Private Helper Methods

    private func getDeviceModelName() async -> String {
        // Use system info directly since SDK methods are private
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            let unicodeScalar = UnicodeScalar(UInt8(value))
            return identifier + String(unicodeScalar)
        }

        #if os(iOS) || os(tvOS)
        return identifier.isEmpty ? UIDevice.current.model : identifier
        #elseif os(macOS)
        return getMacModelName()
        #else
        return identifier.isEmpty ? "Mac" : identifier
        #endif
    }

    #if os(macOS)
    private func getMacModelName() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let modelIdentifier = String(cString: model)

        // Map common model identifiers to friendly names
        let friendlyNames: [String: String] = [
            "Mac14,2": "MacBook Air (M2, 2022)",
            "Mac14,5": "MacBook Pro 14\" (M2 Pro, 2023)",
            "Mac14,6": "MacBook Pro 16\" (M2 Pro/Max, 2023)",
            "Mac14,7": "MacBook Pro 13\" (M2, 2022)",
            "Mac14,9": "MacBook Pro 14\" (M2 Pro/Max, 2023)",
            "Mac14,10": "MacBook Pro 16\" (M2 Pro/Max, 2023)",
            "Mac14,12": "Mac mini (M2, 2023)",
            "Mac14,13": "Mac Studio (M2 Max, 2023)",
            "Mac14,14": "Mac Studio (M2 Ultra, 2023)",
            "Mac14,15": "MacBook Air 15\" (M2, 2023)",
            "Mac15,3": "MacBook Pro 14\" (M3, 2023)",
            "Mac15,4": "iMac 24\" (M3, 2023)",
            "Mac15,5": "iMac 24\" (M3, 2023)",
            "Mac15,6": "MacBook Pro 14\" (M3 Pro/Max, 2023)",
            "Mac15,7": "MacBook Pro 16\" (M3 Pro/Max, 2023)",
            "Mac15,8": "MacBook Pro 14\" (M3 Pro/Max, 2023)",
            "Mac15,9": "MacBook Pro 16\" (M3 Pro/Max, 2023)",
            "Mac15,10": "MacBook Pro 14\" (M3 Pro/Max, 2023)",
            "Mac15,11": "MacBook Pro 16\" (M3 Pro/Max, 2023)",
            "Mac15,12": "MacBook Air 13\" (M3, 2024)",
            "Mac15,13": "MacBook Air 15\" (M3, 2024)",
            "Mac16,1": "MacBook Pro 14\" (M4, 2024)",
            "Mac16,5": "iMac 24\" (M4, 2024)",
            "Mac16,6": "MacBook Pro 14\" (M4 Pro/Max, 2024)",
            "Mac16,7": "MacBook Pro 16\" (M4 Pro/Max, 2024)",
            "Mac16,8": "Mac mini (M4, 2024)",
            "Mac16,10": "Mac mini (M4 Pro, 2024)"
        ]

        return friendlyNames[modelIdentifier] ?? "Mac (\(modelIdentifier))"
    }
    #endif

    private func getChipName() async -> String {
        #if os(macOS)
        // Get chip brand string from sysctl
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        let brandString = String(cString: brand)

        if !brandString.isEmpty {
            return brandString
        }

        // Fallback to model-based detection
        let modelName = getMacModelName()
        if modelName.contains("M4") { return "Apple M4" }
        if modelName.contains("M3") { return "Apple M3" }
        if modelName.contains("M2") { return "Apple M2" }
        if modelName.contains("M1") { return "Apple M1" }
        return "Apple Silicon"
        #else
        // iOS/tvOS detection
        let modelName = await getDeviceModelName()
        if modelName.contains("arm64") || modelName.contains("iPhone") || modelName.contains("iPad") {
            return "Apple Silicon"
        }
        return "Unknown"
        #endif
    }

    private func getMemoryInfo() async -> (total: Int64, available: Int64) {
        // Direct memory detection since SDK properties are private

        // Fallback to system info
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let availableMemory = totalMemory / 2 // Rough estimate

        return (Int64(totalMemory), Int64(availableMemory))
    }

    private func isNeuralEngineAvailable() async -> Bool {
        // Direct neural engine detection since SDK properties are private

        // Fallback - assume true for modern devices
        return true
    }

    private func getAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}
