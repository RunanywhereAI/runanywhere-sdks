/**
 * PlatformAdapter.swift
 *
 * iOS directory adapter used by the Objective-C C bridge.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+State.swift
 */

import Foundation

/// Provides the package-owned model directory to the Objective-C C bridge.
@objc public class PlatformAdapter: NSObject {

    // MARK: - Singleton

    @objc public static let shared = PlatformAdapter()

    private override init() {
        super.init()
    }

    /// Get the app Documents directory path for model storage.
    @objc public func getModelBaseDirectory() -> String? {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path
    }
}
