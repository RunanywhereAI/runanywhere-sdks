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

            // MARK: Error Tracking (Sentry)
            adapter.track_error = platformTrackErrorCallback

            // MARK: Optional Callbacks (handled by Swift directly)
            adapter.http_download = platformHttpDownloadCallback
            adapter.http_download_cancel = platformHttpDownloadCancelCallback
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
    userData _: UnsafeMutableRawPointer?
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
    userData _: UnsafeMutableRawPointer?
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
    userData _: UnsafeMutableRawPointer?
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
    userData _: UnsafeMutableRawPointer?
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
    userData _: UnsafeMutableRawPointer?
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
    userData _: UnsafeMutableRawPointer?
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
    userData _: UnsafeMutableRawPointer?
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
    userData _: UnsafeMutableRawPointer?
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
    userData _: UnsafeMutableRawPointer?
) -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
}

// MARK: - Error Tracking Callback

/// Receives structured error JSON from C++ and sends to Sentry
private func platformTrackErrorCallback(
    errorJson: UnsafePointer<CChar>?,
    userData _: UnsafeMutableRawPointer?
) {
    guard let errorJson = errorJson else { return }

    let jsonString = String(cString: errorJson)

    // Parse the JSON and create a Sentry event
    guard let jsonData = jsonString.data(using: .utf8),
          let errorDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { // swiftlint:disable:this avoid_any_type
        return
    }

    // Convert C++ structured error to Swift SDKError for consistent handling
    let sdkError = createSDKErrorFromCppError(errorDict)

    // Log through the standard logging system (which routes to Sentry)
    let category = errorDict["category"] as? String ?? "general"
    let message = errorDict["message"] as? String ?? "Unknown error"

    // Build metadata from C++ error
    // swiftlint:disable:next prefer_concrete_types avoid_any_type
    var metadata: [String: Any] = [:]

    if let code = errorDict["code"] as? Int {
        metadata["error_code"] = code
    }
    if let codeName = errorDict["code_name"] as? String {
        metadata["error_code_name"] = codeName
    }
    if let sourceFile = errorDict["source_file"] as? String {
        metadata["source_file"] = sourceFile
    }
    if let sourceLine = errorDict["source_line"] as? Int {
        metadata["source_line"] = sourceLine
    }
    if let sourceFunction = errorDict["source_function"] as? String {
        metadata["source_function"] = sourceFunction
    }
    if let modelId = errorDict["model_id"] as? String {
        metadata["model_id"] = modelId
    }
    if let framework = errorDict["framework"] as? String {
        metadata["framework"] = framework
    }
    if let sessionId = errorDict["session_id"] as? String {
        metadata["session_id"] = sessionId
    }
    if let underlyingCode = errorDict["underlying_code"] as? Int, underlyingCode != 0 {
        metadata["underlying_code"] = underlyingCode
        metadata["underlying_message"] = errorDict["underlying_message"] as? String ?? ""
    }
    if let stackFrameCount = errorDict["stack_frame_count"] as? Int {
        metadata["stack_frame_count"] = stackFrameCount
    }

    // Route through logging system which handles Sentry
    Logging.shared.log(level: .error, category: category, message: message, metadata: metadata)

    // Also directly capture in Sentry if available for better error grouping
    if SentryManager.shared.isInitialized {
        SentryManager.shared.captureError(sdkError, context: metadata)
    }
}

// Creates an SDKError from C++ error dictionary for consistent error handling
// swiftlint:disable:next avoid_any_type prefer_concrete_types
private func createSDKErrorFromCppError(_ errorDict: [String: Any]) -> SDKError {
    let code = errorDict["code"] as? Int32 ?? Int32(RAC_ERROR_UNKNOWN)
    let message = errorDict["message"] as? String ?? "Unknown error"
    let categoryName = errorDict["category"] as? String ?? "general"

    // Map category name to ErrorCategory
    let category = ErrorCategory(rawValue: categoryName) ?? .general

    // Map C++ error code to Swift ErrorCode
    let errorCode = CommonsErrorMapping.toSDKError(code)?.code ?? .unknown

    // Build stack trace from C++ if available
    var stackTrace: [String] = []
    if let sourceFile = errorDict["source_file"] as? String,
       let sourceLine = errorDict["source_line"] as? Int,
       let sourceFunction = errorDict["source_function"] as? String {
        stackTrace.append("\(sourceFunction) at \(sourceFile):\(sourceLine)")
    }

    return SDKError(
        code: errorCode,
        message: message,
        category: category,
        stackTrace: stackTrace,
        underlyingError: nil
    )
}

