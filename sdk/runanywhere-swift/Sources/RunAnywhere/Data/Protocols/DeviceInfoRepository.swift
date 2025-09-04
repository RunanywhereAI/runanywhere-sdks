import Foundation

/// Device information repository protocol for specialized device operations
/// DeviceInfoRepositoryImpl will implement both this AND Repository<DeviceInfoData>
public protocol DeviceInfoRepository {
    // Device-specific operations
    func fetchCurrentDeviceInfo() async throws -> DeviceInfoData
    func updateDeviceInfo(_ deviceInfo: DeviceInfoData) async throws
    func getStoredDeviceInfo() async throws -> DeviceInfoData?
    func refreshDeviceInfo() async throws -> DeviceInfoData
}
