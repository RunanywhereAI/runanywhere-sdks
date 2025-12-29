import CRACommons
import Foundation
import Security

/// Swift implementation of the platform adapter for runanywhere-commons.
/// Bridges platform-specific operations from C++ to Swift.
///
/// Provides:
/// - File system operations (read, write, exists, delete)
/// - Secure storage (Keychain)
/// - Logging
/// - Clock (current time)
final class SwiftPlatformAdapter {
    private let logger = SDKLogger(category: "PlatformAdapter")

    /// Shared instance
    static let shared = SwiftPlatformAdapter()

    /// Whether the adapter has been registered with commons
    private var isRegistered = false

    /// The platform adapter struct - MUST be stored as instance property
    /// so it remains valid for the lifetime of this singleton.
    /// C++ stores a raw pointer to this struct, so it must not be deallocated.
    private var adapter = rac_platform_adapter_t()

    private init() {}

    // MARK: - Registration

    /// Registers this adapter with runanywhere-commons.
    /// Should be called once during SDK initialization.
    func register() { // swiftlint:disable:this function_body_length
        guard !isRegistered else { return }

        // Reset the adapter (it's stored as instance property to keep it alive)
        adapter = rac_platform_adapter_t()

        // Logging callback
        adapter.log = { level, category, message, _ in
            SwiftPlatformAdapter.handleLog(level: level, category: category, message: message)
        }

        // File exists callback
        adapter.file_exists = { path, _ -> rac_bool_t in
            SwiftPlatformAdapter.handleFileExists(path: path)
        }

        // File read callback - signature: (path, void** out_data, size_t* out_size, user_data)
        adapter.file_read = { path, outData, outSize, _ -> rac_result_t in
            guard let path = path, let outData = outData, let outSize = outSize else {
                return RAC_ERROR_NULL_POINTER
            }

            let pathString = String(cString: path)

            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: pathString))

                // Allocate buffer and copy data
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
                data.copyBytes(to: buffer, count: data.count)

                outData.pointee = UnsafeMutableRawPointer(buffer)
                outSize.pointee = data.count

