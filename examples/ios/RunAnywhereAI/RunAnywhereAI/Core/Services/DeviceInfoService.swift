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

        // SDK DeviceInfoFactory owns memory / chip / NPU probes (0 available =
        // UNKNOWN). Do not invent half of physical RAM in the example app.
        let sdk = DeviceInfoFactory.current
        #if os(iOS) || os(tvOS)
        let osVersion = UIDevice.current.systemVersion
        #else
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #endif

        deviceInfo = SystemDeviceInfo(
            modelName: sdk.deviceModel.isEmpty ? "Unknown" : sdk.deviceModel,
            chipName: sdk.chipName.isEmpty ? "Unknown" : sdk.chipName,
            totalMemory: sdk.totalMemoryBytes,
            availableMemory: sdk.availableMemoryBytes,
            neuralEngineAvailable: sdk.hasNpu_p,
            osVersion: osVersion,
            appVersion: getAppVersion()
        )
    }

    private func getAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}
