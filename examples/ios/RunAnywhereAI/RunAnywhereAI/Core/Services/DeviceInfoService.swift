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
import RunAnywhereSDK

@MainActor
class DeviceInfoService: ObservableObject {
    static let shared = DeviceInfoService()

    @Published var deviceInfo: SystemDeviceInfo?
    @Published var isLoading = false

    private let sdk = RunAnywhereSDK.shared

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
        #else
        return identifier.isEmpty ? "Mac" : identifier
        #endif
    }

    private func getChipName() async -> String {
        // Direct chip detection since SDK properties are private
        let modelName = await getDeviceModelName()
        if modelName.contains("arm64") || modelName.contains("iPhone") {
            return "Apple Silicon"
        }
        return "Unknown"
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

// MARK: - SDK DeviceInfo Extension

extension DeviceInfo {
    var modelName: String? {
        // Assuming SDK has device model name
        return nil // Replace with actual SDK property when available
    }

    var chipName: String? {
        // Assuming SDK has chip information
        return nil // Replace with actual SDK property when available
    }

    var totalMemory: Int64? {
        // Assuming SDK has memory info
        return nil // Replace with actual SDK property when available
    }

    var availableMemory: Int64? {
        // Assuming SDK has memory info
        return nil // Replace with actual SDK property when available
    }

    var neuralEngineAvailable: Bool? {
        // Assuming SDK has Neural Engine detection
        return nil // Replace with actual SDK property when available
    }
}
