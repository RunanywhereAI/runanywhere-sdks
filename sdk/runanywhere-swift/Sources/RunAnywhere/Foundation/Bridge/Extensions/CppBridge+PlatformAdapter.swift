//
//  CppBridge+PlatformAdapter.swift
//  RunAnywhere SDK
//
//  Platform adapter bridge for fundamental C++ → Swift operations.
//  Provides: logging, file operations, secure storage, clock,
//  directory enumeration, vendor id, and HTTP download fallback.
//

// file_length disabled: every callback must live at file scope (no captures)
// for C interop, so splitting across files would require making them
// `internal`. The directory + HTTP blocks push past the 800-line warning;
// the 1500-line error threshold remains a hard limit.
// swiftlint:disable file_length

import CRACommons
import Foundation
import os
import Security

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

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

            // MARK: Vendor ID (Apple-only — used by commons device-identity chain)
            // Commons walks: secure_get -> get_vendor_id -> generate fresh UUID.
            // Swift only contributes the iOS-specific UIDevice.identifierForVendor;
            // Keychain persistence happens automatically via secure_set/secure_get.
            adapter.get_vendor_id = platformGetVendorIdCallback

            // MARK: Directory Enumeration (model-registry rescan + is_downloaded probe)
            // Populating these slots lets the commons rescan_local refresh path
            // and rac_model_info_make_proto's multi-file is_downloaded gating
            // work on Apple platforms without the warning fallback in
            // ModelRegistryRefreshResult.warnings. Matches the Kotlin / Flutter /
            // RN siblings of CLUSTER-280-SPLIT.
            adapter.file_list_directory = platformFileListDirectoryCallback
            adapter.is_non_empty_directory = platformIsNonEmptyDirectoryCallback

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

// MARK: - Directory Enumeration Callbacks

/// Enumerate a directory into a caller-provided array per the two-call contract
/// on `rac_file_list_directory_fn`. Powers commons rescan_local + the multi-file
/// `is_downloaded` probe (rac_path_is_non_empty_directory).
///
/// Truncation contract (per `rac_directory_entry_t::name`): entries whose UTF-8
/// byte length plus the trailing NUL exceed `RAC_DIRECTORY_ENTRY_NAME_MAX` are
/// skipped rather than truncated so the no-error path never aliases a different
/// artifact. A single WARN log per call summarises any skipped entries.
private func platformFileListDirectoryCallback(
    dirPath: UnsafePointer<CChar>?,
    outEntries: UnsafeMutablePointer<rac_directory_entry_t>?,
    inOutCount: UnsafeMutablePointer<Int>?,
    userData _: UnsafeMutableRawPointer?
) -> rac_result_t {
    guard let dirPath = dirPath, let inOutCount = inOutCount else {
        return RAC_ERROR_INVALID_ARGUMENT
    }

    let pathString = String(cString: dirPath)
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: pathString, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        return RAC_ERROR_FILE_NOT_FOUND
    }

    let entries: [String]
    do {
        entries = try fileManager.contentsOfDirectory(atPath: pathString)
    } catch {
        return RAC_ERROR_INTERNAL
    }

    // Capacity-query call: report total entries without filling the buffer.
    guard let outEntries = outEntries else {
        inOutCount.pointee = entries.count
        return RAC_SUCCESS
    }

    let capacity = inOutCount.pointee
    let nameMax = Int(RAC_DIRECTORY_ENTRY_NAME_MAX)
    var written = 0
    var skipped = 0

    for entryName in entries {
        if written >= capacity { break }

        let didWrite = entryName.withCString { src -> Bool in
            let length = strlen(src)
            // strlen excludes NUL — buffer must fit len + NUL.
            if length + 1 > nameMax {
                return false
            }
            let entryPtr = outEntries.advanced(by: written)
            // Zero-fill the fixed-size name buffer, then copy bytes + NUL.
            withUnsafeMutablePointer(to: &entryPtr.pointee.name) { tuplePtr in
                tuplePtr.withMemoryRebound(to: CChar.self, capacity: nameMax) { nameBuf in
                    memset(nameBuf, 0, nameMax)
                    memcpy(nameBuf, src, length + 1)
                }
            }

            let fullPath = (pathString as NSString).appendingPathComponent(entryName)
            var childIsDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: fullPath, isDirectory: &childIsDir)
            entryPtr.pointee.is_dir = (exists && childIsDir.boolValue) ? RAC_TRUE : RAC_FALSE

            if exists && !childIsDir.boolValue {
                let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                entryPtr.pointee.size_bytes = size
            } else {
                entryPtr.pointee.size_bytes = 0
            }
            return true
        }

        if didWrite {
            written += 1
        } else {
            skipped += 1
        }
    }

    if skipped > 0 {
        let logger = SDKLogger(category: "PlatformAdapter")
        logger.warning("file_list_directory: skipped \(skipped) oversized entry name(s) in \(pathString)")
    }

    inOutCount.pointee = written
    return RAC_SUCCESS
}

