// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// WhisperKitSTTService — installs the Swift-side transcribe bridge into
// the `engines/whisperkit` plugin via `ra_whisperkit_set_callbacks`.
//
// Requires the `WhisperKit` SPM dependency. Sample apps opt in by
// adding `.package(url: "https://github.com/argmaxinc/WhisperKit")` to
// their Package.swift; when the dep is present, `canImport(WhisperKit)`
// gates this entire file.

import Foundation
import CRACommonsCore

#if canImport(WhisperKit)
import WhisperKit
#endif

/// Strong-ref holder for a Swift WhisperKit instance bound to the C
/// session handle returned to the plugin's stt_create.
final class WhisperKitSessionBox {
    #if canImport(WhisperKit)
    let pipe: WhisperKit
    init(pipe: WhisperKit) { self.pipe = pipe }
    #else
    init() {}
    #endif
}

public enum WhisperKitSTTService {

    // Handle registry — strong refs keyed by the raw pointer the C ABI holds.
    private nonisolated(unsafe) static var handles: [OpaquePointer: WhisperKitSessionBox] = [:]
    private static let handlesLock = NSLock()

    /// Install the callback table with the C plugin. Idempotent.
    public static func installCallbacks() {
        var cbs = ra_whisperkit_callbacks_t()
        cbs.create      = { modelPath, _ in
            WhisperKitSTTService.create(modelPath: modelPath)
        }
        cbs.destroy     = { handle, _ in
            WhisperKitSTTService.destroy(handle: handle)
        }
        cbs.transcribe  = { handle, audio, count, sampleRate, language, outText, _ in
            WhisperKitSTTService.transcribe(
                handle: handle, audio: audio, count: count,
                sampleRate: sampleRate, language: language,
                outText: outText)
        }
        cbs.string_free = { ptr, _ in
            if let p = ptr { free(p) }
        }
        cbs.user_data   = nil
        _ = withUnsafePointer(to: cbs) { ra_whisperkit_set_callbacks($0) }
    }

    // MARK: - Bridge implementation

    private static func create(
        modelPath: UnsafePointer<CChar>?
    ) -> OpaquePointer? {
        #if canImport(WhisperKit)
        guard let modelPath = modelPath else { return nil }
        let pathStr = String(cString: modelPath)
        guard !pathStr.isEmpty else { return nil }

        // WhisperKit expects an async setup. Block a local runloop — the
        // caller is not on the main actor so this is safe.
        let result = SyncWrapper<WhisperKit?>()
        Task.detached {
            do {
                let config = WhisperKitConfig(modelFolder: pathStr)
                let pipe = try await WhisperKit(config)
                result.set(pipe)
            } catch {
                result.set(nil)
            }
        }
        guard let pipe = result.wait() else { return nil }
        let box = WhisperKitSessionBox(pipe: pipe)
        let raw = OpaquePointer(Unmanaged.passRetained(box).toOpaque())
        storeHandle(raw, box)
        return raw
        #else
        _ = modelPath
        return nil
        #endif
    }

    private static func destroy(handle: OpaquePointer?) {
        guard let handle = handle else { return }
        if let box = takeHandle(handle) {
            Unmanaged.passUnretained(box).release()
        }
    }

    private static func transcribe(
        handle: OpaquePointer?,
        audio: UnsafePointer<Float>?,
        count: Int,
        sampleRate: Int32,
        language: UnsafePointer<CChar>?,
        outText: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> ra_status_t {
        guard let handle = handle, let outText = outText else {
            return ra_status_t(RA_ERR_INVALID_ARGUMENT)
        }
        #if canImport(WhisperKit)
        guard let box = lookupHandle(handle) else {
            return ra_status_t(RA_ERR_INVALID_ARGUMENT)
        }
        _ = sampleRate
        let samples: [Float] = {
            guard let audio = audio, count > 0 else { return [] }
            return Array(UnsafeBufferPointer(start: audio, count: count))
        }()
        guard !samples.isEmpty else {
            outText.pointee = strdup("")
            return ra_status_t(RA_OK)
        }
        let lang = language.flatMap { String(cString: $0) } ?? "en"

        let result = SyncWrapper<String>()
        Task.detached {
            do {
                let opts = DecodingOptions(language: lang)
                let txs = try await box.pipe.transcribe(
                    audioArray: samples,
                    decodeOptions: opts)
                let text = txs.map(\.text).joined(separator: " ")
                result.set(text)
            } catch {
                result.set("")
            }
        }
        let text = result.wait() ?? ""
        outText.pointee = strdup(text)
        return ra_status_t(RA_OK)
        #else
        _ = audio; _ = count; _ = language; _ = handle
        return ra_status_t(RA_ERR_CAPABILITY_UNSUPPORTED)
        #endif
    }

    // MARK: - Registry helpers

    private static func storeHandle(_ raw: OpaquePointer, _ box: WhisperKitSessionBox) {
        handlesLock.lock(); defer { handlesLock.unlock() }
        handles[raw] = box
    }

    private static func lookupHandle(_ raw: OpaquePointer) -> WhisperKitSessionBox? {
        handlesLock.lock(); defer { handlesLock.unlock() }
        return handles[raw]
    }

    private static func takeHandle(_ raw: OpaquePointer) -> WhisperKitSessionBox? {
        handlesLock.lock(); defer { handlesLock.unlock() }
        return handles.removeValue(forKey: raw)
    }
}

// MARK: - SyncWrapper — bridges async Swift Task results back into
// synchronous C callbacks.

final class SyncWrapper<T>: @unchecked Sendable {
    private let sem = DispatchSemaphore(value: 0)
    private var value: T?
    func set(_ v: T) { value = v; sem.signal() }
    @discardableResult
    func wait(timeout: DispatchTime = .now() + 30) -> T? {
        _ = sem.wait(timeout: timeout)
        return value
    }
}

// MARK: - WhisperKitRuntime installer auto-wire

extension WhisperKitSTT {
    /// Extension point — host apps call `WhisperKitSTT.register()` during
    /// bootstrap and this hook installs the bridge the first time.
    public static func installBridge() {
        WhisperKitSTTService.installCallbacks()
    }
}
