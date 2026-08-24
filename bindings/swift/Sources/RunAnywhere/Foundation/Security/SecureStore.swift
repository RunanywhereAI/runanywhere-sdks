import Foundation

/// Where the SDK keeps small secrets, and the one place that decides.
///
/// Two stores existed and disagreed. The platform adapter honoured
/// `RUNANYWHERE_SWIFT_SECURE_STORE=file` while ``KeychainManager`` always went
/// straight to Security.framework, so turning the override on moved some
/// secrets to disk and left the rest in the keychain. On a locally built Mac
/// app that is not a preference, it is a wall of password prompts: an ad-hoc
/// signature changes on every rebuild, the keychain treats each build as a
/// different program, and it re-authorises every stored item on every launch.
///
/// Both stores now ask this type, so the override moves all of them or none.
enum SecureStore {
    private static let modeEnv = "RUNANYWHERE_SWIFT_SECURE_STORE"
    private static let directoryEnv = "RUNANYWHERE_SWIFT_SECURE_STORE_DIR"

    /// True when secrets should live in a file rather than the keychain.
    ///
    /// Read on every call rather than cached, so a host can set it during its
    /// own `init` before the SDK is initialized.
    static var usesFileStore: Bool {
        guard let rawMode = getenv(modeEnv).map({ String(cString: $0).lowercased() }) else {
            return false
        }
        return rawMode == "file" || rawMode == "filesystem"
    }

    static func read(_ key: String) throws -> Data? {
        let url = try url(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    static func write(_ data: Data, for key: String) throws {
        let url = try url(for: key)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
        // 0o600: the file store stands in for the keychain, so it should not
        // be readable by other accounts on a shared machine.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path
        )
    }

    static func remove(_ key: String) throws {
        let url = try url(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func exists(_ key: String) -> Bool {
        guard let url = try? url(for: key) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func url(for key: String) throws -> URL {
        let root: URL
        if let rawDirectory = getenv(directoryEnv).map({ String(cString: $0) }),
           !rawDirectory.isEmpty {
            root = URL(fileURLWithPath: (rawDirectory as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            root = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appendingPathComponent("RunAnywhere/SecureStore", isDirectory: true)
        }
        return root.appendingPathComponent(hexKey(key), isDirectory: false)
    }

    /// Hex rather than the key itself: keys are dotted reverse-DNS strings and
    /// arbitrary caller text, neither of which is safe as a filename.
    private static func hexKey(_ key: String) -> String {
        key.utf8.map { String(format: "%02x", $0) }.joined()
    }
}
