//
//  CppBridge+PlatformAdapter.swift
//  RunAnywhere SDK
//
//  Platform adapter bridge for fundamental C++ → Swift operations.
//  Provides: logging, file operations, secure storage, clock.
//

import CRACommons
import Foundation
import Security

// MARK: - Platform Adapter Bridge

extension CppBridge {

    /// Platform adapter - provides fundamental OS operations for C++
    ///
    /// C++ code cannot directly:
    /// - Write to disk
    /// - Access Keychain
    /// - Get current time
    /// - Route logs to native logging system
    ///
    /// This bridge provides those capabilities via C function callbacks.
    public enum PlatformAdapter {

        /// Whether the adapter has been registered
        private static var isRegistered = false

        /// The adapter struct - MUST persist for C++ to call
        private static var adapter = rac_platform_adapter_t()

        // MARK: - Registration

        /// Register platform adapter with C++
        /// Must be called FIRST during SDK init (before any C++ operations)
        static func register() {
            guard !isRegistered else { return }

            // Reset adapter
            adapter = rac_platform_adapter_t()

            // MARK: Logging Callback
            adapter.log = platformLogCallback

            // MARK: File Operations
            adapter.file_exists = platformFileExistsCallback
            adapter.file_read = platformFileReadCallback
            adapter.file_write = platformFileWriteCallback
            adapter.file_delete = platformFileDeleteCallback

            // MARK: Secure Storage (Keychain)
            adapter.secure_get = platformSecureGetCallback
            adapter.secure_set = platformSecureSetCallback
            adapter.secure_delete = platformSecureDeleteCallback

            // MARK: Clock
            adapter.now_ms = platformNowMsCallback

            // MARK: Memory Info (not implemented)
            adapter.get_memory_info = { _, _ -> rac_result_t in
                RAC_ERROR_NOT_SUPPORTED
            }

            // MARK: Optional Callbacks (handled by Swift directly)
            adapter.http_download = nil
            adapter.http_download_cancel = nil
            adapter.extract_archive = nil
            adapter.user_data = nil

            // Register with C++
            rac_set_platform_adapter(&adapter)
            isRegistered = true

            // Force link device manager symbols
            _ = rac_device_manager_is_registered()

            SDKLogger(category: "CppBridge.PlatformAdapter").debug("Platform adapter registered")
        }
    }
}

// MARK: - C Function Pointer Callbacks (must be at file scope, no captures)

private let platformKeychainService = "com.runanywhere.sdk"

private func platformLogCallback(
    level: rac_log_level_t,
    category: UnsafePointer<CChar>?,
    message: UnsafePointer<CChar>?,
    userData: UnsafeMutableRawPointer?
) {
    guard let message = message else { return }
    let msgString = String(cString: message)
    let categoryString = category.map { String(cString: $0) } ?? "RAC"

    // Parse structured metadata from C++ log messages
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

// Parse structured metadata from C++ log messages.
// Format: "Message text | key1=value1, key2=value2"
// swiftlint:disable:next avoid_any_type
private func parseLogMetadata(_ message: String) -> (String, [String: Any]?) {
    let parts = message.components(separatedBy: " | ")
    guard parts.count >= 2 else {
        return (message, nil)
    }

    let cleanMessage = parts[0]
    let metadataString = parts.dropFirst().joined(separator: " | ")

    // swiftlint:disable:next avoid_any_type prefer_concrete_types
    var metadata: [String: Any] = [:]
    let pairs = metadataString.components(separatedBy: CharacterSet(charactersIn: ", "))
        .filter { !$0.isEmpty }

    for pair in pairs {
        let keyValue = pair.components(separatedBy: "=")
        guard keyValue.count == 2 else { continue }

        let key = keyValue[0].trimmingCharacters(in: .whitespaces)
        let value = keyValue[1].trimmingCharacters(in: .whitespaces)

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

private func platformFileExistsCallback(
    path: UnsafePointer<CChar>?,
    userData: UnsafeMutableRawPointer?
) -> rac_bool_t {
    guard let path = path else {
        return RAC_FALSE
    }
    let pathString = String(cString: path)
    return FileManager.default.fileExists(atPath: pathString) ? RAC_TRUE : RAC_FALSE
}

private func platformFileReadCallback(
    path: UnsafePointer<CChar>?,
    outData: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
    outSize: UnsafeMutablePointer<Int>?,
    userData: UnsafeMutableRawPointer?
) -> rac_result_t {
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

private func platformFileWriteCallback(
    path: UnsafePointer<CChar>?,
    data: UnsafeRawPointer?,
    size: Int,
    userData: UnsafeMutableRawPointer?
) -> rac_result_t {
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

private func platformFileDeleteCallback(
    path: UnsafePointer<CChar>?,
    userData: UnsafeMutableRawPointer?
) -> rac_result_t {
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

private func platformSecureGetCallback(
    key: UnsafePointer<CChar>?,
    outValue: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    userData: UnsafeMutableRawPointer?
) -> rac_result_t {
    guard let key = key, let outValue = outValue else {
        return RAC_ERROR_NULL_POINTER
    }

    let keyString = String(cString: key)

    // Keychain API requires dictionary with heterogeneous values
    // swiftlint:disable:next avoid_any_type prefer_concrete_types
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: platformKeychainService,
        kSecAttrAccount as String: keyString,
        kSecReturnData as String: true
    ]

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess, let data = result as? Data else {
        return RAC_ERROR_SECURE_STORAGE_FAILED
    }

    if let stringValue = String(data: data, encoding: .utf8) {
        let cString = strdup(stringValue)
        outValue.pointee = cString
        return RAC_SUCCESS
    }

    return RAC_ERROR_SECURE_STORAGE_FAILED
}

private func platformSecureSetCallback(
    key: UnsafePointer<CChar>?,
    value: UnsafePointer<CChar>?,
    userData: UnsafeMutableRawPointer?
) -> rac_result_t {
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
        kSecAttrService as String: platformKeychainService,
        kSecAttrAccount as String: keyString
    ]
    SecItemDelete(deleteQuery as CFDictionary)

    // Add new item
    // swiftlint:disable:next avoid_any_type prefer_concrete_types
    let addQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: platformKeychainService,
        kSecAttrAccount as String: keyString,
        kSecValueData as String: data
    ]

    let status = SecItemAdd(addQuery as CFDictionary, nil)
    return status == errSecSuccess ? RAC_SUCCESS : RAC_ERROR_SECURE_STORAGE_FAILED
}

private func platformSecureDeleteCallback(
    key: UnsafePointer<CChar>?,
    userData: UnsafeMutableRawPointer?
) -> rac_result_t {
    guard let key = key else {
        return RAC_ERROR_NULL_POINTER
    }

    let keyString = String(cString: key)

    // Keychain API requires dictionary with heterogeneous values
    // swiftlint:disable:next avoid_any_type prefer_concrete_types
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: platformKeychainService,
        kSecAttrAccount as String: keyString
    ]

    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
        ? RAC_SUCCESS : RAC_ERROR_SECURE_STORAGE_FAILED
}

private func platformNowMsCallback(
    userData: UnsafeMutableRawPointer?
) -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
}