/// Cheap "is this a non-empty directory" probe consumed by
/// `rac_path_is_non_empty_directory()` so multi-file `is_downloaded` gating
/// avoids the full enumeration cost when an entry is present.
private func platformIsNonEmptyDirectoryCallback(
    path: UnsafePointer<CChar>?,
    userData _: UnsafeMutableRawPointer?
) -> rac_bool_t {
    guard let path = path else { return RAC_FALSE }
    let pathString = String(cString: path)
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: pathString, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        return RAC_FALSE
    }
    let entries = (try? fileManager.contentsOfDirectory(atPath: pathString)) ?? []
    return entries.isEmpty ? RAC_FALSE : RAC_TRUE
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

    // Distinguish a clean "key does not exist" miss from a real Keychain
    // failure per the rac_platform_adapter.h:secure_get contract — commons
    // consumers (e.g. rac_device_get_or_create_persistent_id) depend on the
    // miss code to decide between fallback and propagation.
    if status == errSecItemNotFound {
        return RAC_ERROR_FILE_NOT_FOUND
    }
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

// MARK: - Vendor ID Callback (Apple-only)

/// Provides UIDevice.identifierForVendor.uuidString to the commons
/// device-identity resolver (P2-T13). On macOS the API is unavailable so
/// commons falls through to its synthesized-UUID branch. The returned
/// UUID string is guaranteed to fit in the 36-char canonical form + NUL.
private func platformGetVendorIdCallback(
    outBuffer: UnsafeMutablePointer<CChar>?,
    bufferSize: Int,
    userData _: UnsafeMutableRawPointer?
) -> rac_result_t {
    guard let outBuffer = outBuffer else {
        return RAC_ERROR_NULL_POINTER
    }
    if bufferSize < Int(RAC_DEVICE_ID_BUFFER_MIN_SIZE) {
        return RAC_ERROR_BUFFER_TOO_SMALL
    }

    #if os(iOS) || os(tvOS) || os(visionOS)
    // UIDevice.identifierForVendor is synchronous and thread-safe; no
    // MainActor hop required. Returns nil on rare provisioning errors.
    guard let vendorId = UIDevice.current.identifierForVendor?.uuidString else {
        return RAC_ERROR_NOT_FOUND
    }

    let copied = vendorId.withCString { src -> Bool in
        // strlen excludes NUL — bufferSize must accommodate len + NUL.
        let len = strlen(src)
        guard len + 1 <= bufferSize else { return false }
        memcpy(outBuffer, src, len + 1)
        return true
    }
    return copied ? RAC_SUCCESS : RAC_ERROR_BUFFER_TOO_SMALL
    #else
    // macOS / watchOS have no identifierForVendor analog — let commons
    // fall through to its synthesized-UUID branch.
    return RAC_ERROR_NOT_SUPPORTED
    #endif
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

    // Map C++ error code to RAErrorCode via the canonical commons ABI
    // (rac_result_to_proto_error).
    let errorCode = RASDKError.from(rcResult: code)?.code ?? .unknown

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
    // Per AGENTS.md: NSLock is forbidden — use OSAllocatedUnfairLock.
    private let cancelled = OSAllocatedUnfairLock<Bool>(initialState: false)

    func cancel() {
        cancelled.withLock { $0 = true }
    }

    var isCancelled: Bool {
        cancelled.withLock { $0 }
    }
}

private let platformHttpDownloadQueue = DispatchQueue(
    label: "com.runanywhere.sdk.platformhttpdownload",
    qos: .userInitiated,
    attributes: .concurrent
)

private let platformHttpDownloadFlagsRegistry =
    OSAllocatedUnfairLock<[String: PlatformDownloadCancelFlag]>(initialState: [:])

private func platformDownloadRegister(_ taskId: String, _ flag: PlatformDownloadCancelFlag) {
    platformHttpDownloadFlagsRegistry.withLock { $0[taskId] = flag }
}

private func platformDownloadUnregister(_ taskId: String) {
    platformHttpDownloadFlagsRegistry.withLock { _ = $0.removeValue(forKey: taskId) }
}

private func platformDownloadLookup(_ taskId: String) -> PlatformDownloadCancelFlag? {
    platformHttpDownloadFlagsRegistry.withLock { $0[taskId] }
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
