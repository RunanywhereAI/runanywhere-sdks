//
//  AppleDeviceStateProvider.swift
//  RunAnywhere
//
//  Default Apple-platform device-state provider for the hybrid router.
//

import Foundation
import Network
import os

#if canImport(UIKit)
import UIKit
#endif

public final class AppleDeviceStateProvider: HybridDeviceStateProvider, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.runanywhere.hybrid.device-state")
    private let pathStatus = OSAllocatedUnfairLock<NWPath.Status>(initialState: .requiresConnection)

    public init() {
        let pathStatus = pathStatus
        monitor.pathUpdateHandler = { path in
            pathStatus.withLock { status in
                status = path.status
            }
        }
        monitor.start(queue: monitorQueue)

        #if os(iOS) || os(visionOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        #endif
    }

    deinit {
        monitor.cancel()
        #if os(iOS) || os(visionOS)
        UIDevice.current.isBatteryMonitoringEnabled = false
        #endif
    }

    public func isOnline() -> Bool {
        pathStatus.withLock { status in
            status == .satisfied
        }
    }

    public func batteryPercent() -> Int32 {
        #if os(iOS) || os(visionOS)
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return 100 }
        return Int32((level * 100).rounded()).clamped(to: 0...100)
        #else
        return 100
        #endif
    }

    public func isThermalThrottled() -> Bool {
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            return true
        case .nominal, .fair:
            return false
        @unknown default:
            return false
        }
    }
}

private extension Int32 {
    func clamped(to range: ClosedRange<Int32>) -> Int32 {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
