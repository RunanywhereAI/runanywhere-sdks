//
//  DeviceIdentity.swift
//  RunAnywhere SDK
//
//  Simple utility for device identity management (UUID persistence)
//  Uses lock-based synchronization for thread-safe initialization
//

import Foundation

#if os(iOS) || os(tvOS)
import UIKit
#endif

/// Simple utility for device identity management
/// Provides persistent UUID that survives app reinstalls
public enum DeviceIdentity {

    // MARK: - Properties

    private static let logger = SDKLogger(category: "DeviceIdentity")

    /// Lock for thread-safe UUID initialization (read-check-write atomicity)
    ///
    /// Note: Using NSLock instead of Swift Actor because `persistentUUID` must be
    /// synchronously accessible from non-async contexts (telemetry payloads, batch requests).
    /// Actors require `await` which would break the synchronous API contract.
    /// NSLock provides equivalent thread-safety with synchronous access.
    /// Consider migrating to `OSAllocatedUnfairLock` when dropping iOS 15 support.
    private static let initLock = NSLock()

    /// Cached UUID to avoid repeated keychain lookups after first access
    private static var cachedUUID: String?

    // MARK: - Public API

    /// Get a persistent device UUID that survives app reinstalls
    /// Uses keychain for persistence, falls back to vendor ID or generates new UUID
    /// Thread-safe: uses lock to ensure atomic read-check-write on first access
    public static var persistentUUID: String {
        // Fast path: return cached value without locking (safe after initialization)
        if let cached = cachedUUID {
            return cached
        }

        // Slow path: lock and initialize atomically
        initLock.lock()
        defer { initLock.unlock() }

        // Double-check after acquiring lock (another thread may have initialized)
        if let cached = cachedUUID {
            return cached
        }

        // Strategy 1: Try to get from keychain (survives app reinstalls)
        if let persistentUUID = KeychainManager.shared.retrieveDeviceUUID() {
            cachedUUID = persistentUUID
            return persistentUUID
        }

        // Strategy 2: Use Apple's identifierForVendor
        if let vendorUUID = vendorUUID {
            try? KeychainManager.shared.storeDeviceUUID(vendorUUID)
            logger.debug("Stored vendor UUID in keychain")
            cachedUUID = vendorUUID
            return vendorUUID
        }

        // Strategy 3: Generate new UUID
        let newUUID = UUID().uuidString
        try? KeychainManager.shared.storeDeviceUUID(newUUID)
        logger.debug("Generated and stored new device UUID")
        cachedUUID = newUUID
        return newUUID
    }

    /// Get vendor UUID if available (iOS/tvOS only)
    private static var vendorUUID: String? {
        #if os(iOS) || os(tvOS)
        return UIDevice.current.identifierForVendor?.uuidString
        #else
        return nil
        #endif
    }

    /// Validate if a device UUID is properly formatted
    public static func validateUUID(_ uuid: String) -> Bool {
        uuid.count == 36 && uuid.contains("-")
    }
}
