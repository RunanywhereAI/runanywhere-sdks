//
//  DeviceInfoService.swift
//  RunAnywhereAI
//
//  Device information service using SDK capabilities
//

import Foundation
import UIKit
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
        let osVersion = UIDevice.current.systemVersion
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
        // Try to get from SDK first
        if let sdkDeviceInfo = await sdk.deviceCapabilities?.getDeviceInfo() {
            return sdkDeviceInfo.modelName ?? UIDevice.current.model
        }

        // Fallback to system info
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value))!)
        }

        return identifier
    }

    private func getChipName() async -> String {
        // Try to get from SDK
        if let sdkDeviceInfo = await sdk.deviceCapabilities?.getDeviceInfo() {
            return sdkDeviceInfo.chipName ?? "Unknown"
        }

        // Fallback detection
        let modelName = await getDeviceModelName()
        if modelName.contains("arm64") || modelName.contains("iPhone") {
            return "Apple Silicon"
        }
        return "Unknown"
    }

    private func getMemoryInfo() async -> (total: Int64, available: Int64) {
        // Try to get from SDK
        if let sdkDeviceInfo = await sdk.deviceCapabilities?.getDeviceInfo() {
            return (sdkDeviceInfo.totalMemory ?? 0, sdkDeviceInfo.availableMemory ?? 0)
        }

        // Fallback to system info
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let availableMemory = totalMemory / 2 // Rough estimate

        return (Int64(totalMemory), Int64(availableMemory))
    }

    private func isNeuralEngineAvailable() async -> Bool {
        // Try to get from SDK
        if let sdkDeviceInfo = await sdk.deviceCapabilities?.getDeviceInfo() {
            return sdkDeviceInfo.neuralEngineAvailable ?? false
        }

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
