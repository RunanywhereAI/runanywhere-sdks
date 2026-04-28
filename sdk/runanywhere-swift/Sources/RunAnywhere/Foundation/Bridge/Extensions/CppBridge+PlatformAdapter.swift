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

            // MARK: Memory Info
            adapter.get_memory_info = platformGetMemoryInfoCallback

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

// MARK: - Memory Info Callback

/// Reports process-level memory usage to C++ via the platform adapter.
///
/// Uses `task_vm_info` (mach) for accurate process footprint on Apple platforms.
/// `phys_footprint` is the value Apple uses for Jetsam/OOM accounting, which
/// maps most directly to the "used" memory concept the C++ core expects.
private func platformGetMemoryInfoCallback(
    outInfo: UnsafeMutablePointer<rac_memory_info_t>?,
    userData _: UnsafeMutableRawPointer?
) -> rac_result_t {
    guard let outInfo = outInfo else {
        return RAC_ERROR_NULL_POINTER
    }

    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
    )
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }

    guard kr == KERN_SUCCESS else {
        return RAC_ERROR_INTERNAL
    }

    let total = ProcessInfo.processInfo.physicalMemory
    let used = UInt64(info.phys_footprint)
    let available = total > used ? total - used : 0

    outInfo.pointee.total_bytes = total
    outInfo.pointee.used_bytes = used
    outInfo.pointee.available_bytes = available

    return RAC_SUCCESS
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

    // Convert C++ structured error to Swift SDKException for consistent handling
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

// Creates an SDKException from C++ error dictionary for consistent error handling
// swiftlint:disable:next avoid_any_type prefer_concrete_types
private func createSDKErrorFromCppError(_ errorDict: [String: Any]) -> SDKException {
    let code = errorDict["code"] as? Int32 ?? Int32(RAC_ERROR_UNKNOWN)
    let message = errorDict["message"] as? String ?? "Unknown error"
    let categoryName = errorDict["category"] as? String ?? "internal"

    // Map category name to RAErrorCategory (proto canonical 9-bucket enum)
    let category: RAErrorCategory
    switch categoryName.lowercased() {
    case "network":       category = .network
    case "validation":    category = .validation
    case "model":         category = .model
    case "component":     category = .component
    case "io":            category = .io
    case "auth":          category = .auth
    case "configuration": category = .configuration
    default:              category = .internal
    }

    // Map C++ error code to RAErrorCode
    let errorCode = CommonsErrorMapping.toSDKException(code)?.proto.code ?? .unknown

    return SDKException(
        code: errorCode,
        message: message,
        category: category,
        underlying: nil
    )
}

// MARK: - HTTP Download Callbacks
//
// The C++ platform adapter still exposes an HTTP-download callback
// slot for historical reasons (see `rac_http_download` in
// `rac_platform_adapter.h`). On Swift we route every request through
// the canonical libcurl-backed `rac_http_download_execute` runner so
// the transport matches what the other SDKs use and there is no
// URLSession code left in the SDK. Cancellation is bridged via a
// shared flag map keyed on the task id the platform callback hands
// to the C++ caller.

private final class PlatformDownloadCancelFlag {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

private let platformHttpDownloadQueue = DispatchQueue(
    label: "com.runanywhere.sdk.platformhttpdownload",
    qos: .userInitiated,
    attributes: .concurrent
)

private let platformHttpDownloadRegistryLock = NSLock()
private var platformHttpDownloadFlags: [String: PlatformDownloadCancelFlag] = [:]

private func platformDownloadRegister(_ taskId: String, _ flag: PlatformDownloadCancelFlag) {
    platformHttpDownloadRegistryLock.lock()
    platformHttpDownloadFlags[taskId] = flag
    platformHttpDownloadRegistryLock.unlock()
}

private func platformDownloadUnregister(_ taskId: String) {
    platformHttpDownloadRegistryLock.lock()
    platformHttpDownloadFlags.removeValue(forKey: taskId)
    platformHttpDownloadRegistryLock.unlock()
}

private func platformDownloadLookup(_ taskId: String) -> PlatformDownloadCancelFlag? {
    platformHttpDownloadRegistryLock.lock()
    defer { platformHttpDownloadRegistryLock.unlock() }
    return platformHttpDownloadFlags[taskId]
}

/// Boxed per-download state forwarded into the C progress callback
/// via an opaque pointer (`Unmanaged.passRetained`).
private final class PlatformDownloadProgressState {
    let progressCallback: rac_http_progress_callback_fn?
    let callbackUserData: UnsafeMutableRawPointer?
    let cancelFlag: PlatformDownloadCancelFlag

