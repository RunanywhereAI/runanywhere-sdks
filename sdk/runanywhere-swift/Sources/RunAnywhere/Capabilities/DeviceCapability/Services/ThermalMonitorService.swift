import Foundation

/// Service for monitoring device thermal state
public actor ThermalMonitorService {
    private let logger = SDKLogger(category: "ThermalMonitor")
    private var observers: [UUID: (ThermalState) -> Void] = [:]

    public init() {}

    /// Get current thermal state
    public func getCurrentThermalState() -> ThermalState {
        #if os(iOS) || os(macOS)
        let thermalState = ProcessInfo.processInfo.thermalState
        return ThermalState(from: thermalState)
        #else
        return .nominal
        #endif
    }

    /// Subscribe to thermal state changes
    public func observeThermalStateChanges(_ handler: @escaping (ThermalState) -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    /// Unsubscribe from thermal state changes
    public func stopObserving(_ id: UUID) {
        observers.removeValue(forKey: id)
    }
}

/// Thermal state enumeration
public enum ThermalState: String, Codable {
    case nominal = "nominal"
    case fair = "fair"
    case serious = "serious"
    case critical = "critical"

    #if os(iOS) || os(macOS)
    init(from processInfoState: ProcessInfo.ThermalState) {
        switch processInfoState {
        case .nominal:
            self = .nominal
        case .fair:
            self = .fair
        case .serious:
            self = .serious
        case .critical:
            self = .critical
        @unknown default:
            self = .nominal
        }
    }
    #endif

    public var shouldThrottle: Bool {
        switch self {
        case .nominal, .fair:
            return false
        case .serious, .critical:
            return true
        }
    }
}
