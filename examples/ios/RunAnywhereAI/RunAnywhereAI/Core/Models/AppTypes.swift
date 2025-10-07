//
//  AppTypes.swift
//  RunAnywhereAI
//
//  Essential app types - using SDK types directly
//

import Foundation
import RunAnywhere

// MARK: - System Device Info

struct SystemDeviceInfo {
    let modelName: String
    let chipName: String
    let totalMemory: Int64
    let availableMemory: Int64
    let neuralEngineAvailable: Bool
    let osVersion: String
    let appVersion: String

    init(
        modelName: String = "",
        chipName: String = "",
        totalMemory: Int64 = 0,
        availableMemory: Int64 = 0,
        neuralEngineAvailable: Bool = false,
        osVersion: String = "",
        appVersion: String = ""
    ) {
        self.modelName = modelName
        self.chipName = chipName
        self.totalMemory = totalMemory
        self.availableMemory = availableMemory
        self.neuralEngineAvailable = neuralEngineAvailable
        self.osVersion = osVersion
        self.appVersion = appVersion
    }
}

// MARK: - Helper Extensions

extension Int64 {
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}
