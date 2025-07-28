//
//  DeviceInfoService.swift
//  RunAnywhereAI
//
//  Created by Assistant on 7/27/25.
//

import Foundation
import UIKit
import Darwin

struct SystemDeviceInfo {
    let modelName: String
    let osVersion: String
    let totalMemory: String
    let availableMemory: String
    let usedMemory: String
    let memoryPressure: String
    let batteryLevel: Int
    let batteryState: String
    let processorType: String
    let coreCount: Int
    let neuralEngineAvailable: Bool
    let thermalState: String
}

@MainActor
class DeviceInfoService: ObservableObject {
    static let shared = DeviceInfoService()
    
    @Published var deviceInfo: SystemDeviceInfo?
    @Published var isMonitoring = false
    
    private var updateTimer: Timer?
    
    private init() {
        updateDeviceInfo()
    }
    
    func startMonitoring() {
        isMonitoring = true
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                self.updateDeviceInfo()
            }
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    func updateDeviceInfo() {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        
        let processInfo = ProcessInfo.processInfo
        let totalMemory = processInfo.physicalMemory
        
        // Get system-wide memory info using host_statistics64
        let (availableMemory, usedMemory) = getSystemMemoryInfo()
        
        // Get thermal state
        let thermalState: String = {
            switch processInfo.thermalState {
            case .nominal:
                return "Normal"
            case .fair:
                return "Fair"
            case .serious:
                return "Serious"
            case .critical:
                return "Critical"
            @unknown default:
                return "Unknown"
            }
        }()
        
        // Get battery state
        let batteryState: String = {
            switch device.batteryState {
            case .unknown:
                return "Unknown"
            case .unplugged:
                return "Unplugged"
            case .charging:
                return "Charging"
            case .full:
                return "Full"
            @unknown default:
                return "Unknown"
            }
        }()
        
        // Get processor info
        let processorType = getProcessorName()
        
        // Debug logging
        #if DEBUG
        print("=== Device Info Debug ===")
        print("Model Code: \(getModelCode() ?? "Unknown")")
        print("Model Name: \(modelName())")
        print("OS Version: \(device.systemVersion)")
        print("Processor Raw: \(getRawProcessorName())")
        print("Processor Name: \(processorType)")
        print("Total Memory: \(totalMemory) bytes (\(ByteCountFormatter.string(fromByteCount: Int64(totalMemory), countStyle: .memory)))")
        print("Available Memory: \(availableMemory) bytes (\(ByteCountFormatter.string(fromByteCount: Int64(availableMemory), countStyle: .memory)))")
        print("Used Memory: \(usedMemory) bytes (\(ByteCountFormatter.string(fromByteCount: Int64(usedMemory), countStyle: .memory)))")
        print("Battery Level: \(device.batteryLevel)")
        print("======================")
        #endif
        
        deviceInfo = SystemDeviceInfo(
            modelName: modelName(),
            osVersion: "\(device.systemName) \(device.systemVersion)",
            totalMemory: ByteCountFormatter.string(fromByteCount: Int64(totalMemory), countStyle: .memory),
            availableMemory: ByteCountFormatter.string(fromByteCount: Int64(availableMemory), countStyle: .memory),
            usedMemory: ByteCountFormatter.string(fromByteCount: Int64(usedMemory), countStyle: .memory),
            memoryPressure: getMemoryPressureString(used: usedMemory, total: totalMemory),
            batteryLevel: Int(device.batteryLevel * 100),
            batteryState: batteryState,
            processorType: processorType,
            coreCount: processInfo.processorCount,
            neuralEngineAvailable: checkNeuralEngineAvailability(),
            thermalState: thermalState
        )
    }
    
