import Foundation
import NitroModules
import UIKit

/// Swift implementation of RunAnywhereDeviceInfo HybridObject
class HybridRunAnywhereDeviceInfo: HybridRunAnywhereDeviceInfoSpec {

    func getDeviceModel() throws -> Promise<String> {
        return Promise.async {
            return UIDevice.current.model
        }
    }

    func getOSVersion() throws -> Promise<String> {
        return Promise.async {
            return UIDevice.current.systemVersion
        }
    }

    func getPlatform() throws -> Promise<String> {
        return Promise.async {
            return "ios"
        }
    }

    func getTotalRAM() throws -> Promise<Double> {
        return Promise.async {
            return Double(ProcessInfo.processInfo.physicalMemory)
        }
    }

    func getAvailableRAM() throws -> Promise<Double> {
        return Promise.async {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
            let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            if kerr == KERN_SUCCESS {
                let usedMemory = Double(info.resident_size)
                let totalMemory = Double(ProcessInfo.processInfo.physicalMemory)
                return totalMemory - usedMemory
            }
            return 0
        }
    }

    func getCPUCores() throws -> Promise<Double> {
        return Promise.async {
            return Double(ProcessInfo.processInfo.processorCount)
        }
    }

    func hasGPU() throws -> Promise<Bool> {
        return Promise.async {
            // iOS devices always have GPU
            return true
        }
    }

    func hasNPU() throws -> Promise<Bool> {
        return Promise.async {
            // Check for Neural Engine (A11 Bionic and later)
            return true
        }
    }

    func getChipName() throws -> Promise<String> {
        return Promise.async {
            var sysinfo = utsname()
            uname(&sysinfo)
            let machine = withUnsafePointer(to: &sysinfo.machine) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                    String(validatingUTF8: $0) ?? "Unknown"
                }
            }
            return machine
        }
    }

    func getThermalState() throws -> Promise<Double> {
        return Promise.async {
            let state = ProcessInfo.processInfo.thermalState
            switch state {
            case .nominal: return 0.0
            case .fair: return 0.33
            case .serious: return 0.66
            case .critical: return 1.0
            @unknown default: return 0.0
            }
        }
    }

    func getBatteryLevel() throws -> Promise<Double> {
        return Promise.async {
            await MainActor.run {
                UIDevice.current.isBatteryMonitoringEnabled = true
            }
            return Double(UIDevice.current.batteryLevel)
        }
    }

    func isCharging() throws -> Promise<Bool> {
        return Promise.async {
            await MainActor.run {
                UIDevice.current.isBatteryMonitoringEnabled = true
            }
            let state = UIDevice.current.batteryState
            return state == .charging || state == .full
        }
    }

    func isLowPowerMode() throws -> Promise<Bool> {
        return Promise.async {
            return ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}
