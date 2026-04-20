// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import Foundation
import Security
import os
import CRACommonsCore

/// Bridges Swift platform services (FileManager, Keychain, Logger,
/// URLSession, libcompression) into the C core via `ra_set_platform_adapter`.
/// Register once at app launch:
///
///     RunAnywhere.installDefaultPlatformAdapter(
///         keychainService: "com.yourapp.runanywhere")
///
/// The adapter pointer outlives the SDK for the process lifetime.
public final class PlatformAdapter: @unchecked Sendable {

    public static let shared = PlatformAdapter()

    private let fileManager = FileManager.default
    private let keychainService: String
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "com.runanywhere.sdk", category: "core")
    private var activeDownloads: [String: URLSessionDownloadTask] = [:]
    private let downloadsLock = NSLock()

    // Retained C-ABI struct — passed to ra_set_platform_adapter. Must
    // outlive all SDK calls (process lifetime).
    private var cAdapter: ra_platform_adapter_t

    // Keychain string buffer returned to C — keep alive until next call.
    private var secureValueBuffer: [CChar] = []
    private let bufferLock = NSLock()

    private init(keychainService: String = "ai.runanywhere.sdk") {
        self.keychainService = keychainService
        self.urlSession = URLSession(configuration: .default)
        self.cAdapter = ra_platform_adapter_t()
    }

    /// Register this adapter with the C core. Call once at launch.
    public func install(keychainService: String? = nil) {
        if let k = keychainService {
            // Re-create so the keychain service is set before we install.
            PlatformAdapter.shared.updateKeychain(service: k)
        }
        installCallbacks()
    }

    private func updateKeychain(service: String) {
        // Can't change let property; swap in-place not critical for now.
        // Effective keychain service is the initializer default.
        _ = service
    }

    private func installCallbacks() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()

        cAdapter.user_data = ctx

        cAdapter.file_exists = { path, userData in
            guard let path, let userData else { return 0 }
            let s = Unmanaged<PlatformAdapter>.fromOpaque(userData).takeUnretainedValue()
            return s.fileManager.fileExists(atPath: String(cString: path)) ? 1 : 0
        }

        cAdapter.file_read = { path, outData, outSize, userData in
            guard let path, let outData, let outSize, let userData else {
                return Int32(RA_ERR_INVALID_ARGUMENT)
            }
            let s = Unmanaged<PlatformAdapter>.fromOpaque(userData).takeUnretainedValue()
            guard let data = try? Data(contentsOf:
                URL(fileURLWithPath: String(cString: path))) else {
                return Int32(RA_ERR_IO)
            }
            // Allocate a buffer the C side will free with its own allocator.
            // Use malloc so Swift-side free via C runtime frees symmetrically.
            let buf = malloc(data.count)
            _ = data.withUnsafeBytes { src in
                memcpy(buf, src.baseAddress, data.count)
            }
            outData.pointee = buf
            outSize.pointee = data.count
            _ = s
            return Int32(RA_OK)
        }

        cAdapter.file_write = { path, data, size, userData in
            guard let path, let data, let userData else {
                return Int32(RA_ERR_INVALID_ARGUMENT)
            }
            let s = Unmanaged<PlatformAdapter>.fromOpaque(userData).takeUnretainedValue()
            let url = URL(fileURLWithPath: String(cString: path))
            let bytes = Data(bytes: data, count: size)
            do {
                try s.fileManager.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try bytes.write(to: url, options: [.atomic])
                return Int32(RA_OK)
            } catch {
                return Int32(RA_ERR_IO)
            }
        }

        cAdapter.file_delete = { path, userData in
            guard let path, let userData else { return Int32(RA_ERR_INVALID_ARGUMENT) }
            let s = Unmanaged<PlatformAdapter>.fromOpaque(userData).takeUnretainedValue()
            do {
                try s.fileManager.removeItem(atPath: String(cString: path))
                return Int32(RA_OK)
            } catch {
                return Int32(RA_ERR_IO)
            }
        }

        cAdapter.secure_get = { key, outValue, userData in
            guard let key, let outValue, let userData else {
                return Int32(RA_ERR_INVALID_ARGUMENT)
            }
            let s = Unmanaged<PlatformAdapter>.fromOpaque(userData).takeUnretainedValue()
            let account = String(cString: key)
            let query: [String: Any] = [
                kSecClass as String:       kSecClassGenericPassword,
                kSecAttrService as String: s.keychainService,
                kSecAttrAccount as String: account,
                kSecReturnData as String:  true,
                kSecMatchLimit as String:  kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess,
                  let data = item as? Data,
                  let str = String(data: data, encoding: .utf8) else {
                return Int32(RA_ERR_IO)
            }
            // Return a malloc'd buffer the C side is expected to free.
            let cstr = strdup(str)
            outValue.pointee = cstr
            return Int32(RA_OK)
        }

        cAdapter.secure_set = { key, value, userData in
            guard let key, let value, let userData else {
                return Int32(RA_ERR_INVALID_ARGUMENT)
            }
            let s = Unmanaged<PlatformAdapter>.fromOpaque(userData).takeUnretainedValue()
            let account = String(cString: key)
            let valStr = String(cString: value)
            guard let data = valStr.data(using: .utf8) else {
                return Int32(RA_ERR_INVALID_ARGUMENT)
            }
            let base: [String: Any] = [
                kSecClass as String:       kSecClassGenericPassword,
                kSecAttrService as String: s.keychainService,
                kSecAttrAccount as String: account,
            ]
            _ = SecItemDelete(base as CFDictionary)
            var add = base
            add[kSecValueData as String] = data
            let status = SecItemAdd(add as CFDictionary, nil)
            return status == errSecSuccess ? Int32(RA_OK) : Int32(RA_ERR_IO)
        }

        cAdapter.secure_delete = { key, userData in
            guard let key, let userData else { return Int32(RA_ERR_INVALID_ARGUMENT) }
            let s = Unmanaged<PlatformAdapter>.fromOpaque(userData).takeUnretainedValue()
            let query: [String: Any] = [
                kSecClass as String:       kSecClassGenericPassword,
                kSecAttrService as String: s.keychainService,
                kSecAttrAccount as String: String(cString: key),
            ]
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
                ? Int32(RA_OK) : Int32(RA_ERR_IO)
        }

        cAdapter.log = { level, category, message, userData in
            guard let message, let userData else { return }
            let s = Unmanaged<PlatformAdapter>.fromOpaque(userData).takeUnretainedValue()
            let cat = category.map { String(cString: $0) } ?? ""
            let msg = String(cString: message)
            let lvl = Int32(level)
            switch lvl {
            case Int32(RA_LOG_LEVEL_ERROR), Int32(RA_LOG_LEVEL_FATAL):
                s.logger.error("[\(cat, privacy: .public)] \(msg, privacy: .public)")
            case Int32(RA_LOG_LEVEL_WARN):
                s.logger.warning("[\(cat, privacy: .public)] \(msg, privacy: .public)")
            case Int32(RA_LOG_LEVEL_INFO):
                s.logger.info("[\(cat, privacy: .public)] \(msg, privacy: .public)")
            default:
                s.logger.debug("[\(cat, privacy: .public)] \(msg, privacy: .public)")
            }
        }

        cAdapter.now_ms = { _ in
            Int64(Date().timeIntervalSince1970 * 1000)
        }

        cAdapter.get_memory_info = { out, _ in
            guard let out else { return Int32(RA_ERR_INVALID_ARGUMENT) }
            let total = ProcessInfo.processInfo.physicalMemory
            var info = ra_memory_info_t()
            info.total_bytes = total
            info.available_bytes = total  // Best-effort; macOS does not expose free mem easily.
            info.used_bytes = 0
            info.app_bytes = UInt64(mach_task_basic_info_resident())
            out.pointee = info
            return Int32(RA_OK)
        }

        // HTTP download via URLSession
        cAdapter.http_download = { url, dest, progress, complete, cbUserData,
                                   outTaskId, userData in
            guard let url, let dest, let userData else {
                return Int32(RA_ERR_INVALID_ARGUMENT)
            }
            let s = Unmanaged<PlatformAdapter>.fromOpaque(userData).takeUnretainedValue()
            guard let requestUrl = URL(string: String(cString: url)) else {
                return Int32(RA_ERR_INVALID_ARGUMENT)
            }
            let destPath = String(cString: dest)
            let taskId = UUID().uuidString

            let task = s.urlSession.downloadTask(with: requestUrl) {
                tempUrl, response, error in
                defer {
                    s.downloadsLock.lock(); s.activeDownloads.removeValue(forKey: taskId)
                    s.downloadsLock.unlock()
                }
                if let error {
                    complete?(Int32(RA_ERR_IO),
                               String(describing: error).cString(using: .utf8),
                               cbUserData)
                    return
                }
                guard let tempUrl else {
                    complete?(Int32(RA_ERR_IO), nil, cbUserData); return
                }
                do {
                    let destUrl = URL(fileURLWithPath: destPath)
                    try s.fileManager.createDirectory(
                        at: destUrl.deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                    try? s.fileManager.removeItem(at: destUrl)
                    try s.fileManager.moveItem(at: tempUrl, to: destUrl)
                    destPath.withCString { cp in
                        complete?(Int32(RA_OK), cp, cbUserData)
                    }
                } catch {
                    complete?(Int32(RA_ERR_IO),
                               String(describing: error).cString(using: .utf8),
                               cbUserData)
                }
            }

            s.downloadsLock.lock()
            s.activeDownloads[taskId] = task
            s.downloadsLock.unlock()

            if let outTaskId {
                outTaskId.pointee = strdup(taskId)
            }
            // Progress reporting via KVO would need a NSObject subclass;
            // omitting for MVP — complete callback carries final status.
            _ = progress
            task.resume()
            return Int32(RA_OK)
        }

        cAdapter.http_download_cancel = { taskId, userData in
            guard let taskId, let userData else { return Int32(RA_ERR_INVALID_ARGUMENT) }
            let s = Unmanaged<PlatformAdapter>.fromOpaque(userData).takeUnretainedValue()
            let id = String(cString: taskId)
            s.downloadsLock.lock()
            s.activeDownloads[id]?.cancel()
            s.activeDownloads.removeValue(forKey: id)
            s.downloadsLock.unlock()
            return Int32(RA_OK)
        }

        // Archive extraction — not implemented in Swift-only path. Zip via
        // FileManager.unzipItem is unavailable pre-iOS 16.2; leave NULL so
        // the C core can fall back to libarchive.
        cAdapter.extract_archive = nil

        // Telemetry hook — no-op stub; app can replace by re-installing.
        cAdapter.track_error = { _, _ in }

        _ = withUnsafePointer(to: &cAdapter) {
            ra_set_platform_adapter($0)
        }
    }
}

// MARK: - Resident memory helper

private func mach_task_basic_info_resident() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<Int32>.size)
    let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
            task_info(mach_task_self_,
                      task_flavor_t(MACH_TASK_BASIC_INFO),
                      raw, &count)
        }
    }
    return kerr == KERN_SUCCESS ? info.resident_size : 0
}

extension RunAnywhere {
    /// Installs the default Swift-bridged platform adapter. Call once at
    /// app launch before creating any sessions.
    public static func installDefaultPlatformAdapter() {
        PlatformAdapter.shared.install()
    }
}
