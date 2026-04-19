/**
 * PlatformAdapter.swift
 *
 * iOS platform adapter for C++ callbacks.
 * Bridges iOS-specific implementations (Keychain, FileManager) to C++ layer.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+State.swift
 */

import Foundation

/// Platform adapter that provides iOS implementations for C++ callbacks
@objc public class PlatformAdapter: NSObject {
    
    // MARK: - Singleton
    
    @objc public static let shared = PlatformAdapter()
    
    private override init() {
        super.init()
    }
    
    // MARK: - Secure Storage (Keychain)
    
    /// Get value from Keychain
    @objc public func secureGet(_ key: String) -> String? {
        return KeychainManager.shared.get(forKey: key)
    }
    
    /// Set value in Keychain
    @objc public func secureSet(_ key: String, value: String) -> Bool {
        return KeychainManager.shared.set(value, forKey: key)
    }
    
    /// Delete value from Keychain
    @objc public func secureDelete(_ key: String) -> Bool {
        return KeychainManager.shared.delete(forKey: key)
    }
    
    /// Check if key exists in Keychain
    @objc public func secureExists(_ key: String) -> Bool {
        return KeychainManager.shared.exists(forKey: key)
    }
    
    // MARK: - File Operations
    
    /// Check if file exists
    @objc public func fileExists(_ path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }
    
    /// Read file contents
    @objc public func fileRead(_ path: String) -> String? {
        return try? String(contentsOfFile: path, encoding: .utf8)
    }
    
    /// Write file contents
    @objc public func fileWrite(_ path: String, data: String) -> Bool {
        do {
            try data.write(toFile: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
    
    /// Delete file
    @objc public func fileDelete(_ path: String) -> Bool {
        do {
            try FileManager.default.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Device UUID
    
    /// Get persistent device UUID (from Keychain or generate new)
    @objc public func getPersistentDeviceUUID() -> String {
        // Try to get from Keychain first
        if let existingUUID = KeychainManager.shared.retrieveDeviceUUID() {
            return existingUUID
        }
        
        // Try vendor ID
        #if os(iOS) || os(tvOS)
        if let vendorUUID = UIDevice.current.identifierForVendor?.uuidString {
            _ = KeychainManager.shared.storeDeviceUUID(vendorUUID)
            return vendorUUID
        }
        #endif
        
        // Generate new UUID
        let newUUID = UUID().uuidString
        _ = KeychainManager.shared.storeDeviceUUID(newUUID)
        return newUUID
    }
}

