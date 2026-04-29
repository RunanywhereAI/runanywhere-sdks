//
//  DeviceIdentity.swift
//  RunAnywhere SDK
//
//  Simple utility for device identity management (UUID persistence)
//  Uses lock-based synchronization for thread-safe initialization
//

import Foundation
import os

#if os(iOS) || os(tvOS)
import UIKit
#endif

/// Simple utility for device identity management
/// Provides persistent UUID that survives app reinstalls
public enum DeviceIdentity {

    // MARK: - Properties

    private static let logger = SDKLogger(category: "DeviceIdentity")

    /// Cached UUID, guarded by `OSAllocatedUnfairLock` so the synchronous
    /// API contract holds for non-async callers (telemetry payloads, batch
    /// requests). Per CLAUDE.md, NSLock is forbidden.
    private static let cached = OSAllocatedUnfairLock<String?>(initialState: nil)

    // MARK: - Public API

    /// Get a persistent device UUID that survives app reinstalls
    /// Uses keychain for persistence, falls back to vendor ID or generates new UUID
    /// Thread-safe: lock ensures atomic read-check-write on first access
    public static var persistentUUID: String {
        // Fast path: return cached value if already set
        if let cached = cached.withLock({ $0 }) {
            return cached
        }

        // Slow path: lock and initialize atomically. We resolve the value
        // outside the lock first to avoid blocking other threads on
        // keychain I/O, then commit under the lock.
        let resolved: String

        if let persistentUUID = KeychainManager.shared.retrieveDeviceUUID() {
            resolved = persistentUUID
        } else if let vendorUUID = vendorUUID {
            try? KeychainManager.shared.storeDeviceUUID(vendorUUID)
            logger.debug("Stored vendor UUID in keychain")
            resolved = vendorUUID
        } else {
            let newUUID = UUID().uuidString
            try? KeychainManager.shared.storeDeviceUUID(newUUID)
            logger.debug("Generated and stored new device UUID")
            resolved = newUUID
        }

        return cached.withLock { current in
            // Double-check: another thread may have raced us.
            if let existing = current {
                return existing
            }
            current = resolved
            return resolved
        }
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