    private func getSystemMemoryInfo() -> (available: UInt64, used: UInt64) {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<natural_t>.stride)
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            // Fallback to simpler calculation
            let totalMemory = ProcessInfo.processInfo.physicalMemory
            return (totalMemory / 2, totalMemory / 2) // Rough estimate
        }
        
        let pageSize = UInt64(vm_kernel_page_size)
        
        // Calculate free memory (includes inactive pages that can be reused)
        let freeMemory = UInt64(info.free_count + info.inactive_count) * pageSize
        
        // Calculate used memory (active + wired + compressed)
        let usedMemory = UInt64(info.active_count + info.wire_count + info.compressor_page_count) * pageSize
        
        return (freeMemory, usedMemory)
    }
    
    private func getRawProcessorName() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
    
    private func getProcessorName() -> String {
        let rawModel = getRawProcessorName()
        
        // Map to user-friendly names
        let processorMap: [String: String] = [
            // A18 Pro (iPhone 16 Pro series)
            "D94AP": "A18 Pro",
            "D93AP": "A18 Pro",
            // A18 (iPhone 16 series)
            "D49AP": "A18",
            "D48AP": "A18",
            // A17 Pro (iPhone 15 Pro series)
            "D84AP": "A17 Pro",
            "D83AP": "A17 Pro",
            // A16 Bionic (iPhone 15, 14 Pro series)
            "D73AP": "A16 Bionic",
            "D74AP": "A16 Bionic",
            "D27AP": "A16 Bionic",
            "D28AP": "A16 Bionic",
            // A15 Bionic
            "D63AP": "A15 Bionic",
            "D64AP": "A15 Bionic",
            "D16AP": "A15 Bionic",
            "D17AP": "A15 Bionic",
            // M-series for iPads
            "T8122": "M4",
            "T8112": "M2",
            "T8103": "M1"
        ]
        
        return processorMap[rawModel] ?? rawModel
    }
    
    private func getModelCode() -> String? {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
    }
    
    private func modelName() -> String {
        let modelCode = getModelCode()
        
        let modelMap: [String: String] = [
            // iPhone 16 models
            "iPhone17,4": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16 Pro Max",
            "iPhone17,2": "iPhone 16 Pro",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone16,2": "iPhone 16 Plus",
            "iPhone16,1": "iPhone 16",
            // iPhone 15 models
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone15,4": "iPhone 15",
            "iPhone15,3": "iPhone 15 Pro Max",
            "iPhone15,2": "iPhone 15 Pro",
            // iPhone 14 models
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone14,7": "iPhone 14",
            "iPhone14,6": "iPhone 14 Pro Max",
            "iPhone14,5": "iPhone 14 Pro",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,2": "iPhone 13 Pro",
            // iPhone 13 models
            "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,2": "iPhone 12",
            "iPhone13,1": "iPhone 12 mini",
            // iPad models
            "iPad16,6": "iPad Pro 13-inch (M4)",
            "iPad16,5": "iPad Pro 13-inch (M4)",
            "iPad16,4": "iPad Pro 11-inch (M4)",
            "iPad16,3": "iPad Pro 11-inch (M4)",
            "iPad14,1": "iPad mini (6th generation)",
            "iPad13,19": "iPad (10th generation)",
            "iPad13,18": "iPad Pro 12.9-inch (6th generation)",
            "iPad13,17": "iPad Pro 11-inch (4th generation)",
            // Add more models as needed
        ]
        
        return modelMap[modelCode ?? ""] ?? modelCode ?? "Unknown Device"
    }
    
    private func getMemoryPressureString(used: UInt64, total: UInt64) -> String {
        let usagePercentage = Double(used) / Double(total) * 100
        
        switch usagePercentage {
        case 0..<50:
            return "Low"
        case 50..<70:
            return "Moderate"
        case 70..<85:
            return "High"
        default:
            return "Critical"
        }
    }
    
    private func checkNeuralEngineAvailability() -> Bool {
        let modelName = self.modelName()
        
        // All iPhone 16 models have Neural Engine
        if modelName.contains("iPhone 16") {
            return true
        }
        
        // All iPhone 15 models have Neural Engine
        if modelName.contains("iPhone 15") {
            return true
        }
        
        // All iPhone 14 models have Neural Engine
        if modelName.contains("iPhone 14") {
            return true
        }
        
        // All iPhone 13 models have Neural Engine
        if modelName.contains("iPhone 13") {
            return true
        }
        
        // All iPhone 12 models have Neural Engine
        if modelName.contains("iPhone 12") {
            return true
        }
        
        // iPhone 11 and later have Neural Engine
        if modelName.contains("iPhone 11") {
            return true
        }
        
        // Use model identifier check as fallback
        if let modelCode = getModelCode() {
            // Extract major version number
            let pattern = #"iPhone(\d+),"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: modelCode, range: NSRange(modelCode.startIndex..., in: modelCode)),
               let numberRange = Range(match.range(at: 1), in: modelCode),
               let majorVersion = Int(modelCode[numberRange]) {
                // iPhone 10,x and later have Neural Engine (iPhone 8/X and later)
                return majorVersion >= 10
            }
        }
        
        return false
    }
}