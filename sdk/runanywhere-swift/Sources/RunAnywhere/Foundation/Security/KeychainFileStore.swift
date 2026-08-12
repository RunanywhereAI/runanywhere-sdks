//
//  KeychainFileStore.swift
//  RunAnywhere SDK
//
//  File-backed stand-in for the Keychain, used when
//  `RUNANYWHERE_SWIFT_SECURE_STORE=file` is set.
//
//  This exists for local Mac development. An ad-hoc code signature changes on
//  every rebuild, so the Keychain treats each build as a different program and
//  asks for the login password once per stored item per launch. That makes the
//  app unusable to iterate on. The same switch already gates the platform
//  adapter's secure-store slots, so one variable covers every secret the SDK
//  holds.
//
//  Signed builds never take this path: nothing sets the variable, and the
//  Keychain stays the only store.
//

import Foundation

struct KeychainFileStore {
    let serviceName: String

    private static let modeEnvironmentKey = "RUNANYWHERE_SWIFT_SECURE_STORE"
    private static let directoryEnvironmentKey = "RUNANYWHERE_SWIFT_SECURE_STORE_DIR"

    var isEnabled: Bool {
        guard let raw = ProcessInfo.processInfo.environment[Self.modeEnvironmentKey]?.lowercased()
        else {
            return false
        }
        return raw == "file" || raw == "filesystem"
    }

    func read(for key: String) -> Data? {
        guard let url = url(for: key) else { return nil }
        return try? Data(contentsOf: url)
    }

    func write(_ data: Data, for key: String) throws {
        guard let url = url(for: key) else {
            throw SDKException(
                code: .keychainError,
                message: "Could not resolve the secure store directory",
                category: .auth
            )
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: url, options: [.atomic])
    }

    func delete(for key: String) {
        guard let url = url(for: key) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func url(for key: String) -> URL? {
        let directory: URL
        if let override = ProcessInfo.processInfo.environment[Self.directoryEnvironmentKey],
           !override.isEmpty {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            guard let base = try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ) else {
                return nil
            }
            directory = base
                .appendingPathComponent("RunAnywhere", isDirectory: true)
                .appendingPathComponent("SecureStore", isDirectory: true)
        }

        // Keys are SDK-defined, but percent-encoding keeps a future key
        // containing a slash from escaping the directory.
        let name = "\(serviceName).\(key)"
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return directory.appendingPathComponent(name)
    }
}