    init(
        progressCallback: rac_http_progress_callback_fn?,
        callbackUserData: UnsafeMutableRawPointer?,
        cancelFlag: PlatformDownloadCancelFlag
    ) {
        self.progressCallback = progressCallback
        self.callbackUserData = callbackUserData
        self.cancelFlag = cancelFlag
    }
}

private func platformDownloadProgressTrampoline(
    bytesWritten: UInt64,
    totalBytes: UInt64,
    userData: UnsafeMutableRawPointer?
) -> rac_bool_t {
    guard let userData = userData else { return RAC_TRUE }
    let state = Unmanaged<PlatformDownloadProgressState>.fromOpaque(userData).takeUnretainedValue()

    if state.cancelFlag.isCancelled {
        return RAC_FALSE
    }

    if let progressCallback = state.progressCallback {
        let written = Int64(min(UInt64(Int64.max), bytesWritten))
        let total = Int64(min(UInt64(Int64.max), totalBytes))
        progressCallback(written, total, state.callbackUserData)
    }
    return RAC_TRUE
}

private func platformMapDownloadStatusToResult(_ status: rac_http_download_status_t) -> rac_result_t {
    switch status {
    case RAC_HTTP_DL_OK:
        return RAC_SUCCESS
    default:
        return RAC_ERROR_DOWNLOAD_FAILED
    }
}

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

    guard URL(string: urlString) != nil else {
        return RAC_ERROR_INVALID_ARGUMENT
    }

    let taskId = UUID().uuidString
    outTaskId.pointee = rac_strdup(taskId)

    let cancelFlag = PlatformDownloadCancelFlag()
    platformDownloadRegister(taskId, cancelFlag)

    platformHttpDownloadQueue.async {
        // Ensure the destination directory exists before handing off
        // to curl — the runner opens the destination in write mode
        // but does not create intermediate directories.
        let destinationURL = URL(fileURLWithPath: destination)
        let destinationDir = destinationURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        let state = PlatformDownloadProgressState(
            progressCallback: progressCallback,
            callbackUserData: callbackUserData,
            cancelFlag: cancelFlag
        )
        let stateRef = Unmanaged.passRetained(state)
        defer {
            stateRef.release()
            platformDownloadUnregister(taskId)
        }

        var finalStatus: rac_http_download_status_t = RAC_HTTP_DL_UNKNOWN

        urlString.withCString { urlC in
            destination.withCString { destC in
                var request = rac_http_download_request_t(
                    url: urlC,
                    destination_path: destC,
                    headers: nil,
                    header_count: 0,
                    timeout_ms: 0,
                    follow_redirects: RAC_TRUE,
                    resume_from_byte: 0,
                    expected_sha256_hex: nil
                )

                var httpStatusOut: Int32 = 0
                finalStatus = rac_http_download_execute(
                    &request,
                    platformDownloadProgressTrampoline,
                    stateRef.toOpaque(),
                    &httpStatusOut
                )
            }
        }

        let result = platformMapDownloadStatusToResult(finalStatus)
        let finalPath: String? = result == RAC_SUCCESS ? destination : nil

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
    guard let flag = platformDownloadLookup(taskKey) else {
        return RAC_ERROR_NOT_FOUND
    }
    flag.cancel()
    return RAC_SUCCESS
}