// MARK: - HTTP Download Callbacks

private let httpDownloadQueue = DispatchQueue(label: "com.runanywhere.sdk.httpdownload")
private var httpDownloadTasks: [String: URLSessionDownloadTask] = [:]

private func platformHttpDownloadCallback(
    url: UnsafePointer<CChar>?,
    destinationPath: UnsafePointer<CChar>?,
    progressCallback: rac_http_progress_callback_fn?,
    completeCallback: rac_http_complete_callback_fn?,
    callbackUserData: UnsafeMutableRawPointer?,
    outTaskId: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    userData _: UnsafeMutableRawPointer?
) -> rac_result_t {
    guard let url = url, let destinationPath = destinationPath, let outTaskId = outTaskId else {
        return RAC_ERROR_INVALID_ARGUMENT
    }

    let urlString = String(cString: url)
    let destination = String(cString: destinationPath)

    guard let downloadURL = URL(string: urlString) else {
        return RAC_ERROR_INVALID_ARGUMENT
    }

    let taskId = UUID().uuidString
    outTaskId.pointee = rac_strdup(taskId)

    let session = URLSession(configuration: .default)
    let task = session.downloadTask(with: downloadURL) { tempURL, _, error in
        var result: rac_result_t = RAC_SUCCESS
        var finalPath: String?

        defer {
            httpDownloadQueue.async {
                httpDownloadTasks.removeValue(forKey: taskId)
            }
        }

        if let _ = error {
            result = RAC_ERROR_DOWNLOAD_FAILED
        } else if let tempURL = tempURL {
            do {
                let destinationURL = URL(fileURLWithPath: destination)
                let destinationDir = destinationURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: destinationDir,
                                                        withIntermediateDirectories: true,
                                                        attributes: nil)
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                finalPath = destinationURL.path
            } catch {
                result = RAC_ERROR_DOWNLOAD_FAILED
            }
        } else {
            result = RAC_ERROR_DOWNLOAD_FAILED
        }

        if let progressCallback = progressCallback {
            if let finalPath = finalPath,
               let attrs = try? FileManager.default.attributesOfItem(atPath: finalPath),
               let fileSize = attrs[.size] as? NSNumber {
                progressCallback(fileSize.int64Value, fileSize.int64Value, callbackUserData)
            }
        }

        if let completeCallback = completeCallback {
            if let finalPath = finalPath {
                finalPath.withCString { cPath in
                    completeCallback(result, cPath, callbackUserData)
                }
            } else {
                completeCallback(result, nil, callbackUserData)
            }
        }
    }

    httpDownloadQueue.async {
        httpDownloadTasks[taskId] = task
    }

    task.resume()
    return RAC_SUCCESS
}

private func platformHttpDownloadCancelCallback(
    taskId: UnsafePointer<CChar>?,
    userData _: UnsafeMutableRawPointer?
) -> rac_result_t {
    guard let taskId = taskId else {
        return RAC_ERROR_INVALID_ARGUMENT
    }

    let taskKey = String(cString: taskId)
    var task: URLSessionDownloadTask?

    httpDownloadQueue.sync {
        task = httpDownloadTasks[taskKey]
    }

    guard let downloadTask = task else {
        return RAC_ERROR_NOT_FOUND
    }

    downloadTask.cancel()
    httpDownloadQueue.async {
        httpDownloadTasks.removeValue(forKey: taskKey)
    }
    return RAC_SUCCESS
}
