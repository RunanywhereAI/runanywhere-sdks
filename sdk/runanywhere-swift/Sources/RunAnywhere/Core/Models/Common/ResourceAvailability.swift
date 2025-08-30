import Foundation

/// Resource availability information
public struct ResourceAvailability {
    public let memoryAvailable: Int64
    public let storageAvailable: Int64
    public let acceleratorsAvailable: [HardwareAcceleration]
    public let thermalState: ProcessInfo.ThermalState
    public let batteryLevel: Float?
    public let isLowPowerMode: Bool

    public init(
        memoryAvailable: Int64,
        storageAvailable: Int64,
        acceleratorsAvailable: [HardwareAcceleration],
        thermalState: ProcessInfo.ThermalState,
        batteryLevel: Float? = nil,
        isLowPowerMode: Bool = false
    ) {
        self.memoryAvailable = memoryAvailable
        self.storageAvailable = storageAvailable
        self.acceleratorsAvailable = acceleratorsAvailable
        self.thermalState = thermalState
        self.batteryLevel = batteryLevel
        self.isLowPowerMode = isLowPowerMode
    }

    public func canLoad(model: ModelInfo) -> (canLoad: Bool, reason: String?) {
        // Check memory
        if model.memoryRequired > memoryAvailable {
            let needed = ByteCountFormatter.string(fromByteCount: model.memoryRequired, countStyle: .memory)
            let available = ByteCountFormatter.string(fromByteCount: memoryAvailable, countStyle: .memory)
            return (false, "Insufficient memory: need \(needed), have \(available)")
        }

        // Check storage
        if let downloadSize = model.downloadSize, downloadSize > storageAvailable {
            let needed = ByteCountFormatter.string(fromByteCount: downloadSize, countStyle: .file)
            let available = ByteCountFormatter.string(fromByteCount: storageAvailable, countStyle: .file)
            return (false, "Insufficient storage: need \(needed), have \(available)")
        }

        // Check thermal state
        if thermalState == .critical {
            return (false, "Device is too hot, please wait for it to cool down")
        }

        // Check battery in low power mode
        if isLowPowerMode, let battery = batteryLevel, battery < 0.2 {
            return (false, "Battery too low for model loading in Low Power Mode")
        }

        return (true, nil)
    }
}