                return RAC_SUCCESS
            } catch {
                return RAC_ERROR_FILE_NOT_FOUND
            }
        }

        // File write callback - signature: (path, const void* data, size_t size, user_data)
        adapter.file_write = { path, data, size, _ -> rac_result_t in
            guard let path = path, let data = data else {
                return RAC_ERROR_NULL_POINTER
            }

            let pathString = String(cString: path)
            let fileData = Data(bytes: data, count: size)

            do {
                try fileData.write(to: URL(fileURLWithPath: pathString))
                return RAC_SUCCESS
            } catch {
                return RAC_ERROR_FILE_WRITE_FAILED
            }
        }

        // File delete callback
        adapter.file_delete = { path, _ -> rac_result_t in
            SwiftPlatformAdapter.handleFileDelete(path: path)
        }

        // Secure storage get - signature: (key, char** out_value, user_data)
        adapter.secure_get = { key, outValue, _ -> rac_result_t in
            guard let key = key, let outValue = outValue else {
                return RAC_ERROR_NULL_POINTER
            }

            let keyString = String(cString: key)

            // swiftlint:disable:next avoid_any_type prefer_concrete_types
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: SwiftPlatformAdapter.keychainService,
                kSecAttrAccount as String: keyString,
                kSecReturnData as String: true
            ]

            // swiftlint:disable:next discouraged_optional_collection
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            guard status == errSecSuccess, let data = result as? Data else {
                return RAC_ERROR_SECURE_STORAGE_FAILED
            }

            // Convert data to null-terminated string
            if let stringValue = String(data: data, encoding: .utf8) {
                let cString = strdup(stringValue)
                outValue.pointee = cString
                return RAC_SUCCESS
            }

            return RAC_ERROR_SECURE_STORAGE_FAILED
        }

        // Secure storage set - signature: (key, const char* value, user_data)
        adapter.secure_set = { key, value, _ -> rac_result_t in
            guard let key = key, let value = value else {
                return RAC_ERROR_NULL_POINTER
            }

            let keyString = String(cString: key)
            let valueString = String(cString: value)
            guard let data = valueString.data(using: .utf8) else {
                return RAC_ERROR_SECURE_STORAGE_FAILED
            }

            // Delete existing item first
            // swiftlint:disable:next avoid_any_type prefer_concrete_types
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: SwiftPlatformAdapter.keychainService,
                kSecAttrAccount as String: keyString
            ]
            SecItemDelete(deleteQuery as CFDictionary)

            // Add new item
            // swiftlint:disable:next avoid_any_type prefer_concrete_types
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: SwiftPlatformAdapter.keychainService,
                kSecAttrAccount as String: keyString,
                kSecValueData as String: data
            ]

            let status = SecItemAdd(addQuery as CFDictionary, nil)
            return status == errSecSuccess ? RAC_SUCCESS : RAC_ERROR_SECURE_STORAGE_FAILED
        }

        // Secure storage delete
        adapter.secure_delete = { key, _ -> rac_result_t in
            SwiftPlatformAdapter.handleSecureStorageDelete(key: key)
        }

        // Clock callback - get current time in milliseconds
        adapter.now_ms = { _ -> Int64 in
            Int64(Date().timeIntervalSince1970 * 1000)
        }

        // Memory info callback - signature: (rac_memory_info_t* out_info, user_data)
        adapter.get_memory_info = { _, _ -> rac_result_t in
            // Not implemented - return not supported
            return RAC_ERROR_NOT_SUPPORTED
        }

        // HTTP download callback (optional - set to nil if not implementing)
        // These will be handled by Swift's AlamofireDownloadService directly
        adapter.http_download = nil
        adapter.http_download_cancel = nil

        // Archive extraction callback (optional - set to nil if not implementing)
        // This will be handled by Swift's ArchiveUtility directly
        adapter.extract_archive = nil

        // User data points to self (not used in static callbacks)
        adapter.user_data = nil

        rac_set_platform_adapter(&adapter)
        isRegistered = true

        logger.info("Platform adapter registered with commons")
    }

    // MARK: - Static Callback Handlers

    private static func handleLog(level: rac_log_level_t, category: UnsafePointer<CChar>?, message: UnsafePointer<CChar>?) {
        guard let message = message else { return }
        let msgString = String(cString: message)
        let categoryString = category.map { String(cString: $0) } ?? "RAC"

        // Parse structured metadata from C++ log messages
        // Format: "Message | key1=value1, key2=value2, ..."
        let (cleanMessage, metadata) = parseLogMetadata(msgString)

        let logger = SDKLogger(category: categoryString)
        switch level {
        case RAC_LOG_ERROR:
            logger.error(cleanMessage, metadata: metadata)
        case RAC_LOG_WARNING:
            logger.warning(cleanMessage, metadata: metadata)
        case RAC_LOG_INFO:
            logger.info(cleanMessage, metadata: metadata)
        case RAC_LOG_DEBUG:
            logger.debug(cleanMessage, metadata: metadata)
        case RAC_LOG_TRACE:
            logger.debug("[TRACE] \(cleanMessage)", metadata: metadata)
        default:
            logger.info(cleanMessage, metadata: metadata)
        }
    }

    /// Parses structured metadata from C++ log messages.
    ///
    /// Input format: "Message text | file=foo.cpp:123, func=bar, model=whisper"
    /// Returns: ("Message text", ["file": "foo.cpp:123", "func": "bar", "model": "whisper"])
    private static func parseLogMetadata(_ message: String) -> (String, [String: Any]?) { // swiftlint:disable:this avoid_any_type
        // Split on " | " to separate message from metadata
        let parts = message.components(separatedBy: " | ")
        guard parts.count >= 2 else {
            return (message, nil)
        }

        let cleanMessage = parts[0]
        let metadataString = parts.dropFirst().joined(separator: " | ")

        // Parse key=value pairs (comma or space separated)
        var metadata: [String: Any] = [:] // swiftlint:disable:this prefer_concrete_types avoid_any_type
        let pairs = metadataString.components(separatedBy: CharacterSet(charactersIn: ", "))
            .filter { !$0.isEmpty }

        for pair in pairs {
            let keyValue = pair.components(separatedBy: "=")
            guard keyValue.count == 2 else { continue }

            let key = keyValue[0].trimmingCharacters(in: .whitespaces)
            let value = keyValue[1].trimmingCharacters(in: .whitespaces)

            // Map C++ metadata keys to Swift conventions
            switch key {
            case "file":
                metadata["source_file"] = value
            case "func":
                metadata["source_function"] = value
            case "error_code":
                metadata["error_code"] = Int(value) ?? value
            case "error":
                metadata["error_message"] = value
            case "model":
                metadata["model_id"] = value
            case "framework":
                metadata["framework"] = value
            default:
                metadata[key] = value
            }
        }

        return (cleanMessage, metadata.isEmpty ? nil : metadata)
    }

    private static func handleFileExists(path: UnsafePointer<CChar>?) -> rac_bool_t {
        guard let path = path else {
            return RAC_FALSE
        }

        let pathString = String(cString: path)
        return FileManager.default.fileExists(atPath: pathString) ? RAC_TRUE : RAC_FALSE
    }

    private static func handleFileDelete(path: UnsafePointer<CChar>?) -> rac_result_t {
        guard let path = path else {
            return RAC_ERROR_NULL_POINTER
        }

        let pathString = String(cString: path)

        do {
            try FileManager.default.removeItem(atPath: pathString)
            return RAC_SUCCESS
        } catch {
            return RAC_ERROR_FILE_NOT_FOUND
        }
    }

    // MARK: - Keychain Operations

    private static let keychainService = "com.runanywhere.sdk"

    private static func handleSecureStorageDelete(key: UnsafePointer<CChar>?) -> rac_result_t {
        guard let key = key else {
            return RAC_ERROR_NULL_POINTER
        }

        let keyString = String(cString: key)

        // swiftlint:disable:next avoid_any_type prefer_concrete_types
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keyString
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound ? RAC_SUCCESS : RAC_ERROR_SECURE_STORAGE_FAILED
    }
}
